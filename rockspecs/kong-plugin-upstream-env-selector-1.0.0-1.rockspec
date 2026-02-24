package = "kong-plugin-upstream-env-selector"
version = "1.0.0-1"

source = {
  url = "git://example.com/kong-plugin-upstream-env-selector",
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
    ["kong.plugins.upstream-env-selector.handler"] = "kong/plugins/upstream-env-selector/handler.lua",
    ["kong.plugins.upstream-env-selector.schema"]  = "kong/plugins/upstream-env-selector/schema.lua",
  }
}
