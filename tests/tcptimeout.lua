-- Tests Copas socket timeouts
--
-- Run the test file, it should exit successfully without hanging.

-- make sure we are pointing to the local copas first
package.path = string.format("../src/?.lua;%s", package.path)

local platform = "unix"
if package.config:sub(1,1) == "\\" then
  platform = "windows"
elseif io.popen("uname", "r"):read("*a"):find("Darwin") then
  platform = "mac"
end
print("Testing platform: " .. platform)


_G._TEST = true -- mark as test, to export some internals for testing
local copas = require("copas")
local socket = require("socket")

-- hack; no way to kill copas.loop from thread
local function error(err)
  print(debug.traceback(err, 2))
  os.exit(-1)
end
local function assert(truthy, err)
  if not truthy then
    print(debug.traceback(err, 2))
    os.exit(-1)
  end
end

-- tcp echo server for testing against, returns `ip, port` to connect to
-- send `quit\n` to cause server to disconnect client
-- stops listen server after first connection
local function singleuseechoserver()
  local server = socket.bind("127.0.0.1", 0) -- "localhost" fails because of IPv6 error
  local ip, port = server:getsockname()

  local function echoHandler(skt)
    -- remove server after first connection
    copas.removeserver(server)

    skt = copas.wrap(skt)
    while true do
      local data = skt:receive()
      if not data or data == "quit" then
        break
      end
      skt:send(data..'\n')
    end
  end

  copas.addserver(server, echoHandler)

  return ip, port
end




local tests = {}

function tests.just_exit()
  copas.loop()
end

function tests.connect_and_exit()
  local ip, port = singleuseechoserver()
  copas.addthread(function()
    local client = socket.connect(ip, port)
    client = copas.wrap(client)

    client:close()
  end)

  copas.loop()
end


if platform == "mac" then
  -- this test fails on a Mac, looks like the 'listen(0)' isn't being honoured
  print("\nSkipping test on Mac!\n")
else
  function tests.connect_timeout_copas()
    local server = socket.tcp()
    server:bind("localhost", 0)
    server:listen(0) -- zero backlog, single connection will block further connections
    -- note: not servicing connections
    local ip, port = server:getsockname()

    copas.addthread(function()
      -- fill server's implicit connection backlog
      socket.connect(ip,port)

      local client = socket.tcp()
      client = copas.wrap(client)
      client:settimeout(0.01)
      local status, err = client:connect(ip, port)
      assert(status == nil, "connect somehow succeeded")
      assert(err == "timeout", "connect failed with non-timeout error: "..tostring(err))
      client:close()
    end)

    copas.loop()
  end


  function tests.connect_timeout_socket()
    local server = socket.tcp()
    server:bind("localhost", 0)
    server:listen(0) -- zero backlog, single connection will block further connections
    -- note: not servicing connections
    local ip, port = server:getsockname()

    copas.addthread(function()
      copas.useSocketTimeoutErrors(true)
      -- fill server's implicit connection backlog
      socket.connect(ip,port)

      local client = socket.tcp()
      client = copas.wrap(client)
      client:settimeout(0.01)
      local status, err = client:connect(ip, port)
      assert(status == nil, "connect somehow succeeded")
      -- we test for a different error message becasue we expect socket errors, not copas ones
      assert(err == "Operation already in progress", "connect failed with non-timeout error: "..tostring(err))
      client:close()
    end)

    copas.loop()
  end
end


function tests.receive_timeout()
  local ip, port = singleuseechoserver()

  copas.addthread(function()
    local client = socket.tcp()
    client = copas.wrap(client)
    client:settimeout(0.01)
    local status, err = client:connect(ip, port)
    assert(status, "failed to connect: "..tostring(err))

    client:send("foo\n")
    local data, err = client:receive()
    assert(data, "failed to recieve: "..tostring(err))
    assert(data == "foo", "recieved wrong echo: "..tostring(data))

    local data, err = client:receive()
    assert(data == nil, "somehow recieved echo without sending")
    assert(err == "timeout", "failed with non-timeout error: "..tostring(err))

    client:close()
  end)

  copas.loop()
end


function tests.receive_timeout_clears_copas_timeout()
  -- See issue https://github.com/lunarmodules/copas/issues/185
  local server = socket.bind("127.0.0.1", 0)
  local ip, port = server:getsockname()
  local handler_co

  copas.addserver(server, function(skt)
    handler_co = coroutine.running()
    copas.removeserver(server)

    skt = copas.wrap(skt)
    skt:settimeout(0.01)

    local data, err = skt:receive()
    assert(data == nil, "somehow recieved data without the client sending")
    assert(err == "timeout", "failed with non-timeout error: "..tostring(err))

    skt:close()
  end)

  copas.addthread(function()
    local client = socket.tcp()
    local status, err = client:connect(ip, port)
    assert(status, "failed to connect: "..tostring(err))

    copas.pause(0.25)
    client:close()
  end)

  copas.loop()

  assert(handler_co, "server handler did not run")
  assert(copas._socket_register[handler_co] == nil, "socket_register kept the timed-out coroutine")
  assert(copas._operation_register[handler_co] == nil, "operation_register kept the timed-out coroutine")
  assert(copas._timeout_flags[handler_co] == nil, "timeout_flags kept the timed-out coroutine")
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
