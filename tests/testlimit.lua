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

local handler = function(host)
  print("Starting: "..host.."...")
  local res, err = asynchttp(host)
  if not res then
    print("Error async: "..host.." failed, rerun test! "..tostring(err))
  else
    print("    Done: "..host)
  end
end


local mxt = 3  -- maximum simultaneous threads running

local taskset = limit.new(mxt)   
for _, host in ipairs(targets) do taskset:addthread(handler, host) end

copas.addthread(function()    
    taskset:wait()        -- blocks/yields until all tasks are done
    print("All tasks finished")
  end)  
copas.addthread(function()    
    taskset:wait()        -- blocks/yields until all tasks are done
    print("I was also waiting...")
  end)  


copas.loop()
