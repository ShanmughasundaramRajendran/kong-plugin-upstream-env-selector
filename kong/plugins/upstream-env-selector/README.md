# upstream-env-selector (Kong)

Request-driven upstream selector plugin for Kong.

Repository-level setup and commands:
`/README.md`

## Priority Order

The plugin evaluates selectors in this order:

1. `X-Upstream-Env`
2. `access_policy.sni`
3. `access_policy.header_name`
4. `access_policy.query_param_name`
5. `endpoint.sni`
6. `endpoint.header_name`
7. `endpoint.query_param_name`
8. `X-Client-Id`; if missing, JWT claim `client-id` from `Authorization` (then authenticated consumer fields as fallback)

When a selector value matches a key in `config.upstreams`,
`kong.service.set_upstream(<mapped_upstream_name>)` is called.

If nothing matches, the plugin does not block. Kong uses service default routing.

## Config Shape

```yaml
plugins:
- name: upstream-env-selector
  service: my-service
  config:
    upstream_header_name: X-Upstream-Env
    client_id_header_name: X-Client-Id

    upstreams:
      dev: my-svc-dev-upstream
      prod: my-svc-prod-upstream
      qa: my-svc-qa-upstream
      dev_client: my-svc-dev-upstream
      prod_client: my-svc-prod-upstream
      qa_client: my-svc-qa-upstream

    access_policy:
      sni: true
      header_name: X-Client-Env
      query_param_name: env

    endpoint:
      sni: false
      header_name: X-Resource-Env
      query_param_name: resource_env
```

If you enable Kong `jwt` auth, keep consumer credentials and signed tokens aligned:

- JWT `iss` must match the consumer JWT key.
- JWT payload should include `client-id` claim (for this plugin to map).

## Unit Tests

```bash
pongo up
make test
```
