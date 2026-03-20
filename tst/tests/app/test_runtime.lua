local lu = require("deps.luaunit")
local ccEnv = require("support.cc_test_env")

local function freshModules()
  package.loaded["deps.log"] = nil
  package.loaded["app.runtime"] = nil
  return require("app.runtime")
end

local function baseConfig()
  return {
    warehouse = {
      id = "west",
      address = "WH_WEST",
      display_name = "West Warehouse",
    },
    network = {
      local_wired_modem = "back",
      ender_modem = "top",
      protocol = "warehouse_sync_v1",
      heartbeat_seconds = 5,
    },
    runtime = {
      display_refresh_seconds = 1,
      status_refresh_seconds = 5,
      capacity_refresh_seconds = 300,
    },
    logistics = {
      stock_ticker = "Create_StockTicker_0",
      postbox = "Create_Postbox_0",
    },
    logging = {
      output = {
        file = "/var/wh-controller/warehouse.log",
        level = "info",
        mirror_to_term = false,
        timestamp = "utc",
      },
      retention = {
        mode = "truncate",
        max_lines = 1000,
      },
    },
    train = nil,
    storage = {
      {
        storage_id = "west_a",
        packager = "Create_Packager_0",
      },
    },
  }
end

local function baseState()
  return {
    latest_assignment_batch = nil,
    last_assignment_execution = nil,
  }
end

TestWarehouseRuntime = {}

function TestWarehouseRuntime:setUp()
  ccEnv.install({ epoch = 123456 })
end

function TestWarehouseRuntime:tearDown()
  ccEnv.restore()
end

function TestWarehouseRuntime:testValidateConfiguredPeripheralsRequiresStockTickerPostboxAndPackagers()
  ccEnv.setPeripheral("Create_StockTicker_0", {
    requestFiltered = function()
    end,
  })
  ccEnv.setPeripheral("Create_Postbox_0", {})
  ccEnv.setPeripheral("Create_Packager_0", {
    list = function()
      return {}
    end,
    getItemDetail = function()
      return nil
    end,
  })

  local Runtime = freshModules()
  Runtime.validateConfiguredPeripherals(baseConfig())
end

function TestWarehouseRuntime:testValidateConfiguredPeripheralsFailsWhenPostboxIsMissing()
  ccEnv.setPeripheral("Create_StockTicker_0", {
    requestFiltered = function()
    end,
  })
  ccEnv.setPeripheral("Create_Packager_0", {
    list = function()
      return {}
    end,
    getItemDetail = function()
      return nil
    end,
  })

  local Runtime = freshModules()
  local ok, err = pcall(Runtime.validateConfiguredPeripherals, baseConfig())

  lu.assertFalse(ok)
  lu.assertStrContains(tostring(err), "missing peripheral: Create_Postbox_0")
end

function TestWarehouseRuntime:testRecordPackageEventPersistsUniquePackageIds()
  local Runtime = freshModules()
  local state = baseState()
  state.latest_assignment_batch = {
    batch_id = "tr-1",
    assignments = {},
    total_assignments = 0,
    total_items = 0,
    packages = {
      ["in"] = {},
      ["out"] = {},
    },
  }
  state.last_assignment_execution = {
    batch_id = "tr-1",
    executed_at = 2000,
    status = "queued",
    total_assignments = 0,
    total_items_requested = 0,
    total_items_queued = 0,
    assignments = {},
    packages = {
      ["in"] = {},
      ["out"] = {},
    },
  }

  local persistedBatch
  local persistedExecution
  local packageObject = {
    getOrderData = function()
      return {
        getOrderID = function() return 123 end,
        getLinkIndex = function() return 2 end,
        getIndex = function() return 4 end,
      }
    end,
  }

  local recorded, packageId = Runtime.recordPackageEvent(state, {
    persistAssignmentBatch = function(batch)
      persistedBatch = batch
    end,
    persistAssignmentExecution = function(execution)
      persistedExecution = execution
    end,
  }, "out", packageObject)

  lu.assertTrue(recorded)
  lu.assertEquals(packageId, "123-2-4")
  lu.assertEquals(state.latest_assignment_batch.packages["out"][1], "123-2-4")
  lu.assertEquals(state.last_assignment_execution.packages["out"][1], "123-2-4")
  lu.assertEquals(persistedBatch.packages["out"][1], "123-2-4")
  lu.assertEquals(persistedExecution.packages["out"][1], "123-2-4")
end

function TestWarehouseRuntime:testRecordPackageEventDoesNotPersistDuplicates()
  local Runtime = freshModules()
  local state = baseState()
  state.latest_assignment_batch = {
    batch_id = "tr-1",
    packages = {
      ["in"] = {},
      ["out"] = {
        "123-2-4",
      },
    },
  }
  state.last_assignment_execution = {
    batch_id = "tr-1",
    packages = {
      ["in"] = {},
      ["out"] = {
        "123-2-4",
      },
    },
  }

  local persistedBatchCalls = 0
  local persistedExecutionCalls = 0
  local packageObject = {
    getOrderData = function()
      return {
        getOrderID = function() return 123 end,
        getLinkIndex = function() return 2 end,
        getIndex = function() return 4 end,
      }
    end,
  }

  local recorded = Runtime.recordPackageEvent(state, {
    persistAssignmentBatch = function()
      persistedBatchCalls = persistedBatchCalls + 1
    end,
    persistAssignmentExecution = function()
      persistedExecutionCalls = persistedExecutionCalls + 1
    end,
  }, "out", packageObject)

  lu.assertFalse(recorded)
  lu.assertEquals(persistedBatchCalls, 0)
  lu.assertEquals(persistedExecutionCalls, 0)
end

return TestWarehouseRuntime
