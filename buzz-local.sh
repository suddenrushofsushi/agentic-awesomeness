#!/usr/bin/env bash
# Buzz local stack without just/hermit. Usage: ./buzz-local.sh {services|relay|desktop|status|stop|stop-all}
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/buzz" && pwd)"
RUN="$ROOT/.local-run"; mkdir -p "$RUN"
VITE_PORT=17371   # any free port; keep stable so Tauri's dev config (and cargo cache) stays stable
TARGET=$(rustc -vV | sed -n 's|host: ||p')

load_env() { set -a; . "$ROOT/.env"; set +a; }

services() {
  cd "$ROOT" && docker compose up -d postgres redis minio minio-init
  load_env
  until docker exec buzz-postgres pg_isready -U buzz >/dev/null 2>&1; do sleep 1; done
  "$ROOT/target/debug/buzz-admin" migrate && "$ROOT/scripts/seed-local-community.sh" >/dev/null
}

relay() {
  cd "$ROOT" && load_env
  cargo build -q -p buzz-relay -p buzz-admin
  export BUZZ_GIT_PROBE_WRITERS="${BUZZ_GIT_PROBE_WRITERS:-8}" BUZZ_GIT_PROBE_ROUNDS="${BUZZ_GIT_PROBE_ROUNDS:-2}"
  nohup "$ROOT/target/debug/buzz-relay" >"$RUN/relay.log" 2>&1 & echo $! >"$RUN/relay.pid"
  for _ in $(seq 1 60); do curl -sf --max-time 1 http://127.0.0.1:8080/_readiness >/dev/null && { echo "relay ready ws://localhost:3000 (pid $(cat "$RUN/relay.pid"))"; return; }; sleep 1; done
  echo "relay did not become ready; see $RUN/relay.log" >&2; exit 1
}

desktop() {
  cd "$ROOT"
  cargo build -q -p buzz-acp -p buzz-agent -p buzz-backend-kubernetes -p buzz-dev-mcp -p buzz-cli -p git-credential-nostr
  mkdir -p desktop/src-tauri/binaries
  for b in buzz-acp buzz-agent buzz-backend-kubernetes buzz-dev-mcp git-credential-nostr buzz; do
    cp "target/debug/$b" "desktop/src-tauri/binaries/$b-$TARGET"
  done
  cd desktop; [[ -d node_modules ]] || pnpm install
  export BUZZ_RELAY_URL="${BUZZ_RELAY_URL:-ws://localhost:3000}"
  CFG="{\"build\":{\"devUrl\":\"http://localhost:$VITE_PORT\",\"beforeDevCommand\":\"exec ./node_modules/.bin/vite --port $VITE_PORT --strictPort\"},\"identifier\":\"xyz.block.buzz.app.dev\",\"productName\":\"Buzz Dev\"}"
  nohup pnpm exec tauri dev --config "$CFG" >"$RUN/desktop.log" 2>&1 & echo $! >"$RUN/desktop.pid"
  echo "desktop starting (pid $(cat "$RUN/desktop.pid")); log: $RUN/desktop.log"
}

status() {
  docker ps --filter name=buzz- --format '{{.Names}}\t{{.Status}}\t{{.Ports}}'
  curl -sf --max-time 1 http://127.0.0.1:8080/_readiness >/dev/null && echo "relay: up (ws://localhost:3000)" || echo "relay: down"
  pgrep -fl 'target/debug/buzz-desktop' >/dev/null && echo "desktop: up" || echo "desktop: down"
}

stop() {
  pkill -f 'target/debug/buzz-desktop' 2>/dev/null || true
  [[ -f "$RUN/desktop.pid" ]] && { pkill -P "$(cat "$RUN/desktop.pid")" 2>/dev/null || true; kill "$(cat "$RUN/desktop.pid")" 2>/dev/null || true; rm -f "$RUN/desktop.pid"; }
  pkill -f 'vite.*--port '"$VITE_PORT" 2>/dev/null || true
  [[ -f "$RUN/relay.pid" ]] && { kill "$(cat "$RUN/relay.pid")" 2>/dev/null || true; rm -f "$RUN/relay.pid"; }
  pkill -f 'target/debug/buzz-relay' 2>/dev/null || true
  echo "relay + desktop stopped (docker services still up; use stop-all)"
}

case "${1:-}" in
  services) services ;;
  relay) relay ;;
  desktop) desktop ;;
  up) services; relay; desktop ;;
  status) status ;;
  stop) stop ;;
  stop-all) stop; cd "$ROOT" && docker compose stop ;;
  *) echo "usage: $0 {up|services|relay|desktop|status|stop|stop-all}"; exit 1 ;;
esac
