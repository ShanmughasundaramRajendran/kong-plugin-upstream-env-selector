# Dynamic Routing Bruno Guide

This collection validates upstream selection precedence for the `dynamic-routing` plugin.

## Prerequisites

1. Start local stack:
   `make compose-up`
2. Use Bruno environment:
   `bruno/dynamic-routing/environments/local.bru`
3. For SNI scenarios (`12`, `13`), add host entries:
   `127.0.0.1 access-sni-dev.local endpoint-sni-qa.local`
4. For SNI scenarios, disable TLS cert verification in Bruno.
5. Consumer application mapping is maintained using consumer tag format:
   `upstream_env:<env>` (for example `upstream_env:it`).

## Run Order And Expected Result

| Order | Request File | Scenario | Expected Backend (`environment.ECHO_RESPONSE`) |
|---|---|---|---|
| 01 | `01-Req-Default-Route-No-Selectors.bru` | No selector values | `it` |
| 02 | `02-Req-Default-Header-To-Dev.bru` | Default header `X-Upstream-Env=dev` | `dev` |
| 03 | `03-Req-Default-Header-Overrides-All.bru` | Default header precedence over all selectors | `qa` |
| 04 | `04-Req-Access-Header-Over-Query.bru` | Access header over access query | `qa` |
| 05 | `05-Req-Access-Query-Over-Endpoint-Header.bru` | Access query over endpoint header | `dev` |
| 06 | `06-Req-Endpoint-Header-Over-Query.bru` | Endpoint header over endpoint query | `qa` |
| 07 | `07-Req-Endpoint-Query-To-Dev.bru` | Endpoint query fallback | `dev` |
| 08 | `08-Req-Fallback-Invalid-Selectors-To-Endpoint-Query.bru` | Invalid higher selectors fall through to valid lower selector | `qa` |
| 09 | `09-Req-JWT-ClientId-To-IT.bru` | OIDC introspection `client_id` routing | `it` |
| 10 | `10-Req-ClientId-Header-To-Perf.bru` | Explicit `X-Client-Id` routing | `perf` |
| 11 | `11-Req-Access-Selector-Over-ClientId-And-JWT.bru` | Selector precedence over OIDC `client_id` and `X-Client-Id` | `dev` |
| 12 | `12-Req-Access-Policy-SNI-To-Dev.bru` | Access-policy SNI routing | `dev` |
| 13 | `13-Req-Endpoint-Policy-SNI-To-QA.bru` | Endpoint-policy SNI routing | `qa` |
| 14 | `14-Req-Consumer-Tag-Over-JWT-Claim.bru` | Consumer `upstream_env` fallback when no selector and no introspection header | `it` |

## Notes

- Each request contains Bruno `tests` for status `200` and backend assertion.
- If expected backend does not match, verify Kong is up and the `local` environment is selected.
