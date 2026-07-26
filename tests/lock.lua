-- make sure we are pointing to the local copas first
package.path = string.format("../src/?.lua;%s", package.path)



local copas = require "copas"
local Lock = copas.lock
local gettime = copas.gettime

local test_complete = false
copas.loop(function()

  local lock1 = Lock.new(nil, true)  -- not re-entrant
  assert(lock1:get())
  local s = gettime()
  local _, err = lock1:get(1)
  local duration = gettime() - s
  assert(err == "timeout", "got errror: "..tostring(err))
  assert(duration > 1 and duration < 1.2, string.format("expected timeout of 1 second, but took: %f",duration))

  -- let go and reacquire
  assert(lock1:release())
  local _, err = lock1:release()
  assert(err == "cannot release a lock not owned", "got error: "..tostring(err))

  assert(lock1:get())
  lock1:destroy()
  local _, err = lock1:release()
  assert(err == "destroyed", "got errror: "..tostring(err))


  -- let's scale, go grab a lock
  lock1 = assert(Lock.new(10))
  assert(lock1:get())

  local success_count = 0
  local timeout_count = 0
  local destroyed_count = 0
  -- now add another bunch of threads for the same lock
  local size = 750 -- must be multiple of 3 !!
  print("creating "..size.." threads hitting the lock...", gettime())
  local tracker = {}
  for i = 1, size do
    tracker[i] = true
    copas.addthread(function()
      local timeout
      if i > (size*2)/3 then
        timeout = 60    -- the ones to hit "destroyed"
      elseif i > size/3 and i <= (size*2)/3 then
        timeout = 2     -- the ones to hit "timeout"
      else
        timeout = 1     -- the ones to succeed
      end
      --print(i, "waiting...")
      local ok, err = lock1:get(timeout)
      if ok then
        --print(i, "got it!")
        success_count = success_count + 1
        if i == size/3 then
          copas.pause(3) -- keep it long enough for the next 500 to timeout
          --print(i, "releasing ")
          assert(lock1:release()) -- by now the 2nd 500 timed out
          --print(i, "destroying ")
          assert(lock1:destroy()) -- make the last 500 fail on "destroyed"
        else
          --print(i, "releasing ")
          assert(lock1:release())
        end
        tracker[i] = nil

      elseif err == "timeout" then
        --print(i, "timed out!")
        timeout_count = timeout_count + 1
        --if i == (size*2)/3 then
        --  copas.pause(2) -- to ensure thread 500 finished its sleep above
        --end
        tracker[i] = nil

      elseif err == "destroyed" then
        --print(i, "destroyed!")
        destroyed_count = destroyed_count + 1
        tracker[i] = nil

      else
        tracker[i] = nil
        error("didn't expect error: '"..tostring(err).."' thread "..i)
      end

    end)  -- added thread function
  end -- for loop
  print("releasing "..size.." threads...", gettime())
  assert(lock1:release())
  print("waiting to finish...")
  while next(tracker) do copas.pause(0.1) end
  -- check results
  print("success: ", success_count)
  print("timeout: ", timeout_count)
  print("destroyed: ", destroyed_count)
  assert(success_count == size/3)
  assert(timeout_count == size/3)
  assert(destroyed_count == size/3)

  test_complete = true
end)
assert(test_complete, "test did not complete!")


-- Test 2: canceling a queued waiter must not permanently transfer ownership
-- to it, locking out every legitimate waiter behind it forever.
-- See https://github.com/lunarmodules/copas/issues/199
local test2_complete = false
copas.loop(function()

  local lock2 = assert(Lock.new(5))
  assert(lock2:get()) -- owned by this (the main) coroutine

  -- queue a waiter that will be canceled (eg. via future:cancel()) while
  -- it is still waiting in line for the lock
  local canceled_co = copas.addthread(function()
    lock2:get()
  end)

  -- queue a legitimate waiter behind it
  local waiter_result
  copas.addthread(function()
    local ok, err = lock2:get()
    waiter_result = ok and "got it" or err
    if ok then
      assert(lock2:release())
    end
  end)

  copas.pause(0.1) -- let both threads enqueue behind the lock

  copas.removethread(canceled_co) -- simulate external cancellation

  assert(lock2:release()) -- should hand the lock to the legitimate waiter

  copas.pause(0.1)

  assert(waiter_result == "got it",
    "expected the legitimate waiter to get the lock, got: "..tostring(waiter_result))
  assert(lock2.owner == nil, "expected the lock to be free again")

  test2_complete = true
end)
assert(test2_complete, "test 2 did not complete!")

print("test success!")
