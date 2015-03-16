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

_M.SSLPROTOCOL = "tlsv1"
_M.SSLOPTIONS  = "all"
_M.SSLVERIFY   = "none"


--------------------------------------------------------------------
-- Make a HTTP request over secure connection.  This function receives
--  the same parameters of LuaSocket's HTTP module (except 'proxy' and
--  'redirect') plus LuaSec parameters.
--
-- @param url mandatory (string or table)
-- @param body optional (string)
-- @param sslparams optional (table)
-- @return (string if url == string or 1), code, headers, status
function _M.request(reqt, body, sslparams)
  if type(body)=="table" and sslparams == nil then  -- shift params if 'body' is omitted
    sslparams, body = body, nil
  end
  
  if type(reqt) == "string" then  -- parse to table and recursive call ourselves
    reqt = http.parseRequest(reqt, body)
--    reqt.redirect = false
    local code, headers, status = socket.skip(1, _M.request(reqt))
    return table.concat(reqt.target), code, headers, status
  end
  
  sslparams = reqt                    -- in table format, the ssl parameters must be provided in the table
  sslparams.mode = "client"           -- force client mode
  reqt.create = function() return copas.wrap(socket.tcp(), sslparams) end
  reqt.url = url.build(url.parse(reqt.url, {port = _M.PORT}))  -- set port if not specified in url
  
  -- insert default settings where omitted
  sslparams.protocol = sslparams.protocol or _M.SSLPROTOCOL
  sslparams.options  = sslparams.options  or _M.SSLOPTIONS
  sslparams.verify   = sslparams.verify   or _M.SSLVERIFY
  
  -- Sanity checks
  if http.PROXY or reqt.proxy then
    return nil, "proxy not supported"
  elseif reqt.redirect then --~= false then
    return nil, "redirect not supported"
  end
  
  return http.request(reqt)
end

return _M

