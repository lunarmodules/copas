local copas = require("copas")
local http = require("copas.http")

copas.addthread(function()
  print(copas.http.request("http://www.google.com"))
end)

copas.loop()
