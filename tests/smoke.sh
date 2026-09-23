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
"$AGENT" stamp -C "$T" >/dev/null 2>&1;        [ $? != 0 ] && ok "stamp refuses without --by/--note" || bad "stamp refuses without --by/--note"
"$AGENT" stamp -C "$T/sub" --by claude --note smoke >/dev/null
gate "$T" "git push";                          [ $? = 0 ] && ok "gate allows stamped HEAD"         || bad "gate allows stamped HEAD"
git -C "$T" commit -q --allow-empty -m next
gate "$T" "git push";                          [ $? = 2 ] && ok "new commit needs a new stamp"     || bad "new commit needs a new stamp"

if [ "${1:-}" != "--offline" ]; then
  live() { out=$("$AGENT" "$@" 2>/dev/null); [[ "$out" == *"$want"* ]] && ok "live: $*" || bad "live: $* -> ${out:0:200}"; }
  want=ok-codex; live codex -C "$T" "Reply with exactly: ok-codex"
  want=ok-local; live pi -C "$T" "Reply with exactly: ok-local"
  want=ok-or;    live pi -C "$T" -m openrouter/deepseek/deepseek-v4-pro "Reply with exactly: ok-or"
  if [[ " $* " == *" --review "* ]]; then
    git -C "$T" checkout -q -b feat && printf 'def div(a, b):\n    return a / b\n' > "$T/m.py"
    git -C "$T" add m.py && git -C "$T" commit -q -m "add div"
    "$AGENT" review -C "$T" --base main >/dev/null 2>&1
    gate "$T" "git push"; [ $? = 0 ] && ok "live: Luna review stamps HEAD" || bad "live: Luna review stamps HEAD"
  fi
fi
exit $fail
