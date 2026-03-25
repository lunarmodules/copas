local copas = require("copas")
local semaphore = require("copas.semaphore")


-- nil-safe versions for pack/unpack
local _unpack = unpack or table.unpack
local unpack = function(t, i, j) return _unpack(t, i or 1, j or t.n or #t) end
local pack = function(...) return { n = select("#", ...), ...} end



-- Module table

local M = {}

M.SUCCESS = true
M.PENDING = false
M.ERROR   = "error"

setmetatable(M, {
  __index = function(_, k)
    error("unknown field 'future." .. tostring(k) .. "'", 2)
  end,
})



-- Future class

local future = {}
future.__index = future

-- calling on the future executes the `get` method
future.__call = function(self, ...) return self:get(...) end


local function new_future()
  local self = setmetatable({
    results = nil, -- results will be stored here in a 'packed' table (pcall-style: true/false prefix)
    sema = semaphore.new(9999, 0, math.huge),
    coro = nil -- the coroutine that will execute the task
  }, future)

  return self
end


-- Waits for the task to complete.
-- Returns like pcall: true + results on success, false + errmsg on error.
function future:get()
  if not self.results then
    self.sema:take(1, math.huge) -- wait until the result is ready
  end
  return unpack(self.results)
end


-- Non-blocking check on the future status.
-- Returns:
--   M.PENDING (false)             -- task not yet complete
--   M.SUCCESS (true), results...  -- task completed successfully
--   M.ERROR ("error"), errmsg     -- task failed with an error
function future:try()
  if not self.results then
    return M.PENDING
  end
  if self.results[1] then
    return M.SUCCESS, unpack(self.results, 2)
  else
    return M.ERROR, self.results[2]
  end
end


-- Cancels the task if it has not yet completed.
-- Returns true if cancelled, false if already done.
function future:cancel()
  if self.results then
    return false  -- already done (or already cancelled)
  end
  self.results = pack(false, "cancelled")
  self.sema:give(self.sema:get_wait())
  copas.removethread(self.coro)
  return true
end



-- Module implementation

-- Mimics copas.addnamedthread but returns a future instead of the coroutine.
function M.addnamedthread(name, func, ...)
  local f = new_future()

  f.coro = copas.addnamedthread(name, function(...)
    local results
    local ok, err = pcall(function(...) results = pack(true, func(...)) end, ...)
    if not ok then
      results = pack(false, err)
    end
    if not f.results then  -- don't overwrite a cancel
      f.results = results
      f.sema:give(f.sema:get_wait())
    end
  end, ...)

  return f
end


-- Mimica copas.addthread but returns a future instead of the coroutine.
function M.addthread(func, ...)
  return M.addnamedthread(nil, func, ...)
end


return M
