local copas = require("copas")
local gettime = require("socket").gettime

local DEFAULT_TIMEOUT = 10

local lock = {}
lock.__index = lock


-- registry, locks indexed by the coroutines using them.
local registry = setmetatable({}, { __mode="kv" })



--- Creates a new lock.
-- @param seconds (optional) default timeout in seconds when acquiring the lock (defaults to 10)
-- @param not_reentrant (optional) if truthy the lock will not allow a coroutine to grab the same lock multiple times
-- @return the lock object
function lock.new(seconds, not_reentrant)
  local timeout = tonumber(seconds or DEFAULT_TIMEOUT) or -1
  if timeout < 0 then
    error("expected timeout (1st argument) to be a number greater than or equal to 0, got: " .. tostring(seconds), 2)
  end
  return setmetatable({
            timeout = timeout,
            not_reentrant = not_reentrant,
            queue = {},
            q_tip = 0,  -- index of the first in line waiting
            q_tail = 0, -- index where the next one will be inserted
            owner = nil, -- coroutine holding lock currently
            call_count = nil, -- recursion call count
            errors = setmetatable({}, { __mode = "k" }), -- error indexed by coroutine
          }, lock)
end



do
  local destroyed_func = function()
    return nil, "destroyed"
  end

  local destroyed_lock_mt = {
    __index = function()
      return destroyed_func
    end
  }

  --- destroy a lock.
  -- Releases all waiting threads with `nil+"destroyed"`
  function lock:destroy()
    --print("destroying ",self)
    for i = self.q_tip, self.q_tail do
      local co = self.queue[i]
      if co then
        self.errors[co] = "destroyed"
        --print("marked destroyed ", co)
        copas.wakeup(co)
      end
    end
    if self.owner then
      self.errors[self.owner] = "destroyed"
      --print("marked destroyed ", co)
    end
    self.queue = {}
    self.q_tip = 0
    self.q_tail = 0
    self.destroyed = true

    setmetatable(self, destroyed_lock_mt)
    return true
  end
end


local function timeout_handler(co)
  local self = registry[co]

  for i = self.q_tip, self.q_tail do
    if co == self.queue[i] then
      self.queue[i] = nil
      self.errors[co] = "timeout"
      --print("marked timeout ", co)
      copas.wakeup(co)
      return
    end
  end
  -- if we get here, we own it currently, or we finished it by now, or
  -- the lock was destroyed. Anyway, nothing to do here...
end


--- Acquires the lock.
-- If the lock is owned by another thread, this will yield control, until the
-- lock becomes available, or it times out.
-- If `timeout == 0` then it will immediately return (without yielding).
-- @param timeout (optional) timeout in seconds, if given overrides the timeout passed to `new`.
-- @return wait-time on success, or nil+error+wait_time on failure. Errors can be "timeout", "destroyed", or "lock is not re-entrant"
function lock:get(timeout)
  local co = coroutine.running()
  local start_time

  -- is the lock already taken?
  if self.owner then
    -- are we re-entering?
    if co == self.owner then
      if self.not_reentrant then
        return nil, "lock is not re-entrant", 0
      else
        self.call_count = self.call_count + 1
        return 0
      end
    end

    self.queue[self.q_tail] = co
    self.q_tail = self.q_tail + 1
    timeout = timeout or self.timeout
    if timeout == 0 then
      return nil, "timeout", 0
    end

    -- set up timeout
    registry[co] = self
    copas.timeout(timeout, timeout_handler)

    start_time = gettime()
    copas.sleep(-1)

    local err = self.errors[co]
    self.errors[co] = nil

    --print("released ", co, err)
    if err ~= "timeout" then
      copas.timeout(0)
    end
    if err then
      self.errors[co] = nil
      return nil, err, gettime() - start_time
    end
  end

  -- it's ours to have
  self.owner = co
  self.call_count = 1
  return start_time and (gettime() - start_time) or 0
end


--- Releases the lock currently held.
-- Releasing a lock that is not owned by the current co-routine will return
-- an error.
-- returns true, or nil+err on an error
function lock:release()
  local co = coroutine.running()

  if co ~= self.owner then
    return nil, "cannot release a lock not owned"
  end

  self.call_count = self.call_count - 1
  if self.call_count > 0 then
    -- same coro is still holding it
    return true
  end

  if self.q_tail == self.q_tip then
    -- queue is empty
    self.owner = nil
    return true
  end

  -- need a loop, since an individual coroutine might have been removed
  -- so there might be holes
  while self.q_tip < self.q_tail do
    local next_up = self.queue[self.q_tip]
    if next_up then
      self.owner = next_up
      self.queue[self.q_tip] = nil
      self.q_tip = self.q_tip + 1
      copas.wakeup(next_up)
      return true
    end
    self.q_tip = self.q_tip + 1
  end
  -- queue is empty, reset pointers
  self.q_tip = 0
  self.q_tail = 0
  return true
end



return lock
