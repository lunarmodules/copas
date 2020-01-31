-- make sure we are pointing to the local copas first
package.path = string.format("../src/?.lua;%s", package.path)
local copas = require "copas"

local x

copas.loop(function()
  -- Copas initialization function
  x = true
end)

assert(x, "expected 'x' to be truthy")
print "test success!"
