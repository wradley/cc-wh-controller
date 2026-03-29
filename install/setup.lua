-- Config version check for wh-controller.
-- Runs after cc-pkg installs program files.
--
-- Fresh install (no config): instructs the operator to run wh-controller,
--   which will invoke the setup wizard on first boot.
-- Upgrade (config exists): checks the config version and reports whether
--   manual reconciliation is needed.

local CONFIG_PATH    = "/etc/wh-controller/config.lua"
local CONFIG_VERSION = 1

local scriptDir   = fs.getDir(shell.getRunningProgram())
local installBase = fs.getDir(scriptDir)
local TEMPLATE_PATH = installBase .. "/install/templates/config.lua"

local function readFile(path)
  local f = fs.open(path, "r")
  if not f then return nil end
  local s = f.readAll()
  f.close()
  return s
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

if not fs.exists(CONFIG_PATH) then
  print("No config found at " .. CONFIG_PATH .. ".")
  print("Run wh-controller to complete peripheral setup.")
  return
end

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
