
--- Test for removeserver(skt, true)
-- that keeps the socket open after removal.

local copas = require("copas")
local socket = require("socket")

local wskt = socket.bind("*", 0)
local whost, wport = wskt:getsockname()
wport = tonumber(wport)

-- set up a timeout to not hang on failure
local timeout_timer = copas.timer.new {
  delay = 10,
  callback = function()
      print("timeout!")
      os.exit(1)
  end
}

local connection_handler = function(cskt)
  print(tostring(cskt).." ("..type(cskt)..") received a connection")
  local data, _, partial = cskt:receive()
  if partial and not data then
     data = partial
  end
  print("triggered", data)
  copas.removeserver(wskt, true)
end

local function wait_for_trigger()
   copas.addserver(wskt, copas.handler(connection_handler), "my_TCP_server")
end

local function trigger_it(n)
   local cskt = copas.wrap(socket.tcp())
   local ok = cskt:connect(whost, wport)
   if ok then
      cskt:send("hi "..n)
   end
   cskt:close()
end

copas.addthread(function()
   for i = 1, 3 do
      wait_for_trigger()
      trigger_it(i)
      copas.pause(0.1)
   end
   timeout_timer:cancel()
end)

copas.loop()
