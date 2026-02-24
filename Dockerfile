FROM kong/kong-gateway:latest

USER root

# Keep curl available for local debug/health checks in container shell.
RUN set -eux; \
  if command -v apk >/dev/null 2>&1; then \
    apk add --no-cache curl ca-certificates; \
  elif command -v apt-get >/dev/null 2>&1; then \
    apt-get update; \
    apt-get install -y --no-install-recommends curl ca-certificates; \
    rm -rf /var/lib/apt/lists/*; \
  elif command -v microdnf >/dev/null 2>&1; then \
    microdnf install -y curl ca-certificates; \
    microdnf clean all; \
  fi

USER kong
