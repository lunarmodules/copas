local copas = require("copas")
local http = require("copas.http")

copas.addthread(function()
  copas.sleep(0)
  print("Starting request...")
  print(copas.http.request("http://www.google.com"))
  print("Finished request...")
end)

print("starting loop")
copas.loop()
