local lu = require("deps.luaunit")
local ccEnv = require("support.cc_test_env")

local function freshModules()
  package.loaded["infra.persistence"] = nil
  return require("infra.persistence")
end

local function baseState()
  return {
    latest_assignment_batch = nil,
    latest_assignment_batch_is_persisted = false,
    last_assignment_received_at = nil,
    last_assignment_execution = nil,
    last_assignment_execution_is_persisted = false,
    last_assignment_execution_at = nil,
    owner = nil,
  }
end

TestWarehousePersistence = {}

function TestWarehousePersistence:setUp()
  ccEnv.install({ epoch = 123456 })
end

function TestWarehousePersistence:tearDown()
  ccEnv.restore()
end

function TestWarehousePersistence:testLoadPersistedStateRestoresPackagesAndOwner()
  local Persistence = freshModules()
  local originalLoadBatch = Persistence.loadPersistedAssignmentBatch
  local originalLoadExecution = Persistence.loadPersistedAssignmentExecution
  local originalLoadOwner = Persistence.loadPersistedOwner
  Persistence.loadPersistedAssignmentBatch = function()
    return {
      batch_id = "tr-1",
      sent_at = 1000,
      packages = {
        ["in"] = {
          "111-1-1",
        },
        ["out"] = {
          "222-1-1",
        },
      },
    }, 1100
  end
  Persistence.loadPersistedAssignmentExecution = function()
    return {
      batch_id = "tr-1",
      executed_at = 1200,
      status = "queued",
      packages = {
        ["in"] = {
          "333-1-1",
        },
        ["out"] = {
          "444-1-1",
        },
      },
    }, 1300
  end
  Persistence.loadPersistedOwner = function()
    return {
      coordinator_id = "coord-1",
      coordinator_address = "global-sync",
      claimed_at = 900,
      sender_id = 17,
    }, 1400
  end

  local state = baseState()
  Persistence.loadPersistedState(state)

  Persistence.loadPersistedAssignmentBatch = originalLoadBatch
  Persistence.loadPersistedAssignmentExecution = originalLoadExecution
  Persistence.loadPersistedOwner = originalLoadOwner

  lu.assertTrue(state.latest_assignment_batch_is_persisted)
  lu.assertEquals(state.latest_assignment_batch.packages["out"][1], "222-1-1")
  lu.assertEquals(state.last_assignment_received_at, 1000)
  lu.assertTrue(state.last_assignment_execution_is_persisted)
  lu.assertEquals(state.last_assignment_execution.packages["in"][1], "333-1-1")
  lu.assertEquals(state.last_assignment_execution_at, 1200)
  lu.assertEquals(state.owner.coordinator_id, "coord-1")
  lu.assertEquals(state.owner.sender_id, 17)
end

function TestWarehousePersistence:testLoadPersistedAssignmentBatchReadsSerializedFile()
  local Persistence = freshModules()
  ccEnv.setFile("/var/wh-controller/assignment_batch.txt", textutils.serialize({
    batch = {
      batch_id = "tr-1",
      sent_at = 1000,
      packages = {
        ["in"] = {
          "111-1-1",
        },
        ["out"] = {
          "222-1-1",
        },
      },
    },
    saved_at = 1100,
  }))

  local batch, savedAt = Persistence.loadPersistedAssignmentBatch()

  lu.assertEquals(savedAt, 1100)
  lu.assertEquals(batch.batch_id, "tr-1")
  lu.assertEquals(batch.packages["out"][1], "222-1-1")
end

function TestWarehousePersistence:testLoadPersistedAssignmentExecutionReadsSerializedFile()
  local Persistence = freshModules()
  ccEnv.setFile("/var/wh-controller/assignment_execution.txt", textutils.serialize({
    execution = {
      batch_id = "tr-1",
      executed_at = 1200,
      status = "queued",
      packages = {
        ["in"] = {
          "333-1-1",
        },
        ["out"] = {
          "444-1-1",
        },
      },
    },
    saved_at = 1300,
  }))

  local execution, savedAt = Persistence.loadPersistedAssignmentExecution()

  lu.assertEquals(savedAt, 1300)
  lu.assertEquals(execution.executed_at, 1200)
  lu.assertEquals(execution.packages["in"][1], "333-1-1")
end

function TestWarehousePersistence:testLoadPersistedOwnerReadsSerializedFile()
  local Persistence = freshModules()
  ccEnv.setFile("/var/wh-controller/owner.txt", textutils.serialize({
    owner = {
      coordinator_id = "coord-1",
      coordinator_address = "global-sync",
      claimed_at = 900,
      sender_id = 17,
    },
    saved_at = 1400,
  }))

  local owner, savedAt = Persistence.loadPersistedOwner()

  lu.assertEquals(savedAt, 1400)
  lu.assertEquals(owner.coordinator_id, "coord-1")
  lu.assertEquals(owner.sender_id, 17)
end

return TestWarehousePersistence
