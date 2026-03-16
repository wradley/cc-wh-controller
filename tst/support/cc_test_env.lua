---Minimal ComputerCraft global stubs for warehouse tests.
---@class CcTestEnv
local M = {}

local original = {}
local currentEpoch = 0
local sentMessages = {}
local broadcastMessages = {}
local peripheralObjects = {}
local files = {}

local function deepCopy(value, seen)
  if type(value) ~= "table" then
    return value
  end

  seen = seen or {}
  if seen[value] then
    return seen[value]
  end

  local copy = {}
  seen[value] = copy
  for key, innerValue in pairs(value) do
    copy[deepCopy(key, seen)] = deepCopy(innerValue, seen)
  end
  return copy
end

local function normalizePath(path)
  return tostring(path or ""):gsub("\\", "/")
end

local function parentDir(path)
  local normalized = normalizePath(path)
  local match = normalized:match("^(.*)/[^/]+$")
  return match or ""
end

local function splitPath(path)
  local normalized = normalizePath(path)
  local parts = {}
  for part in normalized:gmatch("[^/]+") do
    parts[#parts + 1] = part
  end
  return parts
end

local function ensureDir(path)
  local normalized = normalizePath(path)
  if normalized == "" then
    return
  end

  local current = ""
  for _, part in ipairs(splitPath(normalized)) do
    current = current == "" and part or (current .. "/" .. part)
    if files[current] == nil then
      files[current] = {
        type = "dir",
      }
    end
  end
end

local function serializeValue(value)
  if type(value) == "table" then
    local pieces = { "{" }
    local first = true
    for key, innerValue in pairs(value) do
      if not first then
        pieces[#pieces + 1] = ","
      end
      first = false

      local renderedKey
      if type(key) == "string" and key:match("^[%a_][%w_]*$") then
        renderedKey = key
      else
        renderedKey = "[" .. serializeValue(key) .. "]"
      end

      pieces[#pieces + 1] = renderedKey .. "=" .. serializeValue(innerValue)
    end
    pieces[#pieces + 1] = "}"
    return table.concat(pieces)
  end

  if type(value) == "string" then
    return string.format("%q", value)
  end

  return tostring(value)
end

---Install test doubles for ComputerCraft globals used by the warehouse layer.
---@param opts? { epoch: integer|nil }
---@return nil
function M.install(opts)
  currentEpoch = opts and opts.epoch or 0
  sentMessages = {}
  broadcastMessages = {}
  peripheralObjects = {}
  files = {}

  original.os = _G.os
  original.textutils = _G.textutils
  original.rednet = _G.rednet
  original.peripheral = _G.peripheral
  original.fs = _G.fs

  _G.os = setmetatable({
    epoch = function()
      return currentEpoch
    end,
  }, {
    __index = original.os,
  })

  _G.textutils = {
    serialize = function(value)
      return serializeValue(deepCopy(value))
    end,
    unserialize = function(value)
      if type(value) == "table" then
        return deepCopy(value)
      end

      local chunk = load("return " .. tostring(value))
      if not chunk then
        return nil
      end

      return chunk()
    end,
  }

  _G.rednet = {
    isOpen = function()
      return true
    end,
    open = function()
      return true
    end,
    send = function(targetId, message, protocol)
      sentMessages[#sentMessages + 1] = {
        target_id = targetId,
        message = deepCopy(message),
        protocol = protocol,
      }
      return true
    end,
    broadcast = function(message, protocol)
      broadcastMessages[#broadcastMessages + 1] = {
        message = deepCopy(message),
        protocol = protocol,
      }
      return true
    end,
  }

  _G.peripheral = {
    wrap = function(name)
      return peripheralObjects[name]
    end,
  }

  _G.fs = setmetatable({
    exists = function(path)
      local normalized = normalizePath(path)
      if files[normalized] ~= nil then
        return true
      end

      return original.fs.exists(path)
    end,
    makeDir = function(path)
      ensureDir(path)
    end,
    delete = function(path)
      local normalized = normalizePath(path)
      if files[normalized] ~= nil then
        files[normalized] = nil
        return
      end

      if original.fs.exists(path) then
        original.fs.delete(path)
      end
    end,
    getDir = function(path)
      return parentDir(path)
    end,
    open = function(path, mode)
      local normalized = normalizePath(path)

      if mode == "r" and files[normalized] == nil then
        return original.fs.open(path, mode)
      end

      local parent = parentDir(normalized)
      ensureDir(parent)

      if mode == "w" then
        local buffer = {}
        return {
          write = function(value)
            buffer[#buffer + 1] = tostring(value)
          end,
          writeLine = function(value)
            buffer[#buffer + 1] = tostring(value) .. "\n"
          end,
          readAll = function()
            return nil
          end,
          close = function()
            files[normalized] = {
              type = "file",
              content = table.concat(buffer),
            }
          end,
        }
      end

      if mode == "a" then
        local existing = files[normalized]
        local buffer = {
          existing and existing.content or "",
        }
        return {
          write = function(value)
            buffer[#buffer + 1] = tostring(value)
          end,
          writeLine = function(value)
            buffer[#buffer + 1] = tostring(value) .. "\n"
          end,
          readAll = function()
            return nil
          end,
          close = function()
            files[normalized] = {
              type = "file",
              content = table.concat(buffer),
            }
          end,
        }
      end

      if mode == "r" then
        local existing = files[normalized]
        if not existing then
          return nil
        end
        return {
          readAll = function()
            return existing.content
          end,
          close = function()
          end,
        }
      end

      return original.fs.open(path, mode)
    end,
  }, {
    __index = original.fs,
  })
end

---Restore the original globals after a test.
---@return nil
function M.restore()
  _G.os = original.os
  _G.textutils = original.textutils
  _G.rednet = original.rednet
  _G.peripheral = original.peripheral
  _G.fs = original.fs
end

---Set the epoch milliseconds returned by `os.epoch("utc")`.
---@param epoch integer
---@return nil
function M.setEpoch(epoch)
  currentEpoch = epoch
end

---Register a wrapped peripheral for later `peripheral.wrap(name)` lookups.
---@param name string
---@param object table
---@return nil
function M.setPeripheral(name, object)
  peripheralObjects[name] = object
end

---Seed a fake filesystem file for persistence reads.
---@param path string
---@param content string
---@return nil
function M.setFile(path, content)
  local normalized = normalizePath(path)
  ensureDir(parentDir(normalized))
  files[normalized] = {
    type = "file",
    content = content,
  }
end

---Return the current fake file contents for assertions.
---@param path string
---@return string|nil
function M.getFile(path)
  local entry = files[normalizePath(path)]
  return entry and entry.content or nil
end

---Return captured rednet sends.
---@return table[]
function M.getSentMessages()
  return sentMessages
end

---Return captured rednet broadcasts.
---@return table[]
function M.getBroadcastMessages()
  return broadcastMessages
end

---Clear captured rednet sends and broadcasts.
---@return nil
function M.clearMessages()
  sentMessages = {}
  broadcastMessages = {}
end

return M
