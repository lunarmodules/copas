--------------------------------------------------------------
-- Limits resource usage while executing tasks.
-- Tasks added will be run in parallel, with a maximum of 
-- simultaneous tasks to prevent consuming all/too many resources.
-- Every task added will immediately be scheduled (if there is room)
-- using the `wait` method one can wait for completion.

local copas = require("copas")
local pack = table.pack or function(...) return {n=select('#',...),...} end
local unpack = function(t) return (table.unpack or unpack)(t, 1, t.n or #t) end

local pcall = pcall
if _VERSION=="Lua 5.1" and not jit then     -- obsolete: only for Lua 5.1 compatibility
  pcall = require("coxpcall").pcall
end

-- Add a task to the queue, returns the coroutine created
-- identical to `copas.addthread`. Can be called while the 
-- set of tasks is executing.
local function add(self, task, ...)
  local carg = pack(...)
  local coro = copas.addthread(function()
      copas.sleep(-1)                            -- go to sleep until being woken
      local suc, err = pcall(task, unpack(carg)) -- start the task
      self:removethread(coroutine.running())           -- dismiss ourselves
      if not suc then error(err) end             -- rethrow error
    end)
  table.insert(self.queue, coro)                 -- store in list
  self:next()
  return coro
end

-- remove a task from the queue. Can be called while the 
-- set of tasks is executing. Will NOT stop the task if 
-- it is already running.
local function remove(self, coro)
  self.queue[coro] = nil
  if self.running[coro] then
    -- it is in the already running set
    self.running[coro] = nil
    self.count = self.count - 1
  else
    -- check the queue and remove if found
    for i, item in ipairs(self.queue) do
      if coro == item then 
        table.remove(self.queue, i)
        break
      end
    end    
  end  
  self:next()
end

-- schedules the next task (if any) for execution, signals completeness
local function nxt(self)
  while self.count < self.maxt do
    local coro = self.queue[1]
    if not coro then break end -- queue is empty, so nothing to add
    -- move it to running and restart the task
    table.remove(self.queue, 1)
    self.running[coro] = coro
    self.count = self.count + 1
    copas.wakeup(coro)
  end
  if self.count == 0 and next(self.waiting) then
    -- all tasks done, resume the waiting tasks so they can unblock/return
    for coro in pairs(self.waiting) do
      copas.wakeup(coro)
    end
  end
end

-- Waits for the tasks. Yields until all are finished
local function wait(self)
  if self.count == 0 then return end  -- There's nothing to do...
  local coro = coroutine.running()
  -- now store this coroutine (so we know which to wakeup) and go to sleep
  self.waiting[coro] = true
  copas.sleep(-1)
  self.waiting[coro] = nil
end

-- creats a new tasksrunner, with maximum maxt simultaneous threads
local function new(maxt)
  return {
    maxt = maxt or 99999,     -- max simultaneous tasks
    count = 0,                -- count of running tasks
    queue = {},               -- tasks waiting (list/array)
    running = {},             -- tasks currently running (indexed by coroutine)
    waiting = {},             -- coroutines, waiting for all tasks being finished (indexed by coro)
    addthread = add,
    removethread = remove,
    next = nxt,
    wait = wait,
  }
end

return { new = new }
  
