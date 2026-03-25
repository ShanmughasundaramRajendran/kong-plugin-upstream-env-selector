# Dynamic Routing: Customer Janus vs Our Kong Plugin

This document compares the customer-provided Janus implementation with our Kong plugin implementation, and explains what we improved and why it adds value.

## Sources Compared

- Customer handler: `/Users/shanmughasundaramrajendran/Downloads/upstream-test-case/handler/handler.txt`
- Customer schema: `/Users/shanmughasundaramrajendran/Downloads/upstream-test-case/handler/schema.txt`
- Our handler: `kong/plugins/dynamic-routing/handler.lua`
- Our schema: `kong/plugins/dynamic-routing/schema.lua`

## Executive Summary

We preserved the customer intent (dynamic upstream selection by request context), but improved the implementation in ways that make behavior more deterministic, easier to operate, and safer to evolve:

1. Clear, explicit precedence with early exit.
2. Stronger config contract and simpler upstream mapping (`host:port`).
3. Better resilience against invalid/missing inputs.
4. Better observability (`reason`, `key`, `backend_id` stored in plugin context).
5. Better verification depth (schema, unit, integration, functional, Bruno scenarios).

## Detailed Comparison

| Area | Customer Janus Implementation | Our Kong Plugin Implementation | Value Added |
|---|---|---|---|
| Gateway runtime | Janus-specific APIs (`janus.*`) | Kong-native APIs (`kong.request`, `kong.service.set_target`) | First-class fit for Kong runtime and lifecycle. |
| Selector precedence | Implemented, but spread across imperative flow | Explicit staged flow: default header -> access policy -> endpoint policy -> consumer username | Easier to reason about, audit, and debug. |
| Upstream model | Pulls complex upstream object (`upstream.servers[1].host/port`) from endpoint metadata | Direct config mapping: `selector -> "host:port"` parsed at runtime | Simpler onboarding and lower config drift risk. |
| Input validation | Basic config checks | Defensive checks for config shape and value types at each step | Fewer runtime surprises from malformed inputs. |
| Policy validation | Combined validation gate in `validate_inputs` | Per-policy resolver gracefully skips invalid policy blocks without breaking others | Higher fault tolerance and partial-config safety. |
| Multi-value safety | Default header supports list in Janus form | Utility helpers normalize and guard non-empty values | Cleaner handling of edge-case request payloads. |
| Observability | Logs + shared upstream id | `kong.ctx.plugin` stores `upstream_backend_id`, `upstream_selector_reason`, `upstream_selector_key` | Better production debugging and root-cause analysis. |
| Consumer fallback | `janus.client.get_authenticated_client_id()` | Authenticated `consumer.username` fallback, also propagated upstream as `client_id` header | Better downstream traceability of routed identity. |
| Schema contract | Janus model definitions with generic fields | Kong schema with explicit plugin scope and typed config structure | Stronger platform alignment and validation clarity. |
| Test strategy | Not bundled in customer snippet | Schema + unit + integration + functional + Bruno scenarios | Higher confidence and safer refactoring. |

## Best Practices We Implemented

### 1) Deterministic Decision Flow

- First-match-wins with strict ordering.
- Each decision point returns immediately after selecting target.
- No hidden fallback branches.

Why this matters:
- Predictable behavior under mixed selector inputs.
- Easier production incident triage.

### 2) Single-Source Upstream Target (`host:port`)

- `config.upstreams` now directly stores routable targets in `host:port`.
- Parser supports standard host format and bracketed IPv6.
- Invalid target formats fail safe (no override) instead of partial routing.

Why this matters:
- Less config duplication.
- Lower chance of host/port mismatch.

### 3) Graceful Degradation Instead of Hard Failure

- Missing/invalid config branches are logged and skipped safely.
- Invalid policy block does not block other valid policy blocks.
- If no match exists, request continues with service default upstream.

Why this matters:
- Better reliability during phased rollout and partial config updates.

### 4) First-Class Observability

On successful override we capture:

- `upstream_backend_id` (`host:port`)
- `upstream_selector_reason` (`default_header`, `access_policy_*`, `endpoint_*`, `client_id`)
- `upstream_selector_key` (matched selector value)

Why this matters:
- Direct mapping from request to routing reason.
- Faster mean-time-to-debug.

### 5) Kong-Native Contract and Scope

- Schema explicitly disables consumer-scoped application (`typedefs.no_consumer`).
- HTTP protocol scoping is explicit.
- Config shape is validated by Kong schema layer.

Why this matters:
- Avoids unsupported attachment patterns.
- Keeps plugin usage aligned with intended runtime semantics.

### 6) Strong Verification Strategy

Current verification layers:

1. Schema tests: `spec/dynamic-routing/01-schema_spec.lua`
2. Unit tests: `spec/dynamic-routing/02-unit_spec.lua`
3. Integration tests: `spec/dynamic-routing/10-integration_spec.lua`
4. Functional pytest: `tests/functional/pytest/test_dynamic_routing.py`
5. Bruno scenarios: `bruno/dynamic-routing/*.bru`

Why this matters:
- Prevents regressions in precedence, fallback, and routing behavior.
- Gives confidence for future enhancements.

## Practical Outcome for Stakeholders

- Easier to configure: fewer moving parts in upstream mapping.
- Easier to operate: explicit selector reason and key in runtime context.
- Easier to extend: modular policy resolver and test-backed behavior.
- Easier to trust in production: deterministic and fail-safe routing decisions.
