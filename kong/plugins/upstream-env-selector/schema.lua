local typedefs = require "kong.db.schema.typedefs"

return {
  name = "upstream-env-selector",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          -- Map of selector_value -> kong_upstream_name (static mode)
          { upstreams = {
              type = "map",
              required = false,
              keys = { type = "string" },
              values = { type = "string" },
            }
          },

          -- Optional dynamic mapping via Redis:
          -- key format: <redis_key_prefix><selector_value> -> upstream_name
          { use_redis = { type = "boolean", required = true, default = false } },
          { redis = {
              type = "record",
              required = false,
              fields = {
                { host = { type = "string", required = true, default = "127.0.0.1" } },
                { port = { type = "number", required = true, default = 6379 } },
                { username = { type = "string", required = false } },
                { password = { type = "string", required = false } },
                { database = { type = "number", required = true, default = 0 } },
                { ssl = { type = "boolean", required = true, default = false } },
                { ssl_verify = { type = "boolean", required = true, default = false } },
                { timeout_ms = { type = "number", required = true, default = 200 } },
                { keepalive_ms = { type = "number", required = true, default = 60000 } },
                { pool_size = { type = "number", required = true, default = 100 } },
              },
            }
          },
          { redis_key_prefix = { type = "string", required = true, default = "upstream:" } },

          -- Default selector header
          { upstream_header_name = { type = "string", required = true, default = "X-Upstream-Env" } },

          -- Access policy (client metadata)
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

          -- Endpoint policy (resource metadata)
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

          -- Last priority (client_id) mapping:
          -- Source can be authenticated consumer fields or request header.
          { client_id_source = {
              type = "string",
              required = true,
              default = "header",
              one_of = { "header", "custom_id", "username", "id" },
            }
          },
          { client_id_header_name = {
              type = "string",
              required = true,
              default = "X-Consumer-Id",
            }
          },

          -- If true: enforce that selected key must exist in mapping.
          -- If false: if no match found, do nothing (Kong keeps normal routing).
          { strict = { type = "boolean", required = true, default = false } },

          -- Normalize selector value (trim + lowercase)
          { normalize = { type = "boolean", required = true, default = true } },

          -- Caching & resilience
          { cache_ttl_sec = { type = "number", required = true, default = 5 } },   -- positive cache TTL
          { negative_ttl_sec = { type = "number", required = true, default = 2 } }, -- cache misses briefly
          { redis_fail_open = { type = "boolean", required = true, default = true } }, -- fail open (default routing) on redis errors
        },

        entity_checks = {
          -- Must have upstreams map unless redis mode is enabled
          { conditional = {
              if_field = "use_redis", if_match = { eq = false },
              then_field = "upstreams", then_match = { required = true },
            }
          },
        },
      }
    },
  },
}
