local helpers = require "spec.helpers"
local socket = require "socket"
local threads = require "llthreads2.ex"

describe("dynamic-routing (integration)", function()
  local proxy_client
  local fixture = {}

  local function get_available_port()
    local server = assert(socket.bind("127.0.0.1", 0))
    local _, port = server:getsockname()
    server:close()
    return port
  end

  local function start_backend_once(host, port, backend_name)
    local thread = threads.new([[
      local socket = require "socket"
      local host, port, backend_name = ...
      local server = assert(socket.bind(host, port))
      server:settimeout(20)
      local client = assert(server:accept())
      client:settimeout(5)

      local headers = {}
      while true do
        local line, err = client:receive("*l")
        if err or line == "" then break end
        local k, v = line:match("^([^:]+):%s*(.*)$")
        if k then headers[k:lower()] = v end
      end

      local body = backend_name
      local received_client_id = headers["x-client-id"] or ""
      local resp = "HTTP/1.1 200 OK\r\n"
        .. "Content-Type: text/plain\r\n"
        .. "Content-Length: " .. #body .. "\r\n"
        .. "x-backend: " .. backend_name .. "\r\n"
        .. "x-received-client-id: " .. received_client_id .. "\r\n"
        .. "Connection: close\r\n\r\n"
        .. body

      client:send(resp)
      client:close()
      server:close()
      return true
    ]], host, port, backend_name)

    assert(thread:start())
    return thread
  end

  local function post_json(client, path, body)
    local res = assert(client:post(path, {
      body = body,
      headers = { ["Content-Type"] = "application/json" },
    }))
    assert.res_status(201, res)
  end

  local function request_and_assert(expected_backend, opts)
    opts = opts or {}
    local target = fixture.backends[expected_backend]
    local t = start_backend_once(target.host, target.port, expected_backend)

    socket.sleep(0.05)
    local path = fixture.route_path
    if opts.query then
      path = path .. "?" .. opts.query
    end

    local res = assert(proxy_client:get(path, { headers = opts.headers }))
    assert.res_status(200, res)
    assert.equal(expected_backend, res.headers["x-backend"])
    if opts.expected_received_client_id ~= nil then
      assert.equal(opts.expected_received_client_id, res.headers["x-received-client-id"])
    end
    assert(t:join())
  end

  lazy_setup(function()
    helpers.get_db_utils(nil, { "routes", "services", "plugins", "upstreams", "targets" }, { "dynamic-routing" })

    assert(helpers.start_kong({ plugins = "bundled,dynamic-routing" }))

    local admin = assert(helpers.admin_client())
    local suffix = tostring(get_available_port())

    fixture.route_path = "/api/orders-int"
    fixture.upstreams = {
      dev = "orders-api-dev-upstream-int-" .. suffix,
      prod = "orders-api-prod-upstream-int-" .. suffix,
      qa = "orders-api-qa-upstream-int-" .. suffix,
      it = "orders-api-it-upstream-int-" .. suffix,
    }

    fixture.backends = {
      dev = { host = "127.0.0.1", port = get_available_port() },
      prod = { host = "127.0.0.1", port = get_available_port() },
      qa = { host = "127.0.0.1", port = get_available_port() },
      it = { host = "127.0.0.1", port = get_available_port() },
    }

    for env, upstream_name in pairs(fixture.upstreams) do
      post_json(admin, "/upstreams", { name = upstream_name })
      post_json(admin, "/upstreams/" .. upstream_name .. "/targets", {
        target = fixture.backends[env].host .. ":" .. fixture.backends[env].port,
      })
    end

    post_json(admin, "/services", {
      name = "orders-gateway-service-int-" .. suffix,
      host = fixture.upstreams.it,
    })

    post_json(admin, "/routes", {
      service = { name = "orders-gateway-service-int-" .. suffix },
      paths = { fixture.route_path },
    })

    post_json(admin, "/plugins", {
      name = "dynamic-routing",
      service = { name = "orders-gateway-service-int-" .. suffix },
      config = {
        upstream_header_name = "X-Upstream-Env",
        sni = false,
        header_name = "X-Upstream-Selector",
        query_param_name = "upsByQP",
        client_id_header_name = "X-Client-Id",
        upstreams = {
          dev = fixture.upstreams.dev,
          prod = fixture.upstreams.prod,
          qa = fixture.upstreams.qa,
          it = fixture.upstreams.it,
          ["qa-client-app"] = fixture.upstreams.qa,
        },
      },
    })

    admin:close()
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    proxy_client = assert(helpers.proxy_client())
  end)

  after_each(function()
    if proxy_client then proxy_client:close() end
  end)

  it("uses default upstream when no selectors are present", function()
    request_and_assert("it")
  end)

  it("uses default X-Upstream-Env header", function()
    request_and_assert("dev", { headers = { ["X-Upstream-Env"] = "dev" } })
  end)

  it("default header has priority over other selectors", function()
    request_and_assert("qa", {
      headers = {
        ["X-Upstream-Env"] = "qa",
        ["X-Upstream-Selector"] = "dev",
      },
      query = "upsByQP=prod",
    })
  end)

  it("uses selector header before selector query", function()
    request_and_assert("prod", {
      headers = { ["X-Upstream-Selector"] = "prod" },
      query = "upsByQP=dev",
    })
  end)

  it("uses selector query when selector header is absent", function()
    request_and_assert("dev", { query = "upsByQP=dev" })
  end)

end)
