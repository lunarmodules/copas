local copas = require("copas")
local http = require("copas.http")

copas.addthread(function()
  copas.sleep(0)
  print("Starting request...")
  print(copas.http.request("http://www.google.com"))
  print("Finished request...")
end)

copas.addthread(function()
  local n = 0
  while n<100 do
    copas.sleep(0)
    print(n)
    n = n + 1
  end
end)

print("starting loop")
copas.loop()
