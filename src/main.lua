--- Main warehouse controller entrypoint and event-loop orchestration.

local function prependPackagePath(path)
  if not package or type(package.path) ~= "string" then
    return
  end

  package.path = table.concat({
    path,
    package.path,
  }, ";")
end

prependPackagePath("/lib/log/0.1.0/?.lua")
prependPackagePath("/lib/log/0.1.0/?/init.lua")
prependPackagePath("/lib/rednet_contracts/0.1.0/?.lua")
prependPackagePath("/lib/rednet_contracts/0.1.0/?/init.lua")

local Config = require("model.config")
local log = require("log")

local CONFIG_PATH = "/etc/wh-controller/config.lua"

if not fs.exists(CONFIG_PATH) then
  local wizard = require("app.wizard")
  local ok = wizard.run(CONFIG_PATH)
  if not ok then
    printError("Setup not completed. Run wh-controller again to configure.")
    return
  end
end

log.config({
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
})

local configOk, configOrError = pcall(Config.load, CONFIG_PATH)
if not configOk then
  log.panic("Failed to load warehouse config: %s", tostring(configOrError))
end

local config = configOrError
local runtime = require("app.runtime")
local executorLib = require("app.executor")
local persistence = require("infra.persistence")
local networkLib = require("infra.network")
local snapshotLib = require("app.snapshot")
local tables = require("util.tables")
local ui = require("ui.controller")

log.config(config.logging)
log.info("Warehouse boot starting for %s", config.warehouse.id)
runtime.validateConfiguredPeripherals(config)
log.info("Validated configured peripherals for %s", config.warehouse.id)

---@type WarehouseState
local state = runtime.newState(config)
local executor = executorLib.new(config, persistence)
persistence.loadPersistedState(state)
log.info("Warehouse state loaded for %s", state.warehouse.id)

local opened = networkLib.openConfiguredModems(state.network)
if opened == 0 then
  log.panic("Could not open any configured modem for rednet")
end
log.info("Opened %d configured modem(s)", opened)

local lastSnapshotAt
snapshotLib.refresh(state, tables)

---Heartbeat broadcast loop.
---@return nil
local function heartbeatLoop()
  networkLib.sendHeartbeat(state)

  while true do
    os.sleep(state.network.heartbeat_seconds)
    networkLib.sendHeartbeat(state)
  end
end

---Inbound coordinator message loop.
---@return nil
local function messageLoop()
  while true do
    local snapshotRequested = networkLib.handleRequest(state, snapshotLib, tables, persistence, executor)
    if snapshotRequested then
      lastSnapshotAt = os.epoch("utc")
    end
  end
end

---Redraw on display/peripheral change events.
---@return nil
local function screenLoop()
  ui.draw(state, tables, lastSnapshotAt)

  while true do
    local event = os.pullEvent()
    if event == "peripheral" or event == "peripheral_detach" or event == "term_resize" then
      ui.draw(state, tables, lastSnapshotAt)
    elseif event == "timer" then
      -- Ignore timers from other parallel branches.
    end
  end
end

---Periodic warehouse snapshot refresh loop.
---@return nil
local function statusRefreshLoop()
  while true do
    os.sleep(state.runtime.status_refresh_seconds)
    snapshotLib.refresh(state, tables)
  end
end

---Periodic display refresh loop.
---@return nil
local function displayRefreshLoop()
  while true do
    os.sleep(state.runtime.display_refresh_seconds)
    ui.draw(state, tables, lastSnapshotAt)
  end
end

---Operator input loop.
---@return nil
local function inputLoop()
  while true do
    local _, char = os.pullEvent("char")
    if ui.handleInput(state, char, executor) then
      ui.draw(state, tables, lastSnapshotAt)
    end
  end
end

---Package sent event loop for outbound transport evidence.
---@return nil
local function packageSentLoop()
  while true do
    local _, packageObject = os.pullEvent("package_sent")
    runtime.recordPackageEvent(state, persistence, "out", packageObject)
  end
end

---Package received event loop for inbound transport evidence.
---@return nil
local function packageReceivedLoop()
  while true do
    local _, packageObject = os.pullEvent("package_received")
    runtime.recordPackageEvent(state, persistence, "in", packageObject)
  end
end

parallel.waitForAny(heartbeatLoop, messageLoop, screenLoop, statusRefreshLoop, displayRefreshLoop, inputLoop, packageSentLoop, packageReceivedLoop)
