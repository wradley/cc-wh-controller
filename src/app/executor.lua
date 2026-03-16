---Warehouse assignment execution backed by the Create stock ticker.
---@class WarehouseExecutor
local M = {}
local log = require("deps.log")

local function assignmentRequestedItems(assignment)
  local total = 0
  for _, item in ipairs(assignment.items or {}) do
    total = total + (item.count or 0)
  end
  return total
end

---Create an assignment executor backed by the configured Create stock ticker.
---@param config WarehouseConfig
---@param persistence WarehousePersistence
---@return WarehouseExecutor
function M.new(config, persistence)
  local stockTicker = peripheral.wrap(config.logistics.stock_ticker)

  if not stockTicker then
    error("missing stock ticker peripheral: " .. config.logistics.stock_ticker, 0)
  end

  if type(stockTicker.requestFiltered) ~= "function" then
    error("configured stock ticker does not support requestFiltered: " .. config.logistics.stock_ticker, 0)
  end

  local executor = {}

  local function persistExecution(state, execution)
    state.last_assignment_execution = execution
    state.last_assignment_execution_is_persisted = false
    state.last_assignment_execution_at = execution.executed_at
    persistence.persistAssignmentExecution(execution)
  end

  ---Queue one assignment batch through the stock ticker and persist the execution result.
  ---@param state WarehouseState
  ---@param batch WarehouseAssignmentBatch|nil
  ---@return boolean ok
  ---@return string status
  ---@return WarehouseAssignmentExecution|nil execution
  function executor.executeBatch(state, batch)
    if not batch then
      log.warn("Execute requested without a loaded assignment batch")
      return false, "no batch loaded"
    end

    if state.last_assignment_execution and state.last_assignment_execution.batch_id == batch.batch_id then
      log.info("Skipped execution for already-queued batch %s", tostring(batch.batch_id))
      return true, "already executed", state.last_assignment_execution
    end

    local execution = {
      batch_id = batch.batch_id,
      executed_at = os.epoch("utc"),
      status = "queued",
      total_assignments = 0,
      total_items_requested = 0,
      total_items_queued = 0,
      assignments = {},
    }

    if (batch.total_assignments or 0) == 0 then
      execution.status = "empty"
      persistExecution(state, execution)
      log.info("Batch %s was empty", tostring(batch.batch_id))
      return true, "empty batch", execution
    end

    for _, assignment in ipairs(batch.assignments or {}) do
      local destinationAddress = assignment.destination_address
      if type(destinationAddress) ~= "string" or destinationAddress == "" then
        error("assignment missing destination_address for " .. tostring(assignment.assignment_id), 0)
      end

      local filters = {}
      for _, item in ipairs(assignment.items or {}) do
        filters[#filters + 1] = {
          name = item.name,
          _requestCount = item.count,
        }
      end

      local queuedItems = 0
      if #filters > 0 then
        queuedItems = stockTicker.requestFiltered(destinationAddress, unpack(filters)) or 0
      end

      local requestedItems = assignmentRequestedItems(assignment)
      execution.assignments[#execution.assignments + 1] = {
        assignment_id = assignment.assignment_id,
        destination = assignment.destination,
        destination_address = destinationAddress,
        line_count = assignment.line_count or #filters,
        requested_items = requestedItems,
        queued_items = queuedItems,
        status = queuedItems >= requestedItems and "queued" or "partial",
      }
      execution.total_assignments = execution.total_assignments + 1
      execution.total_items_requested = execution.total_items_requested + requestedItems
      execution.total_items_queued = execution.total_items_queued + queuedItems
      log.info(
        "Queued assignment %s to %s: requested=%d queued=%d",
        tostring(assignment.assignment_id),
        tostring(destinationAddress),
        requestedItems,
        queuedItems
      )
    end

    if execution.total_items_queued <= 0 and execution.total_items_requested > 0 then
      execution.status = "failed"
    elseif execution.total_items_queued < execution.total_items_requested then
      execution.status = "partial"
    end

    persistExecution(state, execution)
    log.info(
      "Executed batch %s with status=%s assignments=%d requested=%d queued=%d",
      tostring(batch.batch_id),
      tostring(execution.status),
      execution.total_assignments,
      execution.total_items_requested,
      execution.total_items_queued
    )
    return true, execution.status, execution
  end

  return executor
end

return M
