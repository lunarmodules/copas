local copas = require("copas")
local https = require("copas.http")
local luasec = require("ssl.https")

local url = "https://www.google.nl"
local count, countto = 0, 999999

print("first the original LuaSec implementation;")
print(luasec.request(url))
print("\nNow move to async test...\n")

copas.addthread(function()
  while count<countto do
    copas.sleep(0)
    print(count)
    count = count + 1
  end
  --os.exit()  -- causes ugly error due to LuaSec not be closed properly
end)

copas.addthread(function()
  copas.sleep(0)  -- delay, so won't start the test until the copasloop started
  print("Starting request...")
  print(https.request("https://www.google.nl"))
  print("Finished request...")
  countto = count + 10 -- just do a few more and finish the test
end)

print("starting loop")
copas.loop()
