local helpers = require "spec.helpers"
local socket = require "socket"
local threads = require "llthreads2.ex"

describe("upstream-env-selector (integration)", function()
  local admin_client
  local proxy_client

  lazy_setup(function()
    helpers.get_db_utils(nil, {
      "routes",
      "services",
      "plugins",
      "upstreams",
      "targets",
    }, {
      "upstream-env-selector",
    })

    assert(helpers.start_kong({
      plugins = "bundled,upstream-env-selector",
    }))
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

  local function json_headers()
    return { ["Content-Type"] = "application/json" }
  end

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

      while true do
        local line, err = client:receive("*l")
        if err or line == "" then
          break
        end
      end

      local body = backend_name
      local resp = "HTTP/1.1 200 OK\r\n"
        .. "Content-Type: text/plain\r\n"
        .. "Content-Length: " .. #body .. "\r\n"
        .. "x-backend: " .. backend_name .. "\r\n"
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

  it("routes by precedence and supports dev/prod/qa selectors", function()
    local host1, port1 = "127.0.0.1", get_available_port()
    local host2, port2 = "127.0.0.1", get_available_port()
    local host3, port3 = "127.0.0.1", get_available_port()

    local res = assert(admin_client:post("/upstreams", { body = { name = "orders-api-dev-upstream" }, headers = json_headers() }))
    assert.res_status(201, res)
    res = assert(admin_client:post("/upstreams", { body = { name = "orders-api-prod-upstream" }, headers = json_headers() }))
    assert.res_status(201, res)
    res = assert(admin_client:post("/upstreams", { body = { name = "orders-api-qa-upstream" }, headers = json_headers() }))
    assert.res_status(201, res)

    res = assert(admin_client:post("/upstreams/orders-api-dev-upstream/targets", {
      body = { target = host1 .. ":" .. port1 },
      headers = json_headers(),
    }))
    assert.res_status(201, res)

    res = assert(admin_client:post("/upstreams/orders-api-prod-upstream/targets", {
      body = { target = host2 .. ":" .. port2 },
      headers = json_headers(),
    }))
    assert.res_status(201, res)

    res = assert(admin_client:post("/upstreams/orders-api-qa-upstream/targets", {
      body = { target = host3 .. ":" .. port3 },
      headers = json_headers(),
    }))
    assert.res_status(201, res)

    res = assert(admin_client:post("/services", {
      body = { name = "orders-gateway-service", host = "orders-api-prod-upstream" },
      headers = json_headers(),
    }))
    assert.res_status(201, res)

    res = assert(admin_client:post("/routes", {
      body = { service = { name = "orders-gateway-service" }, paths = { "/api/orders" } },
      headers = json_headers(),
    }))
    assert.res_status(201, res)

    res = assert(admin_client:post("/plugins", {
      body = {
        name = "upstream-env-selector",
        config = {
          upstream_header_name = "X-Upstream-Env",
          client_id_header_name = "X-Client-Id",
          upstreams = {
            dev = "orders-api-dev-upstream",
            prod = "orders-api-prod-upstream",
            qa = "orders-api-qa-upstream",
            qa_client = "orders-api-qa-upstream",
          },
          access_policy = { sni = false, header_name = "X-Client-Env", query_param_name = "env" },
          endpoint = { sni = false, header_name = "X-Resource-Env", query_param_name = "resource_env" },
        }
      },
      headers = json_headers(),
    }))
    assert.res_status(201, res)

    local t1 = start_backend_once(host1, port1, "dev")
    socket.sleep(0.05)
    res = assert(proxy_client:get("/api/orders", { headers = { ["X-Upstream-Env"] = "dev" } }))
    assert.res_status(200, res)
    assert.equal("dev", res.headers["x-backend"])
    assert(t1:join())

    local t2 = start_backend_once(host3, port3, "qa")
    socket.sleep(0.05)
    res = assert(proxy_client:get("/api/orders", { headers = { ["X-Client-Env"] = "qa" } }))
    assert.res_status(200, res)
    assert.equal("qa", res.headers["x-backend"])
    assert(t2:join())

    local t3 = start_backend_once(host3, port3, "qa")
    socket.sleep(0.05)
    res = assert(proxy_client:get("/api/orders", { headers = { ["X-Client-Id"] = "qa_client" } }))
    assert.res_status(200, res)
    assert.equal("qa", res.headers["x-backend"])
    assert(t3:join())

    local t4 = start_backend_once(host3, port3, "qa")
    socket.sleep(0.05)
    local jwt = "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJjbGllbnQtaWQiOiJxYV9jbGllbnQifQ."
    res = assert(proxy_client:get("/api/orders", {
      headers = { ["Authorization"] = "Bearer " .. jwt },
    }))
    assert.res_status(200, res)
    assert.equal("qa", res.headers["x-backend"])
    assert(t4:join())

    local t5 = start_backend_once(host2, port2, "prod")
    socket.sleep(0.05)
    res = assert(proxy_client:get("/api/orders"))
    assert.res_status(200, res)
    assert.equal("prod", res.headers["x-backend"])
    assert(t5:join())
  end)
end)
