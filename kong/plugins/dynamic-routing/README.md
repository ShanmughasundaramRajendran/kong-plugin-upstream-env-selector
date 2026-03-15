# dynamic-routing (Kong)

Request-driven upstream selection plugin for Kong.

Repository-level setup and commands:
`/README.md`

## Overview

This plugin overrides which upstream a request is routed to by mapping request-derived selector values to upstream names in `config.upstreams`.

Use this when one Kong route/service must fan out traffic to multiple backend environments (for example `dev`, `qa`, `prod`) based on request context such as headers, query params, TLS SNI, and authenticated consumer identity.

## Scope

This plugin can be configured at:

- global level
- service level
- route level
- consumer level
- consumer + route level

## How It Works

For each request in the `access` phase:

1. The plugin evaluates selectors in strict priority order.
2. For each selector, it extracts a value from the request context.
3. It checks whether that value exists as a key in `config.upstreams`.
4. On first match, it calls `kong.service.set_upstream(<mapped_upstream_name>)`.
5. It stores selector metadata in `kong.ctx.shared`:
   - `upstream_backend_id`
   - `upstream_selector_reason`
   - `upstream_selector_key`
6. If no selector matches, the plugin does not block the request and Kong keeps the service default upstream.

### Routing Priority

The plugin evaluates selectors in this exact order:

1. `upstream_header_name` (default: `X-Upstream-Env`)
2. `sni`
3. `header_name`
4. `query_param_name`
5. authenticated `consumer.username` (also forwarded as `client_id_header_name`, default: `X-Client-Id`)

## Plugin Config Reference

All fields below are under `plugins[].config` in `schema.lua`:

- `upstreams`:
  - Type: `map<string,string>`
  - Required: `true`
  - Constraint: at least one entry (`len_min = 1`)
  - Purpose: selector key -> Kong upstream name
- `upstream_header_name`:
  - Type: `string`
  - Required: `true`
  - Default: `X-Upstream-Env`
  - Purpose: highest-priority request header selector
- `sni`:
  - Type: `boolean`
  - Required: `false`
  - Default: `false`
  - Purpose: when enabled, attempt routing by TLS SNI after `upstream_header_name`
- `header_name`:
  - Type: `string`
  - Required: `false`
  - Constraint: non-empty when set
  - Purpose: secondary request header selector
- `query_param_name`:
  - Type: `string`
  - Required: `false`
  - Constraint: non-empty when set
  - Purpose: request query selector
- `client_id_header_name`:
  - Type: `string`
  - Required: `true`
  - Default: `X-Client-Id`
  - Purpose: header used to forward resolved `consumer.username` upstream

## Selector Matching Details

Given:

```yaml
upstreams:
  dev: orders-api-dev-upstream
  qa: orders-api-qa-upstream
  prod: orders-api-prod-upstream
  qa-client-app: orders-api-qa-upstream
```

Matching behavior:

1. If request header `X-Upstream-Env: dev` is present and `dev` is a key in `upstreams`, route to `orders-api-dev-upstream`.
2. Else, if `sni = true` and TLS SNI is `qa` and `qa` exists in `upstreams`, route to `orders-api-qa-upstream`.
3. Else, if `header_name = X-Upstream-Selector` and that header value is `prod`, route to `orders-api-prod-upstream`.
4. Else, if `query_param_name = upsByQP` and query value is `qa`, route to `orders-api-qa-upstream`.
5. Else, if authenticated consumer exists and `consumer.username = qa-client-app`, route to `orders-api-qa-upstream`.
6. Else, use service default upstream.

To model separate endpoint/access-policy behavior, create separate plugin instances with different Kong scopes and selector config (for example `route` for endpoint behavior, `consumer+route` for access-policy behavior). Kong plugin precedence determines which instance applies to a request.

## Config Shape

```yaml
plugins:
- name: dynamic-routing
  service: my-service
  config:
    upstream_header_name: X-Upstream-Env
    client_id_header_name: X-Client-Id
    sni: true
    header_name: X-Upstream-Selector
    query_param_name: upsByQP
    upstreams:
      dev: my-svc-dev-upstream
      qa: my-svc-qa-upstream
      prod: my-svc-prod-upstream
      qa-client-app: my-svc-qa-upstream
```

For client-id based routing, ensure your auth plugin resolves an authenticated consumer so `kong.client.get_consumer().username` is available in `access` phase.

## Unit Tests

```bash
pongo up
make test
```
