-------------------------------------------------------------------
-- identical to the socket.http request function except that it uses
-- async wrapped Copas sockets

local copas = require("copas")
local socket = require("socket")
local http = require("socket.http")
local ltn12 = require("ltn12")

local create = function()
  return copas.wrap(socket.tcp())
  
--[[  
  local s = socket.tcp()
  local skt = copas.wrap(s)
print(pcall(s.skip, 1, "a", "b"))
print(pcall(skt.skip, 1, "a", "b"))
  print("skipping",skt.skip("a","b","c"))
  local mt = getmetatable(skt)
  local idx = mt.__index
  -- add 'missing' methods
  print("timeout: ", skt.timeout)
  skt:settimeout(0)
  print("timeout: ", skt.timeout, skt)
  idx.close = function(self, ...)
    return self.socket:close(...)
  end
  idx.connect = function(self, ...)
    return self.socket:connect(...)
  end
  
  print("=======")
  for k,v in pairs(mt.__index) do print (k,v) end
  print("=======")
  mt.__index = function (self, key)
    print("Rawget: ", key, rawget(skt, key),"in: ", skt)
    local res = rawget(skt, key) or idx[key]   -- look in wrapper first
    if res then 
      print("Looked up     : ", key)
    else
      print("Failed to find: ", key, "!!!")
      --print(debug.traceback())
      res = skt.socket[key]  -- fetch field from original socket
      if type(res)=="function" then 
        print("wrapped: ", res)
        res = function(_, ...) 
          --print("called: ", key) 
          return res(skt.socket, ...)
        end
        print("... as : ", res)
      end
    end
    return res
  end
  
  for k,v in pairs(idx) do print(k,v) end
  return skt
--]]      
end

copas.http = {}
local _M = copas.http

-- mostly a copy of the version in LuaSockets' http.lua 
-- no 'create' can be passed in the string form, hence a local copy here
local function srequest(u, b)
    local t = {}
    local reqt = {
        url = u,
        sink = ltn12.sink.table(t)
    }
    if b then
        reqt.source = ltn12.source.string(b)
        reqt.headers = {
            ["content-length"] = string.len(b),
            ["content-type"] = "application/x-www-form-urlencoded"
        }
        reqt.method = "POST"
    end
    local code, headers, status = socket.skip(1, _M.request(reqt))
    return table.concat(t), code, headers, status
end

_M.request = socket.protect(function(reqt, body)
  if type(reqt) == "string" then
    return srequest(reqt, body)
  else 
    reqt.create = create  -- insert our own create function here
    return http.request(reqt)
  end
end)

return _M

