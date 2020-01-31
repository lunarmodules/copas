--- Test for removethread(thread)

-- make sure we are pointing to the local copas first
package.path = string.format("../src/?.lua;%s", package.path)

local copas = require("copas")
--local socket = require("socket")

local t1 = copas.addthread(
    function()
        print("endless thread start")
        local n = 0
        while true do
           n = n + 1
           print("endless thread:",n)
           copas.sleep(0.5)
        end
    end)

local t2 = copas.addthread(function()
   for i = 1, 5 do
      copas.sleep(0.6)
   end
   print("stopping endless thread externally")
   copas.removethread(t1)
end)


-- prepare GC test
local validate_gc = setmetatable({
    [t1] = true,
    [t2] = true,
  },{ __mode = "k" })

-- start test
copas.loop()

t1 = nil  -- luacheck: ignore
t2 = nil  -- luacheck: ignore
collectgarbage()
collectgarbage()

--check GC
assert(next(validate_gc) == nil, "the 'validate_gc' table should have been empty!")
print "test success!"
