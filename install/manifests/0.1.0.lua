return {
  program = "wh-controller",
  role = "warehouse",
  version = "0.1.0",
  runtime_entry = "src/main.lua",
  files = {
    { path = "README.md", source_path = "README.md" },
    { path = "src/main.lua", source_path = "src/main.lua" },
    { path = "src/app/executor.lua", source_path = "src/app/executor.lua" },
    { path = "src/app/runtime.lua", source_path = "src/app/runtime.lua" },
    { path = "src/app/snapshot.lua", source_path = "src/app/snapshot.lua" },
    { path = "src/deps/log.lua", source_path = "src/deps/log.lua" },
    { path = "src/infra/network.lua", source_path = "src/infra/network.lua" },
    { path = "src/infra/persistence.lua", source_path = "src/infra/persistence.lua" },
    { path = "src/infra/station.lua", source_path = "src/infra/station.lua" },
    { path = "src/model/config.lua", source_path = "src/model/config.lua" },
    { path = "src/ui/controller.lua", source_path = "src/ui/controller.lua" },
    { path = "src/util/tables.lua", source_path = "src/util/tables.lua" },
  },
  config_template = {
    path = "/etc/wh-controller/config.lua",
    source_path = "install/templates/config.lua",
  },
}
