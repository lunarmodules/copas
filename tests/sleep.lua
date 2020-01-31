-- check no memory leaks when sleeping

-- make sure we are pointing to the local copas first
package.path = string.format("../src/?.lua;%s", package.path)

local copas = require("copas")

local t1 = copas.addthread(
    function()
        copas.sleep(-1)  -- sleep until woken up
    end
)


-- prepare GC test
local validate_gc = setmetatable({
    [t1] = true,
  },{ __mode = "k" })

-- start test
copas.loop()

t1 = nil  -- luacheck: ignore
collectgarbage()
collectgarbage()

--check GC
assert(next(validate_gc) == nil, "the 'validate_gc' table should have been empty!")

print "test success!"
