-------------------------------------------------------------------------------
-- Copas - Coroutine Oriented Portable Asynchronous Services
-- 
-- Offers a dispatcher and socket operations based on coroutines.
-- Usage:
--    copas.addserver(server, handler, timeout)
--    copas.addthread(thread, ...) Create a new coroutine thread and run it with args
--    copas.loop(timeout) - listens infinetely
--    copas.step(timeout) - executes one listening step
--    copas.receive(pattern or number) - receives data from a socket
--    copas.settimeout(client, time) if time=0 copas.receive(bufferSize) - receives partial data from a socket were data<=bufferSize
--    copas.send  - sends data through a socket
--    copas.wrap  - wraps a LuaSocket socket with Copas methods
--    copas.connect - blocks only the thread until connection completes
--    copas.flush - *deprecated* do nothing
--
-- Authors: Andre Carregal and Javier Guerra
-- Contributors: Diego Nehab, Mike Pall, David Burgess and Leonardo Godinho
--
-- Copyright 2006 - Kepler Project (www.keplerproject.org)
--
-- $Id: copas.lua,v 1.25 2006/09/28 16:38:10 jguerra Exp $
-------------------------------------------------------------------------------
local socket = require "socket"

-- Redefines LuaSocket functions with coroutine safe versions
-- (this allows the use of socket.http from within copas)
function socket.protect(func)
  return function (...)
		local ret = {pcall(func, unpack(arg))}
		local status = table.remove(ret,1)
		if status then
			return unpack(ret)
		end
		return nil, unpack(ret)
	end
end

function socket.newtry(finalizer)
	return function (...)
		local status = arg[1]or false
		if (status==false)then
			table.remove(arg,1)
			local ret = {pcall(finalizer, unpack(arg) ) }
			error(arg[1], 0)
		end
		return unpack(arg)
	end
end
-- end of LuaSocket redefinitions

module ("copas", package.seeall)

-- Meta information is public even if begining with an "_"
_COPYRIGHT   = "Copyright (C) 2004-2006 Kepler Project"
_DESCRIPTION = "Coroutine Oriented Portable Asynchronous Services"
_VERSION     = "Copas 1.1"

-------------------------------------------------------------------------------
-- Simple set implementation based on LuaSocket's tinyirc.lua example
-- adds a FIFO queue for each value in the set
-------------------------------------------------------------------------------
local function newset()
    local reverse = {}
    local set = {}
    local q = {}
    setmetatable(set, { __index = {
        insert = function(set, value)
            if not reverse[value] then
                table.insert(set, value)
                reverse[value] = table.getn(set)
            end
        end,

        remove = function(set, value)
            local index = reverse[value]
            if index then
                reverse[value] = nil
                local top = table.remove(set)
                if top ~= value then
                    reverse[top] = index
                    set[index] = top
                end
            end
        end,
		
		push = function (set, key, itm)
			if q[key] == nil then
				q[key] = {itm}
			else
				table.insert (q[key], itm)
			end
		end,
		
        pop = function (set, key)
          local t = q[key]
          if t ~= nil then
            local ret = table.remove (t, 1)
            if t[1] == nil then
              q[key] = nil
            end
            return ret
          end
        end
    }})
    return set
end

local _servers = newset() -- servers being handled
local _reading = newset() -- sockets currently being read
local _writing = newset() -- sockets currently being written

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

-- same as above but with special treatment when reading chunks,
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
end

-- wraps a socket to use Copas methods (send, receive, flush and settimeout)
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

--------------------------------------------------
-- Error handling
--------------------------------------------------

local _errhandlers = {}   -- error handler per coroutine

function setErrorHandler (err)
	local co = coroutine.running()
	if co then
		_errhandlers [co] = err
	end
end

local function _deferror (msg, co, skt)
	print (msg, co, skt)
end

-------------------------------------------------------------------------------
-- Thread handling
-------------------------------------------------------------------------------

local function _doTick (co, skt, ...)
	if not co then return end
	
	local ok, res, new_q = coroutine.resume(co, skt, unpack (arg))
	
	if ok and res and new_q then
		new_q:insert (res)
		new_q:push (res, co)
	else
		if not ok then pcall (_errhandlers [co] or _deferror, res, co, skt) end
		if skt then skt:close() end
		_errhandlers [co] = nil
	end
end

-- accepts a connection on socket input
local function _accept(input, handler)
	local client = input:accept()
	if client then 
		client:settimeout(0)
		local co = coroutine.create(handler)
		_doTick (co, client)
		--_reading:insert(client)
	end
	return client
end

-- handle threads on a queue
local function _tickRead (skt)
	_doTick (_reading:pop (skt), skt)
end

local function _tickWrite (skt)
	_doTick (_writing:pop (skt), skt)
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
-- Adds an new courotine thread to Copas dispatcher
-------------------------------------------------------------------------------
function addthread(thread, ...)
	local co = coroutine.create(thread)
	_doTick (co, nil, unpack(arg))
end

-------------------------------------------------------------------------------
-- tasks registering
-------------------------------------------------------------------------------

local _tasks = {}

local function addtaskRead (tsk)
	-- lets tasks call the default _tick()
	tsk.def_tick = _tickRead
	
	_tasks [tsk] = true
end

local function addtaskWrite (tsk)
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
local _readable_t = {
  events = function(self)
  	local i = 0
  	return function ()
  		i = i + 1
  		return self._evs [i]
  	end
  end,
  
  tick = function (self, input)
  	local handler = _servers[input]
  	if handler then
  		input = _accept(input, handler)
  	else
  		_reading:remove (input)
  		self.def_tick (input)
  	end
  end
}

addtaskRead (_readable_t)


-- a task to check ready to write events
local _writable_t = {
  events = function (self)
  	local i = 0
  	return function ()
  		i = i+1
  		return self._evs [i]
  	end
  end,
  
  tick = function (self, output)
  	_writing:remove (output)
  	self.def_tick (output)
  end
}

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
-- Dispatcher endless loop.
-- Listen to client requests and handles them forever
-------------------------------------------------------------------------------
function loop(timeout)
	while true do
		step(timeout)
	end
end