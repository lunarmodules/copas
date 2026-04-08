-- make sure we are pointing to the local copas first
package.path = string.format("../src/?.lua;%s", package.path)

local copas = require "copas"
local socket = require "socket"
local timer = copas.timer

-- Test 1: cancelall() exits a loop that has a server, a sleeping thread, and a
-- thread blocked on a socket.

copas.loop(function()
  -- register a server that will never get a connection
  local srv = socket.tcp()
  assert(srv:bind("127.0.0.1", 0, 5))
  copas.addserver(srv, function()
    copas.pause(60*60) -- don't handle incoming connections, let them wait
  end)

  -- register a thread that sleeps forever
  copas.addthread(function()
    copas.pause(60*60)
  end)

  -- register a thread that waits on a socket read (connect to our own server)
  local _, port = srv:getsockname()
  copas.addthread(function()
    local client = copas.wrap(socket.tcp())
    client:connect("127.0.0.1", port)
    client:receive("*l")  -- blocks waiting for data that never arrives
  end)

  -- fire cancelall after a short delay
  timer.new({
    delay = 0.5,
    callback = function()
      copas.cancelall()
    end,
  })

  -- set up a timeout timer to make sure the loop exits within a reasonable time
  timer.new({
    delay = 5,
    callback = function()
      print("loop 1 did not exit within 5 seconds")
      os.exit(1) -- exit with error code to indicate failure
    end,
  })
end)

print("loop 1 exited ok")

-- Test 2: after cancelall(), a fresh copas.loop() works correctly.

local loop2_done = false

copas.loop(function()
  copas.addthread(function()
    copas.sleep(0.05)
    loop2_done = true
  end)
end)

assert(loop2_done, "loop 2 did not complete its task")
print("loop 2 exited ok")

print("all tests passed")
