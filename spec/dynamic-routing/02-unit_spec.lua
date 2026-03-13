local PLUGIN_MODULE = "kong.plugins.dynamic-routing.handler"

-- Unit suite for ACCESS phase precedence and fallback behavior.
-- `rewrite` and `log` phases are intentionally no-op for this plugin.
describe("dynamic-routing (unit)", function()
  local cfg
  local set_header_calls

  local function stub_kong(stubs)
    local existing_ngx = _G.ngx or {}
    local log_tbl = {
      debug = function() end,
      err = function() end,
      warn = function() end,
      info = function() end,
    }
    setmetatable(log_tbl, {
      __call = function() end,
    })

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
      log = log_tbl,
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
        ["dev-client-app"] = "up-dev",
        ["qa-client-app"] = "up-qa",
        ["prod-client-app"] = "up-prod",
        ["sni.example.com"] = "up-qa",
      },
      upstream_header_name = "X-Upstream-Env",
      client_id_header_name = "X-Client-Id",
      introspection_header_name = "X-Introspection-Response",
      access_policy = {
        sni = true,
        header_name = "X-Upstream-Env-AP",
        query_param_name = "apUpsByQP",
      },
      endpoint = {
        sni = true,
        header_name = "X-Upstream-Env-EP",
        query_param_name = "epUpsByQP",
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

  it("default header uses direct string value", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Upstream-Env" then return "qa" end
        return nil
      end,
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-qa", selected)
  end)

  it("priority #2: access policy SNI", function()
    local selected
    local plugin = load_plugin({
      ngx = { var = { ssl_server_name = "sni.example.com" } },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-qa", selected)
    assert.equal("access_policy_sni", kong.ctx.shared.upstream_selector_reason)
  end)

  it("priority #3: access policy header", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Upstream-Env-AP" then return "prod" end
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-prod", selected)
    assert.equal("access_policy_header", kong.ctx.shared.upstream_selector_reason)
  end)

  it("priority #4: access policy query", function()
    local selected
    local plugin = load_plugin({
      get_query_arg = function(name)
        if name == "apUpsByQP" then return "qa" end
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-qa", selected)
    assert.equal("access_policy_query", kong.ctx.shared.upstream_selector_reason)
  end)

  it("access policy query uses direct string value", function()
    local selected
    local plugin = load_plugin({
      get_query_arg = function(name)
        if name == "apUpsByQP" then return "qa" end
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-qa", selected)
    assert.equal("access_policy_query", kong.ctx.shared.upstream_selector_reason)
  end)

  it("priority #6: resource header when access policy is disabled", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Upstream-Env-EP" then return "prod" end
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    cfg.access_policy = {}

    plugin:access(cfg)
    assert.equal("up-prod", selected)
    assert.equal("endpoint_header", kong.ctx.shared.upstream_selector_reason)
  end)

  it("does not route by inbound X-Client-Id when introspection claim is absent", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Client-Id" then
          return "dev_client"
        end
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.is_nil(selected)
    assert.is_nil(kong.ctx.shared.upstream_selector_reason)
    assert.is_nil(set_header_calls["X-Client-Id"])
  end)

  it("routes by consumer.username when available", function()
    local selected
    local plugin = load_plugin({
      get_consumer = function()
        return { username = "qa-client-app" }
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-qa", selected)
    assert.equal("client_id", kong.ctx.shared.upstream_selector_reason)
    assert.equal("qa-client-app", set_header_calls["X-Client-Id"])
  end)

  it("does not use consumer upstream_env tag when username is present", function()
    local selected
    local plugin = load_plugin({
      get_consumer = function()
        return {
          username = "qa-client-app",
          tags = { "upstream_env:qa" },
        }
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-qa", selected)
    assert.equal("client_id", kong.ctx.shared.upstream_selector_reason)
    assert.equal("qa-client-app", set_header_calls["X-Client-Id"])
  end)

  it("does not route by introspection claim when consumer is missing", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Introspection-Response" then
          return "eyJjbGllbnRfaWQiOiJkZXZfY2xpZW50In0="
        end
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.is_nil(selected)
    assert.is_nil(kong.ctx.shared.upstream_selector_reason)
    assert.is_nil(set_header_calls["X-Client-Id"])
  end)

  it("uses consumer.username even when introspection and inbound X-Client-Id are present", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Client-Id" then
          return "prod_client"
        end
        if name == "X-Introspection-Response" then
          return "eyJjbGllbnRfaWQiOiJkZXZfY2xpZW50In0="
        end
      end,
      get_consumer = function()
        return { username = "qa-client-app" }
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-qa", selected)
    assert.equal("client_id", kong.ctx.shared.upstream_selector_reason)
    assert.equal("qa-client-app", set_header_calls["X-Client-Id"])
  end)

  it("falls back to no routing when consumer.username is absent", function()
    local selected
    local plugin = load_plugin({
      get_consumer = function()
        return { custom_id = "qa_client" }
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.is_nil(selected)
    assert.is_nil(kong.ctx.shared.upstream_selector_reason)
    assert.is_nil(set_header_calls["X-Client-Id"])
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

  it("default header ignores non-string values", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Upstream-Env" then return { "", "qa" } end
      end,
      set_upstream = function(u) selected = u end,
      ngx = { var = {} },
    })

    plugin:access(cfg)
    assert.is_nil(selected)
    assert.is_nil(kong.ctx.shared.upstream_selector_reason)
  end)

  it("endpoint header ignores non-string values", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Upstream-Env-EP" then return { "prod" } end
      end,
      set_upstream = function(u) selected = u end,
      ngx = { var = {} },
    })

    cfg.access_policy = {}
    plugin:access(cfg)

    assert.is_nil(selected)
    assert.is_nil(kong.ctx.shared.upstream_selector_reason)
  end)

  it("endpoint query ignores non-string values", function()
    local selected
    local plugin = load_plugin({
      get_query_arg = function(name)
        if name == "epUpsByQP" then return { "qa" } end
      end,
      set_upstream = function(u) selected = u end,
      ngx = { var = {} },
    })

    cfg.access_policy = {}
    cfg.endpoint = {
      query_param_name = "epUpsByQP",
    }

    plugin:access(cfg)
    assert.is_nil(selected)
    assert.is_nil(kong.ctx.shared.upstream_selector_reason)
  end)

  it("keeps access policy precedence above endpoint policy", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Upstream-Env-AP" then return "prod" end
        if name == "X-Upstream-Env-EP" then return "qa" end
      end,
      get_query_arg = function(name)
        if name == "apUpsByQP" then return "dev" end
        if name == "epUpsByQP" then return "qa" end
      end,
      ngx = { var = { ssl_server_name = "sni.example.com" } },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)

    assert.equal("up-qa", selected)
    assert.equal("access_policy_sni", kong.ctx.shared.upstream_selector_reason)
    assert.equal("sni.example.com", kong.ctx.shared.upstream_selector_key)
  end)

  it("falls through invalid access policy selectors to endpoint policy selectors", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Upstream-Env-AP" then return "unknown" end
        if name == "X-Upstream-Env-EP" then return "prod" end
      end,
      get_query_arg = function(name)
        if name == "apUpsByQP" then return "unknown" end
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)

    assert.equal("up-prod", selected)
    assert.equal("endpoint_header", kong.ctx.shared.upstream_selector_reason)
  end)

  it("still evaluates endpoint policy when access policy config is invalid", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Upstream-Env-EP" then return "prod" end
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    cfg.access_policy = "invalid-policy"

    plugin:access(cfg)

    assert.equal("up-prod", selected)
    assert.equal("endpoint_header", kong.ctx.shared.upstream_selector_reason)
  end)

  it("still evaluates access policy when endpoint policy config is invalid", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Upstream-Env-AP" then return "qa" end
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    cfg.endpoint = "invalid-policy"

    plugin:access(cfg)

    assert.equal("up-qa", selected)
    assert.equal("access_policy_header", kong.ctx.shared.upstream_selector_reason)
  end)

  it("supports endpoint policy sni when access policy sni is disabled", function()
    local selected
    cfg.upstreams["endpoint.example.com"] = "up-prod"
    local plugin = load_plugin({
      ngx = { var = { ssl_server_name = "endpoint.example.com" } },
      set_upstream = function(u) selected = u end,
    })

    cfg.access_policy.sni = false
    cfg.endpoint.sni = true

    plugin:access(cfg)

    assert.equal("up-prod", selected)
    assert.equal("endpoint_sni", kong.ctx.shared.upstream_selector_reason)
    assert.equal("endpoint.example.com", kong.ctx.shared.upstream_selector_key)
  end)

  it("ignores introspection header values and uses consumer.username", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Introspection-Response" then
          return { "eyJjbGllbnRfaWQiOiJwcm9kX2NsaWVudCJ9" }
        end
      end,
      get_consumer = function()
        return { username = "qa-client-app" }
      end,
      set_upstream = function(u) selected = u end,
      ngx = { var = {} },
    })

    plugin:access(cfg)
    assert.equal("up-qa", selected)
    assert.equal("qa-client-app", set_header_calls["X-Client-Id"])
  end)

  it("uses consumer.username when introspection payload is malformed", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Introspection-Response" then
          return "###invalid###"
        end
      end,
      get_consumer = function()
        return { username = "prod-client-app" }
      end,
      set_upstream = function(u) selected = u end,
      ngx = { var = {} },
    })

    plugin:access(cfg)
    assert.equal("up-prod", selected)
    assert.equal("prod-client-app", set_header_calls["X-Client-Id"])
  end)

  it("uses consumer.username even when introspection payload has non-string client_id", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Introspection-Response" then
          return "eyJjbGllbnRfaWQiOjEyM30="
        end
      end,
      get_consumer = function()
        return { username = "qa-client-app" }
      end,
      set_upstream = function(u) selected = u end,
      ngx = { var = {} },
    })

    plugin:access(cfg)
    assert.equal("up-qa", selected)
    assert.equal("qa-client-app", set_header_calls["X-Client-Id"])
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
      get_consumer = function()
        return { username = "qa-client-app" }
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
