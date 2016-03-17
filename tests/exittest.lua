print([[
Testing to automatically exit the copas loop when nothing remains to be done.
So none of the tests below should hang, as that means it did not exit...
=============================================================================

]])

local copas = require("copas")
local testran

print("1) Testing exiting when a task finishes before the loop even starts")
copas.addthread(function()
  print("","1 running...")
  testran = 1
end)
copas.loop()
assert(testran == 1, "Test 1 was not executed!")
print("1) success")

print("2) Testing exiting when a task finishes within the loop")
copas.addthread(function()
  copas.sleep(0.1) -- wait until loop is running
  print("","2 running...")
  testran = 2
end)
copas.loop()
assert(testran == 2, "Test 2 was not executed!")
print("2) success")

print("3) Testing exiting when a task fails before the loop even starts")
copas.addthread(function()
  print("","3 running...")
  testran = 3
  error("error on purpose")
end)
copas.loop()
assert(testran == 3, "Test 3 was not executed!")
print("3) success")

print("4) Testing exiting when a task fails in the loop")
copas.addthread(function()
  copas.sleep(0.1) -- wait until loop is running
  print("","4 running...")
  testran = 4
  error("error on purpose")
end)
copas.loop()
assert(testran == 4, "Test 4 was not executed!")
print("4) success")

