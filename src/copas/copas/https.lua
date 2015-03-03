-------------------------------------------------------------------
-- identical to the luasec.https module except that it uses
-- async wrapped Copas sockets

local copas = require("copas")
local socket = require("socket")
local http = require("copas.http")
local url = require("socket.url")

copas.https = {}
local _M = copas.https

_M.PORT = 443   -- default port

_M.SSLDEFAULTS = {   -- default parameters
  protocol = "tlsv1",
  options  = "all",
  verify   = "none",
}


--------------------------------------------------------------------
-- Make a HTTP request over secure connection.  This function receives
--  the same parameters of LuaSocket's HTTP module (except 'proxy' and
--  'redirect') plus LuaSec parameters.
--
-- @param url mandatory (string or table)
-- @param body optional (string)
-- @param sslparams optional (table)
-- @return (string if url == string or 1), code, headers, status
function _M.request(requrl, body, sslparams)
  if type(requrl) == "string" then
    sslparams = sslparams or {}
    requrl = url.build(url.parse(requrl, {port = _M.PORT}))  -- set port if not specified in url
  else
    sslparams = requrl  -- in table format, the ssl parameters must be provided in the table
    requrl.url = url.build(url.parse(requrl.url, {port = _M.PORT}))  -- set port if not specified in url
  end
  sslparams.mode = "client"                -- force client mode
  for k, v in pairs(_M.SSLDEFAULTS) do     -- insert default settings where omitted
    sslparams[k] = sslparams[k] or v
  end
  local create = function() return copas.wrap(socket.tcp(), sslparams) end
  if type(requrl) == "string" then
    return http.request(requrl, body, create)
  else
    requrl.create = create
    return http.request(requrl, body)
  end
end

return _M

