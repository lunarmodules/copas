-- test redirecting http <-> https combinations

local copas = require("copas")
local http = require("copas.http")
local ltn12 = require("ltn12")
local dump_all_headers = false
local redirect


local function doreq(url)
  local reqt = {
      url = url,
      redirect = redirect,     --> allows https-> http redirect
      target = {},
  }
  reqt.sink = ltn12.sink.table(reqt.target)

  local result, code, headers, status = http.request(reqt)
  print(string.rep("=",70))
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
  local result, code, headers, status = doreq("https://goo.gl/UBCUc5")  -- https --> https redirect
  assert(tonumber(code)==200)
  assert(headers.location == "https://github.com/brunoos/luasec")
  print("https -> https redirect OK!")
  copas.addthread(function()
    local result, code, headers, status = doreq("http://goo.gl/UBCUc5")  -- http --> https redirect
    assert(tonumber(code)==200)
    assert(headers.location == "https://github.com/brunoos/luasec")
    print("http  -> https redirect OK!")
    copas.addthread(function()
      local result, code, headers, status = doreq("http://goo.gl/tBfqNu")  -- http --> http redirect
      assert(tonumber(code)==200)
      assert(headers.location == "http://www.thijsschreijer.nl/blog/")
      print("http  -> http  redirect OK!")
      copas.addthread(function()
        local result, code, headers, status = doreq("https://goo.gl/tBfqNu")  -- https --> http security test case
        assert(result==nil and code == "Unallowed insecure redirect https to http")
        print("https -> http  redirect, while not allowed OK!:", code)
        copas.addthread(function()
          redirect = "all"
          local result, code, headers, status = doreq("https://goo.gl/tBfqNu")  -- https --> http security test case
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
