local typedefs = require "kong.db.schema.typedefs"

return {
  name = "upstream-env-selector",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { upstreams = {
              type = "map",
              required = true,
              keys = { type = "string" },
              values = { type = "string" },
            }
          },
          { upstream_header_name = { type = "string", required = true, default = "X-Upstream-Env" } },
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
