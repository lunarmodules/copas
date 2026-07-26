-- test scheme validation and normalization in copas/http.lua
--
-- Covers the fix that:
--  * rejects non-string/unsupported request schemes before a connection
--    is attempted (instead of silently falling back to plain HTTP), and
--  * normalizes the scheme to lowercase (from the url and from an
--    explicit override) so mixed-case "HTTPS" URLs select the TLS
--    transport instead of being silently treated as plain HTTP.

local copas = require("copas")
local http = copas.http
local ltn12 = require("ltn12")

local failures = 0

local function check(cond, msg)
  if cond then
    print("OK:     "..msg)
  else
    print("FAILED: "..msg)
    failures = failures + 1
  end
end

-- helper: build a request table with a stub `create` so no real connection
-- is ever attempted; the stub records the (normalized) request table it
-- receives and aborts the request before any socket is opened.
local function stubrequest(url, overrides)
  local captured
  local reqt = {
    url = url,
    target = {},
    create = function(nreqt)
      captured = nreqt
      return nil, "test-abort-before-connect"
    end,
  }
  for k, v in pairs(overrides or {}) do
    reqt[k] = v
  end
  reqt.sink = ltn12.sink.table(reqt.target)
  local ok, err = http.request(reqt)
  return ok, err, captured
end

copas.addthread(function()

  -- non-string scheme (explicit override) is rejected before connecting
  do
    local ok, err, captured = stubrequest("http://localhost/", { scheme = 123 })
    check(ok == nil and tostring(err):match("invalid scheme") ~= nil,
      "non-string scheme is rejected, got: "..tostring(err))
    check(captured == nil, "no connection is attempted for an invalid scheme")
  end

  -- unsupported (but well-formed) scheme is rejected before connecting
  do
    local ok, err, captured = stubrequest("ftp://localhost/")
    check(ok == nil and tostring(err):match("unsupported scheme") ~= nil,
      "unsupported scheme is rejected, got: "..tostring(err))
    check(captured == nil, "no connection is attempted for an unsupported scheme")
  end

  -- mixed-case scheme from the url is normalized to lowercase
  do
    local _, _, captured = stubrequest("HTTPS://localhost/")
    check(captured and captured.scheme == "https",
      "mixed-case 'HTTPS' url scheme is normalized to lowercase, got: "..
      tostring(captured and captured.scheme))
  end

  -- mixed-case scheme passed as an explicit override is normalized too
  do
    local _, _, captured = stubrequest("http://localhost/", { scheme = "HtTp" })
    check(captured and captured.scheme == "http",
      "mixed-case explicit scheme override is normalized to lowercase, got: "..
      tostring(captured and captured.scheme))
  end

  -- once normalized, a "https" scheme must select the TLS transport,
  -- not silently fall back to plain HTTP
  do
    local create = http.getcreatefunc()
    local conn = create({ url = "https://localhost/", scheme = "https" })
    check(conn.ssl_params.wrap ~= false, "normalized 'https' scheme selects the TLS transport")
  end

  -- a plain "http" scheme must not select the TLS transport
  do
    local create = http.getcreatefunc()
    local conn = create({ url = "http://localhost/", scheme = "http" })
    check(conn.ssl_params.wrap == false, "'http' scheme does not select the TLS transport")
  end

  if failures > 0 then
    print(failures.." check(s) failed")
    os.exit(1)
  end

  print("all checks passed")
  os.exit(0)
end)

copas.loop()
