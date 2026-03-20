---Warehouse network transport helpers for coordinator communication.
local contracts = require("rednet_contracts")
local log = require("deps.log")

---@class WarehouseNetwork
local M = {}

local warehouseService = contracts.warehouse_v1
local discoveryService = contracts.discovery_v1

local function emptyPackages()
  return {
    ["in"] = {},
    ["out"] = {},
  }
end

local function copyPackages(packages)
  local normalized = packages or emptyPackages()
  local copied = {
    ["in"] = {},
    ["out"] = {},
  }

  for _, direction in ipairs({ "in", "out" }) do
    for index, packageId in ipairs(normalized[direction] or {}) do
      copied[direction][index] = packageId
    end
  end

  return copied
end

local function publicOwnerRecord(state)
  if not state.owner then
    return nil
  end

  return {
    coordinator_id = state.owner.coordinator_id,
    coordinator_address = state.owner.coordinator_address,
    claimed_at = state.owner.claimed_at,
  }
end

local function openRednet(side)
  if not rednet.isOpen(side) then
    rednet.open(side)
  end

  return rednet.isOpen(side)
end

local function assignmentRequestedItems(assignment)
  local total = 0
  for _, item in ipairs(assignment.items or {}) do
    total = total + (item.count or 0)
  end
  return total
end

local function cachedSnapshot(state)
  local snapshot = state.latest_snapshot
  if type(snapshot) == "table" then
    return snapshot
  end

  return {
    observed_at = state.last_status_refresh_at or os.epoch("utc"),
    inventory = {},
    capacity = {
      storages_online = 0,
      storages_total = 0,
      storages_with_unknown_capacity = 0,
      slot_capacity_total = 0,
      slot_capacity_used = 0,
    },
  }
end

local function buildGetOwnerResult(state)
  return {
    warehouse_id = state.warehouse.id,
    warehouse_address = state.warehouse.address,
    owner = publicOwnerRecord(state),
    observed_at = os.epoch("utc"),
  }
end

local function buildOverviewResult(state, snapshot)
  local lastExecution = nil
  if state.last_assignment_execution then
    local assignments = {}
    for index, assignment in ipairs(state.last_assignment_execution.assignments or {}) do
      assignments[index] = {
        destination = assignment.destination,
        item_count = assignment.queued_items or 0,
      }
    end

    lastExecution = {
      transfer_request_id = state.last_assignment_execution.batch_id,
      status = state.last_assignment_execution.status,
      executed_at = state.last_assignment_execution.executed_at,
      assignments = assignments,
      total_items_requested = state.last_assignment_execution.total_items_requested or 0,
      total_items_queued = state.last_assignment_execution.total_items_queued or 0,
    }
  end

  local activeTransferRequest = nil
  if state.latest_assignment_batch then
    activeTransferRequest = {
      id = state.latest_assignment_batch.batch_id,
      received_at = state.last_assignment_received_at or state.latest_assignment_batch.sent_at or os.epoch("utc"),
    }
  end

  local lastAck = nil
  if state.latest_assignment_batch and state.last_assignment_ack_at then
    lastAck = {
      transfer_request_id = state.latest_assignment_batch.batch_id,
      sent_at = state.last_assignment_ack_at,
    }
  end

  return {
    warehouse_id = state.warehouse.id,
    warehouse_address = state.warehouse.address,
    observed_at = snapshot.observed_at,
    status = {
      online = true,
      storage_online = snapshot.capacity.storages_online or 0,
      storage_total = snapshot.capacity.storages_total or 0,
      slot_capacity_used = snapshot.capacity.slot_capacity_used or 0,
      slot_capacity_total = snapshot.capacity.slot_capacity_total or 0,
      storages_with_unknown_capacity = snapshot.capacity.storages_with_unknown_capacity or 0,
    },
    active_transfer_request = activeTransferRequest,
    last_ack = lastAck,
    last_execution = lastExecution,
    recent_issues = {},
  }
end

local function buildSnapshotResult(state, snapshot)
  return {
    warehouse_id = state.warehouse.id,
    warehouse_address = state.warehouse.address,
    observed_at = snapshot.observed_at,
    inventory = snapshot.inventory or {},
    capacity = {
      slot_capacity_total = snapshot.capacity.slot_capacity_total or 0,
      slot_capacity_used = snapshot.capacity.slot_capacity_used or 0,
    },
  }
end

local function toInternalBatch(params)
  return {
    type = "assignment_batch",
    protocol_version = 1,
    coordinator_id = params.coordinator_id,
    warehouse_id = params.warehouse_id,
    batch_id = params.transfer_request_id,
    sent_at = params.sent_at,
    assignments = params.assignments,
    total_assignments = params.total_assignments,
    total_items = params.total_items,
  }
end

local function buildSetOwnerResult(state, accepted)
  return {
    warehouse_id = state.warehouse.id,
    warehouse_address = state.warehouse.address,
    accepted = accepted,
    owner = publicOwnerRecord(state),
    sent_at = os.epoch("utc"),
  }
end

local function buildTransferRequestStatus(state, transferRequestId)
  if state.last_assignment_execution and state.last_assignment_execution.batch_id == transferRequestId then
    local assignments = {}
    for index, assignment in ipairs(state.last_assignment_execution.assignments or {}) do
      assignments[index] = {
        assignment_id = assignment.assignment_id,
        destination = assignment.destination,
        destination_address = assignment.destination_address,
        line_count = assignment.line_count or 0,
        requested_items = assignment.requested_items or 0,
        queued_items = assignment.queued_items or 0,
        status = assignment.status,
      }
    end

    return {
      warehouse_id = state.warehouse.id,
      warehouse_address = state.warehouse.address,
      transfer_request_id = transferRequestId,
      status = state.last_assignment_execution.status,
      executed_at = state.last_assignment_execution.executed_at,
      total_assignments = state.last_assignment_execution.total_assignments or 0,
      total_items_requested = state.last_assignment_execution.total_items_requested or 0,
      total_items_queued = state.last_assignment_execution.total_items_queued or 0,
      assignments = assignments,
      packages = copyPackages(state.last_assignment_execution.packages),
      sent_at = os.epoch("utc"),
    }
  end

  if state.latest_assignment_batch and state.latest_assignment_batch.batch_id == transferRequestId then
    local assignments = {}
    local totalItemsRequested = 0

    for index, assignment in ipairs(state.latest_assignment_batch.assignments or {}) do
      local requestedItems = assignmentRequestedItems(assignment)
      totalItemsRequested = totalItemsRequested + requestedItems
      assignments[index] = {
        assignment_id = assignment.assignment_id,
        destination = assignment.destination,
        destination_address = assignment.destination_address,
        line_count = assignment.line_count or #(assignment.items or {}),
        requested_items = requestedItems,
        queued_items = 0,
        status = "queued",
      }
    end

    return {
      warehouse_id = state.warehouse.id,
      warehouse_address = state.warehouse.address,
      transfer_request_id = transferRequestId,
      status = "queued",
      executed_at = nil,
      total_assignments = state.latest_assignment_batch.total_assignments or #assignments,
      total_items_requested = state.latest_assignment_batch.total_items or totalItemsRequested,
      total_items_queued = 0,
      assignments = assignments,
      packages = copyPackages(state.latest_assignment_batch.packages),
      sent_at = os.epoch("utc"),
    }
  end

  return nil
end

local function sameOwner(state, params)
  return state.owner
    and state.owner.coordinator_id == params.coordinator_id
    and state.owner.coordinator_address == params.coordinator_address
end

local function isProtocolMismatch(err)
  local path = err and err.details and err.details.path or nil
  return path == "message.protocol" or path == "message.protocol.name" or path == "message.protocol.version"
end

local function senderOwnsWarehouse(state, senderId)
  return state.owner ~= nil and state.owner.sender_id == senderId
end

local function requireOwner(senderId, state, request)
  if senderOwnsWarehouse(state, senderId) then
    return true
  end

  if state.owner == nil then
    log.warn("Rejected %s from sender=%s because warehouse has no owner", tostring(request.method), tostring(senderId))
    warehouseService.replyError(senderId, request, "ownership_required", "warehouse has no accepted coordinator owner")
    return false
  end

  log.warn(
    "Rejected %s from sender=%s because accepted owner sender=%s",
    tostring(request.method),
    tostring(senderId),
    tostring(state.owner.sender_id)
  )
  warehouseService.replyError(senderId, request, "owner_mismatch", "sender is not the accepted coordinator")
  return false
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

---Broadcast a discovery heartbeat for this warehouse.
---@param state WarehouseState
---@return nil
function M.sendHeartbeat(state)
  discoveryService.broadcast({
    device_id = state.warehouse.id,
    device_type = "warehouse_controller",
    sent_at = os.epoch("utc"),
    interval_seconds = state.network.heartbeat_seconds,
    protocols = {
      {
        name = warehouseService.NAME,
        version = warehouseService.VERSION,
        role = "server",
      },
    },
  })
end

---Receive and handle one inbound `warehouse_v1` request.
---@param state WarehouseState
---@param snapshotLib table
---@param tables TableUtil
---@param persistence WarehousePersistence
---@param executor { executeBatch: fun(state: WarehouseState, batch: WarehouseAssignmentBatch|nil): boolean, string, WarehouseAssignmentExecution|nil }|nil
---@return boolean snapshotRequested True when a fresh snapshot was sent back to the requester.
function M.handleRequest(state, snapshotLib, tables, persistence, executor)
  local senderId, request, method, err = warehouseService.receiveRequest()
  if err then
    if isProtocolMismatch(err) then
      log.warn("Rejected warehouse request from sender=%s due to protocol mismatch: %s", tostring(senderId), tostring(err.message))
    else
      log.warn("Ignored invalid warehouse request from sender=%s: %s", tostring(senderId), tostring(err.message))
    end
    return false
  end

  if method == warehouseService.METHODS.GET_OWNER then
    warehouseService.replySuccess(senderId, request, method, buildGetOwnerResult(state))
    return false
  end

  if method == warehouseService.METHODS.SET_OWNER then
    if state.owner == nil or sameOwner(state, request.params) then
      state.owner = {
        coordinator_id = request.params.coordinator_id,
        coordinator_address = request.params.coordinator_address,
        claimed_at = request.params.claimed_at,
        sender_id = senderId,
      }
      persistence.persistOwner(state.owner)
      log.info(
        "Accepted warehouse owner coordinator_id=%s sender=%s",
        tostring(state.owner.coordinator_id),
        tostring(senderId)
      )
      warehouseService.replySuccess(senderId, request, method, buildSetOwnerResult(state, true))
      return false
    end

    log.warn(
      "Rejected owner claim from sender=%s coordinator_id=%s; already owned by coordinator_id=%s sender=%s",
      tostring(senderId),
      tostring(request.params.coordinator_id),
      tostring(state.owner.coordinator_id),
      tostring(state.owner.sender_id)
    )
    warehouseService.replyError(senderId, request, "owner_mismatch", "warehouse is already owned by another coordinator")
    return false
  end

  if method == warehouseService.METHODS.GET_OVERVIEW then
    local snapshot = cachedSnapshot(state)
    warehouseService.replySuccess(senderId, request, method, buildOverviewResult(state, snapshot))
    return false
  end

  if method == warehouseService.METHODS.GET_SNAPSHOT then
    local snapshot = cachedSnapshot(state)
    warehouseService.replySuccess(senderId, request, method, buildSnapshotResult(state, snapshot))
    return false
  end

  if not requireOwner(senderId, state, request) then
    return false
  end

  if method == warehouseService.METHODS.ASSIGN_TRANSFER_REQUEST then
    if request.params.warehouse_id ~= state.warehouse.id then
      warehouseService.replyError(senderId, request, "invalid_params", "transfer request targeted a different warehouse", {
        details = {
          path = "params.warehouse_id",
        },
      })
      return false
    end

    local batch = toInternalBatch(request.params)
    batch.packages = emptyPackages()
    state.latest_assignment_batch = batch
    state.latest_assignment_batch_is_persisted = false
    state.last_assignment_received_at = os.epoch("utc")
    persistence.persistAssignmentBatch(batch)
    state.last_assignment_ack_at = os.epoch("utc")

    log.info(
      "Accepted transfer request %s from sender=%s with %d assignment(s), %d item(s)",
      tostring(batch.batch_id),
      tostring(senderId),
      batch.total_assignments or 0,
      batch.total_items or 0
    )

    if executor then
      local ok, status, execution = executor.executeBatch(state, batch)
      log.info(
        "Transfer request %s execution returned ok=%s status=%s",
        tostring(batch.batch_id),
        tostring(ok),
        tostring(status)
      )
      if execution then
        state.last_assignment_execution = execution
      end
    end

    warehouseService.replySuccess(senderId, request, method, {
      warehouse_id = state.warehouse.id,
      warehouse_address = state.warehouse.address,
      transfer_request_id = batch.batch_id,
      assignment_count = batch.total_assignments or 0,
      item_count = batch.total_items or 0,
      accepted = true,
      sent_at = state.last_assignment_ack_at,
    })
    return false
  end

  if method == warehouseService.METHODS.GET_TRANSFER_REQUEST_STATUS then
    local result = buildTransferRequestStatus(state, request.params.transfer_request_id)
    if not result then
      warehouseService.replyError(
        senderId,
        request,
        "unknown_transfer_request",
        "transfer request status is not available for the requested id"
      )
      return false
    end

    warehouseService.replySuccess(senderId, request, method, result)
    return false
  end

  log.warn("Ignored unknown warehouse method from sender=%s: %s", tostring(senderId), tostring(method))
  warehouseService.replyError(senderId, request, "unknown_method", "unknown warehouse method")
  return false
end

return M
