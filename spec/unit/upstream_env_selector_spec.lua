local PLUGIN_MODULE = "kong.plugins.upstream-env-selector.handler"

describe("upstream-env-selector (unit)", function()
  local cfg

  -- Builds a minimal Kong/ngx runtime for each test so handler logic can run
  -- without a live Kong process.
  local function stub_kong(stubs)
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
      },
      response = {
        exit = stubs.exit or function(status, body) return { status = status, body = body } end,
      },
      log = { debug = function() end, warn = function() end },
      ctx = { shared = {} },
    }

    _G.ngx = stubs.ngx or { var = {}, shared = nil, null = {} }
  end

  -- Reloads the plugin after stubbing globals. The handler captures `kong`/`ngx`
  -- at require-time, so each test needs a fresh module load.
  local function load_plugin(stubs)
    stub_kong(stubs or {})
    package.loaded[PLUGIN_MODULE] = nil
    return require(PLUGIN_MODULE)
  end

  before_each(function()
    -- Baseline config used by most tests; individual tests override specific
    -- knobs to exercise strict mode and selector priority behavior.
    cfg = {
      upstreams = {
        dev = "up-dev",
        qa = "up-qa",
        prod = "up-prod",
        ["api-client-1"] = "up-prod",
        ["sni.example.com"] = "up-qa",
      },
      use_redis = false,
      upstream_header_name = "X-Upstream-Env",
      strict = true,
      normalize = true,
      client_id_source = "header",
      client_id_header_name = "X-Consumer-Id",
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
      cache_ttl_sec = 5,
      negative_ttl_sec = 2,
      redis_fail_open = true,
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
    assert.equal("up-dev", kong.ctx.shared.upstream_backend_id)
    assert.equal("default_header", kong.ctx.shared.upstream_selector_reason)
  end)

  it("supports multi-value default header (first match wins)", function()
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

  it("priority #2: client SNI when default header absent", function()
    local selected
    local plugin = load_plugin({
      ngx = { var = { ssl_server_name = "sni.example.com" }, shared = nil, null = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-qa", selected)
    assert.equal("client_sni", kong.ctx.shared.upstream_selector_reason)
  end)

  it("priority #3: client header_name", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Client-Env" then return "prod" end
        return nil
      end,
      ngx = { var = { ssl_server_name = nil }, shared = nil, null = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-prod", selected)
    assert.equal("client_header", kong.ctx.shared.upstream_selector_reason)
  end)

  it("priority #4: client query param", function()
    local selected
    local plugin = load_plugin({
      get_query_arg = function(name)
        if name == "env" then return "qa" end
        return nil
      end,
      ngx = { var = { ssl_server_name = nil }, shared = nil, null = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-qa", selected)
    assert.equal("client_query", kong.ctx.shared.upstream_selector_reason)
  end)

  it("priority #6: resource header when client policy is disabled", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Resource-Env" then return "prod" end
        return nil
      end,
      ngx = { var = { ssl_server_name = nil }, shared = nil, null = {} },
      set_upstream = function(u) selected = u end,
    })

    cfg.access_policy = {}

    plugin:access(cfg)
    assert.equal("up-prod", selected)
    assert.equal("resource_header", kong.ctx.shared.upstream_selector_reason)
  end)

  it("normalizes selector values (trim + lowercase)", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Upstream-Env" then return "  DEV  " end
        return nil
      end,
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-dev", selected)
    assert.equal("dev", kong.ctx.shared.upstream_selector_key)
  end)

  it("last priority: consumer id header", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Consumer-Id" then return "api-client-1" end
        return nil
      end,
      ngx = { var = { ssl_server_name = nil }, shared = nil, null = {} },
      set_upstream = function(u) selected = u end,
    })

    plugin:access(cfg)
    assert.equal("up-prod", selected)
    assert.equal("client_id", kong.ctx.shared.upstream_selector_reason)
  end)

  it("supports legacy consumer object source when configured", function()
    local selected
    local plugin = load_plugin({
      get_consumer = function()
        return { custom_id = "api-client-1" }
      end,
      ngx = { var = { ssl_server_name = nil }, shared = nil, null = {} },
      set_upstream = function(u) selected = u end,
    })

    cfg.client_id_source = "custom_id"

    plugin:access(cfg)
    assert.equal("up-prod", selected)
    assert.equal("client_id", kong.ctx.shared.upstream_selector_reason)
  end)

  it("strict mode: returns 400 if no match", function()
    local plugin = load_plugin({
      exit = function(status, body)
        return { status = status, body = body }
      end,
      ngx = { var = { ssl_server_name = nil }, shared = nil, null = {} },
    })

    cfg.upstreams = { prod = "up-prod" }
    cfg.strict = true

    local res = plugin:access(cfg)
    assert.is_table(res)
    assert.equal(400, res.status)
  end)

  it("non-strict mode: does not block when no selector matches", function()
    local set_upstream_calls = 0
    local plugin = load_plugin({
      set_upstream = function()
        set_upstream_calls = set_upstream_calls + 1
      end,
      ngx = { var = { ssl_server_name = nil }, shared = nil, null = {} },
    })

    cfg.upstreams = { prod = "up-prod" }
    cfg.access_policy = {}
    cfg.endpoint = {}
    cfg.strict = false

    local res = plugin:access(cfg)
    assert.is_nil(res)
    assert.equal(0, set_upstream_calls)
  end)
end)
