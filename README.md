# kong-plugin-dynamic-routing

Kong plugin for request-time upstream selection.

## What The Plugin Does

`dynamic-routing` maps selector values from the incoming request context to backend targets defined in `config.upstreams`.

When a selector matches, it calls `kong.service.set_target(host, port)` and routes to the mapped backend target.
If no selector matches, Kong continues with the service default upstream.

## Scope

The plugin is intended for:

- global
- service
- route

Use case: one route/service fan-out to multiple backend environments (`dev`, `qa`, `prod`, etc.) using deterministic selector precedence.

## Selector Priority

Per request (`access` phase), evaluation order is:

1. `upstream_header_name` (default `X-Upstream-Env`)
2. `access_policy` selectors (`sni -> header_name -> query_param_name`)
3. `endpoint` selectors (`sni -> header_name -> query_param_name`)
4. authenticated `consumer.username` fallback (forwarded upstream as `client_id`)

## Configuration Surface

Defined in [schema.lua](/Users/shanmughasundaramrajendran/kong-plugin-upstream-env-selector/kong/plugins/dynamic-routing/schema.lua):

- `upstreams` (required map): selector key -> backend host
- `upstreams` values must be `host:port` (for example `orders_api_dev:8080`)
- `upstream_header_name` (required string, default `X-Upstream-Env`)
- `access_policy` (optional record): `sni`, `header_name`, `query_param_name`
- `endpoint` (optional record): `sni`, `header_name`, `query_param_name`

## Runtime Metadata

On successful upstream override, the plugin records:

- `kong.ctx.plugin.upstream_backend_id`
- `kong.ctx.plugin.upstream_selector_reason`
- `kong.ctx.plugin.upstream_selector_key`

## References

- Plugin details: [kong/plugins/dynamic-routing/README.md](/Users/shanmughasundaramrajendran/kong-plugin-upstream-env-selector/kong/plugins/dynamic-routing/README.md)
- Request flow walkthrough: [docs/plugin-code-walkthrough.md](/Users/shanmughasundaramrajendran/kong-plugin-upstream-env-selector/docs/plugin-code-walkthrough.md)
- Local declarative config: [config/kong.yml](/Users/shanmughasundaramrajendran/kong-plugin-upstream-env-selector/config/kong.yml)
