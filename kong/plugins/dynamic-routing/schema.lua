local typedefs = require "kong.db.schema.typedefs"

return {
  -- Plugin id as referenced by Kong config:
  -- plugins:
  -- - name: dynamic-routing
  name = "dynamic-routing",
  fields = {
    -- Scope: can be applied globally, per-service, per-route, or per consumer+route.
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          -- Lookup table: selector value -> kong upstream name.
          { upstreams = {
              type = "map",
              required = true,
              len_min = 1,
              keys = { type = "string" },
              values = { type = "string" },
            }
          },
          -- Highest-priority request header.
          { upstream_header_name = { type = "string", required = true, default = "X-Upstream-Env" } },
          -- Selector fields in this plugin instance.
          { sni = { type = "boolean", required = false, default = false } },
          { header_name = { type = "string", required = false, len_min = 1 } },
          { query_param_name = { type = "string", required = false, len_min = 1 } },
          -- Header name used when forwarding resolved client_id upstream.
          { client_id_header_name = {
              type = "string",
              required = true,
              default = "X-Client-Id",
            }
          },
        },
      }
    },
  },
}
