-------------------------------------------------------------------------------
-- Copas - Coroutine Oriented Portable Asynchronous Services
-- 
-- Offers a dispatcher and socket operations based on coroutines.
-- Usage:
--    copas.addserver(server, handler, timeout)
--    copas.execThread(handler,...) Create a new coroutine and run it with args
--    copas.loop(timeout) - listens infinetely
--    copas.step(timeout) - executes one listening step
--    copas.flush - *deprecated* do nothing
--    copas.receive(pattern or number) - receives data from a socket
--    copas.settimeout(client, time) if time=0 copas.receive(bufferSize) - receives partial data from a socket were data<=bufferSize
--    copas.send  - sends data through a socket
--    copas.wrap  - wraps a LuaSocket socket with Copas methods
--    copas.connect - blocks only the thread until connection completes
--
-- Authors: Andre Carregal and Javier Guerra
-- Contributors: Diego Nehab, Mike Pall and David Burgess
--
-- Copyright 2005 - Kepler Project (www.keplerproject.org)
--
-- $Id: copas.lua,v 1.18 2006/02/10 20:26:28 uid20103 Exp $
-------------------------------------------------------------------------------
require "socket"
-- corrotine safe socket module calls
function socket.protect(func)
	protectedFunc = function (...)
		local ret ={pcall(func,unpack(arg) ) }
		local status = table.remove(ret,1)
		if status then
			return unpack(ret)
		end
		return nil, unpack(ret)
	end
	return protectedFunc
end
function socket.newtry(finalizer)
	tryFunc = function (...)
		local status = arg[1]or false
		if (status==false)then
			table.remove(arg,1)
			local ret={pcall(finalizer,unpack(arg) ) }
			error(arg[1],0)
		end
		return unpack(arg)
	end
	return tryFunc
end

-- end of corrotine safe socket module calls
module "copas"

-- Meta information is public even begining with an "_"
_COPYRIGHT   = "Copyright (C) 2004-2005 Kepler Project"
_DESCRIPTION = "Coroutine Oriented Portable Asynchronous Services"
_VERSION     = "Copas 1.0"

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
-------------------------------------------------------------------------------
-- reads a pattern from a client and yields to the reading set on timeouts
function receive(client, pattern)
  local s, err, part
  pattern = pattern or "*l"
  repeat
    s, err, part = client:receive(pattern, part)
    if s or err ~= "timeout" then return s, err, part end
    coroutine.yield(client, _reading)
  until false
end
-- same as above but with special threatment when reading chunks,
-- unblocks on any data received.
function receivePartial(client, pattern)
  local s, err, part
  pattern = pattern or "*l"
  repeat
    s, err, part = client:receive(pattern)
    if s or ( (type(pattern)=="number") and part~="" and part ~=nil ) or 
       err ~= "timeout" then return s, err, part end
    coroutine.yield(client, _reading)
  until false
end


-- sends data to a client. The operation is buffered and
-- yields to the writing set on timeouts
function send(client,data)
  local s, err,sent
  local from = 1
  local sent = 0
  repeat
    from = from + sent
    s, err, sent = client:send(data, from)
    -- adds extra corrotine swap
    -- garantees that high throuput dont take other threads to starvation 
    if (math.random(100) > 90) then
    	coroutine.yield(client, _writing)
    end
    if s or err ~= "timeout" then return s, err,sent end
    coroutine.yield(client, _writing)
  until false
end

-- waits until connection is completed
function connect(skt,host, port)
	skt:settimeout(0)
	local ret,err = skt:connect (host, port)
	if ret or err ~= "timeout" then return ret, err end
	coroutine.yield(skt, _writing)
	ret,err = skt:connect (host, port)
	if (err=="already connected") then
		return 1
	end
	return ret, err
end
-- flushes a client write buffer (deprecated)
function flush(client)
  return 
end

-- wraps a socket to use Copas methods
local _skt_mt = {__index = {
	send = function (self, data)
			return send (self.socket, data)
		end,
	receive = function (self, pattern)
			if (self.timeout==0) then
  				return receivePartial(self.socket, pattern)
  			end
			return receive (self.socket, pattern)
		end,
	flush = function (self)
			return flush (self.socket)
		end,
	settimeout = function (self,time)
			self.timeout=time
			return
		end,
}}

function wrap (skt)
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
		local co = coroutine.create(handler)
		_firstTick(co,client)
		--_reading:insert(client)
	end
	return client
end

-- handle threads on a queue
local function _tickRead (skt)
	local co = table.remove(_threads[skt].read,1)
	
	local status, res, new_q = coroutine.resume(co)
	if not status then
		error(res)
	end
	if not res then
		skt:close()
	elseif new_q then
		new_q:insert (res)
		
		if (new_q == _reading) then
			if (_threads[res]== nil) then
				_threads[res]={read={},write={}}
			end
			table.insert(_threads[res].read, co)
		end
		if (new_q == _writing) then
			if (_threads[res]== nil) then
				_threads[res]={read={},write={}}
			end
			table.insert(_threads[res].write, co)
		end
	else
		-- still missing error handling here
	end
end
local function _tickWrite (skt)
	local co = table.remove(_threads[skt].write,1)
	
	local status, res, new_q = coroutine.resume(co)
	if not status then
		error(res)
	end
	if not res then
		skt:close()
	elseif new_q then
		new_q:insert (res)
		
		if (new_q == _reading) then
			if (_threads[res]== nil) then
				_threads[res]={read={},write={}}
			end
			table.insert(_threads[res].read, co)
		end
		if (new_q == _writing) then
			if (_threads[res]== nil) then
				_threads[res]={read={},write={}}
			end
			table.insert(_threads[res].write, co)
		end
	else
		-- still missing error handling here
	end
end
--local
 function _firstTick (co,...)
	local status, res, new_q = coroutine.resume(co, unpack(arg))
	if not status then
		error(res)
	end
	if new_q then
		new_q:insert (res)
		
		if (new_q == _reading) then
			if (_threads[res]== nil) then
				_threads[res]={read={},write={}}
			end
			table.insert(_threads[res].read, co)
		end
		if (new_q == _writing) then
			if (_threads[res]== nil) then
				_threads[res]={read={},write={}}
			end
			table.insert(_threads[res].write, co)
		end
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
-- Adds an new thread to Copas 
-------------------------------------------------------------------------------
function execThread(handler,...)
	co = coroutine.create(handler)
	_firstTick(co, unpack(arg))
end

-------------------------------------------------------------------------------
-- tasks registering
-------------------------------------------------------------------------------

local _tasks = {}

function addtaskRead (tsk)
	-- lets tasks call the default _tick()
	tsk.def_tick = _tickRead
	
	_tasks [tsk] = true
end
function addtaskWrite (tsk)
	-- lets tasks call the default _tick()
	tsk.def_tick = _tickWrite
	
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
	else
		_reading:remove (input)
		self.def_tick (input)
	end
end
addtaskRead (_readable_t)


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
addtaskWrite (_writable_t)

local function _select (timeout)
	local err
	_readable_t._evs, _writable_t._evs, err = socket.select(_reading, _writing, timeout)
	return err
end


-------------------------------------------------------------------------------
-- Dispatcher loop step.
-- Listen to client requests and handles them
-------------------------------------------------------------------------------
function step(timeout)

    local err = _select (timeout)
    
    if err == "timeout" then return end

	if err then
		error(err)
	end
		
	for tsk in tasks() do
		for ev in tsk:events () do
			tsk:tick (ev)
		end
	end
end

-------------------------------------------------------------------------------
-- Dispatcher loop.
-- Listen to client requests and handles them
-------------------------------------------------------------------------------
function loop(timeout)
	while true do
		step(timeout)
	end
end
