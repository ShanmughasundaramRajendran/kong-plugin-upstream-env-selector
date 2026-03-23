local kong = kong
local ngx = ngx

local _M = {
  VERSION = "1.0.0",
  -- Must run after auth plugins so consumer context is available before
  -- username-based dynamic upstream selection.
  PRIORITY = 800,
}

-- Plugin lifecycle notes:
-- `rewrite` phase: intentionally not implemented (no route mutation here).
-- `access` phase: implemented below; selector precedence is applied here.
-- `log` phase: intentionally not implemented; selection metadata is already in `kong.ctx.plugin`.

local BY_SNI = "sni"
local BY_HEADER = "header_name"
local BY_QPARAM_NAME = "query_param_name"
local DEFAULT_UPSTREAM_HEADER_NAME = "X-Upstream-Env"
local CLIENT_ID_HEADER_NAME = "client_id"

local function is_non_empty_string(v)
  return type(v) == "string" and v ~= ""
end

local function first_non_empty_string(value)
  if is_non_empty_string(value) then
    return value
  end

  if type(value) == "table" then
    for _, v in ipairs(value) do
      if is_non_empty_string(v) then
        return v
      end
    end
  end

  return nil
end

local function get_target(upstreams, upstream_ports, selector_key)
  local host = upstreams[selector_key]
  local port = tonumber(upstream_ports[selector_key])

  if not is_non_empty_string(host) then
    return nil
  end

  if type(port) ~= "number" or port % 1 ~= 0 then
    return nil
  end

  return {
    host = host,
    port = port,
  }
end

local function get_target_by_sni(enabled, upstreams, upstream_ports)
  if not enabled then
    return nil
  end

  local name = ngx.var.ssl_server_name
  if not is_non_empty_string(name) then
    return nil
  end

  local target = get_target(upstreams, upstream_ports, name)
  if target then
    return target, name
  end

  return nil
end

local function get_target_by_header(header_name, upstreams, upstream_ports)
  if not is_non_empty_string(header_name) then
    return nil
  end

  local env_name = kong.request.get_header(header_name)
  if not is_non_empty_string(env_name) then
    return nil
  end

  local target = get_target(upstreams, upstream_ports, env_name)
  if target then
    return target, env_name
  end

  return nil
end

local function get_target_by_query_param(name, upstreams, upstream_ports)
  if not is_non_empty_string(name) then
    return nil
  end

  local env_name = kong.request.get_query_arg(name)
  if not is_non_empty_string(env_name) then
    return nil
  end

  local target = get_target(upstreams, upstream_ports, env_name)
  if target then
    return target, env_name
  end

  return nil
end

local function resolve_policy_target(policy, upstreams, upstream_ports, policy_name)
  local policy_scope = policy_name == "access_policy" and "access policy" or "endpoint policy"

  if policy == nil then
    return nil
  end

  if type(policy) ~= "table" then
    kong.log(policy_name, " policy is invalid (expected table, got ", type(policy), ")")
    return nil
  end

  local target, key = get_target_by_sni(policy[BY_SNI], upstreams, upstream_ports)
  if target then
    kong.log(
      "rerouting request to target ", target.host, ":", target.port,
      " because ", policy_scope, " SNI selector matched value ", key,
      " (reason=", policy_name, "_sni)"
    )
    return target, key, policy_name .. "_sni"
  end

  target, key = get_target_by_header(policy[BY_HEADER], upstreams, upstream_ports)
  if target then
    kong.log(
      "rerouting request to target ", target.host, ":", target.port,
      " because ", policy_scope, " header selector ", policy[BY_HEADER],
      " matched selector key ", key,
      " (reason=", policy_name, "_header)"
    )
    return target, key, policy_name .. "_header"
  end

  target, key = get_target_by_query_param(policy[BY_QPARAM_NAME], upstreams, upstream_ports)
  if target then
    kong.log(
      "rerouting request to target ", target.host, ":", target.port,
      " because ", policy_scope, " query-param selector ", policy[BY_QPARAM_NAME],
      " matched selector key ", key,
      " (reason=", policy_name, "_query)"
    )
    return target, key, policy_name .. "_query"
  end

  return nil
end

local function set_target(target, reason, selector_key)
  kong.service.set_target(target.host, target.port)
  kong.ctx.plugin.upstream_backend_id = target.host .. ":" .. target.port
  kong.ctx.plugin.upstream_selector_reason = reason
  kong.ctx.plugin.upstream_selector_key = selector_key
end

local function get_client_id()
  local consumer
  if kong.client and kong.client.get_consumer then
    consumer = kong.client.get_consumer()
  end

  -- Client ID source is the authenticated Kong consumer only.
  return consumer and first_non_empty_string(consumer.username) or nil
end

function _M:access(cfg)
  -- ACCESS PHASE:
  -- Determine upstream using strict priority:
  -- 1) default header
  -- 2) access policy / service-context-root selectors (sni -> header -> query)
  -- 3) endpoint policy / endpoint-subpath selectors (sni -> header -> query)
  -- 4) client_id from authenticated consumer.username
  if type(cfg) ~= "table" then
    kong.log("No config loaded")
    return
  end

  local upstreams = cfg.upstreams
  if type(upstreams) ~= "table" then
    kong.log("Missing upstream host map")
    return
  end

  local upstream_ports = cfg.upstream_ports
  if type(upstream_ports) ~= "table" then
    kong.log("Missing upstream port map")
    return
  end

  local default_header_name = cfg.upstream_header_name or DEFAULT_UPSTREAM_HEADER_NAME

  local target, key, reason = get_target_by_header(default_header_name, upstreams, upstream_ports)
  if target then
    kong.log("target found using default header: ", target.host, ":", target.port)
    set_target(target, "default_header", key)
    return
  end

  target, key, reason = resolve_policy_target(cfg.access_policy, upstreams, upstream_ports, "access_policy")
  if target then
    set_target(target, reason, key)
    return
  end

  target, key, reason = resolve_policy_target(cfg.endpoint, upstreams, upstream_ports, "endpoint")
  if target then
    set_target(target, reason, key)
    return
  end

  local client_id = get_client_id()
  if client_id then
    if kong.service and kong.service.request and kong.service.request.set_header then
      kong.service.request.set_header(CLIENT_ID_HEADER_NAME, client_id)
    end

    target = get_target(upstreams, upstream_ports, client_id)
    if target then
      kong.log("rerouting request to target ", target.host, ":", target.port, " based on consumer.username ", client_id)
      set_target(target, "client_id", client_id)
      return
    end
  end

  kong.log("No custom environments configured, using default/primary environment")
end

return _M
