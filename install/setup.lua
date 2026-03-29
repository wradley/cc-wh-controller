-- install/setup.lua (wh-controller)
-- Runs after cc-pkg installs program files.
--
-- Upgrade path (config exists): checks version, reports status.
-- Fresh install (no config):    runs peripheral discovery wizard and writes config.

local CONFIG_PATH    = "/etc/wh-controller/config.lua"
local CONFIG_VERSION = 1

local scriptDir  = fs.getDir(shell.getRunningProgram())
local installBase = fs.getDir(scriptDir)
local TEMPLATE_PATH = installBase .. "/install/templates/config.lua"

--------------------------------------------------------------------------------
-- Filesystem helpers
--------------------------------------------------------------------------------

local function readFile(path)
  local f = fs.open(path, "r")
  if not f then return nil end
  local s = f.readAll()
  f.close()
  return s
end

local function writeFile(path, content)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local f = fs.open(path, "w")
  f.write(content)
  f.close()
end

local function loadLuaFile(path)
  local src = readFile(path)
  if not src then return nil, "not found: " .. path end
  local fn, err = load(src, path)
  if not fn then return nil, "parse error: " .. tostring(err) end
  local ok, result = pcall(fn)
  if not ok then return nil, "eval error: " .. tostring(result) end
  if type(result) ~= "table" then return nil, "must return a table" end
  return result
end

--------------------------------------------------------------------------------
-- Upgrade path: config already exists
--------------------------------------------------------------------------------

if fs.exists(CONFIG_PATH) then
  local cfg, err = loadLuaFile(CONFIG_PATH)
  if not cfg then
    printError("Could not read existing config (" .. tostring(err) .. "); leaving it unchanged.")
    return
  end

  local existing = type(cfg.version) == "number" and cfg.version or 0

  if existing < CONFIG_VERSION then
    print("Config is version " .. existing .. "; this release expects version " .. CONFIG_VERSION .. ".")
    print("Review " .. TEMPLATE_PATH .. " for new required fields.")
    print("Update " .. CONFIG_PATH .. " manually before starting.")
  elseif existing == CONFIG_VERSION then
    print("Config is current (version " .. CONFIG_VERSION .. ").")
  else
    printError("Config version " .. existing .. " is newer than expected (" .. CONFIG_VERSION .. ").")
    printError("Downgrading may be unsafe. Check your installation.")
  end
  return
end

--------------------------------------------------------------------------------
-- Fresh install: peripheral wizard
--------------------------------------------------------------------------------

local W = term.getSize()

local function rule()
  print(string.rep("-", W))
end

local function section(title)
  print("")
  rule()
  print("  " .. title)
  rule()
end

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
      printError("  Required — please enter a value.")
    end
  end
end

local function yesno(question, defaultYes)
  local hint = defaultYes and "[Y/n]" or "[y/N]"
  write("  " .. question .. " " .. hint .. " ")
  local v = string.lower(read() or "")
  if v == "" then return defaultYes end
  return v == "y" or v == "yes"
end

-- Pick a value from a discovered list, or fall back to manual entry.
-- Returns the chosen name, or "" if optional and skipped.
local function pickOrEnter(label, found, required)
  if #found == 1 then
    return prompt(label, found[1])
  elseif #found > 1 then
    print("  Multiple " .. label .. " candidates:")
    for i, name in ipairs(found) do
      print("    " .. i .. ")  " .. name)
    end
    while true do
      write("  Choose number or type name: ")
      local v = read()
      local n = tonumber(v)
      if n and n >= 1 and n <= #found then return found[n] end
      if v and v ~= "" then return v end
    end
  else
    -- nothing found
    if required then
      printError("  None detected. Check wired modem connections.")
      return prompt(label .. " (enter name manually)", "")
    else
      if not yesno("None found. Enter manually?", false) then
        return ""
      end
      write("  " .. label .. ": ")
      return read() or ""
    end
  end
end

local function pickSide(label, found, required)
  if #found == 1 then
    return prompt(label, found[1])
  elseif #found > 1 then
    print("  Multiple " .. label .. " candidates:")
    for i, side in ipairs(found) do
      print("    " .. i .. ")  " .. side)
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
      printError("  No suitable modem found. Check connections.")
    else
      print("  None found.")
    end
    return prompt(label .. " (top/bottom/left/right/front/back)", "")
  end
end

--------------------------------------------------------------------------------
-- Discovery
--------------------------------------------------------------------------------

print("")
print("=== wh-controller Setup Wizard ===")
print("")
print("Scanning peripherals...")

-- Modems: probe each side directly
local wiredSides    = {}
local wirelessSides = {}
for _, side in ipairs({"top", "bottom", "left", "right", "front", "back"}) do
  local p = peripheral.wrap(side)
  if p and type(p.isWireless) == "function" then
    if p.isWireless() then
      wirelessSides[#wirelessSides + 1] = side
    else
      wiredSides[#wiredSides + 1] = side
    end
  end
end

-- Create peripherals: identify by capabilities rather than type name strings.
--   Stock ticker   has requestFiltered() — unique to Create_StockTicker
--   Postbox        has getConfiguration() — unique to Create_Postbox
--   Packager       has makePackage() — unique to Create_Packager
--   Train station  has getStationName() — unique to Create_Station
local stockTickers = {}
local postboxes    = {}
local packagers    = {}
local stations     = {}

for _, name in ipairs(peripheral.getNames()) do
  local p = peripheral.wrap(name)
  if p then
    if     type(p.requestFiltered) == "function" then
      stockTickers[#stockTickers + 1] = name
    elseif type(p.getConfiguration) == "function" then
      postboxes[#postboxes + 1] = name
    elseif type(p.makePackage) == "function" then
      packagers[#packagers + 1] = name
    elseif type(p.getStationName) == "function" then
      stations[#stations + 1] = name
    end
  end
end

print(string.format(
  "  wired modems: %d  |  wireless modems: %d",
  #wiredSides, #wirelessSides
))
print(string.format(
  "  stock tickers: %d  |  postboxes: %d  |  packagers: %d  |  stations: %d",
  #stockTickers, #postboxes, #packagers, #stations
))

--------------------------------------------------------------------------------
-- Section 1: Warehouse Identity
--------------------------------------------------------------------------------

section("1 / 5  Warehouse Identity")

local warehouseId = prompt("ID (e.g. east)", "")
local addrDefault = string.upper(warehouseId)
local warehouseAddress = prompt("Address (e.g. WH_EAST)", addrDefault)
local nameDefault = warehouseId:sub(1, 1):upper() .. warehouseId:sub(2) .. " Warehouse"
local displayName = prompt("Display name", nameDefault)

--------------------------------------------------------------------------------
-- Section 2: Modems
--------------------------------------------------------------------------------

section("2 / 5  Modems")

print("  Wired modem  (local peripherals):")
local wiredModem = pickSide("side", wiredSides, true)

print("  Ender modem  (coordinator communication):")
local enderModem = pickSide("side", wirelessSides, true)

--------------------------------------------------------------------------------
-- Section 3: Logistics Peripherals
--------------------------------------------------------------------------------

section("3 / 5  Logistics Peripherals")

print("  Stock ticker:")
local stockTickerName = pickOrEnter("peripheral name", stockTickers, true)

print("  Postbox:")
local postboxName = pickOrEnter("peripheral name", postboxes, true)

--------------------------------------------------------------------------------
-- Section 4: Storage (Packagers)
--------------------------------------------------------------------------------

section("4 / 5  Storage (Packagers)")

local storageEntries = {}

if #packagers > 0 then
  print("  Found " .. #packagers .. " packager(s). Enter a storage ID for each.")
  print("  Storage IDs label each packager in logs and the coordinator UI.")
  print("")
  for i, pkgName in ipairs(packagers) do
    print("  Packager: " .. pkgName)
    local storageId = prompt("  Storage ID", "storage_" .. i)
    storageEntries[#storageEntries + 1] = { storage_id = storageId, packager = pkgName }
  end
else
  printError("  No packagers detected. Check wired modem connections.")
  print("  Enter at least one packager name manually.")
end

-- Ensure at least one entry.
while #storageEntries == 0 do
  write("  Packager peripheral name: ")
  local pkgName = read()
  if pkgName and pkgName ~= "" then
    local storageId = prompt("  Storage ID", "storage_1")
    storageEntries[#storageEntries + 1] = { storage_id = storageId, packager = pkgName }
  end
end

-- Offer additional entries.
while yesno("Add another packager?", false) do
  write("  Packager peripheral name: ")
  local pkgName = read()
  if pkgName and pkgName ~= "" then
    local storageId = prompt("  Storage ID", "storage_" .. (#storageEntries + 1))
    storageEntries[#storageEntries + 1] = { storage_id = storageId, packager = pkgName }
  end
end

--------------------------------------------------------------------------------
-- Section 5: Train Station (optional)
--------------------------------------------------------------------------------

section("5 / 5  Train Export Station (optional)")

local exportStation = nil

if #stations > 0 then
  print("  Export station:")
  local name = pickOrEnter("peripheral name", stations, false)
  if name ~= "" then exportStation = name end
else
  print("  No train stations detected.")
  if yesno("Configure an export station manually?", false) then
    write("  Export station peripheral name: ")
    local name = read()
    if name and name ~= "" then exportStation = name end
  end
end

--------------------------------------------------------------------------------
-- Build config table
--------------------------------------------------------------------------------

local config = {
  version = CONFIG_VERSION,
  warehouse = {
    id           = warehouseId,
    address      = warehouseAddress,
    display_name = displayName,
  },
  network = {
    local_wired_modem  = wiredModem,
    ender_modem        = enderModem,
    protocol           = "warehouse_sync_v1",
    heartbeat_seconds  = 5,
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

--------------------------------------------------------------------------------
-- Review
--------------------------------------------------------------------------------

section("Review")

print("  warehouse:")
print("    id           = " .. config.warehouse.id)
print("    address      = " .. config.warehouse.address)
print("    display_name = " .. config.warehouse.display_name)
print("  network:")
print("    local_wired_modem = " .. config.network.local_wired_modem)
print("    ender_modem       = " .. config.network.ender_modem)
print("  logistics:")
print("    stock_ticker = " .. config.logistics.stock_ticker)
print("    postbox      = " .. config.logistics.postbox)
print("  storage:")
for i, s in ipairs(config.storage) do
  print("    [" .. i .. "] packager=" .. s.packager .. "  id=" .. s.storage_id)
end
if config.train then
  print("  train:")
  print("    export_station = " .. config.train.export_station)
end

print("")
if not yesno("Write config to " .. CONFIG_PATH .. "?", true) then
  print("")
  print("Cancelled. Re-run the installer to configure again.")
  return
end

--------------------------------------------------------------------------------
-- Serialize config to Lua and write
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
      -- sequence
      for _, item in ipairs(v) do
        lines[#lines + 1] = inner .. serializeVal(item, inner)
      end
    else
      -- map — use a stable key order for readability
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b)
        if type(a) == type(b) then return tostring(a) < tostring(b) end
        return type(a) < type(b)
      end)
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

writeFile(CONFIG_PATH, "return " .. serializeVal(config, "") .. "\n")

print("")
print("Config written to " .. CONFIG_PATH)
print("Start wh-controller to verify peripheral connections.")
