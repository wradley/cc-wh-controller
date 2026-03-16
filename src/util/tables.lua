---Small shared table helpers for warehouse runtime and UI code.
---@class TableUtil
local M = {}

---Count keys in a map-like table, treating `nil` as an empty table.
---@param value table|nil
---@return integer
function M.countTableKeys(value)
  local count = 0
  for _ in pairs(value or {}) do
    count = count + 1
  end
  return count
end

return M
