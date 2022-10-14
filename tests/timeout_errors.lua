-- Tests Copas timeout mnechanism, when a timeout handler errors out
--
-- Run the test file, it should exit successfully without hanging.

-- make sure we are pointing to the local copas first
package.path = string.format("../src/?.lua;%s", package.path)
local copas = require("copas")


local tests = {}


function tests.error_on_timeout()
  local err_received

  copas.addthread(function()
    copas.setErrorHandler(function(err, coro, skt)
      err_received = err
    end, true)
    print "setting timeout in 0.1 seconds"
    copas.timeout(0.1, function()
      print "throwing an error now..."
      error("oops...")
    end)
    print "going to sleep for 1 second"
    copas.pause(1)

    if not (err_received or ""):find("oops...", 1, true) then
      print("expected to find the error string 'oops...', but got: " .. tostring(err_received))
      os.exit(1)
    end
  end)

  copas.loop()
end





-- test "framework"
for name, test in pairs(tests) do
  print("testing: "..tostring(name))
  local status, err = pcall(test)
  if not status then
    error(err)
  end
end

print("[✓] all tests completed successuly")
