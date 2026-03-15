# Dynamic Routing Plugin: Code Walkthrough

This document explains the end-to-end flow of the `dynamic-routing` Kong plugin in this repository.

## 1. What this plugin does

The plugin picks a Kong upstream at request time using selector inputs from:

1. A default header (`X-Upstream-Env`)
2. Access policy selectors (`sni`, header, query)
3. Endpoint policy selectors (`sni`, header, query)
4. Client identity chain (`X-Client-Id` -> OIDC introspection `client_id` -> consumer tag/id fallback)

If no selector maps to `config.upstreams`, the request is not blocked. Kong uses the service default upstream.

## 2. Where the logic lives

- Schema: `kong/plugins/dynamic-routing/schema.lua`
- Runtime selection logic: `kong/plugins/dynamic-routing/handler.lua`
- Declarative local config example: `config/kong.yml`
- Behavior validation:
  - `spec/dynamic-routing/02-unit_spec.lua`
  - `spec/dynamic-routing/10-integration_spec.lua`
  - `tests/functional/pytest/test_dynamic_routing.py`

## 3. Runtime placement inside Kong

- Plugin priority: `PRIORITY = 800`
- Active phase: `access`
- `rewrite` and `log` phases are intentionally not implemented

Reason: upstream selection must happen before proxying, and typically after auth plugins (for introspection/consumer context).

## 4. Config model (schema-driven)

From `schema.lua`, required and key fields are:

- `config.upstreams` (required map): selector key -> Kong upstream name
- `config.upstream_header_name` (default `X-Upstream-Env`)
- `config.client_id_header_name` (default `X-Client-Id`)
- `config.introspection_header_name` (default `X-Kong-Introspection-Response`)
- `config.access_policy` (optional):
  - `sni` (bool)
  - `header_name` (string)
  - `query_param_name` (string)
- `config.endpoint` (optional):
  - `sni` (bool)
  - `header_name` (string)
  - `query_param_name` (string)

In local `config/kong.yml`, the introspection header is overridden to `X-Introspection-Response` to match the OIDC plugin header forwarding.

## 5. End-to-end request flow

```mermaid
flowchart TD
    A[Incoming request] --> B[dynamic-routing access phase]
    B --> C{Default header matches?<br/>X-Upstream-Env -> upstreams[key]}
    C -- yes --> Z[set_upstream and return]
    C -- no --> D{Access policy match?<br/>sni -> header -> query}
    D -- yes --> Z
    D -- no --> E{Endpoint policy match?<br/>sni -> header -> query}
    E -- yes --> Z
    E -- no --> F[Resolve client_id chain]
    F --> G{X-Client-Id present?}
    G -- yes --> H[Use header value]
    G -- no --> I{Introspection header decodes to JSON client_id?}
    I -- yes --> H
    I -- no --> J{Authenticated consumer exists?}
    J -- yes --> K[Use consumer tag upstream_env:* else custom_id/username/id]
    J -- no --> L[No client_id]
    H --> M{upstreams[client_id] exists?}
    K --> M
    M -- yes --> Z
    M -- no --> N[No override; keep service default route]
    L --> N

    Z --> O[kong.service.set_upstream(mapped_upstream)]
    O --> P[Store debug metadata in kong.ctx.shared]
```

### Sequence representation

```mermaid
sequenceDiagram
    participant Client
    participant Kong
    participant OIDC as openid-connect (optional)
    participant DR as dynamic-routing
    participant Up as Kong Upstream

    Client->>Kong: HTTP request
    Kong->>OIDC: Token/auth processing (if enabled)
    OIDC-->>Kong: Consumer + optional introspection header
    Kong->>DR: access(cfg)
    DR->>DR: Evaluate selector precedence
    alt Selector matched
      DR->>Kong: kong.service.set_upstream(name)
      DR->>Kong: set ctx.shared reason/key/backend_id
    else No selector matched
      DR-->>Kong: no override
    end
    Kong->>Up: Proxy request to selected/default upstream
    Up-->>Client: Response
```

## 6. Selector precedence (exact order)

The handler uses this strict order and exits on first successful match:

1. `upstream_header_name` (default `X-Upstream-Env`)
2. `access_policy.sni`
3. `access_policy.header_name`
4. `access_policy.query_param_name`
5. `endpoint.sni`
6. `endpoint.header_name`
7. `endpoint.query_param_name`
8. `client_id` chain

Important behavior:
- If a higher-priority selector is present but does not exist in `config.upstreams`, the plugin continues to lower priorities.
- Header/query values can be single or multi-value. The plugin picks the first non-empty value that maps to an upstream key.

## 7. Client identity fallback chain

When policy selectors do not match, the plugin resolves `client_id` in this order:

1. Request header `client_id_header_name` (`X-Client-Id` by default)
2. Introspection response header (`introspection_header_name`):
   - Read header value
   - Base64 decode
   - Parse JSON
   - Extract `client_id`
3. Authenticated consumer fallback:
   - First matching tag prefix: `upstream_env:<env>` -> use `<env>`
   - Otherwise use first non-empty from: `custom_id`, `username`, `id`

If a client id value is resolved, the plugin also sets it on upstream request headers using `client_id_header_name`.

## 8. What gets written for observability

On successful upstream override, the plugin stores:

- `kong.ctx.shared.upstream_backend_id` -> mapped upstream name
- `kong.ctx.shared.upstream_selector_reason` -> reason such as `default_header`, `access_policy_header`, `endpoint_query`, `client_id`
- `kong.ctx.shared.upstream_selector_key` -> matched selector key (for example `dev`, `qa_client`)

This helps trace exactly why a request was routed to a specific backend.

## 9. Pseudocode view of `access()`

```text
if cfg invalid or cfg.upstreams missing: return

if match default header:
  set_upstream and return

err = validate_inputs(cfg)
if no err:
  if match access_policy in order sni/header/query:
    set_upstream and return
  if match endpoint in order sni/header/query:
    set_upstream and return

client_id = from X-Client-Id or introspection claim or consumer fallback
if client_id exists:
  add/overwrite X-Client-Id to upstream request
  if cfg.upstreams[client_id] exists:
    set_upstream and return

log debug and keep service default routing
```

## 10. Concrete local example (`config/kong.yml`)

- Service default host: `orders-api-it-upstream`
- If no selectors match, traffic stays on IT backend.
- Example key mappings:
  - `dev` -> `orders-api-dev-upstream`
  - `qa_client` -> `orders-api-qa-upstream`
  - `access-sni-dev.local` -> `orders-api-dev-upstream`

So one request can be routed by:
- `X-Upstream-Env: dev`
- or `X-Upstream-Env-AP: dev`
- or `?epUpsByQP=dev`
- or `X-Client-Id: qa_client`
- or introspection payload containing `{"client_id":"perf_client"}`

## 11. Why this design is predictable

- Deterministic precedence: first matching rule wins.
- Non-breaking fallback: no match does not fail request.
- Kong-native upstream switching: uses named upstreams (`kong.service.set_upstream`).
- Test-backed behavior: schema + unit + integration + functional suites validate precedence and fallback.

## 12. Quick debugging checklist

1. Confirm plugin is attached to the service/route being hit.
2. Confirm selector key exists in `config.upstreams` exactly.
3. Confirm higher-priority selectors are not unintentionally set.
4. For introspection-based routing, verify header name alignment between OIDC plugin and `introspection_header_name`.
5. Check `kong.ctx.shared` fields (or logs) for selector reason and key.
