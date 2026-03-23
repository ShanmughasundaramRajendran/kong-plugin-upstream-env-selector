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
    assert.equal("string", upstreams.values.type)

    local upstream_ports = find_field(config_fields, "upstream_ports")
    assert.is_table(upstream_ports)
    assert.is_true(upstream_ports.required)
    assert.equal("map", upstream_ports.type)
    assert.is_table(upstream_ports.keys)
    assert.is_table(upstream_ports.values)
    assert.equal("string", upstream_ports.values.type)
  end)

  it("uses expected defaults for top-level fields", function()
    local config_fields = get_config_fields()
    local upstream_header_name = find_field(config_fields, "upstream_header_name")

    assert.is_table(upstream_header_name)
    assert.is_nil(find_field(config_fields, "client_id_header_name"))

    assert.equal("X-Upstream-Env", upstream_header_name.default)
    assert.is_true(upstream_header_name.required)
  end)

  it("defines access_policy and endpoint nested selector blocks", function()
    local config_fields = get_config_fields()
    local access_policy = find_field(config_fields, "access_policy")
    local endpoint = find_field(config_fields, "endpoint")

    assert.is_table(access_policy)
    assert.is_table(endpoint)

    local access_fields = access_policy.fields
    local endpoint_fields = endpoint.fields

    assert.is_table(access_fields)
    assert.is_table(endpoint_fields)
    assert.is_table(find_field(access_fields, "sni"))
    assert.is_table(find_field(access_fields, "header_name"))
    assert.is_table(find_field(access_fields, "query_param_name"))
    assert.is_table(find_field(endpoint_fields, "sni"))
    assert.is_table(find_field(endpoint_fields, "header_name"))
    assert.is_table(find_field(endpoint_fields, "query_param_name"))
  end)
end)
