-- make sure we are pointing to the local copas first
package.path = string.format("../src/?.lua;%s", package.path)

local copas = require "copas"
local socket = require "socket"
local timer = copas.timer

-- Test 1: cancelall() exits a loop that has a server, a sleeping thread, and a
-- thread blocked on a socket.

local loop1_exited = false

copas.loop(function()
  -- register a server that will never get a connection
  local srv = socket.tcp()
  assert(srv:bind("127.0.0.1", 0))
  srv:listen(5)
  copas.addserver(srv, function() end)

  -- register a thread that sleeps forever
  copas.addthread(function()
    copas.sleep(math.huge)
  end)

  -- register a thread that waits on a socket read (connect to our own server)
  local port = select(2, srv:getsockname())
  copas.addthread(function()
    local client = copas.wrap(socket.tcp())
    client:connect("127.0.0.1", port)
    client:receive("*l")  -- blocks waiting for data that never arrives
  end)

  -- fire cancelall after a short delay
  timer.new({
    delay = 0.1,
    callback = function()
      copas.cancelall()
    end,
  })
end)

loop1_exited = true
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

assert(loop1_exited)
print("all tests passed")
