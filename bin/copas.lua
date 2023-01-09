#!/usr/bin/env lua

-- luacheck: globals copas
copas = require("copas")


-- Error handler that forces an application exit
local function errorhandler(err, co, skt)
  io.stderr:write(copas.gettraceback(err, co, skt).."\n")
  os.exit(1)
end


local function version_info()
  print(copas._VERSION, copas._COPYRIGHT)
  print(copas._DESCRIPTION)
  print("Lua VM:", _G._VERSION)
end


local function load_lib(lib_name)
  require(lib_name)
end


local function run_code(code)
  if loadstring then -- deprecated in Lua 5.2
    assert(loadstring(code, "command line"))()
  else
    assert(load(code, "command line"))()
  end
end


local function run_stdin()
  assert(loadfile())()
end


local function run_file(filename, i)
  -- shift arguments, such that the Lua file being executed is at index 0. The
  -- first argument following the name is at index 1.
  local last = #arg
  local first = #arg
  for idx, v in pairs(arg) do
    if idx < first then first = idx end
  end
  for n = first - i, last do
    arg[n] = arg[n+i] -- luacheck: ignore
  end
  assert(loadfile(filename))()
end


local function show_usage()
  print([[
usage: copas [options]... [script [args]...].
Available options are:
  -e chunk  Execute string 'chunk'.
  -l name   Require library 'name'.
  -v        Show version information.
  --        Stop handling options.
  -         Execute stdin and stop handling options.]])
  os.exit(1)
end


copas(function()
  copas.seterrorhandler(errorhandler)
  local i = 0
  while i < math.max(#arg, 1) do -- if no args, use 1 being 'nil'
    i = i + 1
    local handled = false
    local opt = arg[i] or "-" -- set default action if no args
    -- options to continue handling
    if opt == "-v" then version_info() handled = true end
    if opt == "-l" then i = i + 1 load_lib(arg[i]) handled = true end
    if opt == "-e" then i = i + 1 run_code(arg[i]) handled = true end
    -- options that terminate handling
    if opt == "--" then return end
    if opt == "-"  then return run_stdin() end
    if opt:sub(1,1) == "-" and not handled then return show_usage() end
    if not handled then return run_file(opt, i) end
  end
end)
