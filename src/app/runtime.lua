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

---@class WarehouseTrainDepartureEvent
---@field station_name string
---@field train_name string
---@field sent_at number

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
---@field last_train_departure WarehouseTrainDepartureEvent|nil

---Warehouse runtime state construction.
---@class WarehouseRuntime
local M = {}

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
    train = config.train,
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
    last_train_departure = nil,
  }
end

return M
