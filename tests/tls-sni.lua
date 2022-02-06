-- Tests Copas with a simple Echo server
--
-- Run the test file and the connect to the server using telnet on the used port.
-- The server should be able to echo any input, to stop the test just send the command "quit"

local port = 20000
local copas = require("copas")
local socket = require("socket")
local ssl = require("ssl")
local server

if _VERSION=="Lua 5.1" and not jit then     -- obsolete: only for Lua 5.1 compatibility
  pcall = require("coxpcall").pcall         -- luacheck: ignore
end

local server_params = {
  wrap = {
    mode = "server",
    protocol = "tlsv1",
    key = "tests/certs/serverAkey.pem",
    certificate = "tests/certs/serverA.pem",
    cafile = "tests/certs/rootA.pem",
    verify = {"peer", "fail_if_no_peer_cert"},
    options = {"all", "no_sslv2"},
  },
  sni = {
    strict = true, -- only allow connection 'myhost.com'
    names = {}
  }
}
server_params.sni.names["myhost.com"] = ssl.newcontext(server_params.wrap)

local client_params = {
  wrap = {
    mode = "client",
    protocol = "tlsv1",
    key = "tests/certs/clientAkey.pem",
    certificate = "tests/certs/clientA.pem",
    cafile = "tests/certs/rootA.pem",
    verify = {"peer", "fail_if_no_peer_cert"},
    options = {"all", "no_sslv2"},
  },
  sni = {
    names = "" -- will be added in test below
  }
}

local function echoHandler(skt)
  while true do
    local data, err = skt:receive()
    if not data then
      if err ~= "closed" then
        return error("client connection error: "..tostring(err))
      else
        return -- client closed the connection
      end

    elseif data == "quit" then
      return -- close this client connection

    elseif data == "exit" then
      copas.removeserver(server)
      return -- close this client connection, after stopping the server

    end
    skt:send(data)
  end
end

server = assert(socket.bind("*", port))
copas.addserver(server, copas.handler(echoHandler, server_params))

copas.addthread(function()
  copas.sleep(0.5) -- allow server socket to be ready

  ----------------------
  -- Tests start here --
  ----------------------

  -- try with a bad SNI (non matching)
  client_params.sni.names = "badhost.com"
  local skt = copas.wrap(socket.tcp(), client_params)
  local _, err = pcall(skt.connect, skt, "localhost", port)
  if not tostring(err):match("TLS/SSL handshake failed:") then
    print "expected handshake to fail"
    os.exit(1)
  end


  -- try again with a proper SNI (matching)
  client_params.sni.names = "myhost.com"
  local skt = copas.wrap(socket.tcp(), client_params)
  local success, ok = pcall(skt.connect, skt, "localhost", port)
  if not (success and ok) then
    print "expected connection to be completed"
    os.exit(1)
  end

  print "succesfully completed test"
  os.exit(0)
end)

-- no ugly errors please, comment out when debugging
copas.setErrorHandler(function() end, true)

copas.loop()
