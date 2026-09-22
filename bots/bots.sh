#!/usr/bin/env bash
# Standalone Buzz bots (buzz-acp + ACP adapter), one env file per bot.
# Usage: bots/bots.sh {keygen|start|stop|restart|status|logs} <name>|all
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(dirname "$HERE")"
BIN="${BUZZ_DIR:-$HOME/github/buzz}/target/debug"; RELAY="${BUZZ_ACP_RELAY_URL:-ws://localhost:3000}"   # buzz-acp needs ws://; the buzz CLI wants http://, so keep the vars apart
OWNER="${BUZZ_OWNER_PUBKEY:-$(awk '$1=="owner"{print $2}' "$HERE/PUBKEYS.txt" 2>/dev/null || true)}"
[[ -n "$OWNER" ]] || { echo "owner pubkey unknown: set BUZZ_OWNER_PUBKEY or fix bots/PUBKEYS.txt" >&2; exit 1; }

names() { if [[ "${1:-all}" == all ]]; then ls "$HERE"/*.env | xargs -n1 basename | sed 's/\.env$//'; else echo "$1"; fi; }
pk() { awk -F= '/^PK=/{print $2}' "$HERE/keys/$1.key"; }
sk() { awk -F= '/^SK=/{print $2}' "$HERE/keys/$1.key"; }

keygen() { for n in $(names "$1"); do
  [[ -f "$HERE/keys/$n.key" ]] && { echo "$n: key exists, pubkey $(pk "$n")"; continue; }
  out=$(cd "$(dirname "$BIN")/.." && set -a && . ./.env && set +a && "$BIN/buzz-admin" generate-key)
  { echo "PK=$(awk '/Public key/{print $3}' <<<"$out")"; echo "SK=$(awk '/Secret key/{print $3}' <<<"$out")"; } >"$HERE/keys/$n.key"
  chmod 600 "$HERE/keys/$n.key"; echo "$n $(pk "$n")" >>"$HERE/PUBKEYS.txt"; echo "$n: pubkey $(pk "$n")"; done; }

start() { for n in $(names "$1"); do
  [[ -f "$HERE/pids/$n.pid" ]] && kill -0 "$(cat "$HERE/pids/$n.pid")" 2>/dev/null && { echo "$n: already running"; continue; }
  [[ -f "$HERE/keys/$n.key" ]] || keygen "$n"
  BOT_ALLOW=""; BOT_CWD="$HOME"; BOT_ARGS=""
  . "$HERE/$n.env"
  allow="$OWNER"; for a in $BOT_ALLOW; do allow="$allow,$(pk "$a")"; done
  mkdir -p "$HERE/.build"; cat "$HERE/prompts/_common.md" "$HERE/prompts/$n.md" >"$HERE/.build/$n.md"
  ( exec >"$HERE/logs/$n.log" 2>&1 </dev/null   # detach the whole launcher from the caller's pipes, or `bots.sh start | tail` never returns
    cd "$BOT_CWD" && BUZZ_PRIVATE_KEY="$(sk "$n")" BUZZ_RELAY_URL="$RELAY" \
    nohup "$BIN/buzz-acp" --agent-owner "$OWNER" --respond-to allowlist --respond-to-allowlist "$allow" \
      --agent-command "$BOT_CMD" --agent-args "$BOT_ARGS" --mcp-command "$BIN/buzz-dev-mcp" \
      --system-prompt-file "$HERE/.build/$n.md" --session-policy thread \
      & echo $! >"$HERE/pids/$n.pid" )
  echo "$n: started pid $(cat "$HERE/pids/$n.pid") cwd $BOT_CWD pubkey $(pk "$n")"; done; }

stop() { for n in $(names "$1"); do
  [[ -f "$HERE/pids/$n.pid" ]] || { echo "$n: not running"; continue; }
  p=$(cat "$HERE/pids/$n.pid"); pkill -P "$p" 2>/dev/null || true; kill "$p" 2>/dev/null || true
  for _ in $(seq 1 30); do kill -0 "$p" 2>/dev/null || break; sleep 0.5; done; kill -9 "$p" 2>/dev/null || true
  rm -f "$HERE/pids/$n.pid"; echo "$n: stopped"; done; }

status() { for n in $(names all); do
  if [[ -f "$HERE/pids/$n.pid" ]] && kill -0 "$(cat "$HERE/pids/$n.pid")" 2>/dev/null; then s=up; else s=down; fi
  printf '%-8s %-5s %s\n' "$n" "$s" "$([[ -f "$HERE/keys/$n.key" ]] && pk "$n" || echo no-key)"; done; }

case "${1:-}" in
  keygen|start|stop|status) "$1" "${2:-all}" ;;
  restart) stop "${2:-all}"; start "${2:-all}" ;;
  logs) tail -n "${3:-50}" -f "$HERE/logs/${2:?name}.log" ;;
  *) echo "usage: $0 {keygen|start|stop|restart|status|logs} <name>|all"; exit 1 ;;
esac
