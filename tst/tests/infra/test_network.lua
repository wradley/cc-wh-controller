local lu = require("deps.luaunit")
local ccEnv = require("support.cc_test_env")

local function freshModules()
  package.loaded["deps.log"] = nil
  package.loaded["infra.network"] = nil
  package.loaded["rednet_contracts"] = nil
  package.loaded["rednet_contracts.init"] = nil
  package.loaded["rednet_contracts.discovery_v1"] = nil
  package.loaded["rednet_contracts.errors"] = nil
  package.loaded["rednet_contracts.schema_validation"] = nil
  package.loaded["rednet_contracts.mrpc_v1"] = nil
  package.loaded["rednet_contracts.services.warehouse_v1"] = nil
  return require("infra.network")
end

local function baseState()
  return {
    network = {
      protocol = "warehouse_sync_v1",
      heartbeat_seconds = 5,
    },
    warehouse = {
      id = "west",
      address = "WH_WEST",
    },
    latest_snapshot = {
      type = "snapshot",
      warehouse_id = "west",
      warehouse_address = "WH_WEST",
      observed_at = 2000,
      inventory = {
        ["minecraft:iron_ingot"] = 9,
      },
      capacity = {
        storages_online = 2,
        storages_total = 2,
        storages_with_unknown_capacity = 0,
        slot_capacity_total = 20,
        slot_capacity_used = 4,
      },
    },
    latest_assignment_batch = nil,
    latest_assignment_batch_is_persisted = false,
    last_assignment_received_at = nil,
    last_assignment_ack_at = nil,
    last_assignment_execution = nil,
    last_assignment_execution_is_persisted = false,
    last_assignment_execution_at = nil,
    owner = nil,
  }
end

TestWarehouseNetwork = {}

function TestWarehouseNetwork:setUp()
  ccEnv.install({ epoch = 2000 })
end

function TestWarehouseNetwork:tearDown()
  ccEnv.restore()
end

function TestWarehouseNetwork:testSendHeartbeatUsesDiscoveryContract()
  local Network = freshModules()
  local state = baseState()

  Network.sendHeartbeat(state)

  lu.assertEquals(#ccEnv.getBroadcastMessages(), 1)
  lu.assertEquals(ccEnv.getBroadcastMessages()[1].protocol, "rc.discovery_v1")
  lu.assertEquals(ccEnv.getBroadcastMessages()[1].message.discovery_version, 1)
  lu.assertEquals(ccEnv.getBroadcastMessages()[1].message.device_id, "west")
  lu.assertEquals(ccEnv.getBroadcastMessages()[1].message.protocols[1].name, "warehouse")
end

function TestWarehouseNetwork:testGetOwnerReturnsNilWhenWarehouseIsFree()
  local Network = freshModules()
  local state = baseState()

  ccEnv.queueRednetReceive(17, {
    type = "request",
    protocol = {
      name = "warehouse",
      version = 1,
    },
    request_id = "req-owner-1",
    method = "get_owner",
    params = {},
    sent_at = 2000,
  }, "rc.mrpc_v1")

  local snapshotRequested = Network.handleRequest(state, {}, {}, {}, nil)

  lu.assertFalse(snapshotRequested)
  lu.assertEquals(#ccEnv.getSentMessages(), 1)
  lu.assertTrue(ccEnv.getSentMessages()[1].message.ok)
  lu.assertNil(ccEnv.getSentMessages()[1].message.result.owner)
end

function TestWarehouseNetwork:testSetOwnerPersistsAndRepliesWithAcceptedOwner()
  local Network = freshModules()
  local state = baseState()
  local persistedOwner

  ccEnv.queueRednetReceive(17, {
    type = "request",
    protocol = {
      name = "warehouse",
      version = 1,
    },
    request_id = "req-owner-2",
    method = "set_owner",
    params = {
      coordinator_id = "coord-1",
      coordinator_address = "global-sync",
      claimed_at = 1999,
    },
    sent_at = 2000,
  }, "rc.mrpc_v1")

  Network.handleRequest(state, {}, {}, {
    persistOwner = function(owner)
      persistedOwner = owner
    end,
  }, nil)

  lu.assertEquals(state.owner.coordinator_id, "coord-1")
  lu.assertEquals(state.owner.sender_id, 17)
  lu.assertEquals(persistedOwner.sender_id, 17)
  lu.assertEquals(#ccEnv.getSentMessages(), 1)
  lu.assertTrue(ccEnv.getSentMessages()[1].message.result.accepted)
  lu.assertEquals(ccEnv.getSentMessages()[1].message.result.owner.coordinator_address, "global-sync")
end

function TestWarehouseNetwork:testGetSnapshotFailsClosedWithoutAcceptedOwner()
  local Network = freshModules()
  local state = baseState()

  ccEnv.queueRednetReceive(17, {
    type = "request",
    protocol = {
      name = "warehouse",
      version = 1,
    },
    request_id = "req-snapshot-1",
    method = "get_snapshot",
    params = {},
    sent_at = 2000,
  }, "rc.mrpc_v1")

  local snapshotRequested = Network.handleRequest(state, {}, {}, {}, nil)

  lu.assertFalse(snapshotRequested)
  lu.assertEquals(#ccEnv.getSentMessages(), 1)
  lu.assertFalse(ccEnv.getSentMessages()[1].message.ok)
  lu.assertEquals(ccEnv.getSentMessages()[1].message.error.code, "ownership_required")
end

function TestWarehouseNetwork:testAssignTransferRequestPersistsExecutesAndReplies()
  local Network = freshModules()
  local state = baseState()
  state.owner = {
    coordinator_id = "coord-1",
    coordinator_address = "global-sync",
    claimed_at = 1900,
    sender_id = 17,
  }

  local persistedBatch
  local executorCalls = 0

  ccEnv.queueRednetReceive(17, {
    type = "request",
    protocol = {
      name = "warehouse",
      version = 1,
    },
    request_id = "req-transfer-1",
    method = "assign_transfer_request",
    params = {
      coordinator_id = "coord-1",
      transfer_request_id = "tr-1",
      sent_at = 2000,
      warehouse_id = "west",
      assignments = {
        {
          assignment_id = "assign-1",
          source = "global_inventory",
          destination = "crate-a",
          destination_address = "WH_EAST",
          reason = "rebalance",
          status = "queued",
          items = {
            {
              name = "minecraft:iron_ingot",
              count = 9,
            },
          },
          total_items = 9,
          line_count = 1,
        },
      },
      total_assignments = 1,
      total_items = 9,
    },
    sent_at = 2000,
  }, "rc.mrpc_v1")

  Network.handleRequest(state, {}, {}, {
    persistAssignmentBatch = function(batch)
      persistedBatch = batch
    end,
  }, {
    executeBatch = function(_, batch)
      executorCalls = executorCalls + 1
      return true, "queued", {
        batch_id = batch.batch_id,
        executed_at = 2000,
        status = "queued",
        total_assignments = 1,
        total_items_requested = 9,
        total_items_queued = 9,
        packages = batch.packages,
        assignments = {
          {
            assignment_id = "assign-1",
            destination = "crate-a",
            destination_address = "WH_EAST",
            line_count = 1,
            requested_items = 9,
            queued_items = 9,
            status = "queued",
          },
        },
      }
    end,
  })

  lu.assertEquals(persistedBatch.batch_id, "tr-1")
  lu.assertEquals(state.latest_assignment_batch.batch_id, "tr-1")
  lu.assertEquals(state.latest_assignment_batch.packages["in"][1], nil)
  lu.assertEquals(state.latest_assignment_batch.packages["out"][1], nil)
  lu.assertEquals(executorCalls, 1)
  lu.assertEquals(#ccEnv.getSentMessages(), 1)
  lu.assertTrue(ccEnv.getSentMessages()[1].message.ok)
  lu.assertEquals(ccEnv.getSentMessages()[1].message.result.transfer_request_id, "tr-1")
end

function TestWarehouseNetwork:testGetTransferRequestStatusReturnsExecutionForOwner()
  local Network = freshModules()
  local state = baseState()
  state.owner = {
    coordinator_id = "coord-1",
    coordinator_address = "global-sync",
    claimed_at = 1900,
    sender_id = 17,
  }
  state.last_assignment_execution = {
    batch_id = "tr-1",
    executed_at = 2000,
    status = "queued",
    total_assignments = 1,
    total_items_requested = 9,
    total_items_queued = 9,
    packages = {
      ["in"] = {
        "123-1-1",
      },
      ["out"] = {
        "456-1-1",
      },
    },
    assignments = {
      {
        assignment_id = "assign-1",
        destination = "crate-a",
        destination_address = "WH_EAST",
        line_count = 1,
        requested_items = 9,
        queued_items = 9,
        status = "queued",
      },
    },
  }

  ccEnv.queueRednetReceive(17, {
    type = "request",
    protocol = {
      name = "warehouse",
      version = 1,
    },
    request_id = "req-status-1",
    method = "get_transfer_request_status",
    params = {
      transfer_request_id = "tr-1",
    },
    sent_at = 2000,
  }, "rc.mrpc_v1")

  Network.handleRequest(state, {}, {}, {}, nil)

  lu.assertEquals(#ccEnv.getSentMessages(), 1)
  lu.assertTrue(ccEnv.getSentMessages()[1].message.ok)
  lu.assertEquals(ccEnv.getSentMessages()[1].message.result.status, "queued")
  lu.assertEquals(ccEnv.getSentMessages()[1].message.result.assignments[1].queued_items, 9)
  lu.assertEquals(ccEnv.getSentMessages()[1].message.result.packages["in"][1], "123-1-1")
end

return TestWarehouseNetwork
