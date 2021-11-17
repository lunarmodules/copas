-- make sure we are pointing to the local copas first
package.path = string.format("../src/?.lua;%s", package.path)
local now = require("socket").gettime


local copas = require "copas"
local Queue = require "copas.queue"



local test_complete = false
copas.loop(function()

  -- basic push/pop
  local q = Queue:new()
  q:push "hello"
  assert(q:pop() == "hello", "expected the input to be returned")

  -- yielding on pop when queue is empty
  local s = now()
  copas.addthread(function()
    copas.sleep(0.5)
    q:push("delayed")
  end)
  assert(q:pop() == "delayed", "expected a delayed result")
  assert(now() - s >= 0.5, "result was not delayed!")

  -- pop times out
  local ok, err = q:pop(0.5)
  assert(err == "timeout", "expected a timeout")
  assert(ok == nil)

  -- get_size returns queue size
  assert(q:get_size() == 0)
  q:push(1)
  assert(q:get_size() == 1)
  q:push(2)
  assert(q:get_size() == 2)
  q:push(3)
  assert(q:get_size() == 3)

  -- queue behaves as fifo
  assert(q:pop() == 1)
  assert(q:pop() == 2)
  assert(q:pop() == 3)

  -- stopping
  q:push(1)
  q:push(2)
  q:push(3)
  assert(q:stop())
  local count = 0
  local coro = q:add_worker(function(item)
    count = count + 1
  end)
  copas.sleep(0.1)
  assert(count == 3, "expected all 3 items handled")
  assert(coroutine.status(coro) == "dead", "expected thread to be gone")
  -- coro should be GC'able
  local weak = setmetatable({}, {__mode="v"})
  weak[{}] = coro
  coro = nil  -- luacheck: ignore
  collectgarbage()
  collectgarbage()
  assert(not next(weak))
  -- worker exited, so queue is destroyed now?
  ok, err = q:push()
  assert(err == "destroyed", "expected queue to be destroyed")
  assert(ok == nil)
  ok, err = q:pop()
  assert(err == "destroyed", "expected queue to be destroyed")
  assert(ok == nil)


  test_complete = true
end)

assert(test_complete, "test did not complete!")
print("test success!")
