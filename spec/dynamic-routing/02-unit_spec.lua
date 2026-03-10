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
      log = {
        debug = function() end,
        err = function() end,
      },
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
      upstream_header_name = "X-Upstream-Header",
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

  it("priority #1: uses X-Upstream-Header header", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Upstream-Header" then return "dev" end
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
        if name == "X-Upstream-Header" then return { "unknown", "qa" } end
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

  it("access policy query supports table values and picks first match", function()
    local selected
    local plugin = load_plugin({
      get_query_arg = function(name)
        if name == "apUpsByQP" then return { "unknown", "qa" } end
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

  it("falls back to introspection claim client_id when client id header is absent", function()
    local selected
    local introspection_payload = "eyJjbGllbnRfaWQiOiJxYV9jbGllbnQifQ=="
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Introspection-Response" then
          return introspection_payload
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

  it("introspection claim takes precedence over consumer upstream_env tag", function()
    local selected
    local introspection_payload = "eyJjbGllbnRfaWQiOiJkZXZfY2xpZW50In0="
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Introspection-Response" then
          return introspection_payload
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
    assert.equal("up-dev", selected)
    assert.equal("client_id", kong.ctx.shared.upstream_selector_reason)
    assert.equal("dev_client", set_header_calls["X-Client-Id"])
  end)

  it("falls back to introspection claim client_id when client id header is empty", function()
    local selected
    local introspection_payload = "eyJjbGllbnRfaWQiOiJkZXZfY2xpZW50In0="
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Client-Id" then
          return ""
        end
        if name == "X-Introspection-Response" then
          return introspection_payload
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
        if name == "X-Upstream-Header" then return "  DEV  " end
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
        if name == "X-Upstream-Header" then return { "", "unknown", "qa" } end
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
        if name == "X-Upstream-Env-EP" then return { "unknown", "prod" } end
      end,
      set_upstream = function(u) selected = u end,
      ngx = { var = {} },
    })

    cfg.access_policy = {}
    plugin:access(cfg)

    assert.equal("up-prod", selected)
    assert.equal("endpoint_header", kong.ctx.shared.upstream_selector_reason)
  end)

  it("endpoint query supports table values and picks first valid match", function()
    local selected
    local plugin = load_plugin({
      get_query_arg = function(name)
        if name == "epUpsByQP" then return { "unknown", "qa" } end
      end,
      set_upstream = function(u) selected = u end,
      ngx = { var = {} },
    })

    cfg.access_policy = {}
    cfg.endpoint = {
      query_param_name = "epUpsByQP",
    }

    plugin:access(cfg)
    assert.equal("up-qa", selected)
    assert.equal("endpoint_query", kong.ctx.shared.upstream_selector_reason)
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

  it("introspection header table uses first value for client_id extraction", function()
    local selected
    local qa_introspection = "eyJjbGllbnRfaWQiOiJxYV9jbGllbnQifQ=="
    local prod_introspection = "eyJjbGllbnRfaWQiOiJwcm9kX2NsaWVudCJ9"
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Introspection-Response" then
          return {
            qa_introspection,
            prod_introspection,
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

  it("ignores malformed introspection payload and falls back to authenticated consumer", function()
    local selected
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Introspection-Response" then
          return "###invalid###"
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

  it("ignores introspection payload without string client_id and falls back to consumer", function()
    local selected
    local non_string_client_id_claim = "eyJjbGllbnRfaWQiOjEyM30="
    local plugin = load_plugin({
      get_header = function(name)
        if name == "X-Introspection-Response" then
          return non_string_client_id_claim
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
