-------------------------------------------------------------------------------
-- Copas - Coroutine Oriented Portable Asynchronous Services
-- 
-- Copas Wrapper for socket.http module
-- 
-- Written by Leonardo Godinho da Cunha
-------------------------------------------------------------------------------
local copas = require("copas")
local socket = require("socket")

local cosocket = {}

-- Meta information is public even begining with an "_"
cosocket._COPYRIGHT   = "Copyright (C) 2004-2006 Kepler Project"
cosocket._DESCRIPTION = "Coroutine Oriented Portable Asynchronous Services Wrapper for socket module"
cosocket._NAME        = "Copas.cosocket"
cosocket._VERSION     = "0.1"

function cosocket.tcp ()
	local skt = socket.tcp()
	local w_skt_mt = { __index = skt }
	local ret_skt = setmetatable ({ socket = skt }, w_skt_mt)
	ret_skt.settimeout = function (self,val)
				return self.socket:settimeout (val) 
	   		end 	
	ret_skt.connect = function (self,host, port)
				local ret,err = copas.connect (self.socket,host, port)
				local d = copas.wrap(self.socket)

				self.send= function(client, data)
					local ret,val=d.send(client, data)
					return ret,val
				end
    				self.receive=d.receive
    				self.close = function (w_socket)
    					ret=w_socket.socket:close()
    					return ret
    				end
				return ret,err
			end 
	return  ret_skt
end
