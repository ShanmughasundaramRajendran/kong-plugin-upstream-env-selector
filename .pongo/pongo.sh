#!/usr/bin/env bash
set -euo pipefail

KONG_IMAGE="${KONG_IMAGE:-kong/kong-gateway:latest}" pongo run -- -v spec/unit
# Uncomment to run integration tests.
# KONG_IMAGE="${KONG_IMAGE:-kong/kong-gateway:latest}" pongo run -- -v spec/integration
