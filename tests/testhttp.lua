local copas = require("copas")
local http = require("copas.http")

local count, countto = 0, 999999

copas.addthread(function()
  while count<countto do
    copas.sleep(0)
    print(count)
    count = count + 1
  end
  os.exit()  
end)

copas.addthread(function()
  copas.sleep(0)  -- delay, so won't start the test until the copasloop started
  print("Starting request...")
  print(copas.http.request("http://www.google.com"))
  print("Finished request...")
  countto = count + 10 -- just do a few more and finish the test
end)

print("starting loop")
copas.loop()
