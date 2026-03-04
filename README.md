# kong-plugin-dynamic-routing

Kong plugin + local demo stack + test suites for request-based upstream selection.

Plugin-level docs:
`kong/plugins/dynamic-routing/README.md`

## Routing Priority

The plugin checks selectors in this order and picks the first matching upstream key:

1. `X-Upstream-Env`
2. `access_policy.sni`
3. `access_policy.header_name`
4. `access_policy.query_param_name`
5. `endpoint.sni`
6. `endpoint.header_name`
7. `endpoint.query_param_name`
8. `X-Client-Id` header; if absent, plugin extracts `client_id` from OIDC introspection response header (then authenticated consumer tag/id fallback)

If nothing matches, it does not block the request; Kong keeps default routing.

## Local Stack

```bash
make compose-up
```

Endpoints:

- Proxy: `http://localhost:8000`
- Admin API: `http://localhost:8001`
- Keycloak: `http://localhost:8085`
- Dev echo backend: `http://localhost:8080`
- Prod echo backend: `http://localhost:8081`
- QA echo backend: `http://localhost:8082`
- IT echo backend: `http://localhost:8083`
- Perf echo backend: `http://localhost:8084`

Declarative config used by docker compose:

- [config/kong.yml](/Users/shanmughasundaramrajendran/kong-plugin-dynamic-routing/config/kong.yml)

Notes:

- Local Keycloak is provisioned from `config/keycloak/kong-local-realm.json`.
- OIDC plugin entries point to local Keycloak via `http://host.docker.internal:8085` (from inside Kong container) and use `kong-introspector` client credentials.
- OIDC plugins are `enabled: false` by default; set `enabled: true` in `config/kong.yml` to enforce token validation.
- Dynamic-routing reads `client_id` from the configured introspection response header when `X-Client-Id` is not sent.

## Local Keycloak Credentials

- Admin console: `http://localhost:8085/admin`
- Admin username: `admin`
- Admin password: `admin`
- Realm: `kong-local`
- Introspection client: `kong-introspector`
- Introspection client secret: `kong-introspector-secret`

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
- requests `01..13` (`01-Req-...` naming):
- default route behavior with no selectors
- default header routing and default-header-overrides-all precedence
- access policy header/query precedence
- endpoint policy header/query precedence
- fallback when higher-priority selectors are invalid
- OIDC introspection `client_id` routing and explicit `X-Client-Id` routing
- selector precedence over OIDC-derived `client_id`/`X-Client-Id`
- access-policy SNI routing
- endpoint-policy SNI routing (route `/api/orders-endpoint-sni`)

SNI Bruno setup:

1. Add host entries:
   `127.0.0.1 access-sni-dev.local endpoint-sni-qa.local`
2. Use HTTPS URLs from `local.bru`:
   - `https://access-sni-dev.local:8443`
   - `https://endpoint-sni-qa.local:8443`
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
- `ROUTE_PATH` (default `/api/orders`)
- `PONGO_KONG_IMAGE` (default `kong/kong-gateway:latest`)
