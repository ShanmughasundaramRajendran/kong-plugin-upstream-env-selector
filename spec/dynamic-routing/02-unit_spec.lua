local PLUGIN_MODULE = "kong.plugins.dynamic-routing.handler"

-- Unit suite for ACCESS phase precedence and fallback behavior.
-- `rewrite` and `log` phases are intentionally no-op for this plugin.
describe("dynamic-routing (unit)", function()
  local cfg
  local set_header_calls

  local function stub_kong(stubs)
    local existing_ngx = _G.ngx or {}

    _G.kong = {
      request = {
        get_header = stubs.get_header or function() return nil end,
        get_query_arg = stubs.get_query_arg or function() return nil end,
      },
      client = {
        get_consumer = stubs.get_consumer or function() return nil end,
      },
      service = {
        set_upstream = stubs.set_upstream or function() end,
        request = {
          set_header = stubs.set_request_header or function(name, value)
            set_header_calls[name] = value
          end,
        },
      },
      log = { debug = function() end },
      ctx = { shared = {} },
    }

    _G.ngx = stubs.ngx or { var = {} }
    if not _G.ngx.var then
      _G.ngx.var = {}
    end
    if not _G.ngx.decode_base64 then
      _G.ngx.decode_base64 = existing_ngx.decode_base64
    end
  end

  local function load_plugin(stubs)
    stub_kong(stubs or {})
    package.loaded[PLUGIN_MODULE] = nil
    return require(PLUGIN_MODULE)
  end

  before_each(function()
    set_header_calls = {}
    cfg = {
      upstreams = {
        dev = "up-dev",
        qa = "up-qa",
        prod = "up-prod",
        dev_client = "up-dev",
        qa_client = "up-qa",
        prod_client = "up-prod",
        ["sni.example.com"] = "up-qa",
      },
      upstream_header_name = "X-Upstream-Env",
      client_id_header_name = "X-Client-Id",
      access_policy = {
        sni = true,
        header_name = "X-Client-Env",
        query_param_name = "env",
      },
      endpoint = {
        sni = true,
        header_name = "X-Resource-Env",
        query_param_name = "resource_env",
      },
    }
  end)

  it("priority #1: uses X-Upstream-Env header", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Upstream-Env" then return "dev" end
        return nil
      end,
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-dev", selected)
    assert.equal("default_header", kong.ctx.shared.upstream_selector_reason)
  end)

  it("default header supports table values and picks first match", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Upstream-Env" then return { "unknown", "qa" } end
        return nil
      end,
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-qa", selected)
  end)

  it("priority #2: client SNI", function()
    local selected
    local plugin = load_plugin({
      ngx = { var = { ssl_server_name = "sni.example.com" } },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-qa", selected)
    assert.equal("client_sni", kong.ctx.shared.upstream_selector_reason)
  end)

  it("priority #3: client header", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Client-Env" then return "prod" end
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-prod", selected)
    assert.equal("client_header", kong.ctx.shared.upstream_selector_reason)
  end)

  it("priority #4: client query", function()
    local selected
    local plugin = load_plugin({
      get_query_arg = function(name)
        if name == "env" then return "qa" end
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-qa", selected)
    assert.equal("client_query", kong.ctx.shared.upstream_selector_reason)
  end)

  it("client query supports table values and picks first match", function()
    local selected
    local plugin = load_plugin({
      get_query_arg = function(name)
        if name == "env" then return { "unknown", "qa" } end
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-qa", selected)
    assert.equal("client_query", kong.ctx.shared.upstream_selector_reason)
  end)

  it("priority #6: resource header when access policy is disabled", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Resource-Env" then return "prod" end
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    cfg.access_policy = {}

    plugin:access(cfg)
    assert.equal("up-prod", selected)
    assert.equal("resource_header", kong.ctx.shared.upstream_selector_reason)
  end)

  it("last priority: client id header", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Client-Id" then return "dev_client" end
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-dev", selected)
    assert.equal("client_id", kong.ctx.shared.upstream_selector_reason)
    assert.equal("dev_client", set_header_calls["X-Client-Id"])
  end)

  it("falls back to JWT claim client_id when client id header is absent", function()
    local selected
    local jwt = "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0"
      .. ".eyJjbGllbnRfaWQiOiJxYV9jbGllbnQifQ."
    local plugin = load_plugin({
      get_header = function(name)
        if name == "authorization" then
          return "Bearer " .. jwt
        end
      end,
      get_consumer = function()
        return { custom_id = "prod_client" }
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-qa", selected)
    assert.equal("client_id", kong.ctx.shared.upstream_selector_reason)
    assert.equal("qa_client", set_header_calls["X-Client-Id"])
  end)

  it("uses consumer upstream_env tag when present", function()
    local selected
    local plugin = load_plugin({
      get_consumer = function()
        return {
          custom_id = "neutral_client",
          tags = { "upstream_env:qa" },
        }
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-qa", selected)
    assert.equal("client_id", kong.ctx.shared.upstream_selector_reason)
    assert.equal("qa", set_header_calls["X-Client-Id"])
  end)

  it("consumer upstream_env tag takes precedence over JWT claim", function()
    local selected
    local jwt = "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0"
      .. ".eyJjbGllbnRfaWQiOiJkZXZfY2xpZW50In0."
    local plugin = load_plugin({
      get_header = function(name)
        if name == "authorization" then
          return "Bearer " .. jwt
        end
      end,
      get_consumer = function()
        return {
          custom_id = "neutral_client",
          tags = { "upstream_env:prod" },
        }
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-prod", selected)
    assert.equal("client_id", kong.ctx.shared.upstream_selector_reason)
    assert.equal("prod", set_header_calls["X-Client-Id"])
  end)

  it("falls back to JWT claim client_id when client id header is empty", function()
    local selected
    local jwt = "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0"
      .. ".eyJjbGllbnRfaWQiOiJkZXZfY2xpZW50In0."
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Client-Id" then
          return ""
        end
        if name == "authorization" then
          return "Bearer " .. jwt
        end
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-dev", selected)
    assert.equal("client_id", kong.ctx.shared.upstream_selector_reason)
    assert.equal("dev_client", set_header_calls["X-Client-Id"])
  end)

  it("fallback to authenticated consumer object when header and token are absent", function()
    local selected
    local plugin = load_plugin({
      get_consumer = function()
        return { custom_id = "qa_client" }
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-qa", selected)
    assert.equal("client_id", kong.ctx.shared.upstream_selector_reason)
    assert.equal("qa_client", set_header_calls["X-Client-Id"])
  end)

  it("does not block when no selector matches", function()
    local set_upstream_calls = 0
    local plugin = load_plugin({
      set_upstream = function()
        set_upstream_calls = set_upstream_calls + 1
      end,
      ngx = { var = {} },
    })

    cfg.upstreams = { prod = "up-prod" }
    cfg.access_policy = {}
    cfg.endpoint = {}

    local res = plugin:access(cfg)
    assert.is_nil(res)
    assert.equal(0, set_upstream_calls)
  end)

  it("treats selector values as exact match (no trim/lowercase normalization)", function()
    local set_upstream_calls = 0
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Upstream-Env" then return "  DEV  " end
      end,
      set_upstream = function()
        set_upstream_calls = set_upstream_calls + 1
      end,
      ngx = { var = {} },
    })

    plugin:access(cfg)
    assert.equal(0, set_upstream_calls)
  end)

  it("default header table ignores empty values and picks first valid match", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Upstream-Env" then return { "", "unknown", "qa" } end
      end,
      set_upstream = function(u) selected = u end,
      ngx = { var = {} },
    })

    plugin:access(cfg)
    assert.equal("up-qa", selected)
    assert.equal("default_header", kong.ctx.shared.upstream_selector_reason)
  end)

  it("endpoint header supports table values and picks first valid match", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Resource-Env" then return { "unknown", "prod" } end
      end,
      set_upstream = function(u) selected = u end,
      ngx = { var = {} },
    })

    cfg.access_policy = {}
    plugin:access(cfg)

    assert.equal("up-prod", selected)
    assert.equal("resource_header", kong.ctx.shared.upstream_selector_reason)
  end)

  it("endpoint query supports table values and picks first valid match", function()
    local selected
    local plugin = load_plugin({
      get_query_arg = function(name)
        if name == "resource_env" then return { "unknown", "qa" } end
      end,
      set_upstream = function(u) selected = u end,
      ngx = { var = {} },
    })

    cfg.access_policy = {}
    cfg.endpoint = {
      query_param_name = "resource_env",
    }

    plugin:access(cfg)
    assert.equal("up-qa", selected)
    assert.equal("resource_query", kong.ctx.shared.upstream_selector_reason)
  end)

  it("authorization table uses first bearer value for JWT client_id extraction", function()
    local selected
    local qa_jwt = "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJjbGllbnRfaWQiOiJxYV9jbGllbnQifQ."
    local prod_jwt = "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJjbGllbnRfaWQiOiJwcm9kX2NsaWVudCJ9."
    local plugin = load_plugin({
      get_header = function(name)
        if name == "authorization" then
          return {
            "Bearer " .. qa_jwt,
            "Bearer " .. prod_jwt,
          }
        end
      end,
      set_upstream = function(u) selected = u end,
      ngx = { var = {} },
    })

    plugin:access(cfg)
    assert.equal("up-qa", selected)
    assert.equal("qa_client", set_header_calls["X-Client-Id"])
  end)

  it("ignores malformed JWT payload and falls back to authenticated consumer", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "authorization" then
          return "Bearer aaa.x.ccc"
        end
      end,
      get_consumer = function()
        return { custom_id = "prod_client" }
      end,
      set_upstream = function(u) selected = u end,
      ngx = { var = {} },
    })

    plugin:access(cfg)
    assert.equal("up-prod", selected)
    assert.equal("prod_client", set_header_calls["X-Client-Id"])
  end)

  it("ignores JWT without string client_id and falls back to consumer", function()
    local selected
    local non_string_client_id_jwt = "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJjbGllbnRfaWQiOjEyM30."
    local plugin = load_plugin({
      get_header = function(name)
        if name == "authorization" then
          return "Bearer " .. non_string_client_id_jwt
        end
      end,
      get_consumer = function()
        return { custom_id = "qa_client" }
      end,
      set_upstream = function(u) selected = u end,
      ngx = { var = {} },
    })

    plugin:access(cfg)
    assert.equal("up-qa", selected)
    assert.equal("qa_client", set_header_calls["X-Client-Id"])
  end)

  it("does not fail when cfg is nil", function()
    local set_upstream_calls = 0
    local plugin = load_plugin({
      set_upstream = function()
        set_upstream_calls = set_upstream_calls + 1
      end,
      ngx = { var = {} },
    })

    local ok = pcall(function()
      plugin:access(nil)
    end)
    assert.is_true(ok)
    assert.equal(0, set_upstream_calls)
  end)

  it("does not fail when cfg.upstreams is not a table", function()
    local set_upstream_calls = 0
    local plugin = load_plugin({
      set_upstream = function()
        set_upstream_calls = set_upstream_calls + 1
      end,
      ngx = { var = {} },
    })

    cfg.upstreams = "not-a-table"
    local ok = pcall(function()
      plugin:access(cfg)
    end)
    assert.is_true(ok)
    assert.equal(0, set_upstream_calls)
  end)

  it("still routes by client_id when kong.service.request.set_header is unavailable", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Client-Id" then return "qa_client" end
      end,
      set_upstream = function(u) selected = u end,
      ngx = { var = {} },
    })

    kong.service.request = nil
    local ok = pcall(function()
      plugin:access(cfg)
    end)

    assert.is_true(ok)
    assert.equal("up-qa", selected)
    assert.equal("client_id", kong.ctx.shared.upstream_selector_reason)
  end)
end)
