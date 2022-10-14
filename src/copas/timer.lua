local copas = require("copas")

local xpcall = xpcall
local coroutine_running = coroutine.running

if _VERSION=="Lua 5.1" and not jit then     -- obsolete: only for Lua 5.1 compatibility
  xpcall = require("coxpcall").xpcall
  coroutine_running = require("coxpcall").running
end


local timer = {}
timer.__index = timer


local new_name do
  local count = 0

  function new_name()
    count = count + 1
    return "copas_timer_" .. count
  end
end


do
  local function expire_func(self, initial_delay)
    if self.errorhandler then
      copas.seterrorhandler(self.errorhandler)
    end
    copas.pause(initial_delay)
    while true do
      if not self.cancelled then
        if not self.recurring then
          -- non-recurring timer
          self.cancelled = true
          self.co = nil

          self:callback(self.params)
          return

        else
          -- recurring timer
          self:callback(self.params)
        end
      end

      if self.cancelled then
        -- clean up and exit the thread
        self.co = nil
        self.cancelled = true
        return
      end

      copas.pause(self.delay)
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
    self.co = copas.addnamedthread(self.name, expire_func, self, initial_delay or self.delay)
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


do
  -- xpcall error handler that forwards to the copas errorhandler
  local ehandler = function(err_obj)
    return copas.geterrorhandler()(err_obj, coroutine_running(), nil)
  end


  --- Creates a new timer object.
  -- Note: the callback signature is: `function(timer_obj, params)`.
  -- @param opts (table) `opts.delay` timer delay in seconds, `opts.callback` function to execute, `opts.recurring` boolean
  -- `opts.params` (optional) this value will be passed to the timer callback, `opts.initial_delay` (optional) the first delay to use, defaults to `delay`.
  -- @return timer object, or throws an error on bad input
  function timer.new(opts)
    assert(opts.delay >= 0, "delay must be greater than or equal to 0")
    assert(type(opts.callback) == "function", "expected callback to be a function")

    local callback = function(timer_obj, params)
      xpcall(opts.callback, ehandler, timer_obj, params)
    end

    return setmetatable({
      name = opts.name or new_name(),
      delay = opts.delay,
      callback = callback,
      recurring = not not opts.recurring,
      params = opts.params,
      cancelled = false,
      errorhandler = opts.errorhandler,
    }, timer):arm(opts.initial_delay)
  end
end



return timer
