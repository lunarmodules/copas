-- test normalization of the 'sslparams' table passed to copas.wrap()/copas.handler()
--
-- Covers the fix for https://github.com/lunarmodules/copas/issues/210:
--  * an empty (or otherwise malformed) sslparams table used to silently
--    disable TLS -- identical to passing nil -- even though the doc-comment
--    claimed it enabled TLS "with defaults". No such defaults exist (a
--    certificate is mandatory), so normalize_sslt() now only recognizes the
--    current {wrap=..., sni=...} shape by the presence of those two keys;
--    anything else (an empty table, a garbage-key table, or the legacy flat
--    luasec-context table) is passed straight through as 'wrap' parameters,
--    which LuaSec itself validates and errors on when actually used for a
--    handshake. This never fails open into silent plaintext.
-- Also checks the other supported shapes still normalize as before: no
-- params at all, the legacy flat luasec-context table, and the current
-- {wrap=..., sni=...} table.

local copas = require("copas")
local socket = require("socket")

local failures = 0

local function check(cond, msg)
  if cond then
    print("OK:     "..msg)
  else
    print("FAILED: "..msg)
    failures = failures + 1
  end
end

-- no ssl params at all: TLS fully disabled, no error
do
  local skt = copas.wrap(socket.tcp())
  check(skt.ssl_params.wrap == false, "nil sslparams: wrap is false")
  check(skt.ssl_params.sni == false, "nil sslparams: sni is false")
end

-- empty table: has neither 'wrap' nor 'sni' keys, so it is treated as a
-- (malformed) flat luasec-context table rather than silently disabling TLS.
-- It must never normalize to wrap==false, and using it for a handshake must
-- error rather than silently proceed unencrypted.
do
  local sslt = {}
  local skt = copas.wrap(socket.tcp(), sslt)
  check(skt.ssl_params.wrap == sslt, "empty sslparams table: wrap is the table itself, not false")
  check(skt.ssl_params.sni == false, "empty sslparams table: sni is false")

  local ok, err = pcall(skt.dohandshake, skt)
  check(not ok, "empty sslparams table: handshake throws instead of silently succeeding")
  check(tostring(err):match("create") ~= nil,
    "empty sslparams table: LuaSec's own error surfaces, got: "..tostring(err))
end

-- table with unrelated/misspelled keys: same as the empty-table case, this
-- must not be mistaken for the current {wrap=..., sni=...} format either.
do
  local sslt = { just_some_key = true }
  local skt = copas.wrap(socket.tcp(), sslt)
  check(skt.ssl_params.wrap == sslt, "garbage-key sslparams table: wrap is the table itself, not false")
  check(skt.ssl_params.sni == false, "garbage-key sslparams table: sni is false")

  local ok, err = pcall(skt.dohandshake, skt)
  check(not ok, "garbage-key sslparams table: handshake throws instead of silently succeeding")
  check(tostring(err):match("create") ~= nil,
    "garbage-key sslparams table: LuaSec's own error surfaces, got: "..tostring(err))
end

-- legacy flat table (luasec context params directly, no wrap/sni keys)
do
  local sslt = {
    mode = "client",
    protocol = "any",
  }
  local skt = copas.wrap(socket.tcp(), sslt)
  check(skt.ssl_params.wrap == sslt, "legacy sslparams: wrap is the sslparams table itself")
  check(skt.ssl_params.sni == false, "legacy sslparams: sni is false")
end

-- current-style table with both wrap and sni set
do
  local sslt = {
    wrap = { mode = "client", protocol = "any" },
    sni = { names = "myhost.com", strict = true },
  }
  local skt = copas.wrap(socket.tcp(), sslt)
  check(skt.ssl_params.wrap == sslt.wrap, "current sslparams: wrap matches provided table")
  check(skt.ssl_params.sni == sslt.sni, "current sslparams: sni matches provided table")
end

if failures > 0 then
  print(failures.." check(s) failed")
  os.exit(1)
end

print("all checks passed")
os.exit(0)
