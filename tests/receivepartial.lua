
--- Test for removeserver(skt, true)
-- that keeps the socket open after removal.

local copas = require("copas")
local socket = require("socket")


local status = "stopped"  -- stopped, stop, running

local function start_server(data)
  local server_skt = assert(socket.bind("*", 0))
  local _, wport = assert(server_skt:getsockname())
  wport = tonumber(wport)

  local handler = function(cskt)
    status = "running"

    for i, command in ipairs(data) do
      if type(command) == "number" then
        copas.sleep(command)
      else
        cskt:send(command)
      end
      if status == "stop" then
        status = "stopped"
        break
      end
    end

    -- stop server
    status = "stopped"
    cskt:close()
    copas.removeserver(server_skt)
  end

  copas.addserver(server_skt, copas.handler(handler))

  return wport
end

local function stop_server()
  if status == "running" then
    status = "stop"
  end
  while status ~= "stopped" do
    copas.sleep(0.1)
  end
end

local function run_test(data)
  local port = start_server(data)
  local cskt = copas.wrap(assert(socket.tcp()))
  assert(cskt:connect("localhost", port))

  local result = {}
  local data, err, partial
  while true do
    data, err, partial = cskt:receivepartial("*a", partial)
    print(data,err, partial)
    result[#result + 1] = { data, err, partial }
    if err == "closed" then
      break
    end
  end

  cskt:close()
  stop_server()
end


copas(
  function()
    run_test({1, "hi 1", 1, "hi 2", 1, "hi 3"})
  end
)

