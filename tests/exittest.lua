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
  copas.pause(0.1) -- wait until loop is running
  copas.pause(0.1) -- wait again to make sure its not the initial step in the loop
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
  copas.pause(0.1) -- wait until loop is running
  copas.pause(0.1) -- wait again to make sure its not the initial step in the loop
  print("","4 running...")
  testran = 4
  error("error on purpose")
end)
copas.loop()
assert(testran == 4, "Test 4 was not executed!")
print("4) success")

print("5) Testing exiting when a task permanently sleeps before the loop")
copas.addthread(function()
  print("","5 running...")
  testran = 5
  copas.pauseforever() -- sleep until explicitly woken up
end)
copas.loop()
assert(testran == 5, "Test 5 was not executed!")
print("5) success")

print("6) Testing exiting when a task permanently sleeps in the loop")
copas.addthread(function()
  copas.pause(0.1) -- wait until loop is running
  copas.pause(0.1) -- wait again to make sure its not the initial step in the loop
  print("","6 running...")
  testran = 6
  copas.pauseforever() -- sleep until explicitly woken up
end)
copas.loop()
assert(testran == 6, "Test 6 was not executed!")
print("6) success")

print("7) Testing exiting releasing the exitsemaphore (implicit, no call to copas.exit)")
copas.addthread(function()
  print("","7 running...")
  copas.addthread(function()
    copas.waitforexit()
    testran = 7
  end)
end)
copas.loop()
assert(testran == 7, "Test 7 was not executed!")
print("7) success")

print("8) Testing schduling new tasks while exiting (explicit exit by calling copas.exit)")
testran = 0
copas.addthread(function()
  print("","8 running...")
  copas.addthread(function()
    while true do
      copas.pause(0.1)
      testran = testran + 1
      print("count...")
      if testran == 3 then  -- testran == 3
        print("initiating exit...")
        copas.exit()
        break
      end
    end
  end)
  copas.addthread(function()
    copas.waitforexit()
    print("exit signal received...")
    testran = testran + 1   -- testran == 4
    copas.addthread(function()
      print("running new task from exit handler...")
      copas.pause(1)
      testran = testran + 1 -- testran == 5
      print("new task from exit handler done!")
    end)
  end)
end)
copas.loop()
assert(testran == 5, "Test 8 was not executed!")
print("8) success")
