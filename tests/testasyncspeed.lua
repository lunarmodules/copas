local copas = require("copas")
local synchttp = require("socket.http").request
local asynchttp = require("copas.http").request
local gettime = require("socket").gettime

local targets = {
  "http://www.google.com",
  "http://www.microsoft.com",
  "http://www.apple.com",
  "http://www.facebook.com",
  "http://www.yahoo.com",
}

local function sync(list)
  for _, host in ipairs(list) do
    res, err = synchttp(host)
    if not res then
      print("Error sync: "..host.." failed, rerun test!")
    else
      print("Sync host done: "..host)
    end
  end
end

local handler = function(host)
  res, err = asynchttp(host)
  if not res then
    print("Error async: "..host.." failed, rerun test!")
  else
    print("Async host done: "..host)
  end
end

local function async(list)
  for _, host in ipairs(list) do copas.addthread(handler, host) end
  copas.loop()
end

-- three times to remove caching differences
async(targets)
async(targets)
async(targets)
print("\nNow starting the real test...\n")

local t1 = gettime()
print("Sync:")
sync(targets)
local t2 = gettime()
print("Async:")
async(targets)
local t3 = gettime()

print("\nResults:")
print("========")
print("   Sync : ", t2-t1)
print("   Async: ", t3-t2)


