-------------------------------------------------------------------
-- identical to the socket.http module except that it uses
-- async wrapped Copas sockets

local copas = require("copas")
local socket = require("socket")
local http = require("socket.http")
local ltn12 = require("ltn12")


local create = function() return copas.wrap(socket.tcp()) end

copas.http = setmetatable({}, { 
    -- use original module as metatable, to lookup constants like socket.PROXY, etc.
    __index = require("socket.http"),
    -- Setting constants is forwarded to the luasocket.http module.
    __newindex = function(self, key, value)
        if key == "PORT" then http.PORT = value return end
        if key == "PROXY" then http.PROXY = value return end
        if key == "TIMEOUT" then http.TIMEOUT = value return end
        if key == "USERAGENT" then http.USERAGENT = value return end
        return rawset(self, key, value)
      end,
    })
local _M = copas.http

-- mostly a copy of the version in LuaSockets' http.lua 
-- no 'create' can be passed in the string form, hence a local copy here
local function srequest(u, b, userc)
    local t = {}
    local reqt = {
        url = u,
        sink = ltn12.sink.table(t),
        create = userc
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

-- userc = is a user specified 'create' function, instead of the default copas one
-- used in string version, for advanced supply one in the parameter table
_M.request = socket.protect(function(reqt, body, userc)
  if type(reqt) == "string" then
    return srequest(reqt, body, userc)
  else 
    reqt.create = reqt.create or create  -- insert our own create function here
    return http.request(reqt)
  end
end)

return _M

