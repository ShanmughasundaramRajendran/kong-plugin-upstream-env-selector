local PLUGIN_MODULE = "kong.plugins.dynamic-routing.handler"

describe("dynamic-routing (unit)", function()
  local cfg
  local set_header_calls

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
        set_upstream = stubs.set_upstream or function() end,
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
    cfg = {
      upstreams = {
        dev = "up-dev",
        qa = "up-qa",
        prod = "up-prod",
        ["sni.example.com"] = "up-qa",
        ["qa-client-app"] = "up-qa",
      },
      upstream_header_name = "X-Upstream-Env",
      header_name = "X-Upstream-Selector",
      query_param_name = "upsByQP",
      sni = true,
    }
  end)

  it("uses default header first", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Upstream-Env" then return "dev" end
        if name == "X-Upstream-Selector" then return "qa" end
      end,
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-dev", selected)
    assert.equal("default_header", kong.ctx.plugin.upstream_selector_reason)
  end)

  it("uses sni before header/query selectors", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Upstream-Selector" then return "prod" end
      end,
      get_query_arg = function(name)
        if name == "upsByQP" then return "dev" end
      end,
      ngx = { var = { ssl_server_name = "sni.example.com" } },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-qa", selected)
    assert.equal("sni", kong.ctx.plugin.upstream_selector_reason)
  end)

  it("uses configured selector header when sni misses", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Upstream-Selector" then return "prod" end
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-prod", selected)
    assert.equal("header", kong.ctx.plugin.upstream_selector_reason)
  end)

  it("uses configured selector query when header misses", function()
    local selected
    local plugin = load_plugin({
      get_query_arg = function(name)
        if name == "upsByQP" then return "qa" end
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-qa", selected)
    assert.equal("query", kong.ctx.plugin.upstream_selector_reason)
  end)

  it("routes by consumer.username fallback", function()
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
    assert.equal("client_id", kong.ctx.plugin.upstream_selector_reason)
    assert.equal("qa-client-app", set_header_calls["X-Client-Id"])
  end)

  it("does not route from inbound X-Client-Id", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Client-Id" then return "qa-client-app" end
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.is_nil(selected)
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
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Upstream-Selector" then return { "prod" } end
      end,
      get_query_arg = function(name)
        if name == "upsByQP" then return { "qa" } end
      end,
      ngx = { var = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.is_nil(selected)
  end)
end)
