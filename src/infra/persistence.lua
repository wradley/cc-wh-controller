---Persistence helpers for warehouse controller state snapshots.
---@class WarehousePersistence
local M = {}

local function varDir()
  return "/var/wh-controller"
end

local function batchPath()
  return fs.combine(varDir(), "assignment_batch.txt")
end

local function executionPath()
  return fs.combine(varDir(), "assignment_execution.txt")
end

---Ensure the local `var/` directory exists before persistence writes.
---@return nil
function M.ensureVarDir()
  local path = varDir()
  local parent = fs.getDir(path)
  if parent ~= "" and not fs.exists(parent) then
    fs.makeDir(parent)
  end
  if not fs.exists(path) then
    fs.makeDir(path)
  end
end

---Persist the latest received assignment batch to disk.
---@param message WarehouseAssignmentBatch
---@return nil
function M.persistAssignmentBatch(message)
  M.ensureVarDir()

  local handle = fs.open(batchPath(), "w")
  if not handle then
    error("failed to open assignment batch file for writing", 0)
  end

  handle.write(textutils.serialize({
    batch = message,
    saved_at = os.epoch("utc"),
  }))
  handle.close()
end

---Persist the latest local assignment execution result to disk.
---@param execution WarehouseAssignmentExecution
---@return nil
function M.persistAssignmentExecution(execution)
  M.ensureVarDir()

  local handle = fs.open(executionPath(), "w")
  if not handle then
    error("failed to open assignment execution file for writing", 0)
  end

  handle.write(textutils.serialize({
    execution = execution,
    saved_at = os.epoch("utc"),
  }))
  handle.close()
end

---Remove the persisted assignment batch file when local state is cleared.
---@return nil
function M.clearPersistedAssignmentBatch()
  if fs.exists(batchPath()) then
    fs.delete(batchPath())
  end
end

---Remove the persisted assignment execution file when local state is cleared.
---@return nil
function M.clearPersistedAssignmentExecution()
  if fs.exists(executionPath()) then
    fs.delete(executionPath())
  end
end

---Remove all persisted local assignment state.
---@return nil
function M.clearPersistedAssignmentState()
  M.clearPersistedAssignmentBatch()
  M.clearPersistedAssignmentExecution()
end

local function loadSerialized(path, fieldName)
  if not fs.exists(path) then
    return nil, nil
  end

  local handle = fs.open(path, "r")
  if not handle then
    error("failed to open " .. path .. " for reading", 0)
  end

  local serialized = handle.readAll()
  handle.close()

  local loaded = textutils.unserialize(serialized)
  if type(loaded) ~= "table" then
    error("failed to unserialize " .. path, 0)
  end

  return loaded[fieldName], loaded.saved_at
end

---Load the most recently persisted assignment batch from disk.
---@return WarehouseAssignmentBatch|nil, number|nil
function M.loadPersistedAssignmentBatch()
  return loadSerialized(batchPath(), "batch")
end

---Load the most recently persisted assignment execution result from disk.
---@return WarehouseAssignmentExecution|nil, number|nil
function M.loadPersistedAssignmentExecution()
  return loadSerialized(executionPath(), "execution")
end

---Rehydrate persisted assignment data into the live warehouse runtime state.
---@param state WarehouseState
---@return nil
function M.loadPersistedState(state)
  local batch = M.loadPersistedAssignmentBatch()
  if type(batch) == "table" then
    state.latest_assignment_batch = batch
    state.latest_assignment_batch_is_persisted = true
    state.last_assignment_received_at = batch.sent_at or nil
  end

  local execution = M.loadPersistedAssignmentExecution()
  if type(execution) == "table" then
    state.last_assignment_execution = execution
    state.last_assignment_execution_is_persisted = true
    state.last_assignment_execution_at = execution.executed_at or nil
  end
end

return M
