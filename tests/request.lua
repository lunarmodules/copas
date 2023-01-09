local copas = require("copas")
local http = copas.http

local url = assert(arg[1], "missing url argument")
local debug_mode = not not arg[2]

print("Testing copas.http.request with url " .. url .. (debug_mode and "(in debug mode)" or ""))
local switches, max_switches = 0, 10000000
local done = false


if debug_mode then
  copas.debug.start()
  local socket = require "socket"
  local old_tcp = socket.tcp
  socket.tcp = function(...)
    local sock, err = old_tcp(...)
    if not sock then
      return sock, err
    end
    return copas.debug.socket(sock)
  end
end


copas.addthread(function()
  while switches < max_switches do
    copas.pause()
    switches = switches + 1
  end

  if not done then
    print(("Error: Request not finished after %d thread switches"):format(switches))
    os.exit(1)
  end
end)

copas.addthread(function()
  print("Starting request")
  local content, code, headers, status = http.request(url)
  print(("Finished request after %d thread switches"):format(switches))

  if type(content) ~= "string" or type(code) ~= "number" or
      type(headers) ~= "table" or type(status) ~= "string" then
    print("Error: incorrect return values:")
    print(content)
    print(code)
    print(headers)
    print(status)
    os.exit(1)
  end

  print(("Status: %s, content: %d bytes"):format(status, #content))
  done = true
  max_switches = switches + 10 -- just do a few more and finish the test
end)

print("Starting loop")
copas.loop()

if done then
  print("Finished loop")
else
  print("Error: Finished loop but request is not complete")
  os.exit(1)
end
