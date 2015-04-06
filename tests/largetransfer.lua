-- tests large transmissions, sending and receiving
-- uses `receive` and `receivePartial` 
-- Does send the same string twice simultaneously
-- 
-- Test should;
--  * show timer output, once per minute, and actual time should be 60 second increments
--  * both transmissions should take appr. equal time, then they we're nicely cooperative
--
-- Requires;
--  * test certificates, generated using LuaSec scripts in ./samples/certs
--    generate them and put all the 'A' certificates next to this testscript

local copas = require 'copas'
local socket = require 'socket'

local body = ("A"):rep(1024*1024*10) -- 10 mb string
local start = socket.gettime()
local done = 0
local sparams, cparams

local function runtest()
  local s1 = socket.bind('*', 49500)
  copas.addserver(s1, copas.handler(function(skt)
      --skt:settimeout(0)  -- don't set, uses `receive` method
      local res, err, part = skt:receive('*a')
      res = res or part
      if res ~= body then print("Received doesn't match send") end
      print("Reading... 49500... Done!", socket.gettime()-start, err, #res)
      if copas.removeserver then copas.removeserver(s1) end
    end, sparams))

  local s2 = socket.bind('*', 49501)
  copas.addserver(s2, copas.handler(function(skt)
      skt:settimeout(0)  -- set, uses the `receivePartial` method
      local res, err, part = skt:receive('*a')
      res = res or part
      if res ~= body then print("Received doesn't match send") end
      print("Reading... 49501... Done!", socket.gettime()-start, err, #res)
      if copas.removeserver then copas.removeserver(s2) end
    end, sparams))

  copas.addthread(function()
      copas.sleep(0)
      local skt = socket.tcp()
      skt = copas.wrap(skt, cparams)
      skt:connect("localhost", 49500)
      skt:send(body)
      print("Writing... 49500... Done!", socket.gettime()-start, err, #body)
      skt = nil
      collectgarbage()
      collectgarbage()
      done = done + 1
    end)

  copas.addthread(function()
      copas.sleep(0)
      local skt = socket.tcp()
      skt = copas.wrap(skt, cparams)
      skt:connect("localhost", 49501)
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
end

runtest()   -- run test using regular connection (s/cparams == nil)

-- set ssl parameters and do it again
sparams = {
   mode = "server",
   protocol = "tlsv1",
   key = "./serverAkey.pem",
   certificate = "./serverA.pem",
   cafile = "./rootA.pem",
   verify = {"peer", "fail_if_no_peer_cert"},
   options = {"all", "no_sslv2"},
}
cparams = {
   mode = "client",
   protocol = "tlsv1",
   key = "./clientAkey.pem",
   certificate = "./clientA.pem",
   cafile = "./rootA.pem",
   verify = {"peer", "fail_if_no_peer_cert"},
   options = {"all", "no_sslv2"},
}
done = 0
start = socket.gettime()
runtest()  
