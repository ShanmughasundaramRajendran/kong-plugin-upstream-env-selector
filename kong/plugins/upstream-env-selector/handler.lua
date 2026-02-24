local kong = kong
local ngx = ngx

local redis_connector_ok, redis_connector = pcall(require, "resty.redis")

local _M = {
  VERSION = "1.0.0",
  PRIORITY = 2003,
}

-- shared dict for cache; prefer using 'kong_cache' if available, but shared dict is simplest in custom images.
-- In production, you should ensure nginx_http_lua_shared_dict includes this:
-- lua_shared_dict upstream_env_selector_cache 10m;
local CACHE = ngx.shared and ngx.shared.upstream_env_selector_cache or nil

local function _trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalize(cfg, v)
  if v == nil then
    return nil
  end

  if type(v) ~= "string" then
    v = tostring(v)
  end

  v = _trim(v)
  if v == "" then
    return nil
  end

  if cfg.normalize then
    v = string.lower(v)
  end

  return v
end

local function get_upstream_by_names(names, upstreams)
  if upstreams == nil or names == nil or #names == 0 then
    return nil
  end

  for _, name in ipairs(names) do
    local upstream = upstreams[name]
    if upstream then
      return upstream, name
    end
  end

  return nil
end

-- Kong header can be string or table
local function get_selector_from_header(cfg, header_name)
  local value = kong.request.get_header(header_name)
  if value == nil then
    return nil
  end

  if type(value) == "table" then
    local names = {}
    for _, v in ipairs(value) do
      v = normalize(cfg, v)
      if v then
        table.insert(names, v)
      end
    end
    if #names == 0 then
      return nil
    end
    return names
  end

  value = normalize(cfg, value)
  return value
end

local function get_upstream_by_default_header(cfg, upstreams)
  local header_name = cfg.upstream_header_name
  local selector = get_selector_from_header(cfg, header_name)
  if not selector then
    return nil
  end

  if type(selector) == "table" then
    return get_upstream_by_names(selector, upstreams)
  end

  local upstream = upstreams[selector]
  if upstream then
    return upstream, selector
  end

  return nil
end

local function get_upstream_by_sni(cfg, enabled_flag, upstreams)
  if not enabled_flag then
    return nil
  end

  local sni = ngx.var.ssl_server_name
  sni = normalize(cfg, sni)
  if not sni then
    return nil
  end

  local upstream = upstreams[sni]
  if upstream then
    return upstream, sni
  end
  return nil
end

local function get_upstream_by_header(cfg, header_name, upstreams)
  if not header_name then
    return nil
  end

  local selector = get_selector_from_header(cfg, header_name)
  if not selector then
    return nil
  end

  if type(selector) == "table" then
    return get_upstream_by_names(selector, upstreams)
  end

  local upstream = upstreams[selector]
  if upstream then
    return upstream, selector
  end
  return nil
end

local function get_upstream_by_query_param(cfg, value, upstreams)
  value = normalize(cfg, value)
  if not value then
    return nil
  end

  local upstream = upstreams[value]
  if upstream then
    return upstream, value
  end
  return nil
end

local function validate_inputs(cfg)
  if type(cfg) ~= "table" then
    return "upstream-env-selector: No config loaded"
  end

  if cfg.use_redis ~= true and type(cfg.upstreams) ~= "table" then
    return "upstream-env-selector: Invalid configuration (upstreams missing)"
  end

  local accp = cfg.access_policy
  local epcp = cfg.endpoint

  if accp ~= nil and type(accp) ~= "table" then
    return "upstream-env-selector: Invalid access_policy"
  end
  if epcp ~= nil and type(epcp) ~= "table" then
    return "upstream-env-selector: Invalid endpoint policy"
  end

  accp = accp or {}
  epcp = epcp or {}

  if not (accp.sni or accp.query_param_name or accp.header_name
          or epcp.sni or epcp.query_param_name or epcp.header_name) then
    return "upstream-env-selector: No policy values found"
  end

  if cfg.use_redis then
    if not redis_connector_ok then
      return "upstream-env-selector: Redis enabled but lua-resty-redis not available"
    end
    if type(cfg.redis) ~= "table" then
      return "upstream-env-selector: Redis enabled but config.redis missing"
    end
  end

  return nil
end

local function get_client_id(cfg)
  if cfg.client_id_source == "header" then
    local header_name = cfg.client_id_header_name or "X-Consumer-Id"
    local selector = get_selector_from_header(cfg, header_name)
    if type(selector) == "table" then
      return selector[1]
    end
    return selector
  end

  local consumer = kong.client.get_consumer()
  if not consumer then
    return nil
  end

  local src = cfg.client_id_source
  if src == "custom_id" then
    return normalize(cfg, consumer.custom_id)
  elseif src == "username" then
    return normalize(cfg, consumer.username)
  end

  return normalize(cfg, consumer.id)
end

local function set_upstream(upstream_name, reason, selector_key)
  kong.service.set_upstream(upstream_name)

  -- Expose selection details for debugging/observability.
  kong.ctx.shared.upstream_backend_id = upstream_name
  kong.ctx.shared.upstream_selector_reason = reason
  kong.ctx.shared.upstream_selector_key = selector_key
end

-- cache helpers
local function cache_get(key)
  if not CACHE then
    return nil
  end
  return CACHE:get(key)
end

local function cache_set(key, value, ttl)
  if not CACHE then
    return
  end
  -- best-effort
  CACHE:set(key, value, ttl)
end

local function redis_connect(cfg)
  local red = redis_connector:new()
  red:set_timeout(cfg.redis.timeout_ms)

  local ok, err = red:connect(cfg.redis.host, cfg.redis.port)
  if not ok then
    return nil, err
  end

  if cfg.redis.ssl then
    local sess_ok, sess_err = red:sslhandshake(nil, cfg.redis.host, cfg.redis.ssl_verify)
    if not sess_ok then
      return nil, sess_err
    end
  end

  if cfg.redis.username and cfg.redis.password then
    local auth_ok, auth_err = red:auth(cfg.redis.username, cfg.redis.password)
    if not auth_ok then
      return nil, auth_err
    end
  elseif cfg.redis.password then
    local auth_ok, auth_err = red:auth(cfg.redis.password)
    if not auth_ok then
      return nil, auth_err
    end
  end

  if cfg.redis.database and cfg.redis.database ~= 0 then
    local sel_ok, sel_err = red:select(cfg.redis.database)
    if not sel_ok then
      return nil, sel_err
    end
  end

  return red
end

local function redis_keepalive(cfg, red)
  if not red then
    return
  end
  -- best-effort keepalive
  red:set_keepalive(cfg.redis.keepalive_ms, cfg.redis.pool_size)
end

local function lookup_upstream(cfg, upstreams_map, selector_value)
  -- Normalized selector_value must be non-nil
  if not selector_value then
    return nil
  end

  -- 1) static map mode first (if configured)
  if upstreams_map then
    local u = upstreams_map[selector_value]
    if u then
      return u, "static"
    end
  end

  -- 2) redis mode
  if not cfg.use_redis then
    return nil
  end

  local cache_key = "u:" .. selector_value
  local cached = cache_get(cache_key)
  if cached ~= nil then
    if cached == "__nil__" then
      return nil
    end
    return cached, "cache"
  end

  local red, err = redis_connect(cfg)
  if not red then
    kong.log.warn("upstream-env-selector: redis connect failed: ", err)
    if cfg.redis_fail_open then
      return nil
    end
    return kong.response.exit(503, { message = "Redis unavailable" })
  end

  local key = cfg.redis_key_prefix .. selector_value
  local val, get_err = red:get(key)
  redis_keepalive(cfg, red)

  if get_err then
    kong.log.warn("upstream-env-selector: redis get failed: ", get_err)
    if cfg.redis_fail_open then
      return nil
    end
    return kong.response.exit(503, { message = "Redis error" })
  end

  if val == ngx.null or val == nil or val == "" then
    cache_set(cache_key, "__nil__", cfg.negative_ttl_sec)
    return nil
  end

  cache_set(cache_key, val, cfg.cache_ttl_sec)
  return val, "redis"
end

function _M:access(cfg)
  -- Normalize upstream map keys once per request
  local upstreams = nil
  if type(cfg.upstreams) == "table" then
    upstreams = {}
    for k, v in pairs(cfg.upstreams) do
      local nk = normalize(cfg, k)
      if nk and v and v ~= "" then
        upstreams[nk] = v
      end
    end
  end

  -- 1) Highest priority: default header X-Upstream-Env
  do
    local selector = get_selector_from_header(cfg, cfg.upstream_header_name)
    if selector then
      if type(selector) == "table" then
        -- multi-value: choose first that resolves
        for _, s in ipairs(selector) do
          local u, src_or_res = lookup_upstream(cfg, upstreams, s)
          if type(src_or_res) == "table" and src_or_res.status then
            return src_or_res -- response.exit
          end
          if u then
            kong.log.debug("upstream-env-selector: upstream found using default header: ", u)
            return set_upstream(u, "default_header", s)
          end
        end
      else
        local u, src_or_res = lookup_upstream(cfg, upstreams, selector)
        if type(src_or_res) == "table" and src_or_res.status then
          return src_or_res
        end
        if u then
          kong.log.debug("upstream-env-selector: upstream found using default header: ", u)
          return set_upstream(u, "default_header", selector)
        end
      end
    end
  end

  -- 2) Validate policy config (if invalid -> log and do nothing)
  local err = validate_inputs(cfg)
  if err then
    kong.log.debug(err)
    kong.log.debug("upstream-env-selector: No custom environments configured, using default/primary routing")
    if cfg.strict then
      return kong.response.exit(500, { message = err })
    end
    return
  end

  local policy = cfg.access_policy or {}
  local endpoint = cfg.endpoint or {}

  -- 3) Second priority: client metadata SNI
  do
    local sni = normalize(cfg, ngx.var.ssl_server_name)
    if policy.sni and sni then
      local u, src_or_res = lookup_upstream(cfg, upstreams, sni)
      if type(src_or_res) == "table" and src_or_res.status then
        return src_or_res
      end
      if u then
        kong.log.debug("upstream-env-selector: upstream env by client SNI: ", u)
        return set_upstream(u, "client_sni", sni)
      end
    end
  end

  -- 4) Third priority: client metadata header
  do
    local hn = policy.header_name
    if hn then
      local selector = get_selector_from_header(cfg, hn)
      if selector then
        if type(selector) == "table" then
          for _, s in ipairs(selector) do
            local u, src_or_res = lookup_upstream(cfg, upstreams, s)
            if type(src_or_res) == "table" and src_or_res.status then
              return src_or_res
            end
            if u then
              kong.log.debug("upstream-env-selector: upstream env by client header: ", u)
              return set_upstream(u, "client_header", s)
            end
          end
        else
          local u, src_or_res = lookup_upstream(cfg, upstreams, selector)
          if type(src_or_res) == "table" and src_or_res.status then
            return src_or_res
          end
          if u then
            kong.log.debug("upstream-env-selector: upstream env by client header: ", u)
            return set_upstream(u, "client_header", selector)
          end
        end
      end
    end
  end

  -- 5) Fourth priority: client metadata query param
  if policy.query_param_name then
    local qv = kong.request.get_query_arg(policy.query_param_name)
    qv = normalize(cfg, qv)
    if qv then
      local u, src_or_res = lookup_upstream(cfg, upstreams, qv)
      if type(src_or_res) == "table" and src_or_res.status then
        return src_or_res
      end
      if u then
        kong.log.debug("upstream-env-selector: upstream env by client query param: ", u)
        return set_upstream(u, "client_query", qv)
      end
    end
  end

  -- 6) Fifth priority: resource/endpoint SNI
  do
    local sni = normalize(cfg, ngx.var.ssl_server_name)
    if endpoint.sni and sni then
      local u, src_or_res = lookup_upstream(cfg, upstreams, sni)
      if type(src_or_res) == "table" and src_or_res.status then
        return src_or_res
      end
      if u then
        kong.log.debug("upstream-env-selector: upstream env by resource SNI: ", u)
        return set_upstream(u, "resource_sni", sni)
      end
    end
  end

  -- 7) Sixth priority: resource/endpoint header
  do
    local hn = endpoint.header_name
    if hn then
      local selector = get_selector_from_header(cfg, hn)
      if selector then
        if type(selector) == "table" then
          for _, s in ipairs(selector) do
            local u, src_or_res = lookup_upstream(cfg, upstreams, s)
            if type(src_or_res) == "table" and src_or_res.status then
              return src_or_res
            end
            if u then
              kong.log.debug("upstream-env-selector: upstream env by resource header: ", u)
              return set_upstream(u, "resource_header", s)
            end
          end
        else
          local u, src_or_res = lookup_upstream(cfg, upstreams, selector)
          if type(src_or_res) == "table" and src_or_res.status then
            return src_or_res
          end
          if u then
            kong.log.debug("upstream-env-selector: upstream env by resource header: ", u)
            return set_upstream(u, "resource_header", selector)
          end
        end
      end
    end
  end

  -- 8) Seventh priority: resource/endpoint query param
  if endpoint.query_param_name then
    local qv = kong.request.get_query_arg(endpoint.query_param_name)
    qv = normalize(cfg, qv)
    if qv then
      local u, src_or_res = lookup_upstream(cfg, upstreams, qv)
      if type(src_or_res) == "table" and src_or_res.status then
        return src_or_res
      end
      if u then
        kong.log.debug("upstream-env-selector: upstream env by resource query param: ", u)
        return set_upstream(u, "resource_query", qv)
      end
    end
  end

  -- 9) Last priority: client_id
  local client_id = get_client_id(cfg)
  if client_id then
    local u, src_or_res = lookup_upstream(cfg, upstreams, client_id)
    if type(src_or_res) == "table" and src_or_res.status then
      return src_or_res
    end
    if u then
      kong.log.debug("upstream-env-selector: upstream env by client id: ", u)
      return set_upstream(u, "client_id", client_id)
    end
  end

  -- 10) No match
  kong.log.debug("upstream-env-selector: no match found; leaving default routing")
  if cfg.strict then
    return kong.response.exit(400, { message = "No matching upstream for request" })
  end
end

return _M
