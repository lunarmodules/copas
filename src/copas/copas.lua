-------------------------------------------------------------------------------
-- Copas - Coroutine Oriented Portable Asynchronous Services
-- 
-- Version #4
--
-- Offers a dispatcher and socket operations based on coroutines.
-- Usage:
--    copas.addserver(server, handler)
--    copas.loop()
--
-- The handler should use copas.send, copas.receive instead of
-- the LuaSocket versions.
--
-- copas.flush flushes the writing buffer if necessary, it is also called
-- automatically by copas.loop()
--
-- Authors: Andre Carregal and Javier Guerra
-- Contributors: Diego Nehab, Mike Pall and David Burgess
-- Copyright 2005 - Kepler Project (www.keplerproject.org)
-------------------------------------------------------------------------------
require "socket"

module "copas"

-- Meta information is public even begining with an "_"
_COPYRIGHT   = "Copyright (C) 2004-2005 Kepler Project"
_DESCRIPTION = "Coroutine Oriented Portable Asynchronous Services"
_NAME        = "Copas"
_VERSION     = "1.0 Beta"

-------------------------------------------------------------------------------
-- Simple set implementation based on LuaSocket's tinyirc.lua example
-------------------------------------------------------------------------------
local function _newset()
    local reverse = {}
    local set = {}
    setmetatable(set, { __index = {
        insert = function(set, value) 
            table.insert(set, value)
            reverse[value] = table.getn(set)
        end,
        remove = function(set, value)
            if not reverse[value] then return end
            local last = table.getn(set)
            if last > 1 then
                -- replaces the removed value with the last one
                local index = reverse[value]
                local newvalue = set[last]
                set[index] = newvalue
                reverse[newvalue] = index
            end
            table.setn(set, last - 1)
            -- cleans up the garbage
            reverse[value] = nil
            set[last] = nil
        end,
    }})
    return set
end

local _servers = _newset()
local _reading = _newset() -- sockets currently being read
local _writing = _newset() -- sockets currently being written

-------------------------------------------------------------------------------
-- Coroutine based socket I/O functions.
--
-- Writing operations are buffered to allow a nicer distribution of yields 
-------------------------------------------------------------------------------
local _buffer = {}

-- reads a pattern from a client and yields to reading set on timeouts
function receive(client, pattern)
  local s, err, part
  pattern = pattern or "*l"
  repeat
    s, err, part = client:receive(pattern, part)
--	print ("copas.receive", client, pattern, s, err, part)
    if s or err ~= "timeout" then return s, err end
    coroutine.yield(client, _reading)
  until false
end

-- sends data from a client. The operation is buffered and
-- yield yield to writing set on timeouts
function send(client, data)
  if _buffer[client] == nil then
    _buffer[client] = ""
  end
  if data then
    _buffer[client] = _buffer[client]..data
  end
  if (math.random(100) > 90) or string.len(_buffer[client]) > 2048 then
    flush(client)
  end
end

-- sends a client buffer yielding to writing on timeouts
local function _sendBuffer(client)
  local s, err
  local from = 1
  local sent = 0
  repeat
    from = from + sent
    s, err, sent = client:send(_buffer[client], from)
    if s or err ~= "timeout" then return s, err end
    coroutine.yield(client, _writing)
  until false
end

-- flushes a client write buffer
function flush(client)
  if _buffer[client] == nil then
    _buffer[client] = ""
  end
  _sendBuffer(client)
  _buffer[client] = nil
end


-- wraps a socket to use Copas methods
local _skt_mt = {__index = {
	send = function (self, data)
			return send (self.socket, data)
		end,
	receive = function (self, pattern)
			return receive (self.socket, pattern)
		end,
	flush = function (self)
			return flush (self.socket)
		end,
}}

function skt_wrap (skt)
	return  setmetatable ({socket = skt}, _skt_mt)
end

-------------------------------------------------------------------------------
-- Thread handling
-------------------------------------------------------------------------------

local _threads = {} -- maps sockets and coroutines

-- accepts a connection on socket input
local function _accept(input, handler)
	local client = input:accept()
	if client then 
		client:settimeout(0)
		_threads[client] = coroutine.create(handler)
		_reading:insert(client)
	end
	return client
end

-- handle threads on a queue
local function _tick (skt)
	local co = _threads[skt]
--	queue:remove (skt)
	local status, res, new_q = coroutine.resume(co, skt)
	if not status then
		error(res)
	end
	if not res then
		-- remove the coroutine from the running threads
		_threads[skt] = nil
		flush(skt)
		skt:close()
	elseif new_q then
		new_q:insert (res)
	else
		-- still missing error handling here
	end
end


-------------------------------------------------------------------------------
-- Adds a server/handler pair to Copas dispatcher
-------------------------------------------------------------------------------
function addserver(server, handler, timeout)
  server:settimeout(timeout or 0.1)
  _servers[server] = handler
  _reading:insert(server)
end

-------------------------------------------------------------------------------
-- tasks registering
-------------------------------------------------------------------------------

local _tasks = {}

function addtask (tsk)
	-- lets tasks call the default _tick()
	tsk.def_tick = _tick
	
	_tasks [tsk] = true
end

local function tasks ()
	return next, _tasks
end

-------------------------------------------------------------------------------
-- main tasks: manage readable and writable socket sets
-------------------------------------------------------------------------------
-- a task to check ready to read events
local _readable_t = {}
function _readable_t:events ()
	local i = 0
	return function ()
		i = i+1
		return self._evs [i]
	end
end
function _readable_t:tick (input)
	local handler = _servers[input]
	if handler then
		input = _accept(input, handler)
	end
	_reading:remove (input)
	self.def_tick (input)
end
addtask (_readable_t)


-- a task to check ready to write events
local _writable_t = {}
function _writable_t:events ()
	local i = 0
	return function ()
		i = i+1
		return self._evs [i]
	end
end
function _writable_t:tick (output)
	_writing:remove (output)
	self.def_tick (output)
end
addtask (_writable_t)

local function _select ()
	local err
	_readable_t._evs, _writable_t._evs, err = socket.select(_reading, _writing)
	return err
end


-------------------------------------------------------------------------------
-- Dispatcher loop.
-- Listen to client requests and handles them
-------------------------------------------------------------------------------
function loop()
	local err

	while true do
		err = _select ()

		if err then
			error(err)
		end
		
		for tsk in tasks() do
			for ev in tsk:events () do
				tsk:tick (ev)
			end
		end
	end
end