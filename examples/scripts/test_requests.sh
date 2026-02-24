#!/usr/bin/env bash
set -euo pipefail

PROXY="${PROXY:-http://localhost:8000}"
CURL_OPTS=(--retry 20 --retry-delay 1 --retry-connrefused -s -D -)
JWT_NEUTRAL="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJuZXV0cmFsLWNsaWVudC1rZXkiLCJjbGllbnQtaWQiOiJuZXV0cmFsX2NsaWVudCIsImV4cCI6MjIwODk4ODgwMH0.7E_691oY_22EDmV289scCNwWrMxnc4s5GXalkK1z08I"
JWT_DEV="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJkZXYtY2xpZW50LWtleSIsImNsaWVudC1pZCI6ImRldl9jbGllbnQiLCJleHAiOjIyMDg5ODg4MDB9.W4BML7dw6GrEEXmQbnUDPBuj6QDb6zCrVwufUqTAvLQ"
JWT_PROD="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJwcm9kLWNsaWVudC1rZXkiLCJjbGllbnQtaWQiOiJwcm9kX2NsaWVudCIsImV4cCI6MjIwODk4ODgwMH0.IUWl_C_OBt2KZ50EixFZFM1ip-qSm9jh7SXAdlnA-Fk"
JWT_QA="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJxYS1jbGllbnQta2V5IiwiY2xpZW50LWlkIjoicWFfY2xpZW50IiwiZXhwIjoyMjA4OTg4ODAwfQ.1jdC2PE4GCSsKLRO9-Ea8TQjd-60NvHzfaqYlKtdkS0"
JWT_STAGING="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdGFnaW5nLWNsaWVudC1rZXkiLCJjbGllbnQtaWQiOiJzdGFnaW5nX2NsaWVudCIsImV4cCI6MjIwODk4ODgwMH0.b0hPdmtVdLiqFKhfPkqWgjbw__2JityYKwt732reZjc"
JWT_PERF="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJwZXJmLWNsaWVudC1rZXkiLCJjbGllbnQtaWQiOiJwZXJmX2NsaWVudCIsImV4cCI6MjIwODk4ODgwMH0.TMfEAl00t2ptHt7DBT4HhXqALrPckLeAEcZ9q83XHQE"

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

echo "---- dev via JWT claim client-id=dev_client ----"
curl "${CURL_OPTS[@]}" -H "Authorization: Bearer ${JWT_DEV}" "${PROXY}/api/orders" | head -n 20
echo

echo "---- prod via JWT claim client-id=prod_client ----"
curl "${CURL_OPTS[@]}" -H "Authorization: Bearer ${JWT_PROD}" "${PROXY}/api/orders" | head -n 20
echo

echo "---- qa via JWT claim client-id=qa_client ----"
curl "${CURL_OPTS[@]}" -H "Authorization: Bearer ${JWT_QA}" "${PROXY}/api/orders" | head -n 20
echo

echo "---- staging via JWT claim client-id=staging_client ----"
curl "${CURL_OPTS[@]}" -H "Authorization: Bearer ${JWT_STAGING}" "${PROXY}/api/orders" | head -n 20
echo

echo "---- perf via JWT claim client-id=perf_client ----"
curl "${CURL_OPTS[@]}" -H "Authorization: Bearer ${JWT_PERF}" "${PROXY}/api/orders" | head -n 20
echo

echo "---- default header overrides JWT client-id ----"
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
