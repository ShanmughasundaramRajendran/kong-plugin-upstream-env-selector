# kong-plugin-dynamic-routing

Kong plugin + local demo stack + test suites for request-based upstream selection.

Plugin-level docs:
`kong/plugins/dynamic-routing/README.md`

## How It Works

This plugin overrides which upstream a request is routed to by mapping selector values from request context to entries in `config.upstreams`.

Per request:

1. Evaluate selectors in strict order.
2. Extract selector value from request (header/query/SNI/consumer).
3. If selector value exists as a key in `config.upstreams`, call `kong.service.set_upstream(...)`.
4. Stop at first match.
5. If nothing matches, continue with service default upstream.

### Routing Priority

1. `upstream_header_name` (default `X-Upstream-Env`)
2. `sni`
3. `header_name`
4. `query_param_name`
5. authenticated `consumer.username` (forwarded upstream as `X-Client-Id` by default)

### Selector Matching Examples

Given:

```yaml
upstreams:
  dev: orders-api-dev-upstream
  qa: orders-api-qa-upstream
  prod: orders-api-prod-upstream
  qa-client-app: orders-api-qa-upstream
```

1. If `X-Upstream-Env=dev`, route to `orders-api-dev-upstream`.
2. Else if `sni=true` and TLS SNI is `qa`, route to `orders-api-qa-upstream`.
3. Else if `header_name=X-Upstream-Selector` and header value is `prod`, route to `orders-api-prod-upstream`.
4. Else if `query_param_name=upsByQP` and query value is `qa`, route to `orders-api-qa-upstream`.
5. Else if authenticated `consumer.username=qa-client-app`, route to `orders-api-qa-upstream`.
6. Else service default upstream is used.

### Plugin Config Fields

Defined in [`schema.lua`](/Users/shanmughasundaramrajendran/kong-plugin-upstream-env-selector/kong/plugins/dynamic-routing/schema.lua):

- `upstreams`: required map of selector key -> upstream name (must have at least one entry)
- `upstream_header_name`: required string, default `X-Upstream-Env`
- `sni`: optional boolean selector flag (default `false`)
- `header_name`: optional non-empty selector header name
- `query_param_name`: optional non-empty selector query parameter name
- `client_id_header_name`: required string, default `X-Client-Id` (forwarding header for resolved consumer username)

For detailed plugin docs, see [plugin README](/Users/shanmughasundaramrajendran/kong-plugin-upstream-env-selector/kong/plugins/dynamic-routing/README.md).

## Local Stack

```bash
make compose-up
```

Endpoints:

- Proxy: `http://localhost:8000`
- Admin API: `http://localhost:8001`
- Dev echo backend: `http://localhost:8080`
- Prod echo backend: `http://localhost:8081`
- QA echo backend: `http://localhost:8082`
- IT echo backend: `http://localhost:8083`
- Perf echo backend: `http://localhost:8084`

Declarative config used by docker compose:

- [config/kong.yml](/Users/shanmughasundaramrajendran/kong-plugin-dynamic-routing/config/kong.yml)

Notes:

- Dynamic-routing resolves `client_id` from `kong.client.get_consumer().username`.

## Local JWT Credentials

Client credentials for local token generation:

- `neutral_client` / `neutral-client-secret`
- `dev_client` / `dev-client-secret`
- `qa_client` / `qa-client-secret`
- `it_client` / `it-client-secret`
- `perf_client` / `perf-client-secret`

Get token example:

```bash
examples/scripts/get_keycloak_token.sh it_client
```

Stop stack:

```bash
make compose-down
```

Full cleanup (containers/volumes + local built image):

```bash
make clean
```

## Test Commands

Install JS deps:

```bash
make npm-install
```

Mocha functional tests:

```bash
make test-functional
```

Pongo unit tests:

```bash
make test
```

Pongo integration tests:

```bash
make test-integration
```

Run all suites:

```bash
make test-all
```

## Bruno Collection

- `bruno/dynamic-routing/bruno.json`
- `bruno/dynamic-routing/environments/local.bru`
- customer run guide: [bruno/dynamic-routing/README.md](/Users/shanmughasundaramrajendran/kong-plugin-upstream-env-selector/bruno/dynamic-routing/README.md)
- requests `01..07` (`01-Req-...` naming):
- default route behavior with no selectors
- default header routing and default-header-overrides-all precedence
- configured selector header/query precedence
- explicit `X-Client-Id` ignored for routing
- selector SNI routing
- local declarative config uses one service and single selector set (`sni/header_name/query_param_name`)

SNI Bruno setup:

1. Add host entries:
   `127.0.0.1 access-sni-dev.local`
2. Use HTTPS URLs from `local.bru`:
   - `https://access-sni-dev.local:8443`
3. In Bruno, disable TLS cert validation for local self-signed certs.

Client-id mappings in `config/kong.yml` include:

- `dev_client` -> `dev`
- `prod_client` -> `prod`
- `qa_client` -> `qa`
- `it_client` -> `it`
- `perf_client` -> `perf`

Kong consumer apps declared in `config/kong.yml`:

- `dev-client-app`
- `prod-client-app`
- `qa-client-app`
- `it-client-app`
- `perf-client-app`
- `neutral-client-app` (auth-only token used for non-client_id selector tests)

## Useful Overrides

- `BASE_URL` (default `http://localhost:8000`)
- `ROUTE_PATH` (default `/private/684130/developer-platform/gateway/clients`)
- `PONGO_KONG_IMAGE` (default `kong/kong-gateway:latest`)
