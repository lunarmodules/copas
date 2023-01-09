-- tests timeouts with http requests.
--
-- in sending/receiving headers/body
--

local copas = require 'copas'
local socket = require 'socket'
local ltn12 = require 'ltn12'
local request = copas.http.request

-- copas.debug.start()

local response_body = ("A"):rep(1023).."x" -- 1 kb string
local response_headers = [[HTTP/1.1 200 OK
Date: Mon, 27 Jul 2009 12:28:53 GMT
Server: Apache/2.2.14 (Win32)
Last-Modified: Wed, 22 Jul 2009 19:15:56 GMT
Content-Type: text/html
Content-Length: ]]
local response = response_headers .. tostring(#response_body) .. "\n\n" .. response_body
response = response:gsub("\13?\10", "\13\10") -- update lineendings

local request_headers = {
  Header1 = "header value 1 which is really a dummy value",
  Header2 = "header value 2 which is really a dummy value",
  Header3 = "header value 3 which is really a dummy value",
  Header4 = "header value 4 which is really a dummy value",
  Header5 = "header value 5 which is really a dummy value",
  Header6 = "header value 6 which is really a dummy value",
}
local request_body = response_body
request_headers["Content-Length"] = #request_body
local request_size -- will be set on first test

local timeout = 5
local timeout_bytes_request
local timeout_bytes_response



copas.setErrorHandler(function(msg, co, skt)
  -- on any error we want to exit forcefully
  print(copas.gettraceback(msg, co, skt))
  os.exit(1)
end, true) -- true: make it the default for all threads/coros



local function runtest()
  local s1 = socket.bind('*', 49500)
  copas.addserver(s1, copas.handler(function(skt)
    -- HTTP server that will optionally do a timeout on the request, or on the response
    copas.setsocketname("Server 49500", skt)
    copas.setthreadname("Server 49500")
    -- read bytes up to where we're supposed to do the timeout (if at all)
    print("Server reading port 49500: incoming connection")
    skt:settimeout(1)

    if timeout_bytes_request then
      print("Server reading port 49500: generating request-timeout at byte: ", timeout_bytes_request)
      local res, err, part = skt:receive(timeout_bytes_request)
      if not res then
        print("Server reading port 49500: full request:", err, "received:", part)
        os.exit(1)
      end
      -- we timeout on the request, so sleep here and exit
      copas.pause(timeout + 1) -- sleep 1 second more than the requester timeout, to force a timeout on the request
      print("Server reading port 49500: request-timeout complete")
      return skt:close()
    end

    -- receive full request
    print("Server reading port 49500: reading full request")
    local res, err, part = skt:receive("*a")
    -- print("res",res)
    -- print("err",err)
    -- print("part",part)
    if not res and err == "timeout" then
      res = part
    end
    request_size = #res
    print("request size: ", #res)
    if not res then
      print("Server reading port 49500: first chunk:", err, "received:", part)
      os.exit(1)
    end

    -- request was read, now send the reposnse
    if not timeout_bytes_response then
      -- just send full response, not timeout generation
      local ok, err = skt:send(response)
      if not ok then
        print("Server reading port 49500: failed sending full response:", err)
        os.exit(1)
      end
      print("Server reading port 49500: send full response, done!")
      return skt:close()
    end

    -- we send a partial response and timeout
    print("Server reading port 49500: generating response-timeout at byte: ", timeout_bytes_response)
    local ok, err = skt:send(response:sub(1, timeout_bytes_response))
    if not ok then
      print("Server reading port 49500: failed sending partial response:", err)
      os.exit(1)
    end

    copas.pause(timeout + 1) -- sleep 1 second more than the requester timeout, to force a timeout on the response
    print("Server reading port 49500: response-timeout complete")
    return skt:close()
  end))



  copas.addnamedthread("test request", function()

    print "Waiting a bit for server to start..."
    copas.pause(1) -- give server some time to start

    do
      print("first test: succesfull round trip")
      timeout_bytes_request = nil
      timeout_bytes_response = nil
      -- make request
      local ok, rstatus, rheaders, rstatus_line = request {
        url = "http://localhost:49500/some/path",
        method = "POST",
        headers = request_headers,
        timeout = timeout,
        source = ltn12.source.string(("B"):rep(1023).."x"),  -- request body
        sink = ltn12.sink.table({}), -- response body
      }
      print("Client received response: ")
      print("  ok = "..tostring(ok))
      print("  status = "..tostring(rstatus))
      if not rheaders then
        print("  headers = "..tostring(rheaders))
      else
        print("  headers = {")
        for k, v in pairs(rheaders) do
          print("      "..tostring(k)..": "..tostring(v))
        end
        print("  }")
      end
      print("  status_line = "..tostring(rstatus_line))
      if ok and rstatus == 200 then
        print("Client: received a '200 OK', as expected!")
      else
        print("Client: error when requesting:", rstatus)
        os.exit(1)
      end

      -- cleanup; sleep 2 secs to wait for closing server socket
      -- to ensure any error messages do not get intermixed with the next tests output
      copas.pause(2)
      print(("="):rep(80))
    end


    do
      print("second test: server generates time-out while receiving the headers")
      timeout_bytes_request = 100 -- 100 bytes is still headers
      timeout_bytes_response = nil
      -- make request
      local ok, rstatus, rheaders, rstatus_line = request {
        url = "http://localhost:49500/some/path",
        method = "POST",
        headers = request_headers,
        timeout = timeout,
        source = ltn12.source.string(("B"):rep(1023).."x"),  -- request body
        sink = ltn12.sink.table({}), -- response body
      }
      print("Client received response: ")
      print("  ok = "..tostring(ok))
      print("  status = "..tostring(rstatus))
      if not rheaders then
        print("  headers = "..tostring(rheaders))
      else
        print("  headers = {")
        for k, v in pairs(rheaders) do
          print("      "..tostring(k)..": "..tostring(v))
        end
        print("  }")
      end
      print("  status_line = "..tostring(rstatus_line))
      if not ok and rstatus == "timeout" then
        print("Client: received a timeout error, as expected!")
      else
        print("Client: error when requesting:", rstatus)
        os.exit(1)
      end

      -- cleanup; sleep 2 secs to wait for closing server socket
      -- to ensure any error messages do not get intermixed with the next tests output
      copas.pause(2)
      print(("="):rep(80))
    end


    do
      print("third test: server generates time-out while receiving the body")
      timeout_bytes_request = request_size - 500 -- body = 1k, so 500 before end is right in the middle of the body
      timeout_bytes_response = nil
      -- make request
      local ok, rstatus, rheaders, rstatus_line = request {
        url = "http://localhost:49500/some/path",
        method = "POST",
        headers = request_headers,
        timeout = timeout,
        source = ltn12.source.string(("B"):rep(1023).."x"),  -- request body
        sink = ltn12.sink.table({}), -- response body
      }
      print("Client received response: ")
      print("  ok = "..tostring(ok))
      print("  status = "..tostring(rstatus))
      if not rheaders then
        print("  headers = "..tostring(rheaders))
      else
        print("  headers = {")
        for k, v in pairs(rheaders) do
          print("      "..tostring(k)..": "..tostring(v))
        end
        print("  }")
      end
      print("  status_line = "..tostring(rstatus_line))
      if not ok and rstatus == "timeout" then
        print("Client: received a timeout error, as expected!")
      else
        print("Client: error when requesting:", rstatus)
        os.exit(1)
      end

      -- cleanup; sleep 2 secs to wait for closing server socket
      -- to ensure any error messages do not get intermixed with the next tests output
      copas.pause(2)
      print(("="):rep(80))
    end


    do
      print("fourth test: server generates time-out while sending the headers")
      timeout_bytes_request = nil
      timeout_bytes_response = 100 -- after 100 bytes, is still in the headers
      -- make request
      local ok, rstatus, rheaders, rstatus_line = request {
        url = "http://localhost:49500/some/path",
        method = "POST",
        headers = request_headers,
        timeout = timeout,
        source = ltn12.source.string(("B"):rep(1023).."x"),  -- request body
        sink = ltn12.sink.table({}), -- response body
      }
      print("Client received response: ")
      print("  ok = "..tostring(ok))
      print("  status = "..tostring(rstatus))
      if not rheaders then
        print("  headers = "..tostring(rheaders))
      else
        print("  headers = {")
        for k, v in pairs(rheaders) do
          print("      "..tostring(k)..": "..tostring(v))
        end
        print("  }")
      end
      print("  status_line = "..tostring(rstatus_line))
      if not ok and rstatus == "timeout" then
        print("Client: received a timeout error, as expected!")
      else
        print("Client: error when requesting:", rstatus)
        os.exit(1)
      end

      -- cleanup; sleep 2 secs to wait for closing server socket
      -- to ensure any error messages do not get intermixed with the next tests output
      copas.pause(2)
      print(("="):rep(80))
    end


    do
      print("fifth test: server generates time-out while sending the body")
      timeout_bytes_request = nil
      timeout_bytes_response = #response - 500 -- body = 1024, so 500 before end is right in the middle of the body
      -- make request
      local ok, rstatus, rheaders, rstatus_line = request {
        url = "http://localhost:49500/some/path",
        method = "POST",
        headers = request_headers,
        timeout = timeout,
        source = ltn12.source.string(("B"):rep(1023).."x"),  -- request body
        sink = ltn12.sink.table({}), -- response body
      }
      print("Client received response: ")
      print("  ok = "..tostring(ok))
      print("  status = "..tostring(rstatus))
      if not rheaders then
        print("  headers = "..tostring(rheaders))
      else
        print("  headers = {")
        for k, v in pairs(rheaders) do
          print("      "..tostring(k)..": "..tostring(v))
        end
        print("  }")
      end
      print("  status_line = "..tostring(rstatus_line))
      if not ok and rstatus == "timeout" then
        print("Client: received a timeout error, as expected!")
      else
        print("Client: error when requesting:", rstatus)
        os.exit(1)
      end

      -- cleanup; sleep 2 secs to wait for closing server socket
      -- to ensure any error messages do not get intermixed with the next tests output
      copas.pause(2)
      print(("="):rep(80))
    end


    -- close server and exit
    print("closing server and exiting...")
    copas.removeserver(s1)
  end)

  print("starting loop")
  copas.loop()
  print("Loop done")
end

runtest()
print "test success!"
