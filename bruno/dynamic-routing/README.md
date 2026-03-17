# Dynamic Routing Bruno Guide

This collection validates core upstream selection behavior for the `dynamic-routing` plugin.

## Prerequisites

1. Start local stack:
   `make compose-up`
2. Use Bruno environment:
   `bruno/dynamic-routing/environments/local.bru`
3. For SNI scenario (`07`), add host entry:
   `127.0.0.1 access-sni-dev.local`
4. For SNI scenario, disable TLS cert verification in Bruno.
5. Client-id fallback routing is based on authenticated `consumer.username`.

## Test Suite Order (`01-Req` -> `07-Req`)

| Order | Request File | Scenario | Expected Backend (`environment.ECHO_RESPONSE`) |
|---|---|---|---|
| 01 | `01-Req-Default-Route-No-Selectors.bru` | No selector values | `it` |
| 02 | `02-Req-Default-Header-To-Dev.bru` | Default header `X-Upstream-Env=dev` | `dev` |
| 03 | `03-Req-Default-Header-Overrides-All.bru` | Default header precedence over access/endpoint selectors | `qa` |
| 04 | `04-Req-Access-Header-Over-Query.bru` | Access policy header `X-Upstream-Env-AP` over query `apUpsByQP` | `qa` |
| 05 | `05-Req-Access-Query-Over-Endpoint-Header.bru` | Access policy query `apUpsByQP` over endpoint header `X-Upstream-Env-EP` | `dev` |
| 06 | `06-Req-Endpoint-Header-Over-Query.bru` | Endpoint policy header `X-Upstream-Env-EP` over query `epUpsByQP` | `qa` |
| 07 | `07-Req-Endpoint-Query-To-Dev.bru` | SNI selector routing (`access-sni-dev.local`) | `dev` |

## Route Shape Used In This Suite

- Route path: `/private/684130/developer-platform/gateway/clients`

## Notes

- Each request contains Bruno `tests` for status `200` and backend assertion.
- If expected backend does not match, verify Kong is up and the `local` environment is selected.
- Client-id fallback uses authenticated `consumer.username` and forwards it upstream as `client_id`.
