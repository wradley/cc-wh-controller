return {
  program = "wh-controller",
  role = "warehouse",
  files = {
    "README.md",
    "src/main.lua",
    "src/app/executor.lua",
    "src/app/runtime.lua",
    "src/app/snapshot.lua",
    "src/deps/log.lua",
    "src/infra/network.lua",
    "src/infra/persistence.lua",
    "src/infra/station.lua",
    "src/model/config.lua",
    "src/ui/controller.lua",
    "src/util/tables.lua",
  },
  config_template = {
    path = "/etc/wh-controller/config.lua",
    source_path = "install/templates/config.lua",
  },
}
