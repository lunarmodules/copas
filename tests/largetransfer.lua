-- tests large transmissions, sending and receiving
-- uses `receive` and `receivepartial`
-- Does send the same string twice simultaneously
--
-- Test should;
--  * show timer output, once per second, and actual time should be 1 second increments
--  * both transmissions should take appr. equal time, then they we're nicely cooperative

local copas = require 'copas'
local socket = require 'socket'

-- copas.debug.start()

local body = ("A"):rep(1024*1024*50) -- 50 mb string
local start = copas.gettime()
local done = 0
local sparams, cparams

local function runtest()
  local s1 = socket.bind('*', 49500)
  copas.addserver(s1, copas.handler(function(skt)
      copas.setsocketname("Server 49500", skt)
      copas.setthreadname("Server 49500")
      --skt:settimeout(0)  -- don't set, uses `receive` method
      local res, err, part = skt:receive('*a')
      res = res or part
      if res ~= body then print("Received doesn't match send") end
      print("Server reading port 49500... Done!", copas.gettime()-start, err, #res)
      copas.removeserver(s1)
      done = done + 1
    end, sparams))

  local s2 = socket.bind('*', 49501)
  copas.addserver(s2, copas.handler(function(skt)
      skt:settimeout(0)  -- set, uses the `receivepartial` method
      copas.setsocketname("Server 49501", skt)
      copas.setthreadname("Server 49501")
      local res, err, part = skt:receive('*a')
      res = res or part
      if res ~= body then print("Received doesn't match send") end
      print("Server reading port 49501... Done!", copas.gettime()-start, err, #res)
      copas.removeserver(s2)
      done = done + 1
    end, sparams))

  copas.addnamedthread("Client 49500", function()
      local skt = socket.tcp()
      skt = copas.wrap(skt, cparams)
      copas.setsocketname("Client 49500", skt)
      skt:connect("localhost", 49500)
      local last_byte_sent, err
      repeat
        last_byte_sent, err = skt:send(body, last_byte_sent or 1, -1)
      until last_byte_sent == nil or last_byte_sent == #body
      print("Client writing port 49500... Done!", copas.gettime()-start, err, #body)
      -- we're not closing the socket, so the Copas GC-when-idle can kick-in to clean up
      skt = nil -- luacheck: ignore
      done = done + 1
    end)

  copas.addnamedthread("Client 49501", function()
      local skt = socket.tcp()
      skt = copas.wrap(skt, cparams)
      copas.setsocketname("Client 49501", skt)
      skt:connect("localhost", 49501)
      local last_byte_sent, err
      repeat
        last_byte_sent, err = skt:send(body, last_byte_sent or 1, -1)
      until last_byte_sent == nil or last_byte_sent == #body
      print("Client writing port 49501... Done!", copas.gettime()-start, err, #body)
      -- we're not closing the socket, so the Copas GC-when-idle can kick-in to clean up
      skt = nil -- luacheck: ignore
      done = done + 1
    end)

  copas.addnamedthread("test timeout thread", function()
      local i = 1
      while done ~= 4 do
        copas.pause(1)
        print(i, "seconds:", copas.gettime()-start)
        i = i + 1
        if i > 60 then
          print"timeout"
          os.exit(1)
        end
      end
      print "success!"
    end)

  print("starting loop")
  copas.loop()
  print("Loop done")
end

runtest()   -- run test using regular connection (s/cparams == nil)

-- set ssl parameters and do it again
sparams = {
   mode = "server",
   protocol = "any",
   key = "tests/certs/serverAkey.pem",
   certificate = "tests/certs/serverA.pem",
   cafile = "tests/certs/rootA.pem",
   verify = {"peer", "fail_if_no_peer_cert"},
   options = {"all", "no_sslv2", "no_sslv3", "no_tlsv1"},
  }
cparams = {
   mode = "client",
   protocol = "any",
   key = "tests/certs/clientAkey.pem",
   certificate = "tests/certs/clientA.pem",
   cafile = "tests/certs/rootA.pem",
   verify = {"peer", "fail_if_no_peer_cert"},
   options = {"all", "no_sslv2", "no_sslv3", "no_tlsv1"},
  }
done = 0
start = copas.gettime()
runtest()
