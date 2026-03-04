local helpers = require "spec.helpers"
local socket = require "socket"
local threads = require "llthreads2.ex"

-- Integration suite validating ACCESS phase routing decisions with real Kong upstreams.
describe("dynamic-routing (integration)", function()
  local admin_client
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
        if err or line == "" then
          break
        end

        local k, v = line:match("^([^:]+):%s*(.*)$")
        if k then
          headers[k:lower()] = v
        end
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

  local function json_headers()
    return { ["Content-Type"] = "application/json" }
  end

  local function post_json(client, path, body)
    local res = assert(client:post(path, {
      body = body,
      headers = json_headers(),
    }))
    assert.res_status(201, res)
  end

  local function query_string(params)
    if not params then
      return ""
    end

    local pairs_out = {}
    for k, v in pairs(params) do
      pairs_out[#pairs_out + 1] = k .. "=" .. v
    end
    if #pairs_out == 0 then
      return ""
    end

    return "?" .. table.concat(pairs_out, "&")
  end

  local function request_and_assert(expected_backend, opts)
    opts = opts or {}
    local target = fixture.backends[expected_backend]
    local t = start_backend_once(target.host, target.port, expected_backend)

    socket.sleep(0.05)
    local path = fixture.route_path .. query_string(opts.query)
    local res = assert(proxy_client:get(path, {
      headers = opts.headers,
    }))

    assert.res_status(200, res)
    assert.equal(expected_backend, res.headers["x-backend"])
    if opts.expected_received_client_id ~= nil then
      assert.equal(opts.expected_received_client_id, res.headers["x-received-client-id"])
    end

    assert(t:join())
  end

  local function jwt_for_client_id(client_id)
    if client_id == "qa_client" then
      return "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJjbGllbnRfaWQiOiJxYV9jbGllbnQifQ."
    end

    if client_id == "it_client" then
      return "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJjbGllbnRfaWQiOiJpdF9jbGllbnQifQ."
    end

    return nil
  end

  lazy_setup(function()
    helpers.get_db_utils(nil, {
      "routes",
      "services",
      "plugins",
      "upstreams",
      "targets",
    }, {
      "dynamic-routing",
    })

    assert(helpers.start_kong({
      plugins = "bundled,dynamic-routing",
    }))

    local admin = assert(helpers.admin_client())
    local suffix = tostring(get_available_port())

    fixture.route_path = "/api/orders-int"
    fixture.upstreams = {
      dev = "orders-api-dev-upstream-int-" .. suffix,
      prod = "orders-api-prod-upstream-int-" .. suffix,
      qa = "orders-api-qa-upstream-int-" .. suffix,
      it = "orders-api-it-upstream-int-" .. suffix,
      perf = "orders-api-perf-upstream-int-" .. suffix,
    }

    fixture.backends = {
      dev = { host = "127.0.0.1", port = get_available_port() },
      prod = { host = "127.0.0.1", port = get_available_port() },
      qa = { host = "127.0.0.1", port = get_available_port() },
      it = { host = "127.0.0.1", port = get_available_port() },
      perf = { host = "127.0.0.1", port = get_available_port() },
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
        client_id_header_name = "X-Client-Id",
        introspection_header_name = "X-Introspection-Response",
        upstreams = {
          dev = fixture.upstreams.dev,
          prod = fixture.upstreams.prod,
          qa = fixture.upstreams.qa,
          it = fixture.upstreams.it,
          perf = fixture.upstreams.perf,
          qa_client = fixture.upstreams.qa,
          it_client = fixture.upstreams.it,
          perf_client = fixture.upstreams.perf,
        },
        access_policy = {
          sni = false,
          header_name = "X-Client-Env",
          query_param_name = "env",
        },
        endpoint = {
          sni = false,
          header_name = "X-Resource-Env",
          query_param_name = "resource_env",
        },
      },
    })

    admin:close()
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    admin_client = assert(helpers.admin_client())
    proxy_client = assert(helpers.proxy_client())
  end)

  after_each(function()
    if proxy_client then proxy_client:close() end
    if admin_client then admin_client:close() end
  end)

  it("uses primary upstream when no selectors are present", function()
    request_and_assert("it")
  end)

  it("selects by default X-Upstream-Env header", function()
    request_and_assert("dev", {
      headers = { ["X-Upstream-Env"] = "dev" },
    })
  end)

  it("prioritizes default header over access and endpoint selectors", function()
    request_and_assert("qa", {
      headers = {
        ["X-Upstream-Env"] = "qa",
        ["X-Client-Env"] = "dev",
        ["X-Resource-Env"] = "prod",
      },
      query = {
        env = "prod",
        resource_env = "dev",
      },
    })
  end)

  it("uses access policy header before access query", function()
    request_and_assert("qa", {
      headers = { ["X-Client-Env"] = "qa" },
      query = { env = "dev" },
    })
  end)

  it("uses access query before endpoint header", function()
    request_and_assert("dev", {
      headers = { ["X-Resource-Env"] = "qa" },
      query = { env = "dev" },
    })
  end)

  it("uses endpoint header before endpoint query", function()
    request_and_assert("qa", {
      headers = { ["X-Resource-Env"] = "qa" },
      query = { resource_env = "dev" },
    })
  end)

  it("uses endpoint query when higher selectors are absent", function()
    request_and_assert("dev", {
      query = { resource_env = "dev" },
    })
  end)

  it("falls through invalid higher selectors to valid endpoint query", function()
    request_and_assert("qa", {
      headers = {
        ["X-Client-Env"] = "unknown",
        ["X-Resource-Env"] = "unknown",
      },
      query = {
        env = "unknown",
        resource_env = "qa",
      },
    })
  end)

  it("keeps default upstream when only bearer token is present without introspection header", function()
    request_and_assert("it", {
      headers = {
        ["Authorization"] = "Bearer " .. jwt_for_client_id("it_client"),
      },
    })
  end)

  it("routes by OIDC introspection header client_id when selectors are absent", function()
    request_and_assert("perf", {
      headers = {
        ["Authorization"] = "Bearer " .. jwt_for_client_id("qa_client"),
        ["X-Introspection-Response"] = "eyJjbGllbnRfaWQiOiJwZXJmX2NsaWVudCJ9",
      },
      expected_received_client_id = "perf_client",
    })
  end)

  it("routes by explicit X-Client-Id when selector levels do not match", function()
    request_and_assert("perf", {
      headers = {
        ["X-Client-Id"] = "perf_client",
      },
      expected_received_client_id = "perf_client",
    })
  end)

  it("keeps access selector priority above JWT and X-Client-Id", function()
    request_and_assert("dev", {
      headers = {
        ["X-Client-Env"] = "dev",
        ["X-Client-Id"] = "perf_client",
        ["Authorization"] = "Bearer " .. jwt_for_client_id("qa_client"),
      },
    })
  end)
end)
