-- test reconnecting a socket, shoudl return an error "already connected"
-- test based on Windows behaviour, see comments in `copas.connect()` function
local copas = require("copas")
local socket = require("socket")

local skt = copas.wrap(socket.tcp())

copas.addthread(function()
  copas.sleep(0)
  print("First try... (should succeed)")
  print(skt:connect("google.com",80))
  print("\n\nSecond try... (should error as already connected)")
  print(skt:connect("thijsschreijer.nl",80))
end)

copas.loop()
