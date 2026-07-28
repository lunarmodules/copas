-- make sure we are pointing to the local copas first
package.path = string.format("../src/?.lua;%s", package.path)



local copas = require "copas"
local socket = require "socket"
local gettime = copas.gettime
local timer = copas.timer

local successes = 0

copas.loop(function()

  local count_t1 = 0
  local t1 = timer.new({
    delay = 0.5,
    recurring = true,
    params = "hello world",
    callback = function(timer_obj, params)
      -- let's ensure parameters get passed
      assert(params == "hello world", "expected: hello world")
      successes = successes + 1  -- 6 to come
      count_t1 = count_t1 + 1
      print(params .. " " .. count_t1)
    end,
  })
  -- succes count = 6

  local t2 = timer.new({
    delay = 0.2,  -- we'll override this with 0.1 below
    recurring = false,
    params = {
      start_time = gettime()
    },
    initial_delay = 0.1,  -- initial delay, only 0.1
    callback = function(timer_obj, params)
      assert(gettime() - params.start_time < 0.11, "didn't honour initial delay, or recurred")
      print("this seems to go well, and should print only once")
      successes = successes + 1  -- 1 to come
    end,
  })
  -- succes count = 7

  timer.new({
    delay = 3.3,  --> allows T1 to run 6 times
    callback = function(timer_obj, params)
      t1:cancel()
      local _, err = t2:cancel()
      assert(err == "not armed", "expected t2 to already be stopped")
      successes = successes + 1  -- 1 to come
      assert(count_t1 == 6, "expected t1 to run 6 times!")
      successes = successes + 1  -- 1 to come
      timer_obj:cancel()  -- cancel myself
    end,
  })
  -- succes count = 9

  timer.new({
    delay = 0.1,
    recurring = true,
    callback = function(timer_obj, params)
      -- re-arm myself (recurring), should not be possible
      local ok, err = timer_obj:arm(1)
      assert(err == "already armed", "expected myself to be already armed")
      assert(ok == nil, "expected 'ok' to be nil")
      print("failed to re-arm a recurring timer, so that's ok")
      successes = successes + 1  -- 1 to come
      assert(timer_obj:cancel())  -- cancel myself
    end,
  })
  -- succes count = 10

  local touched = false
  timer.new({
    delay = 0.1,
    recurring = false,
    callback = function(timer_obj, params)
      if touched == false then
        -- re-arm myself (non-recurring), should be possible
        local ok, err = timer_obj:arm(3)
        assert(ok == timer_obj)
        assert(err == nil, "expected 'err' to be nil")
        touched = gettime()
        print("re-armed a non-recurring timer, so that's ok")
        successes = successes + 1  -- 1 to come
      else
        print("a re-armed non-recurring timer executed, so that's ok")
        successes = successes + 1  -- 1 to come
        local t = math.abs(gettime() - touched - 3)
        assert(t < 0.01, "expected a 3 second delay for the rearmed timer. Got: "..(gettime() - touched))
        successes = successes + 1  -- 1 to come
      end
    end,
  })
  -- succes count = 13

  local count = 0
  local params_in = {}
  -- timer shouldn't be cancelled if its handler errors
  timer.new({
    name = "error-test",
    delay = 0.1,
    recurring = true,
    params = params_in,
    errorhandler = function(msg, co, skt)
      local errmsg = copas.gettraceback(msg, co, skt)
      assert(errmsg:find("error%-test"), "the threadname wasn't found")
      assert(errmsg:find("error 1!") or errmsg:find("error 2!"), "the error message wasn't found")
      --print(errmsg)
      successes = successes + 1
    end,
    callback = function(timer_obj, params)
      assert(params == params_in, "Params table wasn't passed along")
      count = count + 1
      if count == 2 then
        -- 2nd call, so we're done
        timer_obj:cancel()
      end
      error("error "..count.."!")
    end,
  })
  -- succes count = 15

  -- Regression test for https://github.com/lunarmodules/copas/issues/206
  -- Cancelling a recurring timer while its callback is yielded on socket I/O
  -- must let the in-progress callback resume and finish (just without
  -- rescheduling), not abandon it mid-flight.
  do
    local io_invocations = 0
    local io_callback_finished = false

    local receiver = socket.udp()
    receiver:setsockname("127.0.0.1", 0)
    local ip, port = receiver:getsockname()
    receiver = copas.wrap(receiver)

    local io_timer
    io_timer = timer.new({
      delay = 0.1,
      recurring = true,
      callback = function()
        io_invocations = io_invocations + 1
        local data = receiver:receive()  -- yields on socket I/O
        assert(data == "wakeup", "expected to receive 'wakeup', got: "..tostring(data))
        io_callback_finished = true
      end,
    })

    copas.addthread(function()
      -- wait until the timer callback is parked waiting on the socket read
      while io_invocations == 0 do
        copas.pause(0.01)
      end
      copas.pause(0.05) -- make sure it actually reached the yield point

      assert(io_timer:cancel())

      local sender = copas.wrap(socket.udp())
      sender:sendto("wakeup", ip, port)

      copas.pause(0.2) -- allow the in-progress callback to resume and finish
      assert(io_callback_finished, "in-progress callback was abandoned after cancel()")
      successes = successes + 1  -- 1 to come

      assert(io_invocations == 1, "timer rescheduled after being cancelled")
      successes = successes + 1  -- 1 to come
    end)
  end
  -- succes count = 17

end)

assert(successes == 17, "number of successes didn't match! got: "..successes)

-- Regression test for https://github.com/lunarmodules/copas/issues/213
-- A recurring timer that cancels-and-rearms itself from within its own
-- callback must not leak the cancelled (old-generation) coroutine into the
-- sleeping heap. Each leaked coroutine would sit there for its full delay,
-- consuming a slot until it (eventually) expires -- forever, for a delay of
-- math.huge, as in the original report.
-- Run in its own isolated loop so the sleeping-heap count isn't affected by
-- other tests' timers.
local leaktest_done = false

copas.loop(function()
  local rearm_count = 0
  local max_rearms = 5
  local baseline = copas.status().timer

  local leak_timer
  leak_timer = timer.new({
    delay = 2,  -- long enough that a leaked old-generation coroutine is still parked when checked
    initial_delay = 0,
    recurring = true,
    callback = function(timer_obj)
      rearm_count = rearm_count + 1
      if rearm_count <= max_rearms then
        assert(timer_obj:cancel())
        assert(timer_obj:arm(0))
      else
        assert(timer_obj:cancel())
      end
    end,
  })

  -- watchdog: without the fix, the leaked coroutines keep the loop alive
  -- until their delay expires (or forever, for math.huge). Bound the
  -- failure mode instead of letting the test suite hang.
  local watchdog
  watchdog = timer.new({
    delay = 5,
    callback = function()
      print("timer leak regression test (issue #213) did not complete within 5 seconds")
      os.exit(1)
    end,
  })

  copas.addthread(function()
    while rearm_count <= max_rearms do
      copas.pause(0.01)
    end
    copas.pause(0.05) -- let everything settle

    assert(leak_timer.cancelled, "expected the timer to be cancelled")
    local timer_count = copas.status().timer
    assert(timer_count <= baseline + 1,
      "leaked timer coroutines detected: expected around "..baseline..", got "..timer_count)

    watchdog:cancel()
    leaktest_done = true
  end)
end)

assert(leaktest_done, "timer leak regression test (issue #213) did not complete")
print("test success!")
