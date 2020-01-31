-- make sure we are pointing to the local copas first
package.path = string.format("../src/?.lua;%s", package.path)



local copas = require "copas"
local gettime = require("socket").gettime
local timer = require "copas.timer"


copas.loop(function()
  local count_t1 = 0
  local t1 = timer.new({
    delay = 0.5,
    recurring = true,
    callback = function(timer_obj, param)
      -- let's ensure parameters get passed
      assert(param == "hello world", "expected: hello world")
      count_t1 = count_t1 + 1
      print(param .. " " .. count_t1)
    end,
  }, "hello world")

  local t2 = timer.new({
    delay = 0.2,  -- we'll override this with 0.1 below
    recurring = false,
    callback = function(timer_obj, param)
      assert(gettime() - param.start_time < 0.11, "didn't honour initial delay, or recurred")
      print("this seems to go well, and should print only once")
    end,
  }, {
    start_time = gettime()
  }, 0.1) -- initial delay, only 0.1

  timer.new({
    delay = 3.3,  --> allows T1 to run 6 times
    callback = function(timer_obj, param)
      t1:cancel()
      local _, err = t2:cancel()
      assert(err == "not armed", "expected t2 to already be stopped")
      assert(count_t1 == 6, "expected t1 to run 6 times!")
      timer_obj:cancel()  -- cancel myself
    end,
  })

end)
print("test success!")
