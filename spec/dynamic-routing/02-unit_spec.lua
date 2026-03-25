local PLUGIN_MODULE = "kong.plugins.dynamic-routing.handler"

describe("dynamic-routing (unit)", function()
  local cfg
  local set_header_calls
  local set_target_calls

  local function stub_kong(stubs)
    local log_tbl = {
      debug = function() end,
      err = function() end,
      warn = function() end,
      info = function() end,
    }
    setmetatable(log_tbl, { __call = function() end })

    _G.kong = {
      request = {
        get_header = stubs.get_header or function() return nil end,
        get_query_arg = stubs.get_query_arg or function() return nil end,
      },
      client = {
        get_consumer = stubs.get_consumer or function() return nil end,
      },
      service = {
        set_target = stubs.set_target or function(host, port)
          table.insert(set_target_calls, { host = host, port = port })
        end,
        request = {
          set_header = stubs.set_request_header or function(name, value)
            set_header_calls[name] = value
          end,
        },
      },
      log = log_tbl,
      ctx = { shared = {}, plugin = {} },
    }

    _G.ngx = stubs.ngx or { var = {} }
    if not _G.ngx.var then
      _G.ngx.var = {}
    end
  end

  local function load_plugin(stubs)
    stub_kong(stubs or {})
    package.loaded[PLUGIN_MODULE] = nil
    return require(PLUGIN_MODULE)
  end

  before_each(function()
    set_header_calls = {}
    set_target_calls = {}
    cfg = {
      upstreams = {
        dev = "orders_api_dev:8080",
        qa = "orders_api_qa:8080",
        prod = "orders_api_prod:8080",
        ["sni.example.com"] = "orders_api_qa:8080",
        ["endpoint.sni.example.com"] = "orders_api_prod:8080",
        ["qa-client-app"] = "orders_api_qa:8080",
      },
      upstream_header_name = "X-Upstream-Env",
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

  it("uses default header first", function()
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Upstream-Env" then return "dev" end
        if name == "X-Upstream-Env-AP" then return "qa" end
      end,
    })

    plugin:access(cfg)
    assert.same({ host = "orders_api_dev", port = 8080 }, set_target_calls[1])
    assert.equal("default_header", kong.ctx.plugin.upstream_selector_reason)
  end)

  it("uses access_policy sni before access_policy header/query", function()
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Upstream-Env-AP" then return "prod" end
      end,
      get_query_arg = function(name)
        if name == "apUpsByQP" then return "dev" end
      end,
      ngx = { var = { ssl_server_name = "sni.example.com" } },
    })

    plugin:access(cfg)
    assert.same({ host = "orders_api_qa", port = 8080 }, set_target_calls[1])
    assert.equal("access_policy_sni", kong.ctx.plugin.upstream_selector_reason)
  end)

  it("uses access_policy header when access_policy sni misses", function()
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Upstream-Env-AP" then return "prod" end
      end,
      ngx = { var = {} },
    })

    plugin:access(cfg)
    assert.same({ host = "orders_api_prod", port = 8080 }, set_target_calls[1])
    assert.equal("access_policy_header", kong.ctx.plugin.upstream_selector_reason)
  end)

  it("uses access_policy query when access_policy header misses", function()
    local plugin = load_plugin({
      get_query_arg = function(name)
        if name == "apUpsByQP" then return "qa" end
      end,
      ngx = { var = {} },
    })

    plugin:access(cfg)
    assert.same({ host = "orders_api_qa", port = 8080 }, set_target_calls[1])
    assert.equal("access_policy_query", kong.ctx.plugin.upstream_selector_reason)
  end)

  it("uses endpoint policy when access_policy does not match", function()
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Upstream-Env-EP" then return "prod" end
      end,
      ngx = { var = {} },
    })

    plugin:access(cfg)
    assert.same({ host = "orders_api_prod", port = 8080 }, set_target_calls[1])
    assert.equal("endpoint_header", kong.ctx.plugin.upstream_selector_reason)
  end)

  it("routes by consumer.username fallback", function()
    local plugin = load_plugin({
      get_consumer = function()
        return { username = "qa-client-app" }
      end,
      ngx = { var = {} },
    })

    plugin:access(cfg)
    assert.same({ host = "orders_api_qa", port = 8080 }, set_target_calls[1])
    assert.equal("client_id", kong.ctx.plugin.upstream_selector_reason)
    assert.equal("qa-client-app", set_header_calls["client_id"])
  end)

  it("does not route from inbound client_id header", function()
    local plugin = load_plugin({
      get_header = function(name)
        if name == "client_id" then return "qa-client-app" end
      end,
      ngx = { var = {} },
    })

    plugin:access(cfg)
    assert.equal(0, #set_target_calls)
  end)

  it("does not fail when cfg is nil", function()
    local plugin = load_plugin({ ngx = { var = {} } })
    assert.is_true(pcall(function() plugin:access(nil) end))
  end)

  it("does not fail when upstreams is not a table", function()
    local plugin = load_plugin({ ngx = { var = {} } })
    cfg.upstreams = "invalid"
    assert.is_true(pcall(function() plugin:access(cfg) end))
  end)

  it("ignores non-string selector return values", function()
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Upstream-Env-AP" then return { "prod" } end
      end,
      get_query_arg = function(name)
        if name == "apUpsByQP" then return { "qa" } end
      end,
      ngx = { var = {} },
    })

    plugin:access(cfg)
    assert.equal(0, #set_target_calls)
  end)
end)
