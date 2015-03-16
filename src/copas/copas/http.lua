-------------------------------------------------------------------
-- identical to the socket.http module except that it uses
-- async wrapped Copas sockets

local copas = require("copas")
local socket = require("socket")
local http = require("socket.http")
local ltn12 = require("ltn12")


local create = function() return copas.wrap(socket.tcp()) end
local forwards = { -- setting these will be forwarded to the original smtp module
  PORT = true,
  PROXY = true,
  TIMEOUT = true,
  USERAGENT = true
}

copas.http = setmetatable({}, { 
    -- use original module as metatable, to lookup constants like socket.PROXY, etc.
    __index = http,
    -- Setting constants is forwarded to the luasocket.http module.
    __newindex = function(self, key, value)
        if forwards[key] then http[key] = value return end
        return rawset(self, key, value)
      end,
    })
local _M = copas.http

---[[ IS HERE UNTIL PR #133 IS ACCEPTED INTO LUASOCKET
-- parses a shorthand form into the advanced table form.
-- adds field `target` to the table. This will hold the return values.
_M.parseRequest = function(u, b)
    local reqt = {
        url = u,
        target = {},
    }
    reqt.sink = ltn12.sink.table(reqt.target)
    if b then
        reqt.source = ltn12.source.string(b)
        reqt.headers = {
            ["content-length"] = string.len(b),
            ["content-type"] = "application/x-www-form-urlencoded"
        }
        reqt.method = "POST"
    end
    return reqt
end
--]]

_M.request = socket.protect(function(reqt, body)
  if type(reqt) == "string" then
    reqt = _M.parseRequest(reqt, body) 
    local code, headers, status = socket.skip(1, _M.request(reqt))
    return table.concat(reqt.target), code, headers, status
  else 
    reqt.create = reqt.create or create  -- insert our own create function here
    return http.request(reqt)
  end
end)

return _M

