local copas = require("copas")

local DEFAULT_TIMEOUT = 10

local semaphore = {}
semaphore.__index = semaphore


-- registry, semaphore indexed by the coroutines using them.
local registry = setmetatable({}, { __mode="kv" })


-- create a new semaphore
-- @param max maximum number of resources the semaphore can hold (this maximum does NOT include resources that have been given but not yet returned).
-- @param seconds (optional, default 10) default semaphore timeout in seconds
-- @param start (optional, default 0) the initial resources available
function semaphore.new(max, start, seconds)
  local timeout = tonumber(seconds or DEFAULT_TIMEOUT) or -1
  if timeout < 0 then
    error("expected timeout (2nd argument) to be a number greater than or equal to 0, got: " .. tostring(seconds), 2)
  end
  if max < 1 then
    error("expected max resources (1st argument) to be a number greater than 0, got: " .. tostring(max), 2)
  end

  local self = setmetatable({
      count = start or 0,
      max = max,
      timeout = timeout,
      q_tip = 1,    -- position of next entry waiting
      q_tail = 1,   -- position where next one will be inserted
      queue = {},
      to_flags = setmetatable({}, { __mode = "k" }), -- timeout flags indexed by coroutine
    }, semaphore)

  return self
end


-- Gives resources.
-- @param given (optional, default 1) number of resources to return. If more
-- than the maximum are returned then it will be capped at the maximum and
-- error "too many" will be returned.
function semaphore:give(given)
  local err
  given = given or 1
  local count = self.count + given
  --print("now at",count, ", after +"..given)
  if count > self.max then
    count = self.max
    err = "too many"
  end

  while self.q_tip < self.q_tail do
    local i = self.q_tip
    local nxt = self.queue[i] -- there can be holes, so nxt might be nil
    if not nxt then
      self.q_tip = i + 1
    else
      if count >= nxt.requested then
        -- release it
        self.queue[i] = nil
        self.to_flags[nxt.co] = nil
        count = count - nxt.requested
        self.q_tip = i + 1
        copas.wakeup(nxt.co)
      else
        break -- we ran out of resources
      end
    end
  end

  if self.q_tip == self.q_tail then  -- reset queue pointers if empty
    self.q_tip = 1
    self.q_tail = 1
  end

  self.count = count
  if err then
    return nil, err
  end
  return true
end



local function timeout_handler(co)
  local self = registry[co]
  --print("checking timeout ", co)

  for i = self.q_tip, self.q_tail do
    local item = self.queue[i]
    if item and co == item.co then
      self.queue[i] = nil
      self.to_flags[co] = true
      --print("marked timeout ", co)
      copas.wakeup(co)
      return
    end
  end
  -- nothing to do here...
end


-- Requests resources from the semaphore.
-- Waits if there are not enough resources available before returning.
-- @param requested (optional, default 1) the number of resources requested
-- @param timeout (optional, defaults to semaphore timeout) timeout in
-- seconds. If 0 it will either succeed or return immediately with error "timeout"
-- @return true
function semaphore:take(requested, timeout)
  requested = requested or 1
  if self.q_tail == 1 and self.count >= requested then
    -- nobody is waiting before us, and there is enough in store
    self.count = self.count - requested
    return true
  end

  if requested > self.max then
    return nil, "too many"
  end

  local to = timeout or self.timeout
  if to == 0 then
    return nil, "timeout"
  end

  -- get in line
  local co = coroutine.running()
  self.to_flags[co] = nil
  registry[co] = self
  copas.timeout(to, timeout_handler)

  self.queue[self.q_tail] = {
    co = co,
    requested = requested,
    --timeout = nil, -- flag indicating timeout
  }
  self.q_tail = self.q_tail + 1

  copas.sleep(-1) -- block until woken
  if self.to_flags[co] then
    -- a timeout happened
    self.to_flags[co] = nil
    return nil, "timeout"
  end

  copas.timeout(0)

  return true
end

-- returns current available resources
function semaphore:get_count()
  return self.count
end

-- returns total shortage for requested resources
function semaphore:get_wait()
  local wait = 0
  for i = self.q_tip, self.q_tail - 1 do
    wait = wait + ((self.queue[i] or {}).requested or 0)
  end
  return wait - self.count
end


return semaphore
