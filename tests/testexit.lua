-- tests whether the main loop automatically exits when all work is done

local copas = require("copas")
local socket = require("socket")

copas.addthread(function()
    local n = 1
    while n<=5 do
      copas.sleep(0)
      print(n)
      n=n+1
    end
  end)

print("Test 1 count to 5... then exit")
copas.loop()
print("Test 1 done")

local server, err = socket.bind("*", 20000)

copas.addserver(server, function(skt)
    print(copas.receive(skt))
    copas.removeserver(server)
  end)

copas.addthread(function()
    copas.sleep(1)
    local skt, err = socket.connect("localhost", 20000)
    print(copas.send(skt, "Hello world!\n"))
  end)

print("Test 2 send and receive some... then exit")
copas.loop()
print("Test 2 done")

