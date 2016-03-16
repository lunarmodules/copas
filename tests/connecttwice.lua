-- test reconnecting a socket, should return an error "already connected"
-- test based on Windows behaviour, see comments in `copas.connect()` function
local copas = require("copas")
local socket = require("socket")

local skt = copas.wrap(socket.tcp())
local done = false

copas.addthread(function()
  copas.sleep(0)
  print("First try... (should succeed)")
  local ok, err = skt:connect("google.com", 80)
  if ok then
    print("Success")
  else
    print("Failed: "..err)
    os.exit(1)
  end

  print("\nSecond try... (should error as already connected)")
  ok, err = skt:connect("thijsschreijer.nl", 80)
  if ok then
    print("Unexpected success")
    os.exit(1)
  else
    print("Failed: "..err)
  end

  done = true
end)

copas.loop()

if not done then
  print("Loop completed with test not finished")
  os.exit(1)
end
