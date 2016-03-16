local copas = require("copas")
local asynchttp = require("copas.http").request
local limit = require("copas.limit")

local targets = {
  "http://www.google.com",
  "http://www.microsoft.com",
  "http://www.apple.com",
  "http://www.facebook.com",
  "http://www.yahoo.com",
}

local mxt = 3  -- maximum simultaneous threads running
local successes = 0
local working = 0

local function worker(host)
  print("Starting: "..host)
  working = working + 1

  if working > mxt then
    print("Error: too many threads running at once")
    os.exit(1)
  end

  local res, err = asynchttp(host)
  if not res or type(err) == "string" then
    print("Error: "..host.." failed: "..err)
    os.exit(1)
  else
    print("    Done: "..host)
    successes = successes + 1
    working = working - 1
  end
end

local taskset = limit.new(mxt)
local done = 0

local function watcher(index)
  taskset:wait()        -- blocks/yields until all tasks are done

  if successes ~= #targets then
    print(("Error: Taskset completed but only %d/%d tasks finished"):format(successes, #targets))
    os.exit(1)
  else
    print(("All tasks finished (%d)"):format(index))
    done = done + 1
  end
end

for _, host in ipairs(targets) do
  taskset:addthread(worker, host)
end

local watchers = 2

for i = 1, watchers do
  copas.addthread(watcher, i)
end

print("Starting loop")
copas.loop()

if done == watchers then
  print("Finished loop")
else
  print(("Error: Loop completed but only %d/%d watchers finished"):format(done, watchers))
  os.exit(1)
end
