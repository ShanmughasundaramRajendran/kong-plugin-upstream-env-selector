local helpers = require "spec.helpers"
local socket = require "socket"
local threads = require "llthreads2.ex"

-- NOTE:
-- This test uses Kong spec helpers. Depending on your Kong/Pongo image version,
-- you may need to adjust mock upstream helpers. The test is written in the
-- common Kong style (start_kong + admin/proxy clients).

describe("upstream-env-selector (integration)", function()
  local admin_client
  local proxy_client

  lazy_setup(function()
    -- Boot Kong with the plugin loaded once for this test block.
    local bp = helpers.get_db_utils(nil, {
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
      nginx_conf = "spec/fixtures/custom_nginx.template",
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

  -- Reused admin API header helper for JSON POST bodies.
  local function json_headers()
    return { ["Content-Type"] = "application/json" }
  end

  local function get_available_port()
    local server = assert(socket.bind("127.0.0.1", 0))
    local _, port = server:getsockname()
    server:close()
    return port
  end

  -- Start a one-request HTTP backend in a background thread.
  -- This is compatible with Pongo/Kong helper versions where helpers.http_server is absent.
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

  it("routes orders API by X-Upstream-Env header and X-Consumer-Id fallback", function()
    local host1, port1 = "127.0.0.1", get_available_port()
    local host2, port2 = "127.0.0.1", get_available_port()

    -- Upstreams
    local res = assert(admin_client:post("/upstreams", { body = { name = "orders-api-dev-upstream" }, headers = json_headers() }))
    assert.res_status(201, res)

    res = assert(admin_client:post("/upstreams", { body = { name = "orders-api-prod-upstream" }, headers = json_headers() }))
    assert.res_status(201, res)

    -- Targets
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

    -- Service host points to prod by default; plugin overrides target upstream.
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

    -- Enable plugin
    res = assert(admin_client:post("/plugins", {
      body = {
        name = "upstream-env-selector",
        config = {
          upstream_header_name = "X-Upstream-Env",
          strict = true,
          normalize = true,
          client_id_source = "header",
          client_id_header_name = "X-Consumer-Id",
          upstreams = { dev = "orders-api-dev-upstream", prod = "orders-api-prod-upstream" },
          access_policy = { sni = false, header_name = "X-Client-Env", query_param_name = "env" },
          endpoint = { sni = false, header_name = "X-Resource-Env", query_param_name = "resource_env" },
        }
      },
      headers = json_headers(),
    }))
    assert.res_status(201, res)

    -- Request dev
    local dev_thread = start_backend_once(host1, port1, "dev")
    socket.sleep(0.05)
    res = assert(proxy_client:get("/api/orders", { headers = { ["X-Upstream-Env"] = "dev" } }))
    assert.res_status(200, res)
    assert.equal("dev", res.headers["x-backend"])
    assert(dev_thread:join())

    -- Request prod
    local prod_thread = start_backend_once(host2, port2, "prod")
    socket.sleep(0.05)
    res = assert(proxy_client:get("/api/orders", { headers = { ["X-Upstream-Env"] = "prod" } }))
    assert.res_status(200, res)
    assert.equal("prod", res.headers["x-backend"])
    assert(prod_thread:join())

    -- Request via consumer id header fallback
    local fallback_thread = start_backend_once(host1, port1, "dev")
    socket.sleep(0.05)
    res = assert(proxy_client:get("/api/orders", { headers = { ["X-Consumer-Id"] = "dev" } }))
    assert.res_status(200, res)
    assert.equal("dev", res.headers["x-backend"])
    assert(fallback_thread:join())
  end)
end)
