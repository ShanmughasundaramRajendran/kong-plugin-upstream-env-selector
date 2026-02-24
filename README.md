# kong-plugin-upstream-env-selector

Repository for the `upstream-env-selector` Kong plugin, local demo stack, and tests.

Plugin reference docs live at:
`kong/plugins/upstream-env-selector/README.md`

## Runtime

- Kong Gateway `latest` (image tag)
- DB-less (declarative config)

## Local Demo

Static map mode:

```bash
make compose-up
make demo
```

Redis map mode:

```bash
make compose-up-redis
make seed-redis
make demo
```

Endpoints:

- Proxy: `http://localhost:8000`
- Admin: `http://localhost:8001`

Demo names used in declarative config:

- Service: `orders-gateway-service`
- Route: `orders-api-route`
- Route path: `/api/orders`
- Upstreams: `orders-api-dev-upstream`, `orders-api-prod-upstream`

## Testing

Unit tests (Pongo/Busted):

```bash
pongo up
make test
pongo down
```

Integration tests (Pongo):

```bash
make test-integration
```

Unit + integration:

```bash
make test-pongo
```

Functional tests (Mocha):

```bash
make npm-install
make test-functional
```

Run all test suites:

```bash
make test-all
```

Optional env overrides:

- `BASE_URL` (default `http://localhost:8000`)
- `ROUTE_PATH` (default `/api/orders`)
- `PONGO_KONG_IMAGE` (default `kong/kong-gateway:latest`)

## Bruno Collection

- `bruno/upstream-env-selector/bruno.json`
- `bruno/upstream-env-selector/environments/local.bru`
- requests `01..06`

## Redis dependency

Redis mode requires `lua-resty-redis` (`resty.redis`).
The included `Dockerfile` installs `curl` and `lua-resty-redis`.
