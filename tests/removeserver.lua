
--- Test for removeserver(skt, true)
-- that keeps the socket open after removal.

local copas = require("copas")
local socket = require("socket")

local wskt = socket.bind("*", 0)
local whost, wport = wskt:getsockname()
wport = tonumber(wport)

local function wait_for_trigger()
   copas.addserver(wskt, function(cskt)
      local data, err, partial = cskt:receive()
      if partial and not data then
         data = partial
      end
      print("triggered", data)
      copas.removeserver(wskt, true)
   end)
end

local function trigger_it(n)
   local cskt = socket.tcp()
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
      copas.sleep(0.1)
   end
end)

copas.loop()
