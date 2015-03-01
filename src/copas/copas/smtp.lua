-------------------------------------------------------------------
-- identical to the socket.smtp module except that it uses
-- async wrapped Copas sockets

local copas = require("copas")
local smtp = require("socket.smtp")

local create = function() return copas.wrap(socket.tcp()) end

copas.smtp = {}
local _M = copas.smtp

_M.message = smtp.message  -- nothing changed here

_M.send = function(mailt)
  mailt.create = create
  return smtp.send(mailt)
end
