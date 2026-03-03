local kong = kong
local ngx = ngx
local cjson = require "cjson.safe"

local _M = {
  VERSION = "1.0.0",
  PRIORITY = 2003,
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
local UPSTREAM_ENV_TAG_PREFIX = "upstream_env:"
local B64CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

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

local function decode_base64(data)
  if ngx and ngx.decode_base64 then
    return ngx.decode_base64(data)
  end

  data = data:gsub("[^" .. B64CHARS .. "=]", "")
  local bitstr = data:gsub(".", function(x)
    if x == "=" then
      return ""
    end

    local idx = B64CHARS:find(x, 1, true)
    if not idx then
      return ""
    end

    local n = idx - 1
    local bits = ""
    for i = 6, 1, -1 do
      bits = bits .. (n % 2^i - n % 2^(i - 1) > 0 and "1" or "0")
    end
    return bits
  end)

  return bitstr:gsub("%d%d%d?%d?%d?%d?%d?%d?", function(x)
    if #x ~= 8 then
      return ""
    end

    local c = 0
    for i = 1, 8 do
      if x:sub(i, i) == "1" then
        c = c + 2^(8 - i)
      end
    end

    return string.char(c)
  end)
end

local function b64url_decode(input)
  if type(input) ~= "string" or input == "" then
    return nil
  end

  local data = input:gsub("-", "+"):gsub("_", "/")
  local mod = #data % 4
  if mod == 2 then
    data = data .. "=="
  elseif mod == 3 then
    data = data .. "="
  elseif mod ~= 0 then
    return nil
  end

  return decode_base64(data)
end

local function get_jwt_claim_client_id()
  local auth = kong.request.get_header("authorization") or kong.request.get_header("Authorization")
  if type(auth) == "table" then
    auth = auth[1]
  end

  if type(auth) ~= "string" then
    return nil
  end

  local token = auth:match("^[Bb]earer%s+(.+)$")
  if not token then
    return nil
  end

  local parts = {}
  for part in token:gmatch("[^%.]+") do
    parts[#parts + 1] = part
  end

  if #parts < 2 then
    return nil
  end

  local payload_json = b64url_decode(parts[2])
  if not payload_json then
    return nil
  end

  local payload = cjson.decode(payload_json)
  if type(payload) ~= "table" then
    return nil
  end

  local client_id = payload["client_id"]
  if type(client_id) == "string" and client_id ~= "" then
    return client_id
  end

  return nil
end

local function get_consumer_upstream_env(consumer)
  if type(consumer) ~= "table" then
    return nil
  end

  local tags = consumer.tags
  if type(tags) ~= "table" then
    return nil
  end

  for _, tag in ipairs(tags) do
    if type(tag) == "string" and tag:sub(1, #UPSTREAM_ENV_TAG_PREFIX) == UPSTREAM_ENV_TAG_PREFIX then
      local env = tag:sub(#UPSTREAM_ENV_TAG_PREFIX + 1)
      if is_non_empty_string(env) then
        return env
      end
    end
  end

  return nil
end

local function get_upstream_by_names(names, upstreams)
  if upstreams == nil or names == nil or #names == 0 then
    return nil
  end

  for _, name in ipairs(names) do
    if is_non_empty_string(name) then
      local upstream = upstreams[name]
      if upstream then
        return upstream, name
      end
    end
  end

  return nil
end

local function get_upstream_by_default_header(header_name, upstreams)
  if not is_non_empty_string(header_name) then
    return nil
  end

  local value = kong.request.get_header(header_name)
  if not value then
    return nil
  end

  local names = type(value) == "table" and value or { value }
  return get_upstream_by_names(names, upstreams)
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
  if not env_name then
    return nil
  end

  local names = type(env_name) == "table" and env_name or { env_name }
  return get_upstream_by_names(names, upstreams)
end

local function get_upstream_by_query_param(name, upstreams)
  if not is_non_empty_string(name) then
    return nil
  end

  local env_name = kong.request.get_query_arg(name)
  if not env_name then
    return nil
  end

  local names = type(env_name) == "table" and env_name or { env_name }
  return get_upstream_by_names(names, upstreams)
end

local function set_upstream(upstream_name, reason, selector_key)
  kong.service.set_upstream(upstream_name)
  kong.ctx.shared.upstream_backend_id = upstream_name
  kong.ctx.shared.upstream_selector_reason = reason
  kong.ctx.shared.upstream_selector_key = selector_key
end

local function validate_inputs(cfg)
  if type(cfg) ~= "table" or not next(cfg) then
    return "dynamic-routing: No config loaded"
  end

  local accp = cfg.access_policy
  local epcp = cfg.endpoint

  if accp ~= nil and type(accp) ~= "table" then
    return "dynamic-routing: Invalid configuration for access_policy"
  end

  if epcp ~= nil and type(epcp) ~= "table" then
    return "dynamic-routing: Invalid configuration for endpoint policy"
  end

  accp = accp or {}
  epcp = epcp or {}

  if not (accp.sni or accp.query_param_name or accp.header_name
    or epcp.sni or epcp.query_param_name or epcp.header_name) then
    return "dynamic-routing: No config values found"
  end

  return nil
end

local function get_client_id(cfg)
  local header_name = (cfg and cfg.client_id_header_name) or DEFAULT_CLIENT_ID_HEADER_NAME
  local client_id = first_non_empty_string(kong.request.get_header(header_name))

  if client_id then
    return client_id
  end

  local consumer
  if kong.client and kong.client.get_consumer then
    consumer = kong.client.get_consumer()
  end

  local consumer_upstream_env = get_consumer_upstream_env(consumer)
  if consumer_upstream_env then
    return consumer_upstream_env
  end

  client_id = get_jwt_claim_client_id()
  if client_id then
    return client_id
  end

  if consumer then
    return first_non_empty_string({ consumer.custom_id, consumer.username, consumer.id })
  end

  return nil
end

function _M:access(cfg)
  -- ACCESS PHASE:
  -- Determine upstream using strict priority:
  -- 1) default header
  -- 2) access policy (sni -> header -> query)
  -- 3) endpoint policy (sni -> header -> query)
  -- 4) client_id chain (header -> jwt claim -> consumer)
  if type(cfg) ~= "table" then
    kong.log.debug("dynamic-routing: No config loaded")
    return
  end

  local upstreams = cfg.upstreams
  if type(upstreams) ~= "table" then
    kong.log.debug("dynamic-routing: Missing upstream map")
    return
  end

  local default_header_name = cfg.upstream_header_name or DEFAULT_UPSTREAM_HEADER_NAME

  local upstream, key = get_upstream_by_default_header(default_header_name, upstreams)
  if upstream then
    kong.log.debug("dynamic-routing: upstream found using default header: ", upstream)
    set_upstream(upstream, "default_header", key)
    return
  end

  local err = validate_inputs(cfg)
  if not err then
    local policy = cfg.access_policy or {}
    local endpoint = cfg.endpoint or {}

    upstream, key = get_upstream_by_sni(policy[BY_SNI], upstreams)
    if upstream then
      kong.log.debug("dynamic-routing: upstream env by client sni: ", upstream)
      set_upstream(upstream, "client_sni", key)
      return
    end

    upstream, key = get_upstream_by_header(policy[BY_HEADER], upstreams)
    if upstream then
      kong.log.debug("dynamic-routing: upstream env by client header: ", upstream)
      set_upstream(upstream, "client_header", key)
      return
    end

    upstream, key = get_upstream_by_query_param(policy[BY_QPARAM_NAME], upstreams)
    if upstream then
      kong.log.debug("dynamic-routing: upstream env by client query param: ", upstream)
      set_upstream(upstream, "client_query", key)
      return
    end

    upstream, key = get_upstream_by_sni(endpoint[BY_SNI], upstreams)
    if upstream then
      kong.log.debug("dynamic-routing: upstream env by resource sni: ", upstream)
      set_upstream(upstream, "resource_sni", key)
      return
    end

    upstream, key = get_upstream_by_header(endpoint[BY_HEADER], upstreams)
    if upstream then
      kong.log.debug("dynamic-routing: upstream env by resource header: ", upstream)
      set_upstream(upstream, "resource_header", key)
      return
    end

    upstream, key = get_upstream_by_query_param(endpoint[BY_QPARAM_NAME], upstreams)
    if upstream then
      kong.log.debug("dynamic-routing: upstream env by resource query param: ", upstream)
      set_upstream(upstream, "resource_query", key)
      return
    end
  end

  local client_id = get_client_id(cfg)
  if client_id then
    local client_id_header_name = (cfg and cfg.client_id_header_name) or DEFAULT_CLIENT_ID_HEADER_NAME
    if kong.service and kong.service.request and kong.service.request.set_header then
      kong.service.request.set_header(client_id_header_name, client_id)
    end

    upstream = upstreams[client_id]
    if upstream then
      kong.log.debug("dynamic-routing: upstream env by client id: ", upstream)
      set_upstream(upstream, "client_id", client_id)
      return
    end
  end

  if err then
    kong.log.debug(err)
  end

  kong.log.debug("dynamic-routing: No custom environments configured, using default/primary environment")
end

return _M
