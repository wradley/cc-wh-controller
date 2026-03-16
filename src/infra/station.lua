---@class WarehouseStation
---@field peripheral_name string
---@field peripheral table
---@field currentStationName fun(): string
---@field matchesEventStation fun(eventStationName: string): boolean

---Train station helper for warehouse export events.
local M = {}

-- Build a small station helper so the controller does not depend on raw
-- peripheral names or event-matching details everywhere else.
---@param config WarehouseConfig
---@return WarehouseStation|nil
function M.new(config)
  if type(config.train) ~= "table" then
    return nil
  end

  local peripheralName = config.train.export_station
  if type(peripheralName) ~= "string" or peripheralName == "" then
    error("config.train.export_station is required when config.train is set", 0)
  end

  local station = peripheral.wrap(peripheralName)
  if not station then
    error("missing train station peripheral: " .. peripheralName, 0)
  end

  if type(station.getStationName) ~= "function" then
    error("configured train station does not support getStationName: " .. peripheralName, 0)
  end

  local stationLib = {
    peripheral_name = peripheralName,
    peripheral = station,
  }

  -- The station name is still useful for UI/debug even though the departure
  -- event is keyed by peripheral name in practice.
  function stationLib.currentStationName()
    return station.getStationName()
  end

  -- train_departure is a global event on the computer, so we filter it down to
  -- the configured export station in case the local wired network ever exposes
  -- multiple station peripherals.
  function stationLib.matchesEventStation(eventStationName)
    return eventStationName == stationLib.peripheral_name
  end

  return stationLib
end

return M
