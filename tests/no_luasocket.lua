-- make sure we are pointing to the local copas first
package.path = string.format("../src/?.lua;%s", package.path)

print([[
Testing to run Copas without LuaSocket, just LuaSystem
=============================================================================
]])

-- patch require to no longer load luasocket
local _require = require
_G.require = function(name)
  if name == "socket" then
    error("luasocket is not allowed in this test")
  end
  return _require(name)
end


local copas = require "copas"
local timer = copas.timer

local successes = 0

local t1 -- luacheck: ignore

copas.loop(function()

  t1 = timer.new({
    delay = 0.1,
    recurring = true,
    callback = function(timer_obj, params)
      successes = successes + 1  -- 6 to come
      if successes == 6 then
        timer_obj:cancel()
      end
    end,
  })
  -- succes count = 6

end)


assert(successes == 6, "number of successes didn't match! got: "..successes)
print("test success!")
