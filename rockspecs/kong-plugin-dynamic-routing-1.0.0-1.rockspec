package = "kong-plugin-dynamic-routing"
version = "1.0.0-1"

source = {
  url = "git://example.com/kong-plugin-dynamic-routing",
  tag = "1.0.0",
}

description = {
  summary = "Dynamic upstream environment selector plugin for Kong Gateway",
  license = "Apache-2.0",
}

dependencies = {
  "lua >= 5.1",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.dynamic-routing.handler"] = "kong/plugins/dynamic-routing/handler.lua",
    ["kong.plugins.dynamic-routing.schema"]  = "kong/plugins/dynamic-routing/schema.lua",
  }
}
