-- Test for copas.wakeup() return value.
-- See https://github.com/lunarmodules/copas/issues/199
--
-- copas.wakeup() must report whether it actually woke a coroutine, so
-- callers (eg. copas.lock) can tell a stale/canceled coroutine from a
-- successfully woken one instead of assuming success unconditionally.

-- make sure we are pointing to the local copas first
package.path = string.format("../src/?.lua;%s", package.path)

local copas = require "copas"

local test_complete = false
copas.loop(function()

  -- waking a coroutine that is actually paused succeeds
  local resumed = false
  local co = copas.addthread(function()
    copas.pauseforever()
    resumed = true
  end)
  copas.pause() -- let 'co' actually reach pauseforever() before waking it
  local ok, err = copas.wakeup(co)
  assert(ok == true, "expected wakeup to return true, got: "..tostring(ok)..", "..tostring(err))
  copas.pause(0.1)
  assert(resumed, "expected the woken thread to have resumed")

  -- waking it again (it's no longer sleeping) fails
  local ok2, err2 = copas.wakeup(co)
  assert(ok2 == nil, "expected re-waking a finished coroutine to fail")
  assert(type(err2) == "string", "expected an error message, got: "..tostring(err2))

  -- waking a coroutine that was canceled (eg. copas.removethread, or
  -- future:cancel()) while sleeping fails, instead of silently no-op'ing
  local co2 = copas.addthread(function()
    copas.pauseforever()
  end)
  copas.removethread(co2)
  local ok3, err3 = copas.wakeup(co2)
  assert(ok3 == nil, "expected wakeup of a canceled coroutine to fail")
  assert(type(err3) == "string", "expected an error message, got: "..tostring(err3))

  -- waking a coroutine copas doesn't know about at all fails
  local co3 = coroutine.create(function() end)
  local ok4, err4 = copas.wakeup(co3)
  assert(ok4 == nil, "expected wakeup of an unrelated coroutine to fail")
  assert(type(err4) == "string", "expected an error message, got: "..tostring(err4))

  test_complete = true
end)
assert(test_complete, "test did not complete!")

print("test success!")
