#!/usr/bin/env bash
set -euo pipefail

PROXY="${PROXY:-http://localhost:8000}"
CURL_OPTS=(--retry 20 --retry-delay 1 --retry-connrefused -s -D -)
TOKEN_NEUTRAL="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJuZXV0cmFsLWNsaWVudC1rZXkiLCJjbGllbnRfaWQiOiJuZXV0cmFsX2NsaWVudCIsImV4cCI6MjIwODk4ODgwMH0.FngrKhY_xwXeTuOiQIshBs1ypUTOOkHvBb2O-tOyAmo"

# Base64 JSON {"client_id":"<env>_client","active":true}
OIDC_INTROSPECTION_DEV="eyJjbGllbnRfaWQiOiJkZXZfY2xpZW50IiwiYWN0aXZlIjp0cnVlfQ=="
OIDC_INTROSPECTION_PROD="eyJjbGllbnRfaWQiOiJwcm9kX2NsaWVudCIsImFjdGl2ZSI6dHJ1ZX0="
OIDC_INTROSPECTION_QA="eyJjbGllbnRfaWQiOiJxYV9jbGllbnQiLCJhY3RpdmUiOnRydWV9"
OIDC_INTROSPECTION_IT="eyJjbGllbnRfaWQiOiJpdF9jbGllbnQiLCJhY3RpdmUiOnRydWV9"
OIDC_INTROSPECTION_PERF="eyJjbGllbnRfaWQiOiJwZXJmX2NsaWVudCIsImFjdGl2ZSI6dHJ1ZX0="

echo "---- dev via X-Upstream-Env ----"
curl "${CURL_OPTS[@]}" -H "X-Upstream-Env: dev" -H "Authorization: Bearer ${TOKEN_NEUTRAL}" "${PROXY}/api/orders" | head -n 20
echo

echo "---- prod via X-Upstream-Env ----"
curl "${CURL_OPTS[@]}" -H "X-Upstream-Env: prod" -H "Authorization: Bearer ${TOKEN_NEUTRAL}" "${PROXY}/api/orders" | head -n 20
echo

echo "---- qa via X-Upstream-Env ----"
curl "${CURL_OPTS[@]}" -H "X-Upstream-Env: qa" -H "Authorization: Bearer ${TOKEN_NEUTRAL}" "${PROXY}/api/orders" | head -n 20
echo

echo "---- dev via client query param (?env=dev) ----"
curl "${CURL_OPTS[@]}" -H "Authorization: Bearer ${TOKEN_NEUTRAL}" "${PROXY}/api/orders?env=dev" | head -n 20
echo

echo "---- prod via resource header X-Resource-Env ----"
curl "${CURL_OPTS[@]}" -H "X-Resource-Env: prod" -H "Authorization: Bearer ${TOKEN_NEUTRAL}" "${PROXY}/api/orders" | head -n 20
echo

echo "---- dev via OIDC introspection header client_id=dev_client ----"
curl "${CURL_OPTS[@]}" \
  -H "Authorization: Bearer ${TOKEN_NEUTRAL}" \
  -H "X-Introspection-Response: ${OIDC_INTROSPECTION_DEV}" \
  "${PROXY}/api/orders" | head -n 20
echo

echo "---- prod via OIDC introspection header client_id=prod_client ----"
curl "${CURL_OPTS[@]}" \
  -H "Authorization: Bearer ${TOKEN_NEUTRAL}" \
  -H "X-Introspection-Response: ${OIDC_INTROSPECTION_PROD}" \
  "${PROXY}/api/orders" | head -n 20
echo

echo "---- qa via OIDC introspection header client_id=qa_client ----"
curl "${CURL_OPTS[@]}" \
  -H "Authorization: Bearer ${TOKEN_NEUTRAL}" \
  -H "X-Introspection-Response: ${OIDC_INTROSPECTION_QA}" \
  "${PROXY}/api/orders" | head -n 20
echo

echo "---- it via OIDC introspection header client_id=it_client ----"
curl "${CURL_OPTS[@]}" \
  -H "Authorization: Bearer ${TOKEN_NEUTRAL}" \
  -H "X-Introspection-Response: ${OIDC_INTROSPECTION_IT}" \
  "${PROXY}/api/orders" | head -n 20
echo

echo "---- perf via OIDC introspection header client_id=perf_client ----"
curl "${CURL_OPTS[@]}" \
  -H "Authorization: Bearer ${TOKEN_NEUTRAL}" \
  -H "X-Introspection-Response: ${OIDC_INTROSPECTION_PERF}" \
  "${PROXY}/api/orders" | head -n 20
echo

echo "---- default header overrides OIDC client_id ----"
curl "${CURL_OPTS[@]}" \
  -H "X-Upstream-Env: qa" \
  -H "Authorization: Bearer ${TOKEN_NEUTRAL}" \
  -H "X-Introspection-Response: ${OIDC_INTROSPECTION_DEV}" \
  "${PROXY}/api/orders" | head -n 20
echo

echo "---- no selector (uses default service upstream) ----"
curl "${CURL_OPTS[@]}" -H "Authorization: Bearer ${TOKEN_NEUTRAL}" "${PROXY}/api/orders" | head -n 20
echo

echo "---- access-policy SNI via https://access-sni-dev.local:8443 ----"
curl "${CURL_OPTS[@]}" -k --resolve access-sni-dev.local:8443:127.0.0.1 \
  -H "Authorization: Bearer ${TOKEN_NEUTRAL}" \
  "https://access-sni-dev.local:8443/api/orders" | head -n 20
echo

echo "---- endpoint SNI via https://endpoint-sni-qa.local:8443 ----"
curl "${CURL_OPTS[@]}" -k --resolve endpoint-sni-qa.local:8443:127.0.0.1 \
  -H "Authorization: Bearer ${TOKEN_NEUTRAL}" \
  "https://endpoint-sni-qa.local:8443/api/orders-endpoint-sni" | head -n 20
echo
