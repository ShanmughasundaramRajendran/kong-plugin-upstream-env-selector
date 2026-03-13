#!/usr/bin/env bash
set -euo pipefail

PROXY="${PROXY:-http://localhost:8000}"
CURL_OPTS=(--retry 20 --retry-delay 1 --retry-connrefused -s -D -)
TOKEN_NEUTRAL="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJuZXV0cmFsLWNsaWVudC1rZXkiLCJjbGllbnRfaWQiOiJuZXV0cmFsX2NsaWVudCIsImV4cCI6MjIwODk4ODgwMH0.FngrKhY_xwXeTuOiQIshBs1ypUTOOkHvBb2O-tOyAmo"

OIDC_INTROSPECTION_DEV="eyJjbGllbnRfaWQiOiJkZXZfY2xpZW50IiwiYWN0aXZlIjp0cnVlfQ=="

echo "---- dev via X-Upstream-Env ----"
curl "${CURL_OPTS[@]}" -H "X-Upstream-Env: dev" -H "Authorization: Bearer ${TOKEN_NEUTRAL}" "${PROXY}/private/684130/developer-platform/gateway/clients" | head -n 20
echo

echo "---- prod via X-Upstream-Env ----"
curl "${CURL_OPTS[@]}" -H "X-Upstream-Env: prod" -H "Authorization: Bearer ${TOKEN_NEUTRAL}" "${PROXY}/private/684130/developer-platform/gateway/clients" | head -n 20
echo

echo "---- qa via X-Upstream-Env ----"
curl "${CURL_OPTS[@]}" -H "X-Upstream-Env: qa" -H "Authorization: Bearer ${TOKEN_NEUTRAL}" "${PROXY}/private/684130/developer-platform/gateway/clients" | head -n 20
echo

echo "---- dev via client query param (?apUpsByQP=dev) ----"
curl "${CURL_OPTS[@]}" -H "Authorization: Bearer ${TOKEN_NEUTRAL}" "${PROXY}/private/684130/developer-platform/gateway/clients?apUpsByQP=dev" | head -n 20
echo

echo "---- prod via resource header X-Upstream-Env-EP ----"
curl "${CURL_OPTS[@]}" -H "X-Upstream-Env-EP: prod" -H "Authorization: Bearer ${TOKEN_NEUTRAL}" "${PROXY}/private/684130/developer-platform/gateway/clients" | head -n 20
echo

echo "---- introspection header is ignored for client_id routing (stays default it) ----"
curl "${CURL_OPTS[@]}" \
  -H "Authorization: Bearer ${TOKEN_NEUTRAL}" \
  -H "X-Introspection-Response: ${OIDC_INTROSPECTION_DEV}" \
  "${PROXY}/private/684130/developer-platform/gateway/clients" | head -n 20
echo

echo "---- default header still overrides all other inputs ----"
curl "${CURL_OPTS[@]}" \
  -H "X-Upstream-Env: qa" \
  -H "Authorization: Bearer ${TOKEN_NEUTRAL}" \
  -H "X-Introspection-Response: ${OIDC_INTROSPECTION_DEV}" \
  "${PROXY}/private/684130/developer-platform/gateway/clients" | head -n 20
echo

echo "---- no selector (uses default service upstream) ----"
curl "${CURL_OPTS[@]}" -H "Authorization: Bearer ${TOKEN_NEUTRAL}" "${PROXY}/private/684130/developer-platform/gateway/clients" | head -n 20
echo

echo "---- access-policy SNI via https://access-sni-dev.local:8443 ----"
curl "${CURL_OPTS[@]}" -k --resolve access-sni-dev.local:8443:127.0.0.1 \
  -H "Authorization: Bearer ${TOKEN_NEUTRAL}" \
  "https://access-sni-dev.local:8443/private/684130/developer-platform/gateway/clients" | head -n 20
echo

echo "---- endpoint SNI via https://endpoint-sni-qa.local:8443 ----"
curl "${CURL_OPTS[@]}" -k --resolve endpoint-sni-qa.local:8443:127.0.0.1 \
  -H "Authorization: Bearer ${TOKEN_NEUTRAL}" \
  "https://endpoint-sni-qa.local:8443/private/684130/developer-platform/gateway/clients-endpoint-sni" | head -n 20
echo
