-------------------------------------------------------------------------------
-- Coroutine-safe xpcall and pcall versions
--
-- Encapsulates the protected calls with a coroutine based loop, so errors can
-- be dealed without the usual pcall/xpcall issues with coroutines.
--
-- Authors: Roberto Ierusalimschy and Andre Carregal 
--
-- Copyright 2005 - Kepler Project (www.keplerproject.org)
-------------------------------------------------------------------------------

local function pack (...) return arg end

function coxpcall(f, err)
  local co = coroutine.create(f)
  while true do
    local results = pack(coroutine.resume(co, unpack(arg)))
    local status = results[1]
    table.remove (results, 1) -- remove status of coroutine.resume
    if not status then
      return false, copcall(err(unpack(results)))
    end
    if coroutine.status(co) == "suspended" then
      arg = pack(coroutine.yield(unpack(results)))
    else
      return true, unpack(results)
    end
  end
end

function copcall(f, ...)
  return coxpcall(function() return f(unpack(arg)) end, error) 
end