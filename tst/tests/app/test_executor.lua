local lu = require("deps.luaunit")
local ccEnv = require("support.cc_test_env")

local function freshModules()
  package.loaded["deps.log"] = nil
  package.loaded["app.executor"] = nil
  return require("app.executor")
end

local function baseConfig()
  return {
    logistics = {
      stock_ticker = "Create_StockTicker_0",
    },
  }
end

local function baseState()
  return {
    last_assignment_execution = nil,
    last_assignment_execution_is_persisted = false,
    last_assignment_execution_at = nil,
  }
end

TestWarehouseExecutor = {}

function TestWarehouseExecutor:setUp()
  ccEnv.install({ epoch = 123456 })
end

function TestWarehouseExecutor:tearDown()
  ccEnv.restore()
end

function TestWarehouseExecutor:testEmptyBatchPersistsEmptyExecution()
  local savedExecution
  ccEnv.setPeripheral("Create_StockTicker_0", {
    requestFiltered = function()
      return 0
    end,
  })

  local Executor = freshModules()
  local executor = Executor.new(baseConfig(), {
    persistAssignmentExecution = function(execution)
      savedExecution = execution
    end,
  })

  local ok, status, execution = executor.executeBatch(baseState(), {
    batch_id = "west:0:0:1",
    total_assignments = 0,
    assignments = {},
  })

  lu.assertTrue(ok)
  lu.assertEquals(status, "empty batch")
  lu.assertEquals(execution.status, "empty")
  lu.assertEquals(savedExecution.batch_id, "west:0:0:1")
end

function TestWarehouseExecutor:testDuplicateBatchReturnsExistingExecution()
  ccEnv.setPeripheral("Create_StockTicker_0", {
    requestFiltered = function()
      error("should not be called")
    end,
  })

  local persistedCalls = 0
  local Executor = freshModules()
  local executor = Executor.new(baseConfig(), {
    persistAssignmentExecution = function()
      persistedCalls = persistedCalls + 1
    end,
  })

  local state = baseState()
  state.last_assignment_execution = {
    batch_id = "batch-1",
    status = "queued",
  }

  local ok, status, execution = executor.executeBatch(state, {
    batch_id = "batch-1",
    total_assignments = 1,
    assignments = {},
  })

  lu.assertTrue(ok)
  lu.assertEquals(status, "already executed")
  lu.assertEquals(execution.batch_id, "batch-1")
  lu.assertEquals(persistedCalls, 0)
end

function TestWarehouseExecutor:testQueuedBatchReportsQueuedExecution()
  local requestCalls = {}
  ccEnv.setPeripheral("Create_StockTicker_0", {
    requestFiltered = function(destinationAddress, ...)
      requestCalls[#requestCalls + 1] = {
        destination_address = destinationAddress,
        filters = { ... },
      }
      return 7
    end,
  })

  local savedExecution
  local Executor = freshModules()
  local executor = Executor.new(baseConfig(), {
    persistAssignmentExecution = function(execution)
      savedExecution = execution
    end,
  })

  local ok, status, execution = executor.executeBatch(baseState(), {
    batch_id = "batch-2",
    total_assignments = 1,
    assignments = {
      {
        assignment_id = "assign-1",
        destination = "east",
        destination_address = "WH_EAST",
        line_count = 2,
        items = {
          { name = "minecraft:white_wool", count = 4 },
          { name = "minecraft:red_wool", count = 3 },
        },
      },
    },
  })

  lu.assertTrue(ok)
  lu.assertEquals(status, "queued")
  lu.assertEquals(savedExecution.total_items_requested, 7)
  lu.assertEquals(execution.total_items_queued, 7)
  lu.assertEquals(#requestCalls, 1)
  lu.assertEquals(requestCalls[1].destination_address, "WH_EAST")
  lu.assertEquals(#requestCalls[1].filters, 2)
end

function TestWarehouseExecutor:testPartialBatchReportsPartialExecution()
  ccEnv.setPeripheral("Create_StockTicker_0", {
    requestFiltered = function()
      return 4
    end,
  })

  local Executor = freshModules()
  local executor = Executor.new(baseConfig(), {
    persistAssignmentExecution = function()
    end,
  })

  local ok, status, execution = executor.executeBatch(baseState(), {
    batch_id = "batch-3",
    total_assignments = 1,
    assignments = {
      {
        assignment_id = "assign-2",
        destination = "mid",
        destination_address = "WH_MID",
        items = {
          { name = "minecraft:white_wool", count = 6 },
        },
      },
    },
  })

  lu.assertTrue(ok)
  lu.assertEquals(status, "partial")
  lu.assertEquals(execution.status, "partial")
  lu.assertEquals(execution.assignments[1].queued_items, 4)
end

return TestWarehouseExecutor
