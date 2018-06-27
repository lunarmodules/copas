--- Test for removethread(thread)

-- make sure we are pointing to the local copas first
package.path = string.format("../src/?.lua;%s", package.path)

local copas = require("copas")
local socket = require("socket")

local t1 = copas.addthread(
    function()
        print("endless thread start")
        local n = 0
        while true do
           n = n + 1
           print("endless thread:",n)
           copas.sleep(0.5)
        end
    end)

copas.addthread(function()
   for i = 1, 5 do
      copas.sleep(0.6)
   end
   print("stopping endless thread externally")
   copas.removethread(t1)
end)

copas.loop()