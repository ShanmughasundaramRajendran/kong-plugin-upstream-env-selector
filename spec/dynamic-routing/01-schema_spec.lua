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
    assert.equal("map", upstreams.type)
    assert.is_table(upstreams.keys)
    assert.is_table(upstreams.values)
  end)

  it("uses expected defaults for header names", function()
    local config_fields = get_config_fields()
    local upstream_header_name = find_field(config_fields, "upstream_header_name")
    local client_id_header_name = find_field(config_fields, "client_id_header_name")

    assert.is_table(upstream_header_name)
    assert.is_table(client_id_header_name)

    assert.equal("X-Upstream-Header", upstream_header_name.default)
    assert.equal("X-Client-Id", client_id_header_name.default)
    assert.is_true(upstream_header_name.required)
    assert.is_true(client_id_header_name.required)
  end)

  it("defines access_policy and endpoint selector blocks", function()
    local config_fields = get_config_fields()
    local access_policy = find_field(config_fields, "access_policy")
    local endpoint = find_field(config_fields, "endpoint")

    assert.is_table(access_policy)
    assert.is_table(endpoint)

    assert.equal("record", access_policy.type)
    assert.equal("record", endpoint.type)
    assert.is_table(access_policy.fields)
    assert.is_table(endpoint.fields)

    local access_sni = find_field(access_policy.fields, "sni")
    local endpoint_sni = find_field(endpoint.fields, "sni")

    assert.is_table(access_sni)
    assert.is_table(endpoint_sni)
    assert.equal(false, access_sni.default)
    assert.equal(false, endpoint_sni.default)
  end)
end)
