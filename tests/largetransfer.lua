-- tests large transmissions, sending and receiving
-- uses `receive` and `receivePartial` 
-- Does send the same string twice simultaneously
-- 
-- Test should;
--  * show timer output, once per minute, and actual time should be 60 second increments
--  * both transmissions should take appr. equal time, then they we're nicely cooperative

local copas = require 'copas'
local socket = require 'socket'

local body = ("A"):rep(1024*1024*10) -- 10 mb string
local start = socket.gettime()
local done = 0

local s1 = socket.bind('*', 49500)
copas.addserver(s1, function(skt)
    skt = copas.wrap(skt)
    --skt:settimeout(0)  -- don't set, uses `receive` method
    local res, err, part = skt:receive('*a')
    res = res or part
    if res ~= body then print("Received doesn't match send") end
    print("Reading... 49500... Done!", socket.gettime()-start, err, #res)
    if copas.removeserver then copas.removeserver(s1) end
  end)

local s2 = socket.bind('*', 49501)
copas.addserver(s2, function(skt)
    skt = copas.wrap(skt)
    skt:settimeout(0)  -- set, uses the `receivePartial` method
    local res, err, part = skt:receive('*a')
    res = res or part
    if res ~= body then print("Received doesn't match send") end
    print("Reading... 49501... Done!", socket.gettime()-start, err, #res)
    if copas.removeserver then copas.removeserver(s2) end
  end)

copas.addthread(function()
    copas.sleep(0)
    skt = copas.wrap(socket.connect("localhost", 49500))
    skt:send(body)
    print("Writing... 49500... Done!", socket.gettime()-start, err, #body)
    skt = nil
    collectgarbage()
    collectgarbage()
    done = done + 1
  end)

copas.addthread(function()
    copas.sleep(0)
    skt = copas.wrap(socket.connect("localhost", 49501))
    skt:send(body)
    print("Writing... 49501... Done!", socket.gettime()-start, err, #body)
    skt = nil
    collectgarbage()
    collectgarbage()
    done = done + 1
  end)

copas.addthread(function()
    copas.sleep(0)
    local i = 1
    while done ~= 2 do
      copas.sleep(60)
      print(i, "minutes:", socket.gettime()-start)
      i = i + 1
    end
  end)

print("starting loop")
copas.loop()
print("Loop done")

