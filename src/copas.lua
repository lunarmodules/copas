-------------------------------------------------------------------------------
-- Copas - Coroutine Oriented Portable Asynchronous Services
--
-- A dispatcher based on coroutines that can be used by TCP/IP servers.
-- Uses LuaSocket as the interface with the TCP/IP stack.
--
-- Authors: Andre Carregal, Javier Guerra, and Fabio Mascarenhas
-- Contributors: Diego Nehab, Mike Pall, David Burgess, Leonardo Godinho,
--               Thomas Harning Jr., and Gary NG
--
-- Copyright 2005-2016 - Kepler Project (www.keplerproject.org)
--
-- $Id: copas.lua,v 1.37 2009/04/07 22:09:52 carregal Exp $
-------------------------------------------------------------------------------

if package.loaded["socket.http"] and (_VERSION=="Lua 5.1") then     -- obsolete: only for Lua 5.1 compatibility
  error("you must require copas before require'ing socket.http")
end

local socket = require "socket"
local binaryheap = require "binaryheap"
local gettime = socket.gettime
local ssl -- only loaded upon demand

local WATCH_DOG_TIMEOUT = 120
local UDP_DATAGRAM_MAX = 8192  -- TODO: dynamically get this value from LuaSocket
local TIMEOUT_PRECISION = 0.1  -- 100ms
local fnil = function() end

local pcall = pcall
if _VERSION=="Lua 5.1" and not jit then     -- obsolete: only for Lua 5.1 compatibility
  pcall = require("coxpcall").pcall
end

-- Redefines LuaSocket functions with coroutine safe versions
-- (this allows the use of socket.http from within copas)
local function statusHandler(status, ...)
  if status then return ... end
  local err = (...)
  if type(err) == "table" then
    return nil, err[1]
  else
    error(err)
  end
end

function socket.protect(func)
  return function (...)
           return statusHandler(pcall(func, ...))
         end
end

function socket.newtry(finalizer)
  return function (...)
           local status = (...)
           if not status then
             pcall(finalizer, select(2, ...))
             error({ (select(2, ...)) }, 0)
           end
           return ...
         end
end

local copas = {}

-- Meta information is public even if beginning with an "_"
copas._COPYRIGHT   = "Copyright (C) 2005-2017 Kepler Project"
copas._DESCRIPTION = "Coroutine Oriented Portable Asynchronous Services"
copas._VERSION     = "Copas 2.0.2"

-- Close the socket associated with the current connection after the handler finishes
copas.autoclose = true

-- indicator for the loop running
copas.running = false


-------------------------------------------------------------------------------
-- Simple set implementation
-- adds a FIFO queue for each socket in the set
-------------------------------------------------------------------------------

local function newsocketset()
  local set = {}

  do  -- set implementation
    local reverse = {}

    -- Adds a socket to the set, does nothing if it exists
    function set:insert(skt)
      if not reverse[skt] then
        self[#self + 1] = skt
        reverse[skt] = #self
      end
    end

    -- Removes socket from the set, does nothing if not found
    function set:remove(skt)
      local index = reverse[skt]
      if index then
        reverse[skt] = nil
        local top = self[#self]
        self[#self] = nil
        if top ~= skt then
          reverse[top] = index
          self[index] = top
        end
      end
    end

  end

  do  -- queues implementation
    local fifo_queues = setmetatable({},{
      __mode = "k",                 -- auto collect queue if socket is gone
      __index = function(self, skt) -- auto create fifo queue if not found
        local newfifo = {}
        self[skt] = newfifo
        return newfifo
      end,
    })

    -- pushes an item in the fifo queue for the socket.
    function set:push(skt, itm)
      local queue = fifo_queues[skt]
      queue[#queue + 1] = itm
    end

    -- pops an item from the fifo queue for the socket
    function set:pop(skt)
      local queue = fifo_queues[skt]
      return table.remove(queue, 1)
    end

  end

  return set
end



-- Threads immediately resumable
local _resumable = {} do
  local resumelist = {}

  function _resumable:push(co)
    resumelist[#resumelist + 1] = co
  end

  function _resumable:clear_resumelist()
    local lst = resumelist
    resumelist = {}
    return lst
  end

  function _resumable:done()
    return resumelist[1] == nil
  end

end



-- Similar to the socket set above, but tailored for the use of
-- sleeping threads
local _sleeping = {} do

  local heap = binaryheap.minUnique()
  local lethargy = setmetatable({}, { __mode = "k" }) -- list of coroutines sleeping without a wakeup time


  -- Required base implementation
  -----------------------------------------
  _sleeping.insert = fnil
  _sleeping.remove = fnil

  -- push a new timer on the heap
  function _sleeping:push(sleeptime, co)
    if sleeptime < 0 then
      lethargy[co] = true
    elseif sleeptime == 0 then
      _resumable:push(co)
    else
      heap:insert(gettime() + sleeptime, co)
    end
  end

  -- find the thread that should wake up to the time, if any
  function _sleeping:pop(time)
    if time < (heap:peekValue() or math.huge) then
      return
    end
    return heap:pop()
  end

  -- additional methods for time management
  -----------------------------------------
  function _sleeping:getnext()  -- returns delay until next sleep expires, or nil if there is none
    local t = heap:peekValue()
    if t then
      -- never report less than 0, because select() might block
      return math.max(t - gettime(), 0)
    end
  end

  function _sleeping:wakeup(co)
    if lethargy[co] then
      lethargy[co] = nil
      _resumable:push(co)
      return
    end
    if heap:remove(co) then
      _resumable:push(co)
    end
  end

  -- @param tos number of timeouts running
  function _sleeping:done(tos)
    -- return true if we have nothing more to do
    -- the timeout task doesn't qualify as work (fallbacks only),
    -- the lethargy also doesn't qualify as work ('dead' tasks),
    -- but the combination of a timeout + a lethargy can be work
    return heap:size() == 1       -- 1 means only the timeout-timer task is running
           and not (tos > 0 and next(lethargy))
  end

end   -- _sleeping



-------------------------------------------------------------------------------
-- Tracking coroutines and sockets
-------------------------------------------------------------------------------

local _servers = newsocketset() -- servers being handled
local _threads = setmetatable({}, {__mode = "k"})  -- registered threads added with addthread()
local _canceled = setmetatable({}, {__mode = "k"}) -- threads that are canceled and pending removal

-- for each socket we log the last read and last write times to enable the
-- watchdog to follow up if it takes too long.
-- tables contain the time, indexed by the socket
local _reading_log = {}
local _writing_log = {}

local _reading = newsocketset() -- sockets currently being read
local _writing = newsocketset() -- sockets currently being written
local _isSocketTimeout = { -- set of errors indicating a socket-timeout
  ["timeout"] = true,      -- default LuaSocket timeout
  ["wantread"] = true,     -- LuaSec specific timeout
  ["wantwrite"] = true,    -- LuaSec specific timeout
}

-------------------------------------------------------------------------------
-- Coroutine based socket timeouts.
-------------------------------------------------------------------------------

local usertimeouts = setmetatable({}, {
    __mode = "k",
    __index = function(self, skt)
      -- if there is no timeout found, we insert one automatically,
      -- a 10 year timeout as substitute for the default "blocking" should do
      self[skt] = 10*365*24*60*60
      return self[skt]
    end,
  })

local useSocketTimeoutErrors = setmetatable({},{ __mode = "k" })


-- sto = socket-time-out
local sto_timeout, sto_timed_out, sto_change_queue, sto_error do

  local socket_register = setmetatable({}, { __mode = "k" })    -- socket by coroutine
  local operation_register = setmetatable({}, { __mode = "k" }) -- operation "read"/"write" by coroutine
  local timeout_flags = setmetatable({}, { __mode = "k" })      -- true if timedout, by coroutine


  local function socket_callback(co)
    local skt = socket_register[co]
    local queue = operation_register[co]

    -- flag the timeout and resume the coroutine
    timeout_flags[co] = true
    _resumable:push(co)

    -- clear the socket from the current queue
    if queue == "read" then
      _reading:remove(skt)
    elseif queue == "write" then
      _writing:remove(skt)
    else
      error("bad queue name; expected 'read'/'write', got: "..tostring(queue))
    end
  end


  -- Sets a socket timeout.
  -- Calling it as `sto_timeout()` will cancel the timeout.
  -- @param queue (string) the queue the socket is currently in, must be either "read" or "write"
  -- @param skt (socket) the socket on which to operate
  -- @return true
  function sto_timeout(skt, queue)
    local co = coroutine.running()
    socket_register[co] = skt
    operation_register[co] = queue
    timeout_flags[co] = nil
    if skt then
      copas.timeout(usertimeouts[skt], socket_callback)
    else
      copas.timeout(0)
    end
    return true
  end


  -- Changes the timeout to a different queue (read/write).
  -- Only usefull with ssl-handshakes and "wantread", "wantwrite" errors, when
  -- the queue has to be changed, so the timeout handler knows where to find the socket.
  -- @param queue (string) the new queue the socket is in, must be either "read" or "write"
  -- @return true
  function sto_change_queue(queue)
    operation_register[coroutine.running()] = queue
    return true
  end


  -- Responds with `true` if the operation timed-out.
  function sto_timed_out()
    return timeout_flags[coroutine.running()]
  end


  -- Returns the poroper timeout error
  function sto_error(err)
    return useSocketTimeoutErrors[coroutine.running()] and err or "timeout"
  end
end



-------------------------------------------------------------------------------
-- Coroutine based socket I/O functions.
-------------------------------------------------------------------------------

local function isTCP(socket)
  return string.sub(tostring(socket),1,3) ~= "udp"
end


function copas.settimeout(skt, timeout)

  if timeout ~= nil and type(timeout) ~= "number" then
    return nil, "timeout must be a 'nil' or a number"
  end

  if timeout and timeout < 0 then
    timeout = nil    -- negative is same as nil; blocking indefinitely
  end

  usertimeouts[skt] = timeout
  return true
end

-- reads a pattern from a client and yields to the reading set on timeouts
-- UDP: a UDP socket expects a second argument to be a number, so it MUST
-- be provided as the 'pattern' below defaults to a string. Will throw a
-- 'bad argument' error if omitted.
function copas.receive(client, pattern, part)
  local s, err
  pattern = pattern or "*l"
  local current_log = _reading_log
  sto_timeout(client, "read")

  repeat
    s, err, part = client:receive(pattern, part)

    if s then
      current_log[client] = nil
      sto_timeout()
      return s, err, part

    elseif not _isSocketTimeout[err] then
      current_log[client] = nil
      sto_timeout()
      return s, err, part

    elseif sto_timed_out() then
      current_log[client] = nil
      return nil, sto_error(err)
    end

    if err == "wantwrite" then -- wantwrite may be returned during SSL renegotiations
      current_log = _writing_log
      current_log[client] = gettime()
      sto_change_queue("write")
      coroutine.yield(client, _writing)
    else
      current_log = _reading_log
      current_log[client] = gettime()
      sto_change_queue("read")
      coroutine.yield(client, _reading)
    end
  until false
end

-- receives data from a client over UDP. Not available for TCP.
-- (this is a copy of receive() method, adapted for receivefrom() use)
function copas.receivefrom(client, size)
  local s, err, port
  size = size or UDP_DATAGRAM_MAX
  sto_timeout(client, "read")

  repeat
    s, err, port = client:receivefrom(size) -- upon success err holds ip address

    if s then
      _reading_log[client] = nil
      sto_timeout()
      return s, err, port

    elseif err ~= "timeout" then
      _reading_log[client] = nil
      sto_timeout()
      return s, err, port

    elseif sto_timed_out() then
      _reading_log[client] = nil
      return nil, sto_error(err)
    end

    _reading_log[client] = gettime()
    coroutine.yield(client, _reading)
  until false
end

-- same as above but with special treatment when reading chunks,
-- unblocks on any data received.
function copas.receivePartial(client, pattern, part)
  local s, err
  pattern = pattern or "*l"
  local current_log = _reading_log
  sto_timeout(client, "read")

  repeat
    s, err, part = client:receive(pattern, part)

    if s or (type(pattern) == "number" and part ~= "" and part ~= nil) then
      current_log[client] = nil
      sto_timeout()
      return s, err, part

    elseif not _isSocketTimeout[err] then
      current_log[client] = nil
      sto_timeout()
      return s, err, part

    elseif sto_timed_out() then
      current_log[client] = nil
      return nil, sto_error(err)
    end

    if err == "wantwrite" then
      current_log = _writing_log
      current_log[client] = gettime()
      sto_change_queue("write")
      coroutine.yield(client, _writing)
    else
      current_log = _reading_log
      current_log[client] = gettime()
      sto_change_queue("read")
      coroutine.yield(client, _reading)
    end
  until false
end

-- sends data to a client. The operation is buffered and
-- yields to the writing set on timeouts
-- Note: from and to parameters will be ignored by/for UDP sockets
function copas.send(client, data, from, to)
  local s, err
  from = from or 1
  local lastIndex = from - 1
  local current_log = _writing_log
  sto_timeout(client, "write")

  repeat
    s, err, lastIndex = client:send(data, lastIndex + 1, to)

    -- adds extra coroutine swap
    -- garantees that high throughput doesn't take other threads to starvation
    if (math.random(100) > 90) then
      current_log[client] = gettime()   -- TODO: how to handle this??
      if current_log == _writing_log then
        coroutine.yield(client, _writing)
      else
        coroutine.yield(client, _reading)
      end
    end

    if s then
      current_log[client] = nil
      sto_timeout()
      return s, err, lastIndex

    elseif not _isSocketTimeout[err] then
      current_log[client] = nil
      sto_timeout()
      return s, err, lastIndex

    elseif sto_timed_out() then
      current_log[client] = nil
      return nil, sto_error(err)
    end

    if err == "wantread" then
      current_log = _reading_log
      current_log[client] = gettime()
      sto_change_queue("read")
      coroutine.yield(client, _reading)
    else
      current_log = _writing_log
      current_log[client] = gettime()
      sto_change_queue("write")
      coroutine.yield(client, _writing)
    end
  until false
end

function copas.sendto(client, data, ip, port)
  -- deprecated; for backward compatibility only, since UDP doesn't block on sending
  return client:sendto(data, ip, port)
end

-- waits until connection is completed
function copas.connect(skt, host, port)
  skt:settimeout(0)
  local ret, err, tried_more_than_once
  sto_timeout(skt, "write")

  repeat
    ret, err = skt:connect(host, port)

    -- non-blocking connect on Windows results in error "Operation already
    -- in progress" to indicate that it is completing the request async. So essentially
    -- it is the same as "timeout"
    if ret or (err ~= "timeout" and err ~= "Operation already in progress") then
      _writing_log[skt] = nil
      sto_timeout()
      -- Once the async connect completes, Windows returns the error "already connected"
      -- to indicate it is done, so that error should be ignored. Except when it is the
      -- first call to connect, then it was already connected to something else and the
      -- error should be returned
      if (not ret) and (err == "already connected" and tried_more_than_once) then
        return 1
      end
      return ret, err

    elseif sto_timed_out() then
      _writing_log[skt] = nil
      return nil, sto_error(err)
    end

    tried_more_than_once = tried_more_than_once or true
    _writing_log[skt] = gettime()
    coroutine.yield(skt, _writing)
  until false
end

---
-- Peforms an (async) ssl handshake on a connected TCP client socket.
-- NOTE: replace all previous socket references, with the returned new ssl wrapped socket
-- Throws error and does not return nil+error, as that might silently fail
-- in code like this;
--   copas.addserver(s1, function(skt)
--       skt = copas.wrap(skt, sparams)
--       skt:dohandshake()   --> without explicit error checking, this fails silently and
--       skt:send(body)      --> continues unencrypted
-- @param skt Regular LuaSocket CLIENT socket object
-- @param sslt Table with ssl parameters
-- @return wrapped ssl socket, or throws an error
function copas.dohandshake(skt, sslt)
  ssl = ssl or require("ssl")
  local nskt, err = ssl.wrap(skt, sslt)
  if not nskt then return error(err) end
  local queue
  nskt:settimeout(0)  -- non-blocking on the ssl-socket
  copas.settimeout(nskt, usertimeouts[skt]) -- copy copas user-timeout to newly wrapped one
  sto_timeout(nskt, "write")

  repeat
    local success, err = nskt:dohandshake()

    if success then
      sto_timeout()
      return nskt

    elseif not _isSocketTimeout[err] then
      sto_timeout()
      return error(err)

    elseif sto_timed_out() then
      return nil, sto_error(err)

    elseif err == "wantwrite" then
      sto_change_queue("write")
      queue = _writing

    elseif err == "wantread" then
      sto_change_queue("read")
      queue = _reading

    else
      error(err)
    end

    coroutine.yield(nskt, queue)
  until false
end

-- flushes a client write buffer (deprecated)
function copas.flush()
end

-- wraps a TCP socket to use Copas methods (send, receive, flush and settimeout)
local _skt_mt_tcp = {
                   __tostring = function(self)
                                  return tostring(self.socket).." (copas wrapped)"
                                end,
                   __index = {

                   send = function (self, data, from, to)
                            return copas.send (self.socket, data, from, to)
                          end,

                   receive = function (self, pattern, prefix)
                               if usertimeouts[self.socket] == 0 then
                                 return copas.receivePartial(self.socket, pattern, prefix)
                               end
                               return copas.receive(self.socket, pattern, prefix)
                             end,

                   flush = function (self)
                             return copas.flush(self.socket)
                           end,

                   settimeout = function (self, time)
                                  return copas.settimeout(self.socket, time)
                                end,

                   -- TODO: socket.connect is a shortcut, and must be provided with an alternative
                   -- if ssl parameters are available, it will also include a handshake
                   connect = function(self, ...)
                     local res, err = copas.connect(self.socket, ...)
                     if res and self.ssl_params then
                       res, err = self:dohandshake()
                     end
                     return res, err
                   end,

                   close = function(self, ...) return self.socket:close(...) end,

                   -- TODO: socket.bind is a shortcut, and must be provided with an alternative
                   bind = function(self, ...) return self.socket:bind(...) end,

                   -- TODO: is this DNS related? hence blocking?
                   getsockname = function(self, ...) return self.socket:getsockname(...) end,

                   getstats = function(self, ...) return self.socket:getstats(...) end,

                   setstats = function(self, ...) return self.socket:setstats(...) end,

                   listen = function(self, ...) return self.socket:listen(...) end,

                   accept = function(self, ...) return self.socket:accept(...) end,

                   setoption = function(self, ...) return self.socket:setoption(...) end,

                   -- TODO: is this DNS related? hence blocking?
                   getpeername = function(self, ...) return self.socket:getpeername(...) end,

                   shutdown = function(self, ...) return self.socket:shutdown(...) end,

                   dohandshake = function(self, sslt)
                     self.ssl_params = sslt or self.ssl_params
                     local nskt, err = copas.dohandshake(self.socket, self.ssl_params)
                     if not nskt then return nskt, err end
                     self.socket = nskt  -- replace internal socket with the newly wrapped ssl one
                     return self
                   end,

               }}

-- wraps a UDP socket, copy of TCP one adapted for UDP.
local _skt_mt_udp = {__index = { }}
for k,v in pairs(_skt_mt_tcp) do _skt_mt_udp[k] = _skt_mt_udp[k] or v end
for k,v in pairs(_skt_mt_tcp.__index) do _skt_mt_udp.__index[k] = v end

_skt_mt_udp.__index.send        = function(self, ...) return self.socket:send(...) end

_skt_mt_udp.__index.sendto      = function(self, ...) return self.socket:sendto(...) end


_skt_mt_udp.__index.receive =     function (self, size)
                                    return copas.receive (self.socket, (size or UDP_DATAGRAM_MAX))
                                  end

_skt_mt_udp.__index.receivefrom = function (self, size)
                                    return copas.receivefrom (self.socket, (size or UDP_DATAGRAM_MAX))
                                  end

                                  -- TODO: is this DNS related? hence blocking?
_skt_mt_udp.__index.setpeername = function(self, ...) return self.socket:setpeername(...) end

_skt_mt_udp.__index.setsockname = function(self, ...) return self.socket:setsockname(...) end

                                    -- do not close client, as it is also the server for udp.
_skt_mt_udp.__index.close       = function(self, ...) return true end


---
-- Wraps a LuaSocket socket object in an async Copas based socket object.
-- @param skt The socket to wrap
-- @sslt (optional) Table with ssl parameters, use an empty table to use ssl with defaults
-- @return wrapped socket object
function copas.wrap (skt, sslt)
  if (getmetatable(skt) == _skt_mt_tcp) or (getmetatable(skt) == _skt_mt_udp) then
    return skt -- already wrapped
  end
  skt:settimeout(0)
  if not isTCP(skt) then
    return  setmetatable ({socket = skt}, _skt_mt_udp)
  else
    return  setmetatable ({socket = skt, ssl_params = sslt}, _skt_mt_tcp)
  end
end

--- Wraps a handler in a function that deals with wrapping the socket and doing the
-- optional ssl handshake.
function copas.handler(handler, sslparams)
  -- TODO: pass a timeout value to set, and use during handshake
  return function (skt, ...)
    skt = copas.wrap(skt)
    if sslparams then skt:dohandshake(sslparams) end
    return handler(skt, ...)
  end
end


--------------------------------------------------
-- Error handling
--------------------------------------------------

local _errhandlers = setmetatable({}, { __mode = "k" })   -- error handler per coroutine

local function _deferror(msg, co, skt)
  msg = ("%s (coroutine: %s, socket: %s)"):format(tostring(msg), tostring(co), tostring(skt))
  if type(co) == "thread" then
    -- regular Copas coroutine
    msg = debug.traceback(co, msg)
  else
    -- not a coroutine, but the main thread, this happens if a timeout callback
    -- (see `copas.timeout` causes an error (those callbacks run on the main thread).
    msg = debug.traceback(msg, 2)
  end
  print(msg)
end

function copas.setErrorHandler (err, default)
  if default then
    _deferror = err
  else
    _errhandlers[coroutine.running()] = err
  end
end

-- if `bool` is truthy, then the original socket errors will be returned in case of timeouts;
-- `timeout, wantread, wantwrite, Operation already in progress`. If falsy, it will always
-- return `timeout`.
function copas.useSocketTimeoutErrors(bool)
  useSocketTimeoutErrors[coroutine.running()] = not not bool -- force to a boolean
end

-------------------------------------------------------------------------------
-- Thread handling
-------------------------------------------------------------------------------

local function _doTick (co, skt, ...)
  if not co then return end

  -- if a coroutine was canceled/removed, don't resume it
  if _canceled[co] then
    _canceled[co] = nil -- also clean up the registry
    _threads[co] = nil
    return
  end

  local ok, res, new_q = coroutine.resume(co, skt, ...)

  if ok and res and new_q then
    new_q:insert (res)
    new_q:push (res, co)
  else
    if not ok then pcall (_errhandlers [co] or _deferror, res, co, skt) end
    if skt and copas.autoclose and isTCP(skt) then
      skt:close() -- do not auto-close UDP sockets, as the handler socket is also the server socket
    end
    _errhandlers [co] = nil
  end
end


-- accepts a connection on socket input
local function _accept(server_skt, handler)
  local client_skt = server_skt:accept()
  if client_skt then
    client_skt:settimeout(0)
    local co = coroutine.create(handler)
    _doTick(co, client_skt)
  end
end


-------------------------------------------------------------------------------
-- Adds a server/handler pair to Copas dispatcher
-------------------------------------------------------------------------------

do
  local function addTCPserver(server, handler, timeout)
    server:settimeout(timeout or 0)
    _servers[server] = handler
    _reading:insert(server)
  end

  local function addUDPserver(server, handler, timeout)
    server:settimeout(timeout or 0)
    local co = coroutine.create(handler)
    _reading:insert(server)
    _doTick(co, server)
  end


  function copas.addserver(server, handler, timeout)
    if isTCP(server) then
      addTCPserver(server, handler, timeout)
    else
      addUDPserver(server, handler, timeout)
    end
  end
end


function copas.removeserver(server, keep_open)
  local skt = server
  local mt = getmetatable(server)
  if mt == _skt_mt_tcp or mt == _skt_mt_udp then
    skt = server.socket
  end

  _servers:remove(skt)
  _reading:remove(skt)

  if keep_open then
    return true
  end
  return server:close()
end



-------------------------------------------------------------------------------
-- Adds an new coroutine thread to Copas dispatcher
-------------------------------------------------------------------------------
function copas.addthread(handler, ...)
  -- create a coroutine that skips the first argument, which is always the socket
  -- passed by the scheduler, but `nil` in case of a task/thread
  local thread = coroutine.create(function(_, ...) return handler(...) end)
  _threads[thread] = true -- register this thread so it can be removed
  _doTick (thread, nil, ...)
  return thread
end

function copas.removethread(thread)
  -- if the specified coroutine is registered, add it to the canceled table so
  -- that next time it tries to resume it exits.
  _canceled[thread] = _threads[thread or 0]
end



-------------------------------------------------------------------------------
-- Sleep/pause management functions
-------------------------------------------------------------------------------

-- yields the current coroutine and wakes it after 'sleeptime' seconds.
-- If sleeptime < 0 then it sleeps until explicitly woken up using 'wakeup'
function copas.sleep(sleeptime)
  coroutine.yield((sleeptime or 0), _sleeping)
end

-- Wakes up a sleeping coroutine 'co'.
function copas.wakeup(co)
  _sleeping:wakeup(co)
end



-------------------------------------------------------------------------------
-- Timeout management
-------------------------------------------------------------------------------

do
  local timeout_register = setmetatable({}, { __mode = "k" })
  local timerwheel = require("timerwheel").new({
      precision = TIMEOUT_PRECISION,                -- timeout precision 100ms
      ringsize = math.floor(60/TIMEOUT_PRECISION),  -- ring size 1 minute
      err_handler = function(...) return _deferror(...) end,
    })

  copas.addthread(function()
    while true do
      copas.sleep(TIMEOUT_PRECISION)
      timerwheel:step()
    end
  end)

  -- get the number of timeouts running
  function copas.gettimeouts()
    return timerwheel:count()
  end

  --- Sets the timeout for the current coroutine.
  -- @param delay delay (seconds), use 0 to cancel the timerout
  -- @param callback function with signature: `function(coroutine)` where coroutine is the routine that timed-out
  -- @return true
  function copas.timeout(delay, callback)
    local co = coroutine.running()
    local existing_timer = timeout_register[co]

    if existing_timer then
      timerwheel:cancel(existing_timer)
    end

    if delay > 0 then
      timeout_register[co] = timerwheel:set(delay, callback, co)
    else
      timeout_register[co] = nil
    end

    return true
  end

end


-------------------------------------------------------------------------------
-- main tasks: manage readable and writable socket sets
-------------------------------------------------------------------------------
-- a task is an object with a required method `step()` that deals with a
-- single step for that task.

local _tasks = {} do
  function _tasks:add(tsk)
    _tasks[#_tasks + 1] = tsk
  end
end


-- a task to check ready to read events
local _readable_task = {} do

  local function tick(skt)
    local handler = _servers[skt]
    if handler then
      _accept(skt, handler)
    else
      _reading:remove(skt)
      _doTick(_reading:pop(skt), skt)
    end
  end

  function _readable_task:step()
    for _, skt in ipairs(self._evs) do
      tick(skt)
    end
  end

  _tasks:add(_readable_task)
end


-- a task to check ready to write events
local _writable_task = {} do

  local function tick(skt)
    _writing:remove(skt)
    _doTick(_writing:pop(skt), skt)
  end

  function _writable_task:step()
    for _, skt in ipairs(self._evs) do
      tick(skt)
    end
  end

  _tasks:add(_writable_task)
end



-- sleeping threads task
local _sleeping_task = {} do

  function _sleeping_task:step()
    local now = gettime()

    local co = _sleeping:pop(now)
    while co do
      -- we're pushing them to _resumable, since that list will be replaced before
      -- executing. This prevents tasks running twice in a row with sleep(0) for example.
      -- So here we won't execute, but at _resumable step which is next
      _resumable:push(co)
      co = _sleeping:pop(now)
    end
  end

  _tasks:add(_sleeping_task)
end



-- resumable threads task
local _resumable_task = {} do

  function _resumable_task:step()
    -- replace the resume list before iterating, so items placed in there
    -- will indeed end up in the next copas step, not in this one, and not
    -- create a loop
    local resumelist = _resumable:clear_resumelist()

    for _, co in ipairs(resumelist) do
      _doTick(co)
    end
  end

  _tasks:add(_resumable_task)
end


-------------------------------------------------------------------------------
-- Checks for reads and writes on sockets
-------------------------------------------------------------------------------
local _select do

  local last_cleansing = 0
  local duration = function(t2, t1) return t2-t1 end

  _select = function(timeout)
    local err
    local now = gettime()

    _readable_task._evs, _writable_task._evs, err = socket.select(_reading, _writing, timeout)
    local r_evs, w_evs = _readable_task._evs, _writable_task._evs

    if duration(now, last_cleansing) > WATCH_DOG_TIMEOUT then
      last_cleansing = now

      -- Check all sockets selected for reading, and check how long they have been waiting
      -- for data already, without select returning them as readable
      for skt,time in pairs(_reading_log) do
        if not r_evs[skt] and duration(now, time) > WATCH_DOG_TIMEOUT then
          -- This one timedout while waiting to become readable, so move
          -- it in the readable list and try and read anyway, despite not
          -- having been returned by select
          _reading_log[skt] = nil
          r_evs[#r_evs + 1] = skt
          r_evs[skt] = #r_evs
        end
      end

      -- Do the same for writing
      for skt,time in pairs(_writing_log) do
        if not w_evs[skt] and duration(now, time) > WATCH_DOG_TIMEOUT then
          _writing_log[skt] = nil
          w_evs[#w_evs + 1] = skt
          w_evs[skt] = #w_evs
        end
      end
    end

    if err == "timeout" and #r_evs + #w_evs > 0 then
      return nil
    else
      return err
    end
  end
end



-------------------------------------------------------------------------------
-- Dispatcher loop step.
-- Listen to client requests and handles them
-- Returns false if no socket-data was handled, or true if there was data
-- handled (or nil + error message)
-------------------------------------------------------------------------------
function copas.step(timeout)
  -- Need to wake up the select call in time for the next sleeping event
  if not _resumable:done() then
    timeout = 0
  else
    timeout = math.min(_sleeping:getnext(), timeout or math.huge)
  end

  local err = _select(timeout)

  for _, tsk in ipairs(_tasks) do
    tsk:step()
  end

  if err then
    if err == "timeout" then
      return false
    end
    return nil, err
  end

  return true
end


-------------------------------------------------------------------------------
-- Check whether there is something to do.
-- returns false if there are no sockets for read/write nor tasks scheduled
-- (which means Copas is in an empty spin)
-------------------------------------------------------------------------------
function copas.finished()
  return #_reading == 0 and #_writing == 0 and _resumable:done() and _sleeping:done(copas.gettimeouts())
end


-------------------------------------------------------------------------------
-- Dispatcher endless loop.
-- Listen to client requests and handles them forever
-------------------------------------------------------------------------------
function copas.loop(initializer, timeout)
  if type(initializer) == "function" then
    copas.addthread(initializer)
  else
    timeout = initializer or timeout
  end

  copas.running = true
  while not copas.finished() do copas.step(timeout) end
  copas.running = false
end

return copas
