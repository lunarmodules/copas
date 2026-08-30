-- Implementation of coroutines that allows to do a yield to a specific coroutine.
-- The target coorutine must be up the coroutine stack of the yielding coroutine.

local pack, unpack do
  pack = table.pack or function(...) return {n=select('#', ...), ...} end
  local _unpack = table.unpack or unpack
  unpack = function(t, i, j) return _unpack(t, i or 1, j or t.n or #t) end
end


local _resume = coroutine.resume
local _yield = coroutine.yield
local _running = coroutine.running

local yieldto_marker = {} -- a marker to identify a yieldto call
local track = {} -- key is a coro, value is the coro to resume next
local resume

--- Yield to a specific coroutine.
-- @tparam coroutine target_co coroutine to yield to
-- @param ... arguments to pass to the coroutine, just as regular `yield`
-- @return the results of the regular `resume` call
local function _yieldto(source_co, target_co, ...)
  local results = pack(_yield(yieldto_marker, source_co, target_co, ...))
  if source_co == _running() then
    -- we reached the source again, just return results
    return unpack(results)
  end

  -- need to resume at least another level
  return resume(unpack(...))
end


local function yieldto(target_co, ...)
  return _yieldto(_running(), target_co, ...)
end

function resume(co, ...)
  local results = pack(_resume(co, ...))
  -- Two options, we got here because someone did:
  -- 1. coroutine.yield(...), or
  -- 2. coroutine.yield(yieldto_marker, source_co, target_co, ...)
  if results[1] ~= yieldto_marker then
    -- simple case, just be transparent with plain Lua-resume
    return unpack(results)
  end

  -- case 2
  local source_co = results[2]
  local target_co = results[3]
  local this_coroutine = _running()
  -- are we the target coroutine?
  if this_coroutine == target_co then
    -- yes, we are the target coroutine
    return unpack(results, 3, results.n)
  end

  -- we are not the target coroutine, we need to yield once more, up the stack.
  -- yield once again up to the target coroutine, and pass results to the source coroutine\
  error("implement this")
  return resume(source_co, _yield(yieldto_marker, target_co, this_coroutine, ...))
end



local coro1
local coro4 = coroutine.create(function()
    local i = 0
    while true do
      i = i + 1
      print("coro 4: yield:", i)
      coroutine.yield(i)
      --print("coro 4: yieldto coro1:", i)
      --yieldto(coro1, i)
    end
  end)

local coro3 = coroutine.create(function()
    local i = 0
    while true do
      i = i + 1
      local argin = "coro4in"..i
      print("coro3 passed to coro4:", argin)
      local ok, arg = coroutine.resume(coro4, argin)
      if not ok then error(arg) end
      print("coro3 received from coro4:", arg)
      if i == 2 then
        i = 0
        coroutine.yield("coro3 to coro2")
      end
    end
    print "coro3 done"
  end)

local coro2 = coroutine.create(function()
    local i = 0
    while true do
      i = i + 1
      local argin = "coro3in"..i
      print("coro2 passed to coro3:", argin)
      local ok, arg = coroutine.resume(coro3, argin)
      if not ok then error(arg) end
      print("coro2 received from coro3:", arg)
      if i == 2 then
        i = 0
        coroutine.yield("coro2 to coro1")
      end
    end
    print "coro2 done"
  end)

coro1 = coroutine.create(function()
    local i = 0
    while true do
      i = i + 1
      local argin = "coro2in"..i
      print("coro1 passed to coro2:", argin)
      local ok, arg = coroutine.resume(coro2, argin)
      if not ok then error(arg) end
      print("coro1 received:", arg)
      if i == 2 then
        break
      end
    end
    print "coro1 done"
  end)

print("coro1 result:",resume(coro1))
