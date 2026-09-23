#!/usr/bin/env bash
# Post a line into a Buzz channel from anywhere, through the Hermes webhook (HMAC-signed). No model turn.
# Usage: tools/buzz-post.sh <route: triage|dept> "text"     [BUZZ_WEBHOOK_URL=https://waterman.terakeet.ai]
set -euo pipefail
ROUTE="${1:?route}"; TEXT="${2:?text}"; URL="${BUZZ_WEBHOOK_URL:-http://localhost:8644}"
SEC=$(grep '^WEBHOOK_SECRET=' "$HOME/.hermes/profiles/buzz/.env" | cut -d= -f2)
BODY=$(python3 -c 'import json,sys; print(json.dumps({"text": sys.argv[1]}))' "$TEXT")
SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$SEC" | awk '{print $NF}')
curl -s -m 15 -X POST "$URL/webhooks/$ROUTE" -H 'Content-Type: application/json' -H "X-Hub-Signature-256: sha256=$SIG" -H "X-Request-ID: post-$(date +%s%N)" -d "$BODY"; echo
