## Runtime
- Kong Gateway **latest** (image tag)
- **DB-less** (declarative config)

# Kong Plugin: upstream-env-selector

This plugin selects the upstream dynamically based on request metadata:
`X-Upstream-Env` has highest priority, then policy selectors, then consumer id fallback.

## Demo Route and Service (meaningful naming)
The demo config now uses:
- Service: `orders-gateway-service`
- Route: `orders-api-route`
- Route path: `/api/orders`
- Upstreams: `orders-api-dev-upstream`, `orders-api-prod-upstream`

## Selection Priority
1. `X-Upstream-Env`
2. `access_policy.sni`
3. `access_policy.header_name`
4. `access_policy.query_param_name`
5. `endpoint.sni`
6. `endpoint.header_name`
7. `endpoint.query_param_name`
8. Consumer id fallback (`header|custom_id|username|id`)

## Mapping Modes
- Static map: `config.upstreams`
- Redis map: `use_redis=true`, key format `<redis_key_prefix><selector>`

## Consumer ID Header Fallback
- `client_id_source: header` uses request header as final selector.
- `client_id_header_name` controls header key (default `X-Consumer-Id`).
- Demo config uses:
  - `client_id_source: header`
  - `client_id_header_name: X-Consumer-Id`

## Local Demo
### Static map
```bash
make compose-up
make demo
```

### Redis map
```bash
make compose-up-redis
make seed-redis
make demo
```

Kong endpoints:
- Proxy: `http://localhost:8000`
- Admin: `http://localhost:8001`

## Tests
### Unit tests (Pongo/Busted)
```bash
pongo up
make test
pongo down
```
Default Pongo base image is `kong/kong-gateway:latest` via `PONGO_KONG_IMAGE`.

### Integration tests (Pongo)
```bash
make test-integration
```

### Pongo suite (unit + integration)
```bash
make test-pongo
```

### Functional tests (Mocha)
- `test/functional/mocha/upstream_env_selector/upstream_env_selector_test.js`

Run with compose stack up:
```bash
make npm-install
make test-functional
```

Run everything:
```bash
make test-all
```

Optional env overrides:
- `BASE_URL` (default `http://localhost:8000`)
- `ROUTE_PATH` (default `/api/orders`)
- `PONGO_KONG_IMAGE` (default `kong/kong-gateway:latest`)

Example:
```bash
make test-functional BASE_URL=http://localhost:8000 ROUTE_PATH=/api/orders
```

## Bruno Collection
- `bruno/upstream-env-selector/bruno.json`
- `bruno/upstream-env-selector/environments/local.bru`
- request files `01..06` for header/query/consumer-id/strict checks

## Redis dependency
Redis mode requires `lua-resty-redis` (`resty.redis`).
The included `Dockerfile` installs `curl` + `lua-resty-redis` in the Kong image.

## Function Hints (`handler.lua`)
- `normalize(cfg, v)`:
  Converts selectors to a stable format (trim + optional lowercase) so map lookups are deterministic.
- `get_selector_from_header(cfg, header_name)`:
  Reads a header as single or multi-value selector and normalizes all values.
- `validate_inputs(cfg)`:
  Checks plugin config shape and required policy values before selection logic continues.
- `get_client_id(cfg)`:
  Resolves fallback selector from request header (`X-Consumer-Id` by default) or authenticated consumer fields (`custom_id`, `username`, `id`) based on `client_id_source`.
- `lookup_upstream(cfg, upstreams_map, selector_value)`:
  Resolves selector to upstream using static map first, then Redis (with shared-dict cache).
- `_M:access(cfg)`:
  Main selector pipeline; executes priority order, sets upstream on first match, and enforces strict mode.
