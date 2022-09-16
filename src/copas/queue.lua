local copas = require "copas"
local Sema = require "copas.semaphore"
local Lock = require "copas.lock"


local Queue = {}
Queue.__index = Queue


local new_name do
  local count = 0

  function new_name()
    count = count + 1
    return "copas_queue_" .. count
  end
end


-- Creates a new Queue instance
function Queue.new(opts)
  opts = opts or {}
  local self = {}
  setmetatable(self, Queue)
  self.name = opts.name or new_name()
  self.sema = Sema.new(10^9)
  self.head = 1
  self.tail = 1
  self.list = {}
  self.workers = setmetatable({}, { __mode = "k" })
  self.stopping = false
  self.worker_id = 0
  return self
end


-- Pushes an item in the queue (can be 'nil')
-- returns true, or nil+err ("stopping", or "destroyed")
function Queue:push(item)
  if self.stopping then
    return nil, "stopping"
  end
  self.list[self.head] = item
  self.head = self.head + 1
  self.sema:give()
  return true
end


-- Pops and item from the queue. If there are no items in the queue it will yield
-- until there are or a timeout happens (exception is when `timeout == 0`, then it will
-- not yield but return immediately)
-- Returns item, or nil+err ("timeout", or "destroyed")
function Queue:pop(timeout)
  local ok, err = self.sema:take(1, timeout)
  if not ok then
    return ok, err
  end
  local item = self.list[self.tail]
  self.tail = self.tail + 1
  if self.tail == self.head then
    -- reset pointers
    self.tail = 1
    self.head = 1
    if self.stopping then
      -- we're stopping and last item being returned, so we're done
      self:destroy()
    end
  end
  return item
end


-- return the number of items left in the queue
function Queue:get_size()
  return self.head - self.tail
end


-- instructs the queue to stop. Will not accept any more 'push' calls.
-- will autocall 'destroy' when the queue is empty.
-- returns immediately. See `finish`
function Queue:stop()
  if not self.stopping then
    self.stopping = true
    self.lock = Lock.new()
    self.lock:get() -- close the lock
    if self:get_size() == 0 then
      -- queue is already empty, so "pop" function cannot call destroy on next
      -- pop, so destroy now.
      self:destroy()
    end
  end
  return true
end


-- Finishes a queue. Calls stop and then waits for the queue to run empty (and be
-- destroyed) before returning. returns true or nil+err ("timeout", or "destroyed")
-- Parameter no_destroy_on_timeout indicates if the queue is not to be forcefully
-- destroyed on a timeout.
function Queue:finish(timeout, no_destroy_on_timeout)
  self:stop()
  local _, err = self.lock:get(timeout)
  -- the lock never gets released, only destroyed, so we have to check the error string
  if err == "timeout" then
    if not no_destroy_on_timeout then
      self:destroy()
    end
    return nil, err
  end
  return true
end


do
  local destroyed_func = function()
    return nil, "destroyed"
  end

  local destroyed_queue_mt = {
    __index = function()
      return destroyed_func
    end
  }

  -- destroys a queue immediately. Abandons what is left in the queue.
  -- Releases all waiting threads with `nil+"destroyed"`
  function Queue:destroy()
    if self.lock then
      self.lock:destroy()
    end
    self.sema:destroy()
    setmetatable(self, destroyed_queue_mt)
    return true
  end
end


-- adds a worker that will handle whatever is passed into the queue. Can be called
-- multiple times to add more workers.
-- The threads automatically exit when the queue is destroyed.
-- worker function signature: `function(item)` (Note: worker functions run
-- unprotected, so wrap code in an (x)pcall if errors are expected, otherwise the
-- worker will exit on an error, and queue handling will stop)
-- Returns the coroutine added.
function Queue:add_worker(worker)
  assert(type(worker) == "function", "expected worker to be a function")
  local coro

  self.worker_id = self.worker_id + 1
  local worker_name = self.name .. ":worker_" .. self.worker_id

  coro = copas.addnamedthread(worker_name, function()
    while true do
      local item = self:pop(10*365*24*60*60) -- wait forever (10yr)
      if not item then
        break -- queue destroyed, exit
      end
      worker(item)
    end
    self.workers[coro] = nil
  end)

  self.workers[coro] = true
  return coro
end

-- returns a list/array of current workers (coroutines) handling the queue.
-- (only the workers added by `add_worker`, and still active, will be in this list)
function Queue:get_workers()
  local lst = {}
  for coro in pairs(self.workers) do
    if coroutine.status(coro) ~= "dead" then
      lst[#lst+1] = coro
    end
  end
  return lst
end

return Queue
