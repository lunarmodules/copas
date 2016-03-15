local copas = require("copas")
local http = require("copas.http")

local function test_request(url, max_switches)
  print("Testing copas.http.request with url " .. url)
  local switches = 0
  local done = false

  copas.addthread(function()
    while switches < max_switches do
      copas.sleep(0)
      switches = switches + 1
    end

    if not done then
      print(("Error: Request not finished after %d thread switches"):format(switches))
      os.exit(1)
    end
  end)

  copas.addthread(function()
    copas.sleep(0)  -- delay, so won't start the test until the copasloop started
    print("Starting request")
    local content, code, headers, status = http.request(url)
    print(("Finished request after %d thread switches"):format(switches))

    if type(content) ~= "string" or type(code) ~= "number" or
        type(headers) ~= "table" or type(status) ~= "string" then
      print("Error: incorrect return values:")
      print(content)
      print(code)
      print(headers)
      print(status)
      os.exit(1)
    end

    print(("Status: %s, content: %d bytes"):format(status, #content))
    done = true
    max_switches = switches + 10 -- just do a few more and finish the test
  end)

  print("Starting loop")
  copas.loop()

  if done then
    print("Finished loop")
  else
    print("Error: Finished loop but request is not complete")
    os.exit(1)
  end
end

test_request("http://www.google.com", 1000000)
test_request("https://www.google.com", 1000000)
