-- make sure we are pointing to the local copas first
package.path = string.format("../src/?.lua;%s", package.path)



local copas = require "copas"
local gettime = require("socket").gettime
local timer = require "copas.timer"

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

end)

assert(successes == 15, "number of successes didn't match! got: "..successes)
print("test success!")
