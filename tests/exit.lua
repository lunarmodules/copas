-- tests whether the main loop automatically exits when all work is done

local copas = require("copas")
local socket = require("socket")

local done = false

copas.addthread(function()
  for i = 1, 5 do
    copas.sleep(0)
    print(i)
  end

  done = true
end)

print("Test 1 count to 5... then exit")
copas.loop()

if done then
  print("Test 1 done")
else
  print("Loop completed with test 1 not finished")
  os.exit(1)
end

done = false
local server = socket.bind("*", 20000)
local message = "Hello world!"

copas.addserver(server, function(skt)
  local received = copas.receive(skt)

  if received ~= message then
    print("Incorrect return from copas.receive: "..tostring(received))
    os.exit(1)
  else
    print("Received "..message)
  end

  copas.removeserver(server)
  done = true
end)

copas.addthread(function()
  copas.sleep(1)
  local skt = socket.connect("localhost", 20000)
  print("Sending "..message.."\\n")
  local bytes = copas.send(skt, message.."\n")

  if bytes ~= #message + 1 then
    print("Incorrect return from copas.send: "..tostring(bytes))
    os.exit(1)
  end
end)

print("Test 2 send and receive some... then exit")
copas.loop()

if done then
  print("Test 2 done")
else
  print("Loop completed with test 2 not finished")
  os.exit(1)
end
