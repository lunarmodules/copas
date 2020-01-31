local copas = require("copas")



local timer = {}
timer.__index = timer



do
  local function expire_func(self, initial_delay)
    copas.sleep(initial_delay)
    while true do
      if not self.cancelled then
        self:callback(self.params)
      end

      if (not self.recurring) or self.cancelled then
        -- clean up and exit the thread
        self.co = nil
        self.cancelled = true
        return
      end

      copas.sleep(self.delay)
    end
  end


  --- Arms the timer object.
  -- @param initial_delay (optional) the first delay to use, if not provided uses the timer delay
  -- @return timer object, nil+error, or throws an error on bad input
  function timer:arm(initial_delay)
    assert(initial_delay == nil or initial_delay >= 0, "delay must be greater than or equal to 0")
    if self.co then
      return nil, "already armed"
    end

    self.cancelled = false
    self.co = copas.addthread(expire_func, self, initial_delay or self.delay)
    return self
  end
end



--- Cancels a running timer.
-- @return timer object, or nil+error
function timer:cancel()
  if not self.co then
    return nil, "not armed"
  end

  if self.cancelled then
    return nil, "already cancelled"
  end

  self.cancelled = true
  copas.wakeup(self.co)       -- resume asap
  copas.removethread(self.co) -- will immediately drop the thread upon resuming
  self.co = nil
  return self
end



--- Creates a new timer object.
-- Note: the callback signature is: `function(timer_obj, params)`.
-- @param opts (table) `opts.delay` timer delay in seconds, `opts.callback` function to execute, `opts.recurring` boolean
-- `opts.params` (optional) this value will be passed to the timer callback, `opts.initial_delay` (optional) the first delay to use, defaults to `delay`.
-- @return timer object, or throws an error on bad input
function timer.new(opts)
  assert(opts.delay >= 0, "delay must be greater than or equal to 0")
  assert(type(opts.callback) == "function", "expected callback to be a function")
  return setmetatable({
    delay = opts.delay,
    callback = opts.callback,
    recurring = not not opts.recurring,
    params = opts.params,
    cancelled = false,
  }, timer):arm(opts.initial_delay)
end



return timer
