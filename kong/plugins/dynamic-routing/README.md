# dynamic-routing (Kong)

Request-driven upstream selector plugin for Kong.

Repository-level setup and commands:
`/README.md`

## Priority Order

The plugin evaluates selectors in this order:

1. `X-Upstream-Header`
2. `access_policy.sni` for service-context-root access policy
3. `access_policy.header_name` for service-context-root access policy
4. `access_policy.query_param_name` for service-context-root access policy
5. `endpoint.sni` for endpoint-subpath policy
6. `endpoint.header_name` for endpoint-subpath policy
7. `endpoint.query_param_name` for endpoint-subpath policy
8. `X-Client-Id`; if missing, authenticated consumer tag `upstream_env:<key>`; then JWT claim `client_id` from `Authorization` (then authenticated consumer fields as fallback)

When a selector value matches a key in `config.upstreams`,
`kong.service.set_upstream(<mapped_upstream_name>)` is called.

If nothing matches, the plugin does not block. Kong uses service default routing.

`access_policy` is intended for the service context root portion of the request path. `endpoint` is intended for the remaining endpoint/resource subpath. Their selector priority order stays unchanged: access-policy selectors are still evaluated before endpoint-policy selectors.

## Config Shape

```yaml
plugins:
- name: dynamic-routing
  service: my-service
  config:
    upstream_header_name: X-Upstream-Header
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
      header_name: X-Upstream-Env-AP
      query_param_name: apUpsByQP

    endpoint:
      sni: false
      header_name: X-Upstream-Env-EP
      query_param_name: epUpsByQP
```

If you enable Kong `jwt` auth, keep consumer credentials and signed tokens aligned:

- JWT `iss` must match the consumer JWT key.
- JWT payload should include `client_id` claim (for this plugin to map).
- Optional and recommended: set consumer tags in Kong as `upstream_env:<key>` to maintain environment mapping in consumer application configuration.

## Unit Tests

```bash
pongo up
make test
```
