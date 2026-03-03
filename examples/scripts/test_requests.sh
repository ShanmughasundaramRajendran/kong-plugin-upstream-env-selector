#!/usr/bin/env bash
set -euo pipefail

PROXY="${PROXY:-http://localhost:8000}"
CURL_OPTS=(--retry 20 --retry-delay 1 --retry-connrefused -s -D -)
JWT_NEUTRAL="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJuZXV0cmFsLWNsaWVudC1rZXkiLCJjbGllbnRfaWQiOiJuZXV0cmFsX2NsaWVudCIsImV4cCI6MjIwODk4ODgwMH0.FngrKhY_xwXeTuOiQIshBs1ypUTOOkHvBb2O-tOyAmo"
JWT_DEV="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJkZXYtY2xpZW50LWtleSIsImNsaWVudF9pZCI6ImRldl9jbGllbnQiLCJleHAiOjIyMDg5ODg4MDB9.yW48zbOdY4y25DWQJ-aBxf2HYZrmQ03hQvnxhPmOqWE"
JWT_PROD="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJwcm9kLWNsaWVudC1rZXkiLCJjbGllbnRfaWQiOiJwcm9kX2NsaWVudCIsImV4cCI6MjIwODk4ODgwMH0.55GEwKqnbUPrVnXwphThR5gPTLAH8FC1gNaiUgqhd8w"
JWT_QA="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJxYS1jbGllbnQta2V5IiwiY2xpZW50X2lkIjoicWFfY2xpZW50IiwiZXhwIjoyMjA4OTg4ODAwfQ.NLiV9nxno2AsCy3veuEIS1Hl3QEjBbwZAXDaORLUSRc"
JWT_IT="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpdC1jbGllbnQta2V5IiwiY2xpZW50X2lkIjoiaXRfY2xpZW50IiwiZXhwIjoyMjA4OTg4ODAwfQ.o-2ZVIQmatMOyeYqIqapRURgbDaczW6UPzBytuCAaH8"
JWT_PERF="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJwZXJmLWNsaWVudC1rZXkiLCJjbGllbnRfaWQiOiJwZXJmX2NsaWVudCIsImV4cCI6MjIwODk4ODgwMH0.m2TlHFM_5Wdsu6MaJ8P9ZngvPMvO3wTMMcLnlYM7T3g"

echo "---- dev via X-Upstream-Env ----"
curl "${CURL_OPTS[@]}" -H "X-Upstream-Env: dev" -H "Authorization: Bearer ${JWT_NEUTRAL}" "${PROXY}/api/orders" | head -n 20
echo

echo "---- prod via X-Upstream-Env ----"
curl "${CURL_OPTS[@]}" -H "X-Upstream-Env: prod" -H "Authorization: Bearer ${JWT_NEUTRAL}" "${PROXY}/api/orders" | head -n 20
echo

echo "---- qa via X-Upstream-Env ----"
curl "${CURL_OPTS[@]}" -H "X-Upstream-Env: qa" -H "Authorization: Bearer ${JWT_NEUTRAL}" "${PROXY}/api/orders" | head -n 20
echo

echo "---- dev via client query param (?env=dev) ----"
curl "${CURL_OPTS[@]}" -H "Authorization: Bearer ${JWT_NEUTRAL}" "${PROXY}/api/orders?env=dev" | head -n 20
echo

echo "---- prod via resource header X-Resource-Env ----"
curl "${CURL_OPTS[@]}" -H "X-Resource-Env: prod" -H "Authorization: Bearer ${JWT_NEUTRAL}" "${PROXY}/api/orders" | head -n 20
echo

echo "---- dev via JWT claim client_id=dev_client ----"
curl "${CURL_OPTS[@]}" -H "Authorization: Bearer ${JWT_DEV}" "${PROXY}/api/orders" | head -n 20
echo

echo "---- prod via JWT claim client_id=prod_client ----"
curl "${CURL_OPTS[@]}" -H "Authorization: Bearer ${JWT_PROD}" "${PROXY}/api/orders" | head -n 20
echo

echo "---- qa via JWT claim client_id=qa_client ----"
curl "${CURL_OPTS[@]}" -H "Authorization: Bearer ${JWT_QA}" "${PROXY}/api/orders" | head -n 20
echo

echo "---- it via JWT claim client_id=it_client ----"
curl "${CURL_OPTS[@]}" -H "Authorization: Bearer ${JWT_IT}" "${PROXY}/api/orders" | head -n 20
echo

echo "---- perf via JWT claim client_id=perf_client ----"
curl "${CURL_OPTS[@]}" -H "Authorization: Bearer ${JWT_PERF}" "${PROXY}/api/orders" | head -n 20
echo

echo "---- default header overrides JWT client_id ----"
curl "${CURL_OPTS[@]}" -H "X-Upstream-Env: qa" -H "Authorization: Bearer ${JWT_DEV}" "${PROXY}/api/orders" | head -n 20
echo

echo "---- no selector (uses default service upstream) ----"
curl "${CURL_OPTS[@]}" -H "Authorization: Bearer ${JWT_NEUTRAL}" "${PROXY}/api/orders" | head -n 20
echo

echo "---- access-policy SNI via https://access-sni-dev.local:8443 ----"
curl "${CURL_OPTS[@]}" -k --resolve access-sni-dev.local:8443:127.0.0.1 \
  -H "Authorization: Bearer ${JWT_NEUTRAL}" \
  "https://access-sni-dev.local:8443/api/orders" | head -n 20
echo

echo "---- endpoint SNI via https://endpoint-sni-qa.local:8443 ----"
curl "${CURL_OPTS[@]}" -k --resolve endpoint-sni-qa.local:8443:127.0.0.1 \
  -H "Authorization: Bearer ${JWT_NEUTRAL}" \
  "https://endpoint-sni-qa.local:8443/api/orders-endpoint-sni" | head -n 20
echo
