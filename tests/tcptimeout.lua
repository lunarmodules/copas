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


-- See issue https://github.com/lunarmodules/copas/issues/208
-- Two coroutines waiting on the same socket at the same time is a bug in
-- the caller, not something Copas should silently queue for: exactly one
-- of them must win the claim and run to completion, the other must get an
-- immediate "Operation already in progress" error back as a normal return
-- value (the same way it would see "timeout" or "closed"), not be silently
-- abandoned.
--
-- Note: copas.receive/send both have a built-in fairness mechanism (a
-- random chance, each retry, to yield via copas.pause() before re-trying)
-- to stop one busy coroutine from starving others. That means which of the
-- two racing coroutines below actually wins the claim is not deterministic,
-- so the assertions below check the invariant (one winner, one conflict),
-- not which specific coroutine ends up being which.
function tests.duplicate_read_waiter_errors()
  local server = socket.bind("127.0.0.1", 0)
  local ip, port = server:getsockname()
  local results = {}

  copas.addserver(server, function(skt)
    copas.removeserver(server)
    copas.settimeout(skt, 0.1)

    local function waiter()
      -- nothing is ever sent, so the winner only ever ends via its own
      -- timeout; the loser gets the claim-conflict error immediately
      local s, err = copas.receive(skt, 10)
      results[#results + 1] = { s, err }
    end

    copas.addthread(waiter)
    copas.addthread(waiter)

    -- outlive both threads above, otherwise this handler returning would
    -- trigger copas.autoclose and close `skt` out from under them before
    -- either gets a chance to run
    copas.pause(1)
  end)

  copas.addthread(function()
    local client = socket.connect(ip, port)
    -- comfortably past the server's read timeout, so there's no race
    -- between the timeout and the connection closing
    copas.pause(1)
    client:close()
  end)

  copas.loop()

  assert(#results == 2, "expected both waiters to finish, got: "..#results)

  local conflicts, timeouts = 0, 0
  for _, r in ipairs(results) do
    if r[1] == nil and r[2] == "Operation already in progress" then
      conflicts = conflicts + 1
    elseif r[1] == nil and r[2] == "timeout" then
      timeouts = timeouts + 1
    end
  end
  assert(conflicts == 1, "expected exactly one claim-conflict result, got: "..conflicts)
  assert(timeouts == 1, "expected exactly one normal timeout result, got: "..timeouts)
end


function tests.duplicate_write_waiter_errors()
  -- a payload well past default OS socket buffers, sent to a peer that
  -- never reads, so send() reliably has to wait rather than complete
  -- in one non-blocking call
  local body = ("A"):rep(1024 * 1024 * 8)

  local server = socket.bind("127.0.0.1", 0)
  local ip, port = server:getsockname()
  local results = {}

  copas.addserver(server, function(skt)
    copas.removeserver(server)
    -- deliberately never read: keeps the client's send() waiting
    copas.pause(2)
    copas.close(skt)
  end)

  copas.addthread(function()
    local client = socket.connect(ip, port)
    client = copas.wrap(client)
    -- comfortably longer than the server's 2 second delay above, so the
    -- connection closing is what ends the winner, not a race with its own
    -- timeout
    client:settimeout(10)

    local function waiter()
      -- the winner ends once the server above closes the connection; the
      -- loser gets the claim-conflict error immediately
      local status, err = client:send(body)
      results[#results + 1] = { status, err }
    end

    copas.addthread(waiter)
    copas.addthread(waiter)
  end)

  copas.loop()

  assert(#results == 2, "expected both waiters to finish, got: "..#results)

  local conflicts, closes = 0, 0
  for _, r in ipairs(results) do
    if r[1] == nil and r[2] == "Operation already in progress" then
      conflicts = conflicts + 1
    elseif r[1] == nil and r[2] == "closed" then
      closes = closes + 1
    end
  end
  assert(conflicts == 1, "expected exactly one claim-conflict result, got: "..conflicts)
  assert(closes == 1, "expected exactly one normal closed result, got: "..closes)
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
