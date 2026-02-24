#!/usr/bin/env bash
set -euo pipefail

REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${REDIS_PORT:-6379}"

echo "Seeding redis keys on ${REDIS_HOST}:${REDIS_PORT}"
redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" SET upstream:dev orders-api-dev-upstream
redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" SET upstream:prod orders-api-prod-upstream
echo "Done."
