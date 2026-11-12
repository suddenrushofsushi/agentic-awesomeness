#!/usr/bin/env bash
# Smoke test. Offline: push gate + stamp. Live (skip with --offline): one tiny prompt per agent.
#   tests/smoke.sh [--offline] [--review]    # --review also runs one real Codex review (slow)
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"; AGENT="$HERE/bin/agent"; GATE="$HERE/hooks/push-gate.py"
fail=0; ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
gate() { python3 -c 'import json,sys; print(json.dumps({"cwd":sys.argv[1],"tool_input":{"command":sys.argv[2]}}))' "$1" "$2" | "$GATE" 2>/dev/null; }

unstamp() { rm -f "$T/.git/agent-review/$(git -C "$T" rev-parse HEAD)"; }  # so a test sees only its own review
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
for redir in "git push origin other 2>&1 | tail -3" "git push origin other >/dev/null 2>&1" "git push &>log origin other" \
             "git push origin other > main"; do
  gate "$T" "$redir"; [ $? = 0 ] && ok "gate ignores redirect: $redir" || bad "gate ignores redirect: $redir"
done
gate "$T" "git push origin main 2>&1 | tail -3"; [ $? = 2 ] && ok "redirect does not hide an unstamped ref" || bad "redirect does not hide an unstamped ref"
gate "$T" "git push origin other 2 >log";      [ $? = 2 ] && ok "spaced digit stays a refspec"     || bad "spaced digit stays a refspec"
for lit in "git push origin other '>' main" "git push origin other \\> main"; do
  gate "$T" "$lit"; [ $? = 2 ] && ok "quoted > stays a refspec: $lit" || bad "quoted > stays a refspec: $lit"
done
git -C "$T" branch 'rel;' other && git -C "$T" branch 'rel;2'  # only rel; is stamped
gate "$T" "git push origin rel\\;2>/dev/null"; [ $? = 2 ] && ok "escaped ; keeps the digit in the ref" || bad "escaped ; keeps the digit in the ref"
gate "$T" "git commit -m 'a > b' && git push origin other 2>&1"; [ $? = 0 ] && ok "quoted > elsewhere keeps redirects working" || bad "quoted > elsewhere keeps redirects working"
"$AGENT" stamp -C "$T" --by someone --note x >/dev/null 2>&1; [ $? != 0 ] && ok "stamp refuses unknown --by" || bad "stamp refuses unknown --by"

# review stamping rule, with a fake codex that prints canned findings
FAKE="$T/fake-codex"; git -C "$T" checkout -q -b feat-fake
printf '#!/bin/sh\necho "- [P1] fake blocking finding"\n' > "$FAKE"; chmod +x "$FAKE"
CODEX_BIN="$FAKE" "$AGENT" review -C "$T" --base main >/dev/null 2>&1
gate "$T" "git push";                          [ $? = 2 ] && ok "review with P1 does not stamp"    || bad "review with P1 does not stamp"
printf '#!/bin/sh\necho "- [P2] fake minor finding"\n' > "$FAKE"
CODEX_BIN="$FAKE" "$AGENT" review -C "$T" --base main >/dev/null 2>&1
gate "$T" "git push";                          [ $? = 0 ] && ok "review with only P2 stamps"       || bad "review with only P2 stamps"
unstamp
printf '#!/bin/sh\necho "- [P2] fake finding\n  A partial \\`[P1]\\` would block here."\n' > "$FAKE"
CODEX_BIN="$FAKE" "$AGENT" review -C "$T" --base main >/dev/null 2>&1
gate "$T" "git push";                          [ $? = 0 ] && ok "[P1] quoted in a P2's prose stamps" || bad "[P1] quoted in a P2's prose stamps"
for f in '1. [P1] numbered' '**[P1] bold**' '{"title": "[P0] json"}' '### [P1] heading' '- `[P1]` quoted tag'; do
  unstamp; printf '#!/bin/sh\ncat <<"X"\n%s\nX\n' "$f" > "$FAKE"
  CODEX_BIN="$FAKE" "$AGENT" review -C "$T" --base main >/dev/null 2>&1
  gate "$T" "git push"; [ $? = 2 ] && ok "blocks format: $f" || bad "blocks format: $f"
done
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$0.args"\necho ok\n' > "$FAKE"
CODEX_BIN="$FAKE" "$AGENT" review -C "$T" --base main "extra check" >/dev/null 2>&1
! grep -qx -- '--base' "$FAKE.args" && grep -q 'main...HEAD' "$FAKE.args" && grep -q 'ponytail-review' "$FAKE.args" && grep -q 'extra check' "$FAKE.args" \
  && ok "review puts base, lens, and extra prompt in one prompt (no --base flag)" || bad "review prompt form: $(tr '\n' ' ' < "$FAKE.args" | cut -c1-200)"

# complex diff (15 files) adds the second reviewer: its P1 blocks, its failure does not
git -C "$T" checkout -q -b feat-big main
for i in $(seq 15); do echo "x = $i" > "$T/f$i.py"; done
git -C "$T" add -- 'f*.py' &&git -C "$T" commit -q -m big
FAKEPI="$T/fake-pi"; printf '#!/bin/sh\necho "- [P2] fake minor finding"\n' > "$FAKE"
cat > "$FAKEPI" <<'EOF'
#!/bin/sh
echo '{"type":"agent_end","messages":[{"role":"assistant","content":[{"type":"text","text":"- [P1] fake kimi finding"}]}]}'
EOF
chmod +x "$FAKEPI"
CODEX_BIN="$FAKE" PI_BIN="$FAKEPI" "$AGENT" review -C "$T" --base main >/dev/null 2>&1
gate "$T" "git push";                          [ $? = 2 ] && ok "complex diff: second reviewer P1 blocks" || bad "complex diff: second reviewer P1 blocks"
printf '#!/bin/sh\nexit 1\n' > "$FAKEPI"
CODEX_BIN="$FAKE" PI_BIN="$FAKEPI" "$AGENT" review -C "$T" --base main >/dev/null 2>&1
gate "$T" "git push";                          [ $? = 0 ] && ok "complex diff: second reviewer failure fails open" || bad "complex diff: second reviewer failure fails open"
unstamp
cat > "$FAKEPI" <<'EOF2'
#!/bin/sh
echo '{"type":"agent_end","messages":[{"role":"assistant","stopReason":"error","errorMessage":"overloaded","content":[{"type":"text","text":"- [P1] partial kimi text"}]}]}'
EOF2
CODEX_BIN="$FAKE" PI_BIN="$FAKEPI" "$AGENT" review -C "$T" --base main >/dev/null 2>&1
gate "$T" "git push";                          [ $? = 0 ] && ok "complex diff: second reviewer API error (rc 0) fails open" || bad "complex diff: second reviewer API error (rc 0) fails open"
unstamp
cat > "$FAKEPI" <<'EOF2'
#!/bin/sh
echo '{"type":"agent_end","messages":[{"role":"assistant","stopReason":"error","errorMessage":"overloaded","content":[]}]}'
echo '{"type":"agent_end","messages":[{"role":"assistant","stopReason":"stop","content":[{"type":"text","text":"- [P1] kimi after retry"}]}]}'
EOF2
CODEX_BIN="$FAKE" PI_BIN="$FAKEPI" "$AGENT" review -C "$T" --base main >/dev/null 2>&1
gate "$T" "git push";                          [ $? = 2 ] && ok "complex diff: second reviewer recovered after retry still blocks" || bad "complex diff: second reviewer recovered after retry still blocks"
unstamp
cat > "$FAKEPI" <<EOF2
#!/bin/sh
# first call: empty answer (Morph quirk); second call: a P1
if [ -e "$T/.pi-called" ]; then
  echo '{"type":"agent_end","messages":[{"role":"assistant","stopReason":"stop","content":[{"type":"text","text":"- [P1] found on second try"}]}]}'
else
  touch "$T/.pi-called"
  echo '{"type":"agent_end","messages":[{"role":"assistant","stopReason":"stop","content":[{"type":"text","text":""}]}]}'
fi
EOF2
CODEX_BIN="$FAKE" PI_BIN="$FAKEPI" "$AGENT" review -C "$T" --base main >/dev/null 2>&1
gate "$T" "git push";                          [ $? = 2 ] && ok "complex diff: empty second answer is retried once" || bad "complex diff: empty second answer is retried once"
rm -f "$T/.pi-called"
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
    gate "$T" "git push"; [ $? = $want ] && ok "live: review stamps unless P0/P1 (want $want)" || bad "live: review stamp rule"
  fi
fi
exit $fail
