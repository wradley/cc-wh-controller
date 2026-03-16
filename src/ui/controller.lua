---Terminal UI rendering and input handling for the warehouse controller.
---@class WarehouseUi
local M = {}

local function ageSeconds(epochMs)
  if not epochMs then
    return nil
  end

  return math.floor((os.epoch("utc") - epochMs) / 1000)
end

local function drawStatus(state, store, lastSnapshotAt)
  term.clear()
  term.setCursorPos(1, 1)
  print(state.warehouse.display_name or state.warehouse.id)
  print(state.warehouse.address)
  print("")
  print("Heartbeat: " .. tostring(state.network.heartbeat_seconds) .. "s")

  if state.latest_snapshot then
    print("Storages: " .. state.latest_snapshot.capacity.storages_online .. "/" .. state.latest_snapshot.capacity.storages_total)
    if state.latest_snapshot.capacity.storages_with_unknown_capacity == 0 then
      local used = state.latest_snapshot.capacity.slot_capacity_used or 0
      local total = state.latest_snapshot.capacity.slot_capacity_total or 0
      local free = state.latest_snapshot.capacity.slot_capacity_free or 0
      local usedPercent = 0
      if total > 0 then
        usedPercent = math.floor((used / total) * 100 + 0.5)
      end
      print(tostring(used) .. "/" .. tostring(total) .. " slots in use (" .. tostring(usedPercent) .. "%), " .. tostring(free) .. " free")
    else
      print(tostring(state.latest_snapshot.capacity.slot_capacity_used or 0) .. "/? slots in use")
    end
    print("Items: " .. tostring(store.countTableKeys(state.latest_snapshot.inventory)))
  else
    print("Status: loading")
  end

  if state.last_capacity_probe_at then
    print("Capacity probe: " .. tostring(math.floor((os.epoch("utc") - state.last_capacity_probe_at) / 1000)) .. "s ago")
  else
    print("Capacity probe: never")
  end

  if state.last_status_refresh_at then
    print("Status updated: " .. tostring(math.floor((os.epoch("utc") - state.last_status_refresh_at) / 1000)) .. "s ago")
  end

  if lastSnapshotAt then
    print("")
    print("Last snapshot reply: " .. tostring(math.floor((os.epoch("utc") - lastSnapshotAt) / 1000)) .. "s ago")
  end

  print("")
  if state.latest_assignment_batch then
    local persistedSuffix = state.latest_assignment_batch_is_persisted and " (persisted)" or ""
    print("Batch ready: " .. tostring(state.latest_assignment_batch.total_assignments or 0) .. " tx / " .. tostring(state.latest_assignment_batch.total_items or 0) .. " items" .. persistedSuffix)
    local batchAgeSeconds = ageSeconds(state.last_assignment_received_at)
    if batchAgeSeconds then
      print("Batch age: " .. tostring(batchAgeSeconds) .. "s ago")
    end
  else
    print("Batch ready: none")
  end

  if state.last_assignment_execution then
    local persistedSuffix = state.last_assignment_execution_is_persisted and " (persisted)" or ""
    local executionAgeSeconds = ageSeconds(state.last_assignment_execution_at) or 0
    print("Last exec: " .. tostring(state.last_assignment_execution.total_items_queued or 0) .. "/" .. tostring(state.last_assignment_execution.total_items_requested or 0) .. " items " .. tostring(state.last_assignment_execution.status) .. persistedSuffix)
    print("Exec age: " .. tostring(executionAgeSeconds) .. "s ago")
  end

  if state.last_train_departure then
    print("Train dep: " .. tostring(state.last_train_departure.train_name or "?"))
    print("Dep age: " .. tostring(math.floor((os.epoch("utc") - state.last_train_departure.sent_at) / 1000)) .. "s ago")
  end
end

---Draw the warehouse controller terminal view.
---@param state WarehouseState
---@param store TableUtil
---@param lastSnapshotAt number|nil
---@return nil
function M.draw(state, store, lastSnapshotAt)
  drawStatus(state, store, lastSnapshotAt)
end

---Handle one character of operator input for the warehouse controller.
---@param state WarehouseState
---@param char string
---@param executor WarehouseExecutor
---@return boolean handled
function M.handleInput(state, char, executor)
  return false
end

return M
