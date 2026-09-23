#!/usr/bin/env bash
# Smoke test. Offline: push gate + stamp. Live (skip with --offline): one tiny prompt per agent.
#   tests/smoke.sh [--offline] [--review]    # --review also runs one real Luna review (slow)
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"; AGENT="$HERE/bin/agent"; GATE="$HERE/hooks/push-gate.py"
fail=0; ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
gate() { python3 -c 'import json,sys; print(json.dumps({"cwd":sys.argv[1],"tool_input":{"command":sys.argv[2]}}))' "$1" "$2" | "$GATE" 2>/dev/null; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
git -C "$T" init -q -b main && git -C "$T" commit -q --allow-empty -m init
mkdir -p "$T/sub"

gate "$T" "git status";                        [ $? = 0 ] && ok "gate ignores non-push"            || bad "gate ignores non-push"
gate "$T" "git log --grep push";               [ $? = 0 ] && ok "gate ignores 'push' as an arg"    || bad "gate ignores 'push' as an arg"
gate "$T" "git push origin main";              [ $? = 2 ] && ok "gate blocks unreviewed push"      || bad "gate blocks unreviewed push"
gate /tmp "cd $T && git push";                 [ $? = 2 ] && ok "gate follows cd"                  || bad "gate follows cd"
gate /tmp "git -C $T push";                    [ $? = 2 ] && ok "gate follows -C"                  || bad "gate follows -C"
gate "$T" "git push origin --delete old";      [ $? = 0 ] && ok "gate allows ref delete"           || bad "gate allows ref delete"
gate "$T" "AGENT_REVIEW_SKIP=1 git push";      [ $? = 0 ] && ok "gate bypass works"                || bad "gate bypass works"
gate "$T" "echo AGENT_REVIEW_SKIP=1; git push"; [ $? = 2 ] && ok "bypass must prefix the push"      || bad "bypass must prefix the push"
gate "$T" "AGENT_REVIEW_SKIP=1 git status && git push"; [ $? = 2 ] && ok "bypass on another command does not count" || bad "bypass on another command does not count"
for wrapped in "env git push" "env FOO=1 git push origin main" "command git push" "timeout 60 git push" \
               "bash -c 'git push origin main'" "sh -lc \"cd $T && git push\"" "eval git push" "(cd $T && git push)" \
               "echo \$(git push)" "xargs git push"; do
  gate "$T" "$wrapped"; [ $? = 2 ] && ok "gate sees wrapped: $wrapped" || bad "gate sees wrapped: $wrapped"
done
gate "$T" "echo 'git push'";                   [ $? = 0 ] && ok "gate ignores quoted text"         || bad "gate ignores quoted text"
gate "$T" "grep -n 'git push' README.md";      [ $? = 0 ] && ok "gate ignores grep for push"       || bad "gate ignores grep for push"
gate /tmp "git -C /nonexistent push";          [ $? = 2 ] && ok "gate fails closed on unknown repo" || bad "gate fails closed on unknown repo"
echo 'not json git push' | "$GATE" 2>/dev/null; [ $? = 2 ] && ok "gate crash near a push blocks"  || bad "gate crash near a push blocks"
echo 'not json ls' | "$GATE" 2>/dev/null;      [ $? = 0 ] && ok "gate crash elsewhere allows"      || bad "gate crash elsewhere allows"
"$AGENT" stamp -C "$T" >/dev/null 2>&1;        [ $? != 0 ] && ok "stamp refuses without --by/--note" || bad "stamp refuses without --by/--note"
"$AGENT" stamp -C "$T/sub" --by claude --note smoke >/dev/null
gate "$T" "git push";                          [ $? = 0 ] && ok "gate allows stamped HEAD"         || bad "gate allows stamped HEAD"
git -C "$T" branch other
git -C "$T" commit -q --allow-empty -m next
gate "$T" "git push";                          [ $? = 2 ] && ok "new commit needs a new stamp"     || bad "new commit needs a new stamp"
gate "$T" "git push origin other";             [ $? = 0 ] && ok "gate checks the named ref (stamped)" || bad "gate checks the named ref (stamped)"
gate "$T" "git push -u origin HEAD:main";      [ $? = 2 ] && ok "gate checks refspec source"       || bad "gate checks refspec source"
gate "$T" "git push origin other main";        [ $? = 2 ] && ok "gate checks every refspec"        || bad "gate checks every refspec"
gate "$T" "git push origin :old";              [ $? = 0 ] && ok "gate allows :dst delete"          || bad "gate allows :dst delete"
gate "$T" "git push --all origin";             [ $? = 2 ] && ok "gate blocks --all"                || bad "gate blocks --all"
gate "$T" "git push origin nosuchref";         [ $? = 2 ] && ok "gate blocks unresolvable ref"     || bad "gate blocks unresolvable ref"
"$AGENT" stamp -C "$T" --by someone --note x >/dev/null 2>&1; [ $? != 0 ] && ok "stamp refuses unknown --by" || bad "stamp refuses unknown --by"

# review stamping rule, with a fake codex that prints canned findings
FAKE="$T/fake-codex"; git -C "$T" checkout -q -b feat-fake
printf '#!/bin/sh\necho "- [P1] fake blocking finding"\n' > "$FAKE"; chmod +x "$FAKE"
CODEX_BIN="$FAKE" "$AGENT" review -C "$T" --base main >/dev/null 2>&1
gate "$T" "git push";                          [ $? = 2 ] && ok "review with P1 does not stamp"    || bad "review with P1 does not stamp"
printf '#!/bin/sh\necho "- [P2] fake minor finding"\n' > "$FAKE"
CODEX_BIN="$FAKE" "$AGENT" review -C "$T" --base main >/dev/null 2>&1
gate "$T" "git push";                          [ $? = 0 ] && ok "review with only P2 stamps"       || bad "review with only P2 stamps"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$0.args"\necho ok\n' > "$FAKE"
CODEX_BIN="$FAKE" "$AGENT" review -C "$T" --base main "extra check" >/dev/null 2>&1
! grep -qx -- '--base' "$FAKE.args" && grep -q 'main...HEAD' "$FAKE.args" && grep -q 'ponytail-review' "$FAKE.args" && grep -q 'extra check' "$FAKE.args" \
  && ok "review puts base, lens, and extra prompt in one prompt (no --base flag)" || bad "review prompt form: $(tr '\n' ' ' < "$FAKE.args" | cut -c1-200)"
git -C "$T" checkout -q main

if [ "${1:-}" != "--offline" ]; then
  live() { out=$("$AGENT" "$@" 2>/dev/null); [[ "$out" == *"$want"* ]] && ok "live: $*" || bad "live: $* -> ${out:0:200}"; }
  want=ok-codex; live codex -C "$T" "Reply with exactly: ok-codex"
  want=ok-local; live pi -C "$T" "Reply with exactly: ok-local"
  want=ok-or;    live pi -C "$T" -m openrouter/deepseek/deepseek-v4-pro "Reply with exactly: ok-or"
  if [[ " $* " == *" --review "* ]]; then
    git -C "$T" checkout -q -b feat-live && printf 'def div(a, b):\n    return a / b\n' > "$T/m.py"
    git -C "$T" add m.py && git -C "$T" commit -q -m "add div"
    "$AGENT" review -C "$T" --base main 2>&1 | grep -q "\[P[01]\]" && want=2 || want=0
    gate "$T" "git push"; [ $? = $want ] && ok "live: Luna review stamps unless P0/P1 (want $want)" || bad "live: Luna review stamp rule"
  fi
fi
exit $fail
