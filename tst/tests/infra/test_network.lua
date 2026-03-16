local lu = require("deps.luaunit")
local ccEnv = require("support.cc_test_env")

local function freshModules()
  package.loaded["deps.log"] = nil
  package.loaded["infra.network"] = nil
  return require("infra.network")
end

local function baseState()
  return {
    network = {
      protocol = "warehouse_sync_v1",
    },
    warehouse = {
      id = "west",
      address = "WH_WEST",
    },
    latest_snapshot = {
      type = "snapshot",
      warehouse_id = "west",
      warehouse_address = "WH_WEST",
    },
    latest_assignment_batch = nil,
    latest_assignment_batch_is_persisted = false,
    last_assignment_received_at = nil,
    last_assignment_ack_at = nil,
    last_assignment_execution = nil,
    last_assignment_execution_is_persisted = false,
    last_assignment_execution_at = nil,
  }
end

TestWarehouseNetwork = {}

function TestWarehouseNetwork:setUp()
  ccEnv.install({ epoch = 2000 })
end

function TestWarehouseNetwork:tearDown()
  ccEnv.restore()
end

function TestWarehouseNetwork:testSnapshotRequestClearsPersistedBatchWhenCoordinatorHasNoActiveBatch()
  local Network = freshModules()
  local state = baseState()
  state.latest_assignment_batch = {
    batch_id = "old-batch",
    total_assignments = 2,
    total_items = 15,
  }
  state.latest_assignment_batch_is_persisted = true
  state.last_assignment_received_at = 1111
  state.last_assignment_execution = {
    batch_id = "old-batch",
    status = "queued",
  }
  state.last_assignment_execution_is_persisted = true
  state.last_assignment_execution_at = 1112

  local cleared = 0
  local refreshed = 0
  local snapshotRequested = Network.handleMessage(
    state,
    0,
    {
      type = "get_snapshot",
      active_batch_id = nil,
    },
    "warehouse_sync_v1",
    {
      refresh = function(currentState)
        refreshed = refreshed + 1
        currentState.latest_snapshot = {
          type = "snapshot",
          warehouse_id = "west",
          warehouse_address = "WH_WEST",
        }
      end,
    },
    {},
    {
      clearPersistedAssignmentState = function()
        cleared = cleared + 1
      end,
    },
    nil
  )

  lu.assertTrue(snapshotRequested)
  lu.assertEquals(refreshed, 1)
  lu.assertEquals(cleared, 1)
  lu.assertNil(state.latest_assignment_batch)
  lu.assertNil(state.last_assignment_execution)
  lu.assertEquals(#ccEnv.getSentMessages(), 1)
  lu.assertEquals(ccEnv.getSentMessages()[1].message.type, "snapshot")
end

function TestWarehouseNetwork:testSnapshotRequestKeepsMatchingBatch()
  local Network = freshModules()
  local state = baseState()
  state.latest_assignment_batch = {
    batch_id = "batch-1",
    total_assignments = 1,
    total_items = 5,
  }

  local cleared = 0
  local snapshotRequested = Network.handleMessage(
    state,
    0,
    {
      type = "get_snapshot",
      active_batch_id = "batch-1",
    },
    "warehouse_sync_v1",
    {
      refresh = function()
      end,
    },
    {},
    {
      clearPersistedAssignmentState = function()
        cleared = cleared + 1
      end,
    },
    nil
  )

  lu.assertTrue(snapshotRequested)
  lu.assertEquals(cleared, 0)
  lu.assertEquals(state.latest_assignment_batch.batch_id, "batch-1")
end

function TestWarehouseNetwork:testAssignmentBatchPersistsAcksAndExecutes()
  local Network = freshModules()
  local state = baseState()
  local persistedBatch
  local executorCalls = 0

  local handled = Network.handleMessage(
    state,
    0,
    {
      type = "assignment_batch",
      warehouse_id = "west",
      batch_id = "batch-2",
      total_assignments = 1,
      total_items = 9,
      assignments = {
        {
          assignment_id = "assign-1",
        },
      },
    },
    "warehouse_sync_v1",
    {},
    {},
    {
      persistAssignmentBatch = function(message)
        persistedBatch = message
      end,
    },
    {
      executeBatch = function(_, batch)
        executorCalls = executorCalls + 1
        return true, "queued", {
          batch_id = batch.batch_id,
          status = "queued",
          executed_at = 2000,
          total_assignments = 1,
          total_items_requested = 9,
          total_items_queued = 9,
          assignments = {},
        }
      end,
    }
  )

  lu.assertFalse(handled)
  lu.assertEquals(persistedBatch.batch_id, "batch-2")
  lu.assertEquals(executorCalls, 1)
  lu.assertEquals(state.latest_assignment_batch.batch_id, "batch-2")
  lu.assertFalse(state.latest_assignment_batch_is_persisted)
  lu.assertEquals(#ccEnv.getSentMessages(), 2)
  lu.assertEquals(ccEnv.getSentMessages()[1].message.type, "assignment_ack")
  lu.assertEquals(ccEnv.getSentMessages()[2].message.type, "assignment_execution")
end

function TestWarehouseNetwork:testAssignmentBatchForDifferentWarehouseIsIgnored()
  local Network = freshModules()
  local state = baseState()
  local persistedCalls = 0

  local handled = Network.handleMessage(
    state,
    0,
    {
      type = "assignment_batch",
      warehouse_id = "east",
      batch_id = "batch-x",
      total_assignments = 1,
      total_items = 4,
      assignments = {},
    },
    "warehouse_sync_v1",
    {},
    {},
    {
      persistAssignmentBatch = function()
        persistedCalls = persistedCalls + 1
      end,
    },
    {
      executeBatch = function()
        error("should not execute")
      end,
    }
  )

  lu.assertFalse(handled)
  lu.assertEquals(persistedCalls, 0)
  lu.assertNil(state.latest_assignment_batch)
  lu.assertEquals(#ccEnv.getSentMessages(), 0)
end

return TestWarehouseNetwork
