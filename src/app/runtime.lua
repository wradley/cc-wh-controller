---@class WarehouseSnapshotCapacityCacheEntry
---@field packager string
---@field slot_capacity_total integer
---@field checked_at number

---@class WarehouseSnapshotMessage
---@field type '"snapshot"'
---@field protocol_version integer
---@field warehouse_id string
---@field warehouse_address string
---@field observed_at number
---@field inventory table<string, integer>
---@field capacity { slot_capacity_total: integer, slot_capacity_used: integer, slot_capacity_free: integer, storages_online: integer, storages_total: integer, storages_with_unknown_capacity: integer }

---@class WarehouseAssignmentBatchItem
---@field name string
---@field count integer
---@field transfer_id string|nil

---@class WarehouseAssignment
---@field assignment_id string
---@field source string
---@field destination string
---@field destination_address string|nil
---@field reason string
---@field status string
---@field items WarehouseAssignmentBatchItem[]
---@field total_items integer
---@field line_count integer

---@class WarehouseAssignmentBatch
---@field type '"assignment_batch"'|string
---@field protocol_version integer
---@field coordinator_id string|nil
---@field warehouse_id string
---@field batch_id string
---@field plan_refreshed_at number|nil
---@field sent_at number|nil
---@field assignments WarehouseAssignment[]
---@field total_assignments integer
---@field total_items integer
---@field packages WarehouseTrackedPackages|nil

---@class WarehouseTrackedPackages
---@field ["in"] string[]
---@field ["out"] string[]

---@class WarehouseAssignmentExecutionEntry
---@field assignment_id string
---@field destination string
---@field destination_address string
---@field line_count integer
---@field requested_items integer
---@field queued_items integer
---@field status string

---@class WarehouseAssignmentExecution
---@field batch_id string
---@field executed_at number
---@field status string
---@field total_assignments integer
---@field total_items_requested integer
---@field total_items_queued integer
---@field assignments WarehouseAssignmentExecutionEntry[]
---@field packages WarehouseTrackedPackages|nil

---@class WarehouseAcceptedOwner
---@field coordinator_id string
---@field coordinator_address string
---@field claimed_at number
---@field sender_id integer

---@class WarehouseSnapshotRequest
---@field type '"get_snapshot"'
---@field coordinator_id string|nil
---@field cycle_active boolean|nil
---@field active_batch_id string|nil
---@field sent_at number|nil

---Top-level runtime state for one warehouse controller.
---@class WarehouseState
---@field config WarehouseConfig
---@field warehouse WarehouseConfigIdentity
---@field network WarehouseConfigNetwork
---@field runtime WarehouseConfigRuntime
---@field logistics WarehouseConfigLogistics
---@field train WarehouseConfigTrain|nil
---@field storage WarehouseStorageEntry[]
---@field capacity_refresh_ms integer
---@field storage_capacity_cache table<string, WarehouseSnapshotCapacityCacheEntry>
---@field latest_snapshot WarehouseSnapshotMessage|nil
---@field last_capacity_probe_at number|nil
---@field last_status_refresh_at number|nil
---@field latest_assignment_batch WarehouseAssignmentBatch|nil
---@field latest_assignment_batch_is_persisted boolean
---@field last_assignment_received_at number|nil
---@field last_assignment_ack_at number|nil
---@field last_assignment_execution WarehouseAssignmentExecution|nil
---@field last_assignment_execution_is_persisted boolean
---@field last_assignment_execution_at number|nil
---@field owner WarehouseAcceptedOwner|nil

---Warehouse runtime state construction.
---@class WarehouseRuntime
local M = {}

local log = require("deps.log")

local function emptyPackages()
  return {
    ["in"] = {},
    ["out"] = {},
  }
end

local function ensureTrackedPackages(target)
  if type(target.packages) ~= "table" then
    target.packages = emptyPackages()
  end
  if type(target.packages["in"]) ~= "table" then
    target.packages["in"] = {}
  end
  if type(target.packages["out"]) ~= "table" then
    target.packages["out"] = {}
  end
  return target.packages
end

local function appendUnique(list, value)
  for _, existing in ipairs(list or {}) do
    if existing == value then
      return false
    end
  end

  list[#list + 1] = value
  return true
end

local function buildPackageId(packageObject)
  if type(packageObject) ~= "table" or type(packageObject.getOrderData) ~= "function" then
    return nil, "package object has no getOrderData()"
  end

  local orderData = packageObject.getOrderData()
  if type(orderData) ~= "table" then
    return nil, "package has no order data"
  end

  local orderId = orderData.getOrderID and orderData.getOrderID() or nil
  local linkIndex = orderData.getLinkIndex and orderData.getLinkIndex() or nil
  local index = orderData.getIndex and orderData.getIndex() or nil
  if orderId == nil or linkIndex == nil or index == nil then
    return nil, "package order data was missing id, link index, or index"
  end

  return string.format("%s-%s-%s", tostring(orderId), tostring(linkIndex), tostring(index))
end

local function requirePeripheral(name, expectedMethod)
  local peripheralObject = peripheral.wrap(name)
  if not peripheralObject then
    error("missing peripheral: " .. tostring(name), 0)
  end

  if expectedMethod and type(peripheralObject[expectedMethod]) ~= "function" then
    error("configured peripheral does not support " .. expectedMethod .. ": " .. tostring(name), 0)
  end

  return peripheralObject
end

---Build a fresh warehouse runtime state table from validated config.
---@param config WarehouseConfig
---@return WarehouseState
function M.newState(config)
  return {
    config = config,
    warehouse = config.warehouse,
    network = config.network,
    runtime = config.runtime,
    logistics = config.logistics,
    storage = config.storage,
    capacity_refresh_ms = config.runtime.capacity_refresh_seconds * 1000,
    storage_capacity_cache = {},
    latest_snapshot = nil,
    last_capacity_probe_at = nil,
    last_status_refresh_at = nil,
    latest_assignment_batch = nil,
    latest_assignment_batch_is_persisted = false,
    last_assignment_received_at = nil,
    last_assignment_ack_at = nil,
    last_assignment_execution = nil,
    last_assignment_execution_is_persisted = false,
    last_assignment_execution_at = nil,
    owner = nil,
  }
end

---Fail loudly when required configured peripherals are not available.
---@param config WarehouseConfig
---@return nil
function M.validateConfiguredPeripherals(config)
  requirePeripheral(config.logistics.stock_ticker, "requestFiltered")
  requirePeripheral(config.logistics.postbox, nil)

  for _, entry in ipairs(config.storage or {}) do
    local packager = requirePeripheral(entry.packager, "list")
    if type(packager.getItemDetail) ~= "function" then
      error("configured peripheral does not support getItemDetail: " .. tostring(entry.packager), 0)
    end
  end
end

---Record one package event against the currently tracked transfer request.
---@param state WarehouseState
---@param persistence WarehousePersistence
---@param direction '"in"'|'"out"'
---@param packageObject table
---@return boolean recorded
---@return string|nil packageId
function M.recordPackageEvent(state, persistence, direction, packageObject)
  local currentRequestId = state.latest_assignment_batch and state.latest_assignment_batch.batch_id
    or (state.last_assignment_execution and state.last_assignment_execution.batch_id)
    or nil
  if not currentRequestId then
    return false, nil
  end

  local packageId, err = buildPackageId(packageObject)
  if not packageId then
    log.warn("Ignored %s package event for request=%s: %s", tostring(direction), tostring(currentRequestId), tostring(err))
    return false, nil
  end

  local recorded = false
  if state.latest_assignment_batch and state.latest_assignment_batch.batch_id == currentRequestId then
    local packages = ensureTrackedPackages(state.latest_assignment_batch)
    if appendUnique(packages[direction], packageId) then
      persistence.persistAssignmentBatch(state.latest_assignment_batch)
      recorded = true
    end
  end

  if state.last_assignment_execution and state.last_assignment_execution.batch_id == currentRequestId then
    local packages = ensureTrackedPackages(state.last_assignment_execution)
    if appendUnique(packages[direction], packageId) then
      persistence.persistAssignmentExecution(state.last_assignment_execution)
      recorded = true
    end
  end

  if recorded then
    log.info("Recorded package %s for request=%s direction=%s", packageId, tostring(currentRequestId), direction)
  end

  return recorded, packageId
end

return M
