-- Tests Copas socket timeouts
--
-- Run the test file, it should exit successfully without hanging.

-- make sure we are pointing to the local copas first
package.path = string.format("../src/?.lua;%s", package.path)



--local platform = "unix"
--if package.config:sub(1,1) == "\\" then
--  platform = "windows"
--elseif io.popen("uname", "r"):read("*a"):find("Darwin") then
--  platform = "mac"
--end
--print("Testing platform: " .. platform)



local copas = require("copas")



local tests = {}

if _VERSION ~= "Lua 5.1" then
  -- do not run these for Lua 5.1 since it has a different stacktrace

  tests.default_properly_formats_coro_errors = function()
    local old_print = print
    local msg
    print = function(errmsg)   --luacheck: ignore
      msg = errmsg
      --old_print(msg)
    end

    copas.loop(function()
      local f = function()
        error("hi there!")
      end
      f()
    end)

    print = old_print   --luacheck: ignore

    assert(msg:find("errhandlers%.lua:%d-: hi there! %(coroutine: thread: 0x%x-, socket: nil%)"), "got:\n"..msg)
    assert(msg:find("stack traceback:.+errhandlers%.lua"), "got:\n"..msg)
  end


  tests.default_properly_formats_timerwheel_errors = function()
    local old_print = print
    local msg
    print = function(errmsg)   --luacheck: ignore
      msg = errmsg
      --old_print(msg)
    end

    copas.loop(function()
      copas.timeout(0.01, function(co)
          local f = function()
            error("hi there!")
          end
          f()
      end)
      copas.sleep(1)
    end)

    print = old_print   --luacheck: ignore

    assert(msg:find("errhandlers%.lua:%d-: hi there! %(coroutine: nil, socket: nil%)"), "got:\n"..msg)
    assert(msg:find("stack traceback:.+errhandlers%.lua"), "got:\n"..msg)
  end
end


tests.handler_gets_called_if_set = function()
  local call_count = 0
  copas.loop(function()
    copas.setErrorHandler(function() call_count = call_count + 1 end)

    error("end of the world!")
  end)

  assert(call_count == 1, "expected callcount 1, got: " .. tostring(call_count))
end



tests.default_handler_gets_called_if_set = function()
  local call_count = 0
  copas.setErrorHandler(function() call_count = call_count + 10 end, true)
  copas.loop(function()

    error("end of the world!")
  end)

  assert(call_count == 10, "expected callcount 10, got: " .. tostring(call_count))
end



tests.default_handler_doesnt_get_called_if_overridden = function()
  local call_count = 0
  copas.setErrorHandler(function() call_count = call_count + 10 end, true)
  copas.loop(function()
    copas.setErrorHandler(function() call_count = call_count + 1 end)

    error("end of the world!")
  end)

  assert(call_count == 1, "expected callcount 1, got: " .. tostring(call_count))
end


tests.timerwheel_callbacks_call_the_default_error_handler = function()
  local call_count = 0
  copas.setErrorHandler(function() call_count = call_count - 10 end, true)
  copas.loop(function()
    copas.timeout(0.01, function(co) error("hi there!") end)
    copas.sleep(1)
  end)

  assert(call_count == -10, "expected callcount -10, got: " .. tostring(call_count))
end


-- test "framework"
for name, test in pairs(tests) do
  -- reload copas, to clear default err handlers
  package.loaded.copas = nil
  copas = require "copas"

  print("testing: "..tostring(name))
  local status, err = pcall(test)
  if not status then
    error(err)
  end
end

print("[✓] all tests completed successuly")
