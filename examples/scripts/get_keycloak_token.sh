#!/usr/bin/env bash
set -euo pipefail

CLIENT_ID="${1:-it_client}"

case "$CLIENT_ID" in
  neutral_client) CLIENT_SECRET="neutral-client-secret" ;;
  dev_client) CLIENT_SECRET="dev-client-secret" ;;
  qa_client) CLIENT_SECRET="qa-client-secret" ;;
  it_client) CLIENT_SECRET="it-client-secret" ;;
  perf_client) CLIENT_SECRET="perf-client-secret" ;;
  kong-introspector) CLIENT_SECRET="kong-introspector-secret" ;;
  *)
    echo "Unknown client_id: $CLIENT_ID" >&2
    echo "Allowed: neutral_client dev_client qa_client it_client perf_client kong-introspector" >&2
    exit 1
    ;;
esac

KC_BASE_URL="${KC_BASE_URL:-http://localhost:8085}"
KC_REALM="${KC_REALM:-kong-local}"

curl -fsS -X POST \
  "$KC_BASE_URL/realms/$KC_REALM/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_id=$CLIENT_ID" \
  --data-urlencode "client_secret=$CLIENT_SECRET"
