---Warehouse network transport helpers for coordinator communication.
---@class WarehouseNetwork
local M = {}
local log = require("deps.log")

local function clearLocalAssignmentState(state, persistence, reason)
  state.latest_assignment_batch = nil
  state.latest_assignment_batch_is_persisted = false
  state.last_assignment_received_at = nil
  state.last_assignment_ack_at = nil
  state.last_assignment_execution = nil
  state.last_assignment_execution_is_persisted = false
  state.last_assignment_execution_at = nil
  persistence.clearPersistedAssignmentState()
  log.info("Cleared local assignment state: %s", reason)
end

local function reconcileAssignmentState(state, message, persistence)
  local localBatch = state.latest_assignment_batch
  local localBatchId = localBatch and localBatch.batch_id or nil
  local activeBatchId = message.active_batch_id

  if localBatchId == nil then
    return
  end

  if activeBatchId == nil then
    clearLocalAssignmentState(state, persistence, "coordinator reported no active batch")
    return
  end

  if localBatchId ~= activeBatchId then
    clearLocalAssignmentState(
      state,
      persistence,
      "coordinator batch mismatch local=" .. tostring(localBatchId) .. " active=" .. tostring(activeBatchId)
    )
  end
end

local function openRednet(side)
  if not rednet.isOpen(side) then
    rednet.open(side)
  end

  return rednet.isOpen(side)
end

---Open the configured warehouse modems for rednet traffic.
---@param network WarehouseConfigNetwork
---@return integer opened
function M.openConfiguredModems(network)
  local opened = 0

  if openRednet(network.ender_modem) then
    opened = opened + 1
  end

  if network.local_wired_modem ~= network.ender_modem and openRednet(network.local_wired_modem) then
    opened = opened + 1
  end

  return opened
end

---Broadcast a heartbeat for this warehouse.
---@param state WarehouseState
---@return nil
function M.sendHeartbeat(state)
  rednet.broadcast({
    type = "heartbeat",
    protocol_version = 1,
    warehouse_id = state.warehouse.id,
    warehouse_address = state.warehouse.address,
    sent_at = os.epoch("utc"),
  }, state.network.protocol)
end

---Acknowledge receipt of an assignment batch to the coordinator.
---@param state WarehouseState
---@param senderId integer
---@param message WarehouseAssignmentBatch
---@return nil
function M.sendAssignmentAck(state, senderId, message)
  rednet.send(senderId, {
    type = "assignment_ack",
    protocol_version = 1,
    warehouse_id = state.warehouse.id,
    warehouse_address = state.warehouse.address,
    batch_id = message.batch_id,
    assignment_count = message.total_assignments or 0,
    item_count = message.total_items or 0,
    sent_at = os.epoch("utc"),
  }, state.network.protocol)
  state.last_assignment_ack_at = os.epoch("utc")
end

---Send the result of local assignment execution to the coordinator.
---@param state WarehouseState
---@param senderId integer
---@param execution WarehouseAssignmentExecution
---@return nil
function M.sendAssignmentExecution(state, senderId, execution)
  rednet.send(senderId, {
    type = "assignment_execution",
    protocol_version = 1,
    warehouse_id = state.warehouse.id,
    warehouse_address = state.warehouse.address,
    batch_id = execution.batch_id,
    status = execution.status,
    executed_at = execution.executed_at,
    total_assignments = execution.total_assignments or 0,
    total_items_requested = execution.total_items_requested or 0,
    total_items_queued = execution.total_items_queued or 0,
    assignments = execution.assignments or {},
    sent_at = os.epoch("utc"),
  }, state.network.protocol)
end

-- Forward coarse rail movement to the coordinator so cycle completion can wait
-- for post-execution departures without tracking individual packages.
---@param state WarehouseState
---@param eventMessage WarehouseTrainDepartureEvent
---@return nil
function M.sendTrainDeparture(state, eventMessage)
  rednet.broadcast({
    type = "train_departure_notice",
    protocol_version = 1,
    warehouse_id = state.warehouse.id,
    warehouse_address = state.warehouse.address,
    station_name = eventMessage.station_name,
    train_name = eventMessage.train_name,
    sent_at = eventMessage.sent_at or os.epoch("utc"),
  }, state.network.protocol)
end

---Handle one inbound coordinator message.
---@param state WarehouseState
---@param senderId integer
---@param message table
---@param protocol string
---@param snapshotLib table
---@param tables TableUtil
---@param persistence WarehousePersistence
---@param executor { executeBatch: fun(state: WarehouseState, batch: WarehouseAssignmentBatch|nil): boolean, string, WarehouseAssignmentExecution|nil }|nil
---@return boolean snapshotRequested True when a fresh snapshot was sent back to the requester.
function M.handleMessage(state, senderId, message, protocol, snapshotLib, tables, persistence, executor)
  if protocol ~= state.network.protocol or type(message) ~= "table" then
    return false
  end

  if message.type == "get_snapshot" then
    reconcileAssignmentState(state, message, persistence)
    log.info("Received snapshot request from coordinator %s", tostring(senderId))
    snapshotLib.refresh(state, tables)
    rednet.send(senderId, state.latest_snapshot, state.network.protocol)
    return true
  end

  if message.type == "ping" then
    rednet.send(senderId, {
      type = "pong",
      protocol_version = 1,
      warehouse_id = state.warehouse.id,
      warehouse_address = state.warehouse.address,
      sent_at = os.epoch("utc"),
    }, state.network.protocol)
    return false
  end

  if message.type == "heartbeat" or message.type == "train_departure_notice" then
    return false
  end

  if message.type == "assignment_batch" then
    if message.warehouse_id ~= state.warehouse.id then
      log.warn(
        "Ignored assignment batch %s for warehouse=%s from sender=%s; local warehouse=%s",
        tostring(message.batch_id),
        tostring(message.warehouse_id),
        tostring(senderId),
        tostring(state.warehouse.id)
      )
      return false
    end

    log.info(
      "Received assignment batch %s from sender=%s with %d assignment(s), %d item(s)",
      tostring(message.batch_id),
      tostring(senderId),
      message.total_assignments or 0,
      message.total_items or 0
    )
    state.latest_assignment_batch = message
    state.latest_assignment_batch_is_persisted = false
    state.last_assignment_received_at = os.epoch("utc")
    persistence.persistAssignmentBatch(message)
    M.sendAssignmentAck(state, senderId, message)
    if executor then
      local ok, status, execution = executor.executeBatch(state, message)
      log.info(
        "Assignment batch %s execution returned ok=%s status=%s",
        tostring(message.batch_id),
        tostring(ok),
        tostring(status)
      )
      if execution then
        M.sendAssignmentExecution(state, senderId, execution)
      end
    end
    return false
  end

  log.warn("Ignored unknown message type from sender=%s: %s", tostring(senderId), tostring(message.type))

  return false
end

return M
