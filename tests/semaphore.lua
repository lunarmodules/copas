-- make sure we are pointing to the local copas first
package.path = string.format("../src/?.lua;%s", package.path)


local copas = require "copas"
local now = copas.gettime
local semaphore = copas.semaphore



local test_complete = false
copas.loop(function()

  local sema = semaphore.new(10, 5, 1)
  assert(sema:get_count() == 5)

  assert(sema:take(3))
  assert(sema:get_count() == 2)

  local ok, _, err
  local start = now()
  _, err = sema:take(3, 0) -- 1 too many, immediate timeout
  assert(err == "timeout", "expected a timeout")
  assert(now() - start < 0.001, "expected it not to block with timeout = 0")

  start = now()
  _, err = sema:take(10, 0) -- way too many, immediate timeout
  assert(err == "timeout", "expected a timeout")
  assert(now() - start < 0.001, "expected it not to block with timeout = 0")

  start = now()
  _, err = sema:take(11) -- more than 'max'; "too many" error
  assert(err == "too many", "expected a 'too many' error")
  assert(now() - start < 0.001, "expected it not to block")

  start = now()
  _, err = sema:take(10) -- not too many, let's timeout
  assert(err == "timeout", "expected a 'timeout' error")
  assert(now() - start > 1, "expected it to block for 1s")

  assert(sema:get_count() == 2)

  --validate async threads
  local state = 0
  copas.addthread(function()
    assert(sema:take(5))
    print("got the first 5!")
    state = state + 1
  end)
  copas.addthread(function()
    assert(sema:take(5))
    print("got the next 5!")
    state = state + 2
  end)
  copas.pause(0.1)
  assert(state == 0, "expected state to still be 0")
  assert(sema:get_count() == 2, "expected count to still have 2 resources")

  assert(sema:give(4))
  assert(sema:get_count() == 1, "expected count to now have 1 resource")
  copas.pause(0.1)
  assert(state == 1, "expected 1 from the first thread to be added to state")

  assert(sema:give(4))
  assert(sema:get_count() == 0, "gave 4 more, so 5 in total, releasing 5, leaves 0 as expected")
  copas.pause(0.1)
  assert(state == 3, "expected 2 from the 2nd thread to be added to state")


  ok, err = sema:give(100)
  assert(not ok)
  assert(err == "too many")
  assert(sema:get_count() == 10)

  -- validate destroying
  assert(sema:take(sema:get_count())) -- empty the semaphore
  assert(sema:get_count() == 0, "should be empty now")
  local state = 0
  copas.addthread(function()
    local ok, err = sema:take(5)
    if ok then
      print("got 5, this is unexpected")
    elseif err == "destroyed" then
      state = state + 1
    end
  end)
  copas.addthread(function()
    local ok, err = sema:take(5)
    if ok then
      print("got 5, this is unexpected")
    elseif err == "destroyed" then
      state = state + 1
    end
  end)
  copas.pause(0.1)
  assert(sema:destroy())
  copas.pause(0.1)
  assert(state == 2, "expected 2 threads to error with 'destroyed'")

  -- only returns errors from now on, on all methods
  ok, err = sema:destroy();   assert(ok == nil and err == "destroyed", "expected an error")
  ok, err = sema:give(1);     assert(ok == nil and err == "destroyed", "expected an error")
  ok, err = sema:take(1);     assert(ok == nil and err == "destroyed", "expected an error")
  ok, err = sema:get_count(); assert(ok == nil and err == "destroyed", "expected an error")



  -- timeouts get cancelled upon destruction
  -- we set a timeout to 0.5 seconds, then destroy the semaphore
  -- the timeout should not execute
  -- Reproduce https://github.com/lunarmodules/copas/issues/118
  local track_table = setmetatable({}, { __mode = "v" })
  local sema = semaphore.new(10, 0, 0.5)
  track_table.sema = sema
  local state = 0
  track_table.coro = copas.addthread(function()
    local ok, err = sema:take(1)
    if ok then
      print("got one, this is unexpected")
    elseif err == "destroyed" then
      state = state + 1
    end
  end)
  copas.pause(0.1)
  assert(sema:destroy())
  copas.pause(0.1)
  assert(state == 1, "expected 1 thread to error with 'destroyed'")
  sema = nil

  local errors = 0
  copas.setErrorHandler(function(msg)
    print("got error: "..tostring(msg))
    print("--------------------------------------")
    errors = errors + 1
  end, true)

  collectgarbage()  -- collect garbage to force eviction from the semaphore registry
  collectgarbage()

  copas.pause(0.5) -- wait for the timeout to expire if it is still set
  assert(errors == 0, "expected no errors")

  test_complete = true
end)
assert(test_complete, "test did not complete!")


-- Test 2: canceling a queued waiter must not permanently leak the
-- resources handed to it, nor starve legitimate waiters behind it.
-- See https://github.com/lunarmodules/copas/issues/199 (same root cause
-- as the copas.lock bug: `copas.wakeup()` failures were ignored).
local test2_complete = false
copas.loop(function()

  -- 2a: a lone canceled waiter must not leak the resources given to it
  local sema2 = semaphore.new(10, 0, 5)
  local canceled_co = copas.addthread(function()
    sema2:take(5)
  end)
  copas.pause(0.1) -- let it enqueue

  copas.removethread(canceled_co) -- simulate external cancellation

  assert(sema2:give(5))
  copas.pause(0.1)

  assert(sema2:get_count() == 5,
    "expected the 5 given resources to remain available, got: "..tostring(sema2:get_count()))

  -- 2b: a legitimate waiter behind a canceled one must still be served
  local sema3 = semaphore.new(10, 0, 5)
  local canceled_co2 = copas.addthread(function()
    sema3:take(5)
  end)
  local waiter_result
  copas.addthread(function()
    local ok, err = sema3:take(5)
    waiter_result = ok and "got it" or err
  end)
  copas.pause(0.1) -- let both enqueue

  copas.removethread(canceled_co2) -- simulate external cancellation

  assert(sema3:give(5))
  copas.pause(0.1)

  assert(waiter_result == "got it",
    "expected the legitimate waiter to be served, got: "..tostring(waiter_result))

  -- 2c: a canceled waiter requesting MORE than what's available must not
  -- block a legitimate waiter behind it that requests less; the canceled
  -- entry has to be dropped regardless of resource sufficiency, not just
  -- when there happen to be enough resources to satisfy its own request.
  local sema4 = semaphore.new(10, 0, 5)
  local canceled_co3 = copas.addthread(function()
    sema4:take(2) -- will be canceled while waiting for 2
  end)
  local waiter_result2
  copas.addthread(function()
    local ok, err = sema4:take(1) -- only needs 1
    waiter_result2 = ok and "got it" or err
  end)
  copas.pause(0.1) -- let both enqueue

  copas.removethread(canceled_co3) -- simulate external cancellation

  assert(sema4:give(1)) -- not enough for the canceled request (2), plenty for the real one (1)
  copas.pause(0.1)

  assert(waiter_result2 == "got it",
    "expected the smaller legitimate waiter to be served ahead of a stale bigger request, got: "
    ..tostring(waiter_result2))
  assert(sema4:get_count() == 0,
    "expected the 1 given resource to have gone to the waiter, got: "..tostring(sema4:get_count()))

  test2_complete = true
end)
assert(test2_complete, "test 2 did not complete!")


-- Test 3: get_wait() must not count queued waiters that were canceled
-- externally (eg. via copas.removethread) -- they will never consume the
-- resources handed to them, so counting their `requested` overstates how
-- much is actually needed to release everyone still legitimately waiting.
local test3_complete = false
copas.loop(function()

  local sema = semaphore.new(10, 0, 5)
  local canceled_co = copas.addthread(function() sema:take(1) end)
  copas.addthread(function() sema:take(1) end)
  copas.addthread(function() sema:take(1) end)
  copas.pause(0.1) -- let all 3 enqueue

  assert(sema:get_wait() == 3, "expected all 3 live waiters to be counted")

  copas.removethread(canceled_co) -- simulate external cancellation

  assert(sema:get_wait() == 2,
    "expected the canceled waiter to be excluded, got: "..tostring(sema:get_wait()))

  test3_complete = true
end)
assert(test3_complete, "test 3 did not complete!")


-- Test 4: release_all() must release every waiter regardless of how many
-- times `max` it takes to do so (unlike give(math.huge), which is capped
-- at `max` and strands the rest). See https://github.com/lunarmodules/copas/issues/203.
local test4_complete = false
copas.loop(function()

  local sema = semaphore.new(2, 0, 5) -- max = 2, well below the waiter count
  local released = 0
  for _ = 1, 5 do
    copas.addthread(function()
      assert(sema:take(1))
      released = released + 1
    end)
  end
  copas.pause(0.1) -- let all 5 enqueue

  sema:release_all()
  copas.pause(0.1)

  assert(released == 5, "expected all 5 waiters to be released, got: "..tostring(released))
  assert(sema:get_count() == 0,
    "expected no leftover balance after releasing everyone, got: "..tostring(sema:get_count()))

  -- release_all() combined with a canceled waiter mixed into the queue
  -- must not leave a stray leftover balance either (that would be the
  -- fixed get_wait() bug resurfacing through release_all()).
  local sema2 = semaphore.new(2, 0, 5)
  local canceled_co = copas.addthread(function() sema2:take(1) end)
  local released2 = 0
  for _ = 1, 3 do
    copas.addthread(function()
      assert(sema2:take(1))
      released2 = released2 + 1
    end)
  end
  copas.pause(0.1) -- let all 4 enqueue

  copas.removethread(canceled_co) -- simulate external cancellation

  sema2:release_all()
  copas.pause(0.1)

  assert(released2 == 3, "expected the 3 legitimate waiters to be released, got: "..tostring(released2))
  assert(sema2:get_count() == 0,
    "expected no leftover balance, got: "..tostring(sema2:get_count()))

  test4_complete = true
end)
assert(test4_complete, "test 4 did not complete!")

print("test success!")
