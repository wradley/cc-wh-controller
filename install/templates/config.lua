return {
  version = 1,
  warehouse = {
    id = "warehouse-id-here",
    address = "WH_ADDRESS_HERE",
    display_name = "Warehouse Name",
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
  train = {
    export_station = "Create_Station_0",
  },
  storage = {
    {
      storage_id = "storage_a",
      packager = "Create_Packager_0",
    },
  },
}
