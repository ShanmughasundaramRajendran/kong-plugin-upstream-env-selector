local typedefs = require "kong.db.schema.typedefs"

return {
  -- Plugin id as referenced by Kong config:
  -- plugins:
  -- - name: dynamic-routing
  name = "dynamic-routing",
  fields = {
    -- Scope: can be applied globally, per-service, or per-route.
    -- It is intentionally not valid as a consumer-scoped plugin.
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          -- Lookup table: selector value -> backend target in `host:port` format.
          -- Example:
          -- upstreams = {
          --   dev = "orders_api_dev:8080",
          --   qa  = "orders_api_qa:8080",
          -- }
          { upstreams = {
              type = "map",
              required = true,
              len_min = 1,
              keys = { type = "string" },
              values = { type = "string", len_min = 1 },
            }
          },
          -- Highest-priority request header.
          { upstream_header_name = { type = "string", required = true, default = "X-Upstream-Env" } },
          -- Access policy selectors (evaluated before endpoint selectors).
          { access_policy = {
              type = "record",
              required = false,
              fields = {
                { sni = { type = "boolean", required = false, default = false } },
                { header_name = { type = "string", required = false, len_min = 1 } },
                { query_param_name = { type = "string", required = false, len_min = 1 } },
              },
            }
          },
          -- Endpoint policy selectors.
          { endpoint = {
              type = "record",
              required = false,
              fields = {
                { sni = { type = "boolean", required = false, default = false } },
                { header_name = { type = "string", required = false, len_min = 1 } },
                { query_param_name = { type = "string", required = false, len_min = 1 } },
              },
            }
          },
        },
      }
    },
  },
}
