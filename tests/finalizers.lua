--- Test for finalizers

local copas = require("copas")

local function check_table(expected, result)
  local l = 0
  for _, entry in ipairs(result) do
    l = math.max(l, #tostring(entry))
  end

  local passed = true
  for i = 1, math.max(#result, #expected) do
    if result[i] ~= expected[i] then
      for n = 1, math.max(#result, #expected) do
        local res = tostring(result[n]) .. string.rep(" ", l + 2)
        print(n, res:sub(1,l+2), expected[n], result[n] == expected[n] and "" or "  <--- failed")
      end
      passed = false
      break
    end
  end
  return passed
end

-- GC tester
local supported = false
setmetatable({}, {__gc = function(self) supported = true end})
collectgarbage()
collectgarbage()
print("GC supported:", supported)



-- Run multiple finalizers in the right order.
-- Include the proper task names
local ctx = {}
copas(function()
  copas.addnamedthread("finalizer-test", function()
    -- add finalizer
    copas.setfinalizer(function(myctx, coro)
      print("finalizer1 runs")
      table.insert(myctx, "finalizer 1 called: " .. copas.getthreadname())
    end, ctx)

    -- add another finalizer, to be called in reverse order
    copas.setfinalizer(function(myctx, coro)
      print("finalizer2 runs")
      table.insert(myctx, "finalizer 2 called: " .. copas.getthreadname())
    end, ctx)

    copas.setthreadname("test task")
    copas.setfinalizer(function(myctx, coro)
      print("finalizer3 runs")
      table.insert(myctx, "finalizer 3 called: " .. copas.getthreadname())
    end, ctx)

    table.insert(ctx, "task starting")
    copas.pause(1)
    table.insert(ctx, "task finished")
  end)
end)

assert(check_table({
  "task starting",
  "task finished",
  "finalizer 3 called: [finalizer]test task",
  "finalizer 2 called: [finalizer]finalizer-test",
  "finalizer 1 called: [finalizer]finalizer-test",
}, ctx), "test failed!")

print("test 1 success!")


-- run finalizer on a task that errors
local ctx = {}
copas(function()
  copas.addnamedthread("finalizer-test", function()
    -- add finalizer
    copas.setfinalizer(function(myctx, coro)
      print("finalizer1 runs")
      table.insert(myctx, "finalizer 1 called: " .. copas.getthreadname())
    end, ctx)

    -- add another finalizer, to be called in reverse order
    copas.setfinalizer(function(myctx, coro)
      print("finalizer2 runs")
      table.insert(myctx, "finalizer 2 called: " .. copas.getthreadname())
    end, ctx)

    copas.setthreadname("test task")
    copas.setfinalizer(function(myctx, coro)
      print("finalizer3 runs")
      table.insert(myctx, "finalizer 3 called: " .. copas.getthreadname())
    end, ctx)

    table.insert(ctx, "task starting")
    copas.pause(1)
    error("ooooops... (this error is on purpose!)")  --> here we throw an error so we have no normal exit
    table.insert(ctx, "task finished")
  end)
end)

assert(check_table({
  "task starting",
  "finalizer 3 called: [finalizer]test task",
  "finalizer 2 called: [finalizer]finalizer-test",
  "finalizer 1 called: [finalizer]finalizer-test",
}, ctx), "test failed!")

print("test 2 success!")
