# upstream-env-selector (Kong)

Production-ready Kong plugin for request-driven upstream selection.

## What it does

Chooses a Kong Upstream dynamically based on request metadata, in this order:

1. Default header `X-Upstream-Env` (supports multi-value header; first match wins)
2. access_policy.sni (TLS SNI)
3. access_policy.header_name
4. access_policy.query_param_name
5. endpoint.sni (TLS SNI)
6. endpoint.header_name
7. endpoint.query_param_name
8. consumer id fallback (`header` or authenticated consumer `custom_id/username/id`)

Then calls `kong.service.set_upstream(<upstream_name>)`.

If nothing matches:
- `strict=false` -> do nothing (Kong routes normally)
- `strict=true`  -> 400

## Mapping sources

### Static map (recommended for per-service/per-route behavior)

Configure `config.upstreams` as a map of selector_value -> kong_upstream_name.

### Redis map (for centralized control)

Enable `use_redis=true` and configure:

- Redis key format: `<redis_key_prefix><selector_value>` -> `upstream_name`
- Includes positive/negative caching using `lua_shared_dict upstream_env_selector_cache`.
- `redis_fail_open=true` (default) leaves default routing if Redis is down (safer).

## Example (DB-less / declarative)

```yaml
plugins:
- name: upstream-env-selector
  service: my-service
  config:
    upstream_header_name: X-Upstream-Env
    strict: false
    normalize: true
    client_id_source: header
    client_id_header_name: X-Consumer-Id

    # Static
    upstreams:
      dev: my-svc-dev
      qa: my-svc-qa
      prod: my-svc-prod

    access_policy:
      sni: true
      header_name: X-Client-Env
      query_param_name: env

    endpoint:
      sni: false
      header_name: X-Resource-Env
      query_param_name: resource_env
```

## Redis example

```yaml
plugins:
- name: upstream-env-selector
  service: my-service
  config:
    use_redis: true
    redis:
      host: redis
      port: 6379
      database: 0
      timeout_ms: 200
      keepalive_ms: 60000
      pool_size: 100
    redis_key_prefix: upstream:
    cache_ttl_sec: 5
    negative_ttl_sec: 2
    redis_fail_open: true
```

Set keys:

```
SET upstream:dev my-svc-dev
SET upstream:prod my-svc-prod
```

## Nginx shared dict

If you use Redis mode (or want caching), add:

```
lua_shared_dict upstream_env_selector_cache 10m;
```

to your Kong nginx template / custom nginx config.

## Run unit tests

```bash
pongo up
make test
```
