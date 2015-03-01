-------------------------------------------------------------------
-- identical to the socket.ftp module except that it uses
-- async wrapped Copas sockets

local copas = require("copas")
local socket = require("socket")
local ftp = require("socket.ftp")
local ltn12 = require("ltn12")
local url = require("socket.url")


local create = function() return copas.wrap(socket.tcp()) end

copas.ftp = {}
local _M = copas.ftp

_M.command = function(cmdt)
  cmdt.create = create
  return ftp.command(cmdt)
end

-- a copy of the version in LuaSockets' ftp.lua 
-- no 'create' can be passed in the string form, hence a local copy here
local default = {
    path = "/",
    scheme = "ftp"
}

-- a copy of the version in LuaSockets' ftp.lua 
-- no 'create' can be passed in the string form, hence a local copy here
local function parse(u)
    local t = socket.try(url.parse(u, default))
    socket.try(t.scheme == "ftp", "wrong scheme '" .. t.scheme .. "'")
    socket.try(t.host, "missing hostname")
    local pat = "^type=(.)$"
    if t.params then
        t.type = socket.skip(2, string.find(t.params, pat))
        socket.try(t.type == "a" or t.type == "i",
            "invalid type '" .. t.type .. "'")
    end
    return t
end

-- mostly a copy of the version in LuaSockets' ftp.lua 
-- no 'create' can be passed in the string form, hence a local copy here
local function sput(u, body)
    local putt = parse(u)
    putt.source = ltn12.source.string(body)
    return _M.put(putt)
end

_M.put = socket.protect(function(putt, body)
    if type(putt) == "string" then 
      return sput(putt, body)
    else 
      putt.create = create
      return ftp.put(putt)
    end
end)

-- mostly a copy of the version in LuaSockets' ftp.lua 
-- no 'create' can be passed in the string form, hence a local copy here
local function sget(u)
    local gett = parse(u)
    local t = {}
    gett.sink = ltn12.sink.table(t)
    _M.get(gett)
    return table.concat(t)
end

_M.get = socket.protect(function(gett)
    if type(gett) == "string" then 
      return sget(gett)
    else 
      gett.create = create
      return ftp.get(gett)
    end
end)
