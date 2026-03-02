local typedefs = require "kong.db.schema.typedefs"

return {
  -- Plugin id as referenced by Kong config:
  -- plugins:
  -- - name: dynamic-routing
  name = "dynamic-routing",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          -- Lookup table: selector value -> kong upstream name.
          { upstreams = {
              type = "map",
              required = true,
              keys = { type = "string" },
              values = { type = "string" },
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
                { header_name = { type = "string", required = false } },
                { query_param_name = { type = "string", required = false } },
              },
            }
          },
          -- Endpoint policy selectors.
          { endpoint = {
              type = "record",
              required = false,
              fields = {
                { sni = { type = "boolean", required = false, default = false } },
                { header_name = { type = "string", required = false } },
                { query_param_name = { type = "string", required = false } },
              },
            }
          },
          -- Final fallback selector source before consumer fallback.
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
