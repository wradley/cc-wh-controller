---Peripheral setup wizard for wh-controller.
---Runs interactively to discover peripherals and write the initial config.
---Each section re-scans peripherals so connections made mid-wizard are picked up.
local Wizard = {}

--------------------------------------------------------------------------------
-- Filesystem helpers
--------------------------------------------------------------------------------

local function writeFile(path, content)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local f = fs.open(path, "w")
  f.write(content)
  f.close()
end

--------------------------------------------------------------------------------
-- Peripheral scanning
--------------------------------------------------------------------------------

---Scan all sides for modems, returning separate wired and wireless lists.
---@return string[] wiredSides
---@return string[] wirelessSides
local function scanModems()
  local wired, wireless = {}, {}
  for _, side in ipairs({"top", "bottom", "left", "right", "front", "back"}) do
    local p = peripheral.wrap(side)
    if p and type(p.isWireless) == "function" then
      if p.isWireless() then
        wireless[#wireless + 1] = side
      else
        wired[#wired + 1] = side
      end
    end
  end
  return wired, wireless
end

---Find all peripherals of a given Create type name.
---@param typeName string
---@return string[]
local function scanByType(typeName)
  local found = {}
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, typeName) then
      found[#found + 1] = name
    end
  end
  return found
end

--------------------------------------------------------------------------------
-- UI helpers
--------------------------------------------------------------------------------

local function section(n, total, title)
  print("")
  local w = term.getSize()
  print(string.rep("-", w))
  print(string.format("  %d / %d  %s", n, total, title))
  print(string.rep("-", w))
end

---Prompt for input, pre-filling with a default value if supplied.
---If no default and input is empty, re-prompts (required field).
---@param label string
---@param default string|nil
---@return string
local function prompt(label, default)
  if default and default ~= "" then
    write("  " .. label .. " [" .. default .. "]: ")
    local v = read(nil, nil, nil, default)
    if not v or v == "" then return default end
    return v
  else
    while true do
      write("  " .. label .. ": ")
      local v = read()
      if v and v ~= "" then return v end
      printError("  Required.")
    end
  end
end

---@param question string
---@param defaultYes boolean
---@return boolean
local function yesno(question, defaultYes)
  local hint = defaultYes and "[Y/n]" or "[y/N]"
  write("  " .. question .. " " .. hint .. " ")
  local v = string.lower(read() or "")
  if v == "" then return defaultYes end
  return v == "y" or v == "yes"
end

---Poll until at least one item is found or the user presses a key to skip.
---Shows a dot for each polling cycle so the user knows it is alive.
---@param label string  Human-readable name of what is being waited for.
---@param scanFn fun(): string[]  Function that returns current candidates.
---@return string[]  Found candidates, or empty table if user skipped.
local function waitForPeripherals(label, scanFn)
  local found = scanFn()
  if #found > 0 then return found end

  print("  No " .. label .. " found. Connect it, then wait for detection.")
  term.write("  Scanning (any key to enter manually): ")

  local result = {}
  parallel.waitForAny(
    function()
      while true do
        os.sleep(1)
        result = scanFn()
        if #result > 0 then return end
        term.write(".")
      end
    end,
    function()
      os.pullEvent("key")
    end
  )
  print("")
  return result
end

---Present a list of found candidates and let the user pick one, accept a
---pre-filled default, or type a name manually.
---@param label string
---@param found string[]
---@param required boolean
---@return string  Chosen name, or "" if optional and skipped.
local function pickOrEnter(label, found, required)
  if #found == 1 then
    return prompt(label, found[1])
  elseif #found > 1 then
    print("  Multiple candidates found:")
    for i, name in ipairs(found) do
      print(string.format("    %d)  %s", i, name))
    end
    while true do
      write("  Choose number or type name: ")
      local v = read()
      local n = tonumber(v)
      if n and n >= 1 and n <= #found then return found[n] end
      if v and v ~= "" then return v end
    end
  else
    -- nothing found after waiting
    if required then
      printError("  Still not found. Enter the peripheral name manually.")
      return prompt(label, "")
    else
      if not yesno("  Not found. Enter manually?", false) then
        return ""
      end
      write("  " .. label .. ": ")
      return read() or ""
    end
  end
end

---Pick a modem side from detected candidates or fall back to manual entry.
---@param label string
---@param found string[]
---@param required boolean
---@return string
local function pickSide(label, found, required)
  if #found == 1 then
    return prompt(label .. " side", found[1])
  elseif #found > 1 then
    print("  Multiple candidates found:")
    for i, side in ipairs(found) do
      print(string.format("    %d)  %s", i, side))
    end
    while true do
      write("  Choose number or type side name: ")
      local v = read()
      local n = tonumber(v)
      if n and n >= 1 and n <= #found then return found[n] end
      if v and v ~= "" then return v end
    end
  else
    if required then
      printError("  No modem found. Enter side manually.")
    end
    return prompt(label .. " side (top/bottom/left/right/front/back)", "")
  end
end

--------------------------------------------------------------------------------
-- Config serializer
--------------------------------------------------------------------------------

local function serializeVal(v, indent)
  local t = type(v)
  if t == "string" then
    return string.format("%q", v)
  elseif t == "number" or t == "boolean" then
    return tostring(v)
  elseif t == "table" then
    local inner = indent .. "  "
    local lines = {}
    if #v > 0 then
      for _, item in ipairs(v) do
        lines[#lines + 1] = inner .. serializeVal(item, inner)
      end
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      for _, k in ipairs(keys) do
        local keyStr = type(k) == "string" and k or ("[" .. tostring(k) .. "]")
        lines[#lines + 1] = inner .. keyStr .. " = " .. serializeVal(v[k], inner)
      end
    end
    if #lines == 0 then return "{}" end
    return "{\n" .. table.concat(lines, ",\n") .. ",\n" .. indent .. "}"
  end
  return tostring(v)
end

--------------------------------------------------------------------------------
-- Wizard entry point
--------------------------------------------------------------------------------

---Run the peripheral setup wizard and write the config to configPath.
---Returns true if the config was written, false if the user cancelled.
---@param configPath string
---@return boolean
function Wizard.run(configPath)
  print("")
  print("=== wh-controller Setup Wizard ===")
  print("Each section scans for connected peripherals.")
  print("Connect missing hardware at any point and it will be detected.")

  --------------------------------------------------------------------------
  -- 1 / 5  Warehouse Identity
  --------------------------------------------------------------------------
  section(1, 5, "Warehouse Identity")

  local warehouseId = prompt("ID (e.g. east)", "")
  local warehouseAddress = prompt("Address (e.g. WH_EAST)", "WH_" .. string.upper(warehouseId))
  local nameDefault = warehouseId:sub(1, 1):upper() .. warehouseId:sub(2) .. " Warehouse"
  local displayName = prompt("Display name", nameDefault)

  --------------------------------------------------------------------------
  -- 2 / 5  Modems
  --------------------------------------------------------------------------
  section(2, 5, "Modems")

  print("  Wired modem (local peripherals):")
  local wiredSides = waitForPeripherals("wired modem", function()
    local w, _ = scanModems(); return w
  end)
  local wiredModem = pickSide("Wired modem", wiredSides, true)

  print("  Ender modem (coordinator communication):")
  local wirelessSides = waitForPeripherals("ender modem", function()
    local _, w = scanModems(); return w
  end)
  local enderModem = pickSide("Ender modem", wirelessSides, true)

  --------------------------------------------------------------------------
  -- 3 / 5  Logistics Peripherals
  --------------------------------------------------------------------------
  section(3, 5, "Logistics Peripherals")

  print("  Stock ticker:")
  local tickers = waitForPeripherals("stock ticker", function()
    return scanByType("Create_StockTicker")
  end)
  local stockTickerName = pickOrEnter("peripheral name", tickers, true)

  print("  Postbox:")
  local postboxes = waitForPeripherals("postbox", function()
    return scanByType("create:package_postbox")
  end)
  local postboxName = pickOrEnter("peripheral name", postboxes, true)

  --------------------------------------------------------------------------
  -- 4 / 5  Storage (Packagers)
  --------------------------------------------------------------------------
  section(4, 5, "Storage (Packagers)")

  print("  Scanning for packagers...")
  local packagerNames = waitForPeripherals("packagers", function()
    return scanByType("Create_Packager")
  end)

  local storageEntries = {}

  if #packagerNames > 0 then
    print("  Found " .. #packagerNames .. " packager(s).")
    print("  Enter a storage ID for each. IDs label packagers in logs and the coordinator UI.")
    print("")
    for i, pkgName in ipairs(packagerNames) do
      print("  Packager: " .. pkgName)
      local storageId = prompt("  Storage ID", "storage_" .. i)
      storageEntries[#storageEntries + 1] = { storage_id = storageId, packager = pkgName }
    end
  else
    printError("  No packagers detected. Enter at least one manually.")
  end

  while #storageEntries == 0 do
    write("  Packager peripheral name: ")
    local pkgName = read()
    if pkgName and pkgName ~= "" then
      local storageId = prompt("  Storage ID", "storage_1")
      storageEntries[#storageEntries + 1] = { storage_id = storageId, packager = pkgName }
    end
  end

  while yesno("Add another packager?", false) do
    write("  Packager peripheral name: ")
    local pkgName = read()
    if pkgName and pkgName ~= "" then
      local storageId = prompt("  Storage ID", "storage_" .. (#storageEntries + 1))
      storageEntries[#storageEntries + 1] = { storage_id = storageId, packager = pkgName }
    end
  end

  --------------------------------------------------------------------------
  -- 5 / 5  Train Export Station (optional)
  --------------------------------------------------------------------------
  section(5, 5, "Train Export Station (optional)")

  local stationNames = scanByType("Create_Station")
  local exportStation = nil

  if #stationNames > 0 then
    print("  Export station:")
    local name = pickOrEnter("peripheral name", stationNames, false)
    if name ~= "" then exportStation = name end
  else
    print("  No train stations detected.")
    if yesno("Configure an export station manually?", false) then
      write("  Export station peripheral name: ")
      local name = read()
      if name and name ~= "" then exportStation = name end
    end
  end

  --------------------------------------------------------------------------
  -- Review
  --------------------------------------------------------------------------
  section(0, 0, "Review")

  print("  warehouse.id           = " .. warehouseId)
  print("  warehouse.address      = " .. warehouseAddress)
  print("  warehouse.display_name = " .. displayName)
  print("  network.local_wired_modem = " .. wiredModem)
  print("  network.ender_modem    = " .. enderModem)
  print("  logistics.stock_ticker = " .. stockTickerName)
  print("  logistics.postbox      = " .. postboxName)
  for i, s in ipairs(storageEntries) do
    print(string.format("  storage[%d]  packager=%-24s  id=%s", i, s.packager, s.storage_id))
  end
  if exportStation then
    print("  train.export_station   = " .. exportStation)
  end

  print("")
  if not yesno("Write config to " .. configPath .. "?", true) then
    print("Cancelled. Run wh-controller again to configure.")
    return false
  end

  --------------------------------------------------------------------------
  -- Build and write config
  --------------------------------------------------------------------------
  local config = {
    version = 1,
    warehouse = {
      id           = warehouseId,
      address      = warehouseAddress,
      display_name = displayName,
    },
    network = {
      local_wired_modem = wiredModem,
      ender_modem       = enderModem,
      protocol          = "warehouse_sync_v1",
      heartbeat_seconds = 5,
    },
    runtime = {
      display_refresh_seconds  = 1,
      status_refresh_seconds   = 5,
      capacity_refresh_seconds = 300,
    },
    logistics = {
      stock_ticker = stockTickerName,
      postbox      = postboxName,
    },
    logging = {
      output = {
        file           = "/var/wh-controller/warehouse.log",
        level          = "info",
        mirror_to_term = false,
        timestamp      = "utc",
      },
      retention = {
        mode      = "truncate",
        max_lines = 1000,
      },
    },
    storage = storageEntries,
  }
  if exportStation then
    config.train = { export_station = exportStation }
  end

  writeFile(configPath, "return " .. serializeVal(config, "") .. "\n")
  print("")
  print("Config written to " .. configPath)

  --------------------------------------------------------------------------
  -- Startup registration (optional)
  --------------------------------------------------------------------------
  print("")
  if yesno("Start wh-controller automatically at boot?", true) then
    local STARTUP = "/startup.lua"
    local line    = 'shell.run("/bin/wh-controller")\n'
    local existing = ""
    local f = fs.open(STARTUP, "r")
    if f then existing = f.readAll(); f.close() end
    -- only append if the line isn't already there
    if not existing:find('wh%-controller', 1, false) then
      local out = fs.open(STARTUP, "w")
      out.write(existing)
      if existing ~= "" and existing:sub(-1) ~= "\n" then out.write("\n") end
      out.write(line)
      out.close()
      print("Added to " .. STARTUP)
    else
      print("Already present in " .. STARTUP .. " — skipped.")
    end
  end

  return true
end

return Wizard
