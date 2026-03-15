local schema = require "kong.plugins.dynamic-routing.schema"

local function get_config_fields()
  for _, field in ipairs(schema.fields) do
    if field.config then
      return field.config.fields
    end
  end

  return nil
end

local function find_field(fields, name)
  for _, field in ipairs(fields) do
    if field[name] then
      return field[name]
    end
  end

  return nil
end

describe("dynamic-routing (schema)", function()
  it("declares plugin name and top-level config record", function()
    assert.equal("dynamic-routing", schema.name)
    assert.is_table(schema.fields)

    local config_fields = get_config_fields()
    assert.is_table(config_fields)
  end)

  it("requires upstreams map in config", function()
    local config_fields = get_config_fields()
    local upstreams = find_field(config_fields, "upstreams")

    assert.is_table(upstreams)
    assert.is_true(upstreams.required)
    assert.equal(1, upstreams.len_min)
    assert.equal("map", upstreams.type)
    assert.is_table(upstreams.keys)
    assert.is_table(upstreams.values)
  end)

  it("uses expected defaults for header names", function()
    local config_fields = get_config_fields()
    local upstream_header_name = find_field(config_fields, "upstream_header_name")
    local client_id_header_name = find_field(config_fields, "client_id_header_name")
    local sni = find_field(config_fields, "sni")
    local header_name = find_field(config_fields, "header_name")
    local query_param_name = find_field(config_fields, "query_param_name")

    assert.is_table(upstream_header_name)
    assert.is_table(client_id_header_name)
    assert.is_table(sni)
    assert.is_table(header_name)
    assert.is_table(query_param_name)

    assert.equal("X-Upstream-Env", upstream_header_name.default)
    assert.equal("X-Client-Id", client_id_header_name.default)
    assert.equal(false, sni.default)
    assert.equal(1, header_name.len_min)
    assert.equal(1, query_param_name.len_min)
    assert.is_true(upstream_header_name.required)
    assert.is_true(client_id_header_name.required)
  end)

  it("does not define access_policy or endpoint nested blocks", function()
    local config_fields = get_config_fields()
    local access_policy = find_field(config_fields, "access_policy")
    local endpoint = find_field(config_fields, "endpoint")

    assert.is_nil(access_policy)
    assert.is_nil(endpoint)
  end)
end)
