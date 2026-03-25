local copas = require("copas")
local semaphore = require("copas.semaphore")


-- nil-safe versions for pack/unpack
local _unpack = unpack or table.unpack
local unpack = function(t, i, j) return _unpack(t, i or 1, j or t.n or #t) end
local pack = function(...) return { n = select("#", ...), ...} end



-- Future class

local future = {}
future.__index = future

-- calling on the future executes the `get` method
future.__call = function(self, ...) return self:get(...) end


local function new_future()
  local self = setmetatable({
    results = nil, -- results will be stored here in a 'packed' table
    sema = semaphore.new(9999, 0, math.huge),
    coro = nil -- the coroutine that will execute the task
  }, future)

  return self
end


-- Waits for the task to complete and returns the results.
-- Can be called multiple times.
function future:get()
  if not self.results then
    self.sema:take(1, math.huge) -- wait until the result is ready
  end
  return unpack(self.results)
end


-- Checks if the results are ready.
-- Returns true/false, and if true, also returns the results.
function future:try()
  if not self.results then
    return false
  end

  return true, unpack(self.results)
end



-- Module table

local M = {}


function M.addnamedthread(name, func, ...)
  local f = new_future()

  f.coro = copas.addnamedthread(name, function(...)
    f.results = pack(func(...))     -- execute task, store all results
    f.sema:give(f.sema:get_wait())  -- release all waiting threads
  end, ...)

  return future
end


function M.addthread(func, ...)
  return M.addnamedthread(nil, func, ...)
end


return M
