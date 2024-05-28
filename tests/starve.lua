-- tests looping 100% in receive/send
-- Should not prevent other threads from running
--
-- Test should;
--  * sleep incremental, not on absolute time so it slowly diverges if the timer
--    thread is being starved
--  * seconds printed and elapsed should stay very close

local copas = require 'copas'
local socket = require 'socket'

--copas.debug.start()

local body = ("A"):rep(1024*1024*50) -- 50 mb string
local done = 0

local function runtest()
  local s1 = socket.bind('*', 49500)
  copas.addserver(s1, copas.handler(function(skt)
      copas.setsocketname("Server 49500", skt)
      copas.setthreadname("Server 49500")
      print "Server 49500 accepted incoming connection"
      local end_time = copas.gettime() + 30 -- we run for 30 seconds
      while end_time > copas.gettime() do
        local res, err, _ = skt:receive(1) -- single byte from 50mb chunks
        if res == nil and err ~= "timeout" then
          print("Server 49500 returned: " .. err)
          os.exit(1)
        end
      end
      done = done + 1
      print("Server reading port 49500... Done!")
      skt:close()
      copas.removeserver(s1)
  end))

  copas.addnamedthread("Client 49500", function()
    local skt = socket.tcp()
    skt = copas.wrap(skt)
    copas.setsocketname("Client 49500", skt)
    skt:connect("localhost", 49500)
    local last_byte_sent, err, complete
    while not complete do
      repeat
        last_byte_sent, err = skt:send(body, last_byte_sent or 1, -1)
        if err == "closed" then
          -- server closed connection, so exit, test is finished
          complete = true
          break
        end
        if last_byte_sent == nil and err ~= "timeout" then
          print("client 49500 returned: " .. err)
          os.exit(1)
        end
      until last_byte_sent == nil or last_byte_sent == #body
    end
    print("Client writing port 49500... Done!")
    skt:close()
    done = done + 1
  end)

  copas.addnamedthread("test timeout thread", function()
      local i = 0
      local start = copas.gettime()
      while done ~= 2 do
        copas.pause(1) -- delta sleep, so it slowly diverges if starved
        i = i + 1
        local time_passed = copas.gettime()-start
        print("slept "..i.." seconds, time passed: ".. time_passed.." seconds")
        if math.abs(i - time_passed) > 2 then
          print("timer diverged by more than 2 seconds: failed!")
          os.exit(1)
        end
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

runtest()
