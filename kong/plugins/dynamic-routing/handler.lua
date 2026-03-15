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
-- `log` phase: intentionally not implemented; selection metadata is already in `kong.ctx.shared`.

local BY_SNI = "sni"
local BY_HEADER = "header_name"
local BY_QPARAM_NAME = "query_param_name"
local DEFAULT_UPSTREAM_HEADER_NAME = "X-Upstream-Env"
local DEFAULT_CLIENT_ID_HEADER_NAME = "X-Client-Id"

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

local function get_upstream_by_sni(enabled, upstreams)
  if not enabled then
    return nil
  end

  local name = ngx.var.ssl_server_name
  if not is_non_empty_string(name) then
    return nil
  end

  local upstream = upstreams[name]
  if upstream then
    return upstream, name
  end

  return nil
end

local function get_upstream_by_header(header_name, upstreams)
  if not is_non_empty_string(header_name) then
    return nil
  end

  local env_name = kong.request.get_header(header_name)
  if not is_non_empty_string(env_name) then
    return nil
  end

  local upstream = upstreams[env_name]
  if upstream then
    return upstream, env_name
  end

  return nil
end

local function get_upstream_by_query_param(name, upstreams)
  if not is_non_empty_string(name) then
    return nil
  end

  local env_name = kong.request.get_query_arg(name)
  if not is_non_empty_string(env_name) then
    return nil
  end

  local upstream = upstreams[env_name]
  if upstream then
    return upstream, env_name
  end

  return nil
end

local function resolve_selector_upstream(cfg, upstreams)
  local upstream, key = get_upstream_by_sni(cfg[BY_SNI], upstreams)
  if upstream then
    kong.log(
      "rerouting request to upstream ", upstream,
      " because sni selector matched value ", key,
      " (reason=sni)"
    )
    return upstream, key, "sni"
  end

  upstream, key = get_upstream_by_header(cfg[BY_HEADER], upstreams)
  if upstream then
    kong.log(
      "rerouting request to upstream ", upstream,
      " because header selector ", cfg[BY_HEADER],
      " matched selector key ", key,
      " (reason=header)"
    )
    return upstream, key, "header"
  end

  upstream, key = get_upstream_by_query_param(cfg[BY_QPARAM_NAME], upstreams)
  if upstream then
    kong.log(
      "rerouting request to upstream ", upstream,
      " because query-param selector ", cfg[BY_QPARAM_NAME],
      " matched selector key ", key,
      " (reason=query)"
    )
    return upstream, key, "query"
  end

  return nil
end

local function set_upstream(upstream_name, reason, selector_key)
  kong.service.set_upstream(upstream_name)
  kong.ctx.shared.upstream_backend_id = upstream_name
  kong.ctx.shared.upstream_selector_reason = reason
  kong.ctx.shared.upstream_selector_key = selector_key
end

function _M:configure(configs)
  if type(configs) ~= "table" then
    return
  end

  for _, plugin_conf in ipairs(configs) do
    local cfg = plugin_conf.config or plugin_conf
    if type(cfg) == "table" then
      if type(cfg.upstreams) ~= "table" then
        error("invalid dynamic-routing plugin configuration: upstreams must be a table")
      end

      local has_selector = cfg[BY_SNI]
        or is_non_empty_string(cfg[BY_HEADER])
        or is_non_empty_string(cfg[BY_QPARAM_NAME])

      if not has_selector then
        kong.log("dynamic-routing config has no sni/header_name/query_param_name selectors; only default header/client id fallback will apply")
      end
    end
  end
end

local function get_client_id()
  local consumer
  if kong.client and kong.client.get_consumer then
    consumer = kong.client.get_consumer()
  end

  return consumer and first_non_empty_string(consumer.username) or nil
end

function _M:access(cfg)
  -- ACCESS PHASE:
  -- Determine upstream using strict priority:
  -- 1) default header
  -- 2) configured selectors in this plugin instance (sni -> header -> query)
  -- 3) client_id from authenticated consumer.username
  if type(cfg) ~= "table" then
    kong.log("No config loaded")
    return
  end

  local upstreams = cfg.upstreams
  if type(upstreams) ~= "table" then
    kong.log("Missing upstream map")
    return
  end

  local default_header_name = cfg.upstream_header_name or DEFAULT_UPSTREAM_HEADER_NAME

  local upstream, key, reason = get_upstream_by_header(default_header_name, upstreams)
  if upstream then
    kong.log("upstream found using default header: ", upstream)
    set_upstream(upstream, "default_header", key)
    return
  end

  upstream, key, reason = resolve_selector_upstream(cfg, upstreams)
  if upstream then
    set_upstream(upstream, reason, key)
    return
  end

  local client_id = get_client_id()
  if client_id then
    local client_id_header_name = (cfg and cfg.client_id_header_name) or DEFAULT_CLIENT_ID_HEADER_NAME
    if kong.service and kong.service.request and kong.service.request.set_header then
      kong.service.request.set_header(client_id_header_name, client_id)
    end

    upstream = upstreams[client_id]
    if upstream then
      kong.log("rerouting request to upstream ", upstream, " based on consumer.username ", client_id)
      set_upstream(upstream, "client_id", client_id)
      return
    end
  end

  kong.log("No custom environments configured, using default/primary environment")
end

return _M
