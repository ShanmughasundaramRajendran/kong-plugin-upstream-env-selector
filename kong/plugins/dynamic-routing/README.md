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

It is not supported at consumer level.

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
2. `access_policy.sni`
3. `access_policy.header_name`
4. `access_policy.query_param_name`
5. `endpoint.sni`
6. `endpoint.header_name`
7. `endpoint.query_param_name`
8. authenticated `consumer.username` (also forwarded as `client_id_header_name`, default: `X-Client-Id`)

`access_policy` selectors are always evaluated before `endpoint` selectors.

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
- `access_policy`:
  - Type: `record`
  - Required: `false`
  - Fields:
    - `sni` (`boolean`, default `false`)
    - `header_name` (`string`, non-empty if set)
    - `query_param_name` (`string`, non-empty if set)
  - Validation: if provided, at least one of `sni/header_name/query_param_name` must be configured
- `endpoint`:
  - Type: `record`
  - Required: `false`
  - Fields:
    - `sni` (`boolean`, default `false`)
    - `header_name` (`string`, non-empty if set)
    - `query_param_name` (`string`, non-empty if set)
  - Validation: if provided, at least one of `sni/header_name/query_param_name` must be configured
- `client_id_header_name`:
  - Type: `string`
  - Required: `true`
  - Default: `X-Client-Id`
  - Purpose: header used to forward resolved `consumer.username` upstream
- `introspection_header_name`:
  - Type: `string`
  - Required: `false`
  - Default: `X-Kong-Introspection-Response`
  - Note: currently not used for routing decisions

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
2. Else, if `access_policy.sni = true` and TLS SNI is `qa` and `qa` exists in `upstreams`, route to `orders-api-qa-upstream`.
3. Else, if `access_policy.header_name = X-Upstream-Env-AP` and that header value is `prod`, route to `orders-api-prod-upstream`.
4. Else, if `access_policy.query_param_name = apUpsByQP` and query value is `qa`, route to `orders-api-qa-upstream`.
5. Else, evaluate `endpoint` selectors in the same order (`sni` -> `header` -> `query`).
6. Else, if authenticated consumer exists and `consumer.username = qa-client-app`, route to `orders-api-qa-upstream`.
7. Else, use service default upstream.

## Config Shape

```yaml
plugins:
- name: dynamic-routing
  service: my-service
  config:
    upstream_header_name: X-Upstream-Env
    client_id_header_name: X-Client-Id
    upstreams:
      dev: my-svc-dev-upstream
      qa: my-svc-qa-upstream
      prod: my-svc-prod-upstream
      qa-client-app: my-svc-qa-upstream
    access_policy:
      sni: true
      header_name: X-Upstream-Env-AP
      query_param_name: apUpsByQP
    endpoint:
      sni: false
      header_name: X-Upstream-Env-EP
      query_param_name: epUpsByQP
```

For client-id based routing, ensure your auth plugin resolves an authenticated consumer so `kong.client.get_consumer().username` is available in `access` phase.

## Unit Tests

```bash
pongo up
make test
```
