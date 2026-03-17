# dynamic-routing (Kong)

Request-driven upstream selection plugin for Kong Gateway.

## What It Does

The plugin selects a Kong upstream at request time by mapping selector values from request context to `config.upstreams`.

When a selector value matches a key in `config.upstreams`, the plugin routes with `kong.service.set_upstream(...)`.

If no selector matches, Kong continues with the service default upstream.

## Scope

The plugin can be applied at:

- global
- service
- route

## Request-Time Behavior

Runs in `access` phase and evaluates selectors in strict order:

1. `upstream_header_name` (default `X-Upstream-Env`)
2. `access_policy` selectors (`sni -> header_name -> query_param_name`)
3. `endpoint` selectors (`sni -> header_name -> query_param_name`)
4. authenticated `consumer.username` fallback (forwarded as `client_id`)

On first match, routing is updated and evaluation stops.

## Configuration

All fields are under `plugins[].config`.

- `upstreams` (`map<string,string>`, required)
  - selector key -> Kong upstream name
- `upstream_header_name` (`string`, required, default `X-Upstream-Env`)
  - highest-priority header selector
- `access_policy` (`record`, optional)
  - selectors: `sni`, `header_name`, `query_param_name`
- `endpoint` (`record`, optional)
  - selectors: `sni`, `header_name`, `query_param_name`
  - header used when forwarding resolved consumer username

## Example

```yaml
plugins:
- name: dynamic-routing
  service: orders-service
  config:
    upstream_header_name: X-Upstream-Env
    upstreams:
      dev: orders-api-dev-upstream
      qa: orders-api-qa-upstream
      prod: orders-api-prod-upstream
      qa-client-app: orders-api-qa-upstream
    access_policy:
      sni: true
      header_name: X-Upstream-Env-AP
      query_param_name: apUpsByQP
    endpoint:
      sni: true
      header_name: X-Upstream-Env-EP
      query_param_name: epUpsByQP
```

## Observability

When an upstream is selected, the plugin stores decision metadata in `kong.ctx.plugin`:

- `upstream_backend_id`
- `upstream_selector_reason`
- `upstream_selector_key`

## Reference

Repository-level setup and local run instructions are in `/README.md`.
