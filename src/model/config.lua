---@class WarehouseConfigIdentity
---@field id string Stable warehouse identifier used in coordinator messages.
---@field address string Routing address used by Create logistics.
---@field display_name string Human-readable warehouse name for the terminal UI.

---@class WarehouseConfigNetwork
---@field local_wired_modem string Local wired modem side used for nearby peripherals/networking.
---@field ender_modem string Ender modem side used for coordinator messaging.
---@field protocol string Rednet protocol shared with the coordinator.
---@field heartbeat_seconds number Heartbeat broadcast interval in seconds.

---@class WarehouseConfigRuntime
---@field display_refresh_seconds number How often to redraw the terminal UI.
---@field status_refresh_seconds number How often to rebuild the warehouse snapshot.
---@field capacity_refresh_seconds number How often to re-probe storage slot capacity.

---@class WarehouseConfigLogistics
---@field stock_ticker string Peripheral name for the Create stock ticker.

---@class WarehouseConfigLogging
---@field output LogOutputConfig
---@field retention LogRetentionConfig

---@class WarehouseConfigTrain
---@field export_station string Peripheral name for the Create station used for exports.

---@class WarehouseStorageEntry
---@field storage_id string Stable storage identifier for UI/debugging.
---@field packager string Peripheral name for the Create packager attached to this storage.

---Warehouse controller configuration defaults and validation.
---@class WarehouseConfig
---@field version integer
---@field warehouse WarehouseConfigIdentity
---@field network WarehouseConfigNetwork
---@field runtime WarehouseConfigRuntime
---@field logistics WarehouseConfigLogistics
---@field logging WarehouseConfigLogging
---@field train WarehouseConfigTrain|nil
---@field storage WarehouseStorageEntry[]
local Config = {}

local function validatePositiveNumber(value, name)
  if type(value) ~= "number" or value <= 0 then
    error(name .. " must be a positive number", 0)
  end
end

local function loadConfigModule(path)
  if type(path) ~= "string" or path == "" then
    error("config path is required", 0)
  end

  if not fs.exists(path) then
    error("missing config file: " .. path, 0)
  end

  return dofile(path)
end

---Build the default warehouse controller config.
---@return WarehouseConfig
function Config.default()
  return {
    version = 1,
    warehouse = {
      id = "west",
      address = "WH_WEST",
      display_name = "West Warehouse",
    },
    network = {
      local_wired_modem = "back",
      ender_modem = "top",
      protocol = "warehouse_sync_v1",
      heartbeat_seconds = 5,
    },
    runtime = {
      display_refresh_seconds = 1,
      status_refresh_seconds = 5,
      capacity_refresh_seconds = 300,
    },
    logistics = {
      stock_ticker = "Create_StockTicker_0",
    },
    logging = {
      output = {
        file = "/var/wh-controller/warehouse.log",
        level = "info",
        mirror_to_term = false,
        timestamp = "utc",
      },
      retention = {
        mode = "truncate",
        max_lines = 1000,
      },
    },
    train = {
      export_station = "Create_Station_0",
    },
    storage = {
      {
        storage_id = "west_a",
        packager = "Create_Packager_0",
      },
      {
        storage_id = "west_b",
        packager = "Create_Packager_1",
      },
      {
        storage_id = "west_c",
        packager = "Create_Packager_5",
      },
      {
        storage_id = "west_d",
        packager = "Create_Packager_6",
      },
    },
  }
end

---Validate and normalize a deserialized warehouse config table.
---@param cfg table
---@return WarehouseConfig
function Config.fromDeserialized(cfg)
  if type(cfg) ~= "table" then
    error("config module must return a table", 0)
  end

  if cfg.version ~= 1 then
    error("unsupported config version: " .. tostring(cfg.version), 0)
  end

  if type(cfg.warehouse) ~= "table" then
    error("config.warehouse is required", 0)
  end

  if type(cfg.network) ~= "table" then
    error("config.network is required", 0)
  end

  if type(cfg.runtime) ~= "table" then
    error("config.runtime is required", 0)
  end

  if type(cfg.logistics) ~= "table" then
    error("config.logistics is required", 0)
  end

  if type(cfg.logging) ~= "table" then
    error("config.logging is required", 0)
  end

  if cfg.train ~= nil and type(cfg.train) ~= "table" then
    error("config.train must be a table when provided", 0)
  end

  if type(cfg.storage) ~= "table" or #cfg.storage == 0 then
    error("config.storage must contain at least one storage entry", 0)
  end

  if type(cfg.warehouse.id) ~= "string" or cfg.warehouse.id == "" then
    error("config.warehouse.id is required", 0)
  end

  if type(cfg.warehouse.address) ~= "string" or cfg.warehouse.address == "" then
    error("config.warehouse.address is required", 0)
  end

  if type(cfg.network.protocol) ~= "string" or cfg.network.protocol == "" then
    error("config.network.protocol is required", 0)
  end

  validatePositiveNumber(cfg.network.heartbeat_seconds, "config.network.heartbeat_seconds")
  validatePositiveNumber(cfg.runtime.display_refresh_seconds, "config.runtime.display_refresh_seconds")
  validatePositiveNumber(cfg.runtime.status_refresh_seconds, "config.runtime.status_refresh_seconds")
  validatePositiveNumber(cfg.runtime.capacity_refresh_seconds, "config.runtime.capacity_refresh_seconds")

  if type(cfg.logistics.stock_ticker) ~= "string" or cfg.logistics.stock_ticker == "" then
    error("config.logistics.stock_ticker is required", 0)
  end

  if type(cfg.logging.output) ~= "table" then
    error("config.logging.output is required", 0)
  end

  if type(cfg.logging.retention) ~= "table" then
    error("config.logging.retention is required", 0)
  end

  if type(cfg.logging.output.file) ~= "string" or cfg.logging.output.file == "" then
    error("config.logging.output.file is required", 0)
  end

  if cfg.logging.output.level ~= "info" and cfg.logging.output.level ~= "warn" and cfg.logging.output.level ~= "error" and cfg.logging.output.level ~= "panic" then
    error("config.logging.output.level must be info, warn, error, or panic", 0)
  end

  if type(cfg.logging.output.mirror_to_term) ~= "boolean" then
    error("config.logging.output.mirror_to_term must be a boolean", 0)
  end

  if cfg.logging.output.timestamp ~= "utc" and cfg.logging.output.timestamp ~= "epoch" then
    error("config.logging.output.timestamp must be utc or epoch", 0)
  end

  if cfg.logging.retention.mode ~= "none" and cfg.logging.retention.mode ~= "truncate" then
    error("config.logging.retention.mode must be none or truncate", 0)
  end

  if type(cfg.logging.retention.max_lines) ~= "number" or cfg.logging.retention.max_lines < 1 then
    error("config.logging.retention.max_lines must be a positive number", 0)
  end

  if cfg.train ~= nil then
    if type(cfg.train.export_station) ~= "string" or cfg.train.export_station == "" then
      error("config.train.export_station is required", 0)
    end
  end

  for index, entry in ipairs(cfg.storage) do
    if type(entry.storage_id) ~= "string" or entry.storage_id == "" then
      error("config.storage[" .. index .. "].storage_id is required", 0)
    end

    if type(entry.packager) ~= "string" or entry.packager == "" then
      error("config.storage[" .. index .. "].packager is required", 0)
    end
  end

  return cfg
end

---Load warehouse config from a Lua file path or fall back to defaults.
---@param path string
---@return WarehouseConfig
function Config.load(path)
  return Config.fromDeserialized(loadConfigModule(path))
end

return Config
