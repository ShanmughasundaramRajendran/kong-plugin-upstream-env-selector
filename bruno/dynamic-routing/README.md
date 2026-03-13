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
5. Client-id fallback mapping is based on authenticated `consumer.username`.

## Test Suite Order (`01-Req` -> `14-Req`)

| Order | Request File | Scenario | Expected Backend (`environment.ECHO_RESPONSE`) |
|---|---|---|---|
| 01 | `01-Req-Default-Route-No-Selectors.bru` | No selector values | `it` |
| 02 | `02-Req-Default-Header-To-Dev.bru` | Default header `X-Upstream-Env=dev` | `dev` |
| 03 | `03-Req-Default-Header-Overrides-All.bru` | Default header precedence over all selectors | `qa` |
| 04 | `04-Req-Access-Header-Over-Query.bru` | Access-policy header over access-policy query | `qa` |
| 05 | `05-Req-Access-Query-Over-Endpoint-Header.bru` | Access-policy query over endpoint-policy header | `dev` |
| 06 | `06-Req-Endpoint-Header-Over-Query.bru` | Endpoint-policy header over endpoint-policy query | `qa` |
| 07 | `07-Req-Endpoint-Query-To-Dev.bru` | Endpoint-policy query fallback | `dev` |
| 08 | `08-Req-Fallback-Invalid-Selectors-To-Endpoint-Query.bru` | Invalid access/endpoint selectors fall through to valid endpoint-subpath query | `qa` |
| 09 | `09-Req-JWT-ClientId-To-IT.bru` | Introspection header is ignored when selectors do not match | `it` |
| 10 | `10-Req-ClientId-Header-To-Perf.bru` | Inbound `X-Client-Id` is ignored for routing | `it` |
| 11 | `11-Req-Access-Selector-Over-ClientId-And-JWT.bru` | Selector precedence over introspection/header client-id inputs | `dev` |
| 12 | `12-Req-Access-Policy-SNI-To-Dev.bru` | Access-policy SNI routing | `dev` |
| 13 | `13-Req-Endpoint-Policy-SNI-To-QA.bru` | Endpoint-policy SNI routing | `qa` |
| 14 | `14-Req-Consumer-Tag-Over-JWT-Claim.bru` | Consumer username fallback (token claim does not override routing) | `it` |

## Route Shape Used In This Suite

- Service context root: `/private/684130`
- Endpoint path example: `/developer-platform/gateway/clients`

## Notes

- Each request contains Bruno `tests` for status `200` and backend assertion.
- If expected backend does not match, verify Kong is up and the `local` environment is selected.
