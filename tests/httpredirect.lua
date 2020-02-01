-- test redirecting http <-> https combinations

local copas = require("copas")
local http = require("copas.http")
local ltn12 = require("ltn12")
local dump_all_headers = false
local redirect
local socket = require "socket"


local function doreq(url)
  local reqt = {
      url = url,
      redirect = redirect,     --> allows https-> http redirect
      target = {},
  }
  reqt.sink = ltn12.sink.table(reqt.target)

  local result, code, headers, status = http.request(reqt)
  print(string.rep("-",70))
  print("Fetching:",url,"==>",code, status)
  if dump_all_headers then
    if headers then
      print("HEADERS")
      for k,v in pairs(headers) do print("",k,v) end
    end
  else
    print("      at:", (headers or {}).location)
  end
  --print(string.rep("=",70))
  return result, code, headers, status
end

local done = false

copas.addthread(function()
  local _, code, headers = doreq("https://goo.gl/UBCUc5")  -- https --> https redirect
  assert(tonumber(code)==200)
  assert(headers.location == "https://github.com/brunoos/luasec")
  print("https -> https redirect OK!")
  copas.addthread(function()
    local _, code, headers = doreq("http://goo.gl/UBCUc5")  -- http --> https redirect
    assert(tonumber(code)==200)
    assert(headers.location == "https://github.com/brunoos/luasec")
    print("http  -> https redirect OK!")
    copas.addthread(function()
      --local result, code, headers, status = doreq("http://goo.gl/tBfqNu")  -- http --> http redirect
      -- the above no longer works for testing, since Google auto-inserts a
      -- initial redirect to the same url, over https, hence the final
      -- redirect is a downgrade which then errors out
      -- so we set up a local http-server to deal with this
      local server = assert(socket.bind("127.0.0.1", 9876))
      local crlf = string.char(13)..string.char(10)
      copas.addserver(server, function(skt)
          skt = copas.wrap(skt)
          assert(skt:receive())
          local response =
              "HTTP/1.1 302 Found" .. crlf ..
              "Location: http://www.thijsschreijer.nl/blog/" .. crlf .. crlf
          assert(skt:send(response))
          skt:close()
      end)
      -- execute test request
      local _, code, headers = doreq("http://localhost:9876/")  -- http --> http redirect
      copas.removeserver(server)  -- immediately close server again
      assert(tonumber(code)==200)
      assert(headers.location == "http://www.thijsschreijer.nl/blog/")
      print("http  -> http  redirect OK!")
      copas.addthread(function()
        local result, code = doreq("https://goo.gl/tBfqNu")  -- https --> http security test case
        assert(result==nil and code == "Unallowed insecure redirect https to http")
        print("https -> http  redirect, while not allowed OK!:", code)
        copas.addthread(function()
          redirect = "all"
          local _, code, headers = doreq("https://goo.gl/tBfqNu")  -- https --> http security test case
          assert(tonumber(code)==200)
          assert(headers.location == "http://www.thijsschreijer.nl/blog/")
          print("https -> http  redirect, while allowed OK!")
          done = true
        end)
      end)
    end)
  end)
end)

copas.loop()

if not done then
  print("Some checks above failed")
  os.exit(1)
end
