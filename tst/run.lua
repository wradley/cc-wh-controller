local function projectRoot()
  local running = shell and shell.getRunningProgram and shell.getRunningProgram() or "tst/run.lua"
  return fs.getDir(fs.getDir(running))
end

local function prependPackagePath(path)
  if not package or type(package.path) ~= "string" then
    error("package.path is unavailable in this environment", 0)
  end

  package.path = table.concat({
    path,
    package.path,
  }, ";")
end

local root = projectRoot()
prependPackagePath("/" .. fs.combine(root, "?.lua"))
prependPackagePath("/" .. fs.combine(root, "?/init.lua"))
prependPackagePath("/" .. fs.combine(root, "src/?.lua"))
prependPackagePath("/" .. fs.combine(root, "src/?/init.lua"))
prependPackagePath("/" .. fs.combine(root, "tst/?.lua"))
prependPackagePath("/" .. fs.combine(root, "tst/?/init.lua"))

_G.os.getenv = settings.get
_G.os.exit = function(code, ...)
  if code == 0 then
    term.setTextColour(colors.green)
    print("Success!")
    term.setTextColour(colors.white)
  else
    printError("Failure!", ...)
  end
end

local lu = require("deps.luaunit")

_G.TestWarehouseExecutor = require("tests.app.test_executor")
_G.TestWarehouseNetwork = require("tests.infra.test_network")

return os.exit(lu.LuaUnit.run())
