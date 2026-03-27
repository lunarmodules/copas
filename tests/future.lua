-- make sure we are pointing to the local copas first
package.path = string.format("../src/?.lua;%s", package.path)

local copas = require "copas"
local future = copas.future


local test_complete = false
copas.loop(function()

  -- get(): waits for task, returns true + results on success (pcall-style)
  do
    local f = future.addthread(function()
      copas.pause(0.05)
      return "hello", "world"
    end)
    local ok, a, b = f:get()
    assert(ok == true, "expected true on success")
    assert(a == "hello" and b == "world", "unexpected results: "..tostring(a)..", "..tostring(b))
    print("ok: get() success")
  end


  -- get(): returns false + errmsg when task errors
  do
    local f = future.addthread(function()
      error("boom")
    end)
    local ok, err = f:get()
    assert(ok == false, "expected false on error, got: "..tostring(ok))
    assert(type(err) == "string" and err:find("boom"), "expected 'boom' in error, got: "..tostring(err))
    print("ok: get() error propagation")
  end


  -- get() can be called multiple times on the same future
  do
    local f = future.addthread(function() return 42 end)
    local ok1, v1 = f:get()
    local ok2, v2 = f:get()
    assert(ok1 == true and v1 == 42, "first get() failed")
    assert(ok2 == true and v2 == 42, "second get() failed")
    print("ok: get() idempotent")
  end


  -- callable future: f(...) is equivalent to f:get(...)
  do
    local f = future.addthread(function() return "via call" end)
    local ok, v = f()
    assert(ok == true and v == "via call", "callable future failed")
    print("ok: future callable via __call")
  end


  -- multiple threads waiting on the same future all receive the result
  do
    local f = future.addthread(function()
      copas.pause(0.1)
      return "shared"
    end)
    local results = {}
    for i = 1, 5 do
      local idx = i
      copas.addthread(function()
        local ok, v = f:get()
        results[idx] = ok and v
      end)
    end
    copas.pause(0.3)
    for i = 1, 5 do
      assert(results[i] == "shared", "thread "..i.." did not get result, got: "..tostring(results[i]))
    end
    print("ok: multiple waiters on get()")
  end


  -- try(): returns PENDING while task is still running
  do
    local f = future.addthread(function()
      copas.pause(0.2)
      return "done"
    end)
    local status = f:try()
    assert(status == future.PENDING, "expected PENDING, got: "..tostring(status))
    f:get()  -- wait for completion
    print("ok: try() PENDING")
  end


  -- try(): returns SUCCESS + results after task completes
  do
    local f = future.addthread(function() return 1, 2, 3 end)
    f:get()
    local status, a, b, c = f:try()
    assert(status == future.SUCCESS, "expected SUCCESS, got: "..tostring(status))
    assert(a == 1 and b == 2 and c == 3, "unexpected results from try()")
    print("ok: try() SUCCESS")
  end


  -- try(): returns ERROR + errmsg after task errors
  do
    local f = future.addthread(function()
      error("oh no")
    end)
    f:get()
    local status, err = f:try()
    assert(status == future.ERROR, "expected ERROR, got: "..tostring(status))
    assert(type(err) == "string" and err:find("oh no"), "unexpected error message: "..tostring(err))
    print("ok: try() ERROR")
  end


  -- cancel(): cancels a pending task, get() returns false + "cancelled"
  do
    local task_ran = false
    local f = future.addthread(function()
      copas.pause(5)
      task_ran = true
      return "should not reach"
    end)
    local cancelled = f:cancel()
    assert(cancelled == true, "expected cancel() to return true")
    local ok, err = f:get()
    assert(ok == false, "expected false after cancel, got: "..tostring(ok))
    assert(err == "cancelled", "expected 'cancelled', got: "..tostring(err))
    copas.pause(0.1)
    assert(not task_ran, "task body should not have run after cancel()")
    print("ok: cancel() pending task")
  end


  -- cancel(): try() returns ERROR + "cancelled" after cancel
  do
    local f = future.addthread(function()
      copas.pause(5)
    end)
    f:cancel()
    local status, err = f:try()
    assert(status == future.ERROR, "expected ERROR after cancel, got: "..tostring(status))
    assert(err == "cancelled", "expected 'cancelled', got: "..tostring(err))
    print("ok: try() ERROR after cancel()")
  end


  -- cancel(): returns false if task already completed
  do
    local f = future.addthread(function() return "done" end)
    f:get()
    local cancelled = f:cancel()
    assert(cancelled == false, "expected cancel() to return false when already done")
    print("ok: cancel() on completed future returns false")
  end


  -- addnamedthread: returns a usable future
  do
    local f = future.addnamedthread("test-task", function() return "named" end)
    local ok, v = f:get()
    assert(ok == true and v == "named", "addnamedthread() failed")
    print("ok: addnamedthread()")
  end


  -- typo guard: accessing an unknown field throws a meaningful error
  do
    local ok, err = pcall(function() return future.PNEDING end)
    assert(not ok, "expected an error for unknown field")
    assert(err:find("future%.PNEDING"), "expected field name in error message, got: "..tostring(err))
    print("ok: typo guard on unknown field")
  end


  test_complete = true
end)
assert(test_complete, "test did not complete!")
print("test success!")
