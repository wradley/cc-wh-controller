---@class WarehouseStorageSnapshot
---@field storage_id string
---@field packager string
---@field online boolean
---@field slot_capacity_total integer|nil
---@field slot_capacity_used integer
---@field slot_capacity_free integer|nil
---@field distinct_items integer
---@field items table<string, integer>

---Warehouse snapshot building and refresh helpers.
---@class WarehouseSnapshotBuilder
local M = {}

local function canReadSlot(peripheralObject, slot)
  return pcall(peripheralObject.getItemDetail, slot)
end

local function probeSlotCapacity(peripheralObject)
  local capacity = 0
  local steps = { 1000, 100, 10, 1 }

  for _, step in ipairs(steps) do
    while canReadSlot(peripheralObject, capacity + step) do
      capacity = capacity + step
    end
  end

  return capacity
end

local function getCachedSlotCapacity(state, entry, peripheralObject)
  local now = os.epoch("utc")
  local cached = state.storage_capacity_cache[entry.storage_id]

  if cached and cached.packager == entry.packager and (now - cached.checked_at) < state.capacity_refresh_ms then
    return cached.slot_capacity_total
  end

  local slotCapacityTotal = probeSlotCapacity(peripheralObject)
  state.storage_capacity_cache[entry.storage_id] = {
    packager = entry.packager,
    slot_capacity_total = slotCapacityTotal,
    checked_at = now,
  }

  return slotCapacityTotal
end

local function getLastCapacityProbeAt(state)
  local latestCheckedAt

  for _, cached in pairs(state.storage_capacity_cache) do
    if not latestCheckedAt or cached.checked_at > latestCheckedAt then
      latestCheckedAt = cached.checked_at
    end
  end

  return latestCheckedAt
end

local function readStorage(state, entry, tables)
  local peripheralObject = peripheral.wrap(entry.packager)
  local listed = peripheralObject.list()

  local items = {}
  local usedSlots = 0
  for _, item in pairs(listed) do
    usedSlots = usedSlots + 1
    if item and item.name and item.count then
      items[item.name] = (items[item.name] or 0) + item.count
    end
  end

  local slotCapacityTotal = getCachedSlotCapacity(state, entry, peripheralObject)
  local slotCapacityFree
  if slotCapacityTotal then
    slotCapacityFree = math.max(slotCapacityTotal - usedSlots, 0)
  end

  return {
    storage_id = entry.storage_id,
    packager = entry.packager,
    online = true,
    slot_capacity_total = slotCapacityTotal,
    slot_capacity_used = usedSlots,
    slot_capacity_free = slotCapacityFree,
    distinct_items = tables.countTableKeys(items),
    items = items,
  }
end

---Build the current aggregate snapshot payload for this warehouse.
---@param state WarehouseState
---@param tables TableUtil
---@return WarehouseSnapshotMessage
function M.build(state, tables)
  local inventoryTotals = {}
  local totals = {
    slot_capacity_total = 0,
    slot_capacity_used = 0,
    slot_capacity_free = 0,
    storages_online = 0,
    storages_total = #state.storage,
    storages_with_unknown_capacity = 0,
  }

  for _, entry in ipairs(state.storage) do
    local storage = readStorage(state, entry, tables)

    if storage.online then
      totals.storages_online = totals.storages_online + 1
      totals.slot_capacity_used = totals.slot_capacity_used + (storage.slot_capacity_used or 0)

      if storage.slot_capacity_total then
        totals.slot_capacity_total = totals.slot_capacity_total + storage.slot_capacity_total
        totals.slot_capacity_free = totals.slot_capacity_free + (storage.slot_capacity_free or 0)
      else
        totals.storages_with_unknown_capacity = totals.storages_with_unknown_capacity + 1
      end

      for itemName, count in pairs(storage.items or {}) do
        inventoryTotals[itemName] = (inventoryTotals[itemName] or 0) + count
      end
    end
  end

  return {
    type = "snapshot",
    protocol_version = 1,
    warehouse_id = state.warehouse.id,
    warehouse_address = state.warehouse.address,
    observed_at = os.epoch("utc"),
    inventory = inventoryTotals,
    capacity = totals,
  }
end

---Refresh the live snapshot and probe timestamps on warehouse state.
---@param state WarehouseState
---@param tables TableUtil
---@return nil
function M.refresh(state, tables)
  state.latest_snapshot = M.build(state, tables)
  state.last_capacity_probe_at = getLastCapacityProbeAt(state)
  state.last_status_refresh_at = os.epoch("utc")
end

return M
