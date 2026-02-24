#!/usr/bin/env bash
set -euo pipefail

PROXY="${PROXY:-http://localhost:8000}"
CURL_OPTS=(--retry 20 --retry-delay 1 --retry-connrefused -s -D -)

echo "---- dev via X-Upstream-Env ----"
curl "${CURL_OPTS[@]}" -H "X-Upstream-Env: dev" "${PROXY}/api/orders" | head -n 20
echo

echo "---- prod via X-Upstream-Env ----"
curl "${CURL_OPTS[@]}" -H "X-Upstream-Env: prod" "${PROXY}/api/orders" | head -n 20
echo

echo "---- dev via client query param (?env=dev) ----"
curl "${CURL_OPTS[@]}" "${PROXY}/api/orders?env=dev" | head -n 20
echo

echo "---- prod via resource header X-Resource-Env ----"
curl "${CURL_OPTS[@]}" -H "X-Resource-Env: prod" "${PROXY}/api/orders" | head -n 20
echo

echo "---- dev via consumer id header X-Consumer-Id ----"
curl "${CURL_OPTS[@]}" -H "X-Consumer-Id: dev" "${PROXY}/api/orders" | head -n 20
echo
