return {
  manifest_version = 1,
  type = "program",
  name = "wh-controller",
  version = "0.2.0",
  source_base = "https://raw.githubusercontent.com/wradley/cc-wh-controller/refs/heads/main",
  source_prefix = nil,
  files = {
    "README.md",
    "install/templates/config.lua",
    "src/main.lua",
    "src/app/executor.lua",
    "src/app/runtime.lua",
    "src/app/snapshot.lua",
    "src/infra/network.lua",
    "src/infra/persistence.lua",
    "src/model/config.lua",
    "src/ui/controller.lua",
    "src/util/tables.lua",
  },
  deps = {
    log              = { version = "0.1.0" },
    rednet_contracts = { version = "0.1.0" },
  },
  dev_deps = {
    luaunit = { version = "3.4" },
  },
}
