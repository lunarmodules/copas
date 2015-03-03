local copas = require("copas")
local http = require("copas.http")

copas.addthread(function()
  copas.sleep(0)
  print("Starting request...")
  local skt = copas.wrap(socket.tcp(), {})
  print("Connect: ", skt:connect("www.google.com", 443))
  print("Finished request...")
end)

copas.addthread(function()
  local n = 0
  while n<500 do
    copas.sleep(0)
    print(n)
    n = n + 1
  end
end)

print("starting loop")
copas.loop()
