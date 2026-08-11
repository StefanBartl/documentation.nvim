-- TESTS/api_spec.lua — `documentation.core.api`, the answers behind the
-- generated page's `/api/*` routes now that more than one host asks them.
--
-- The property under test is the contract both hosts depend on, not the
-- joins themselves (`browse_telemetry_spec.lua` and `browse_loaded_spec.lua`
-- already own those): every route answers with a *table*, never nil and
-- never an error, and says `available = false` plus a `reason` when there is
-- nothing to show. That is what lets the Telemetry and Loaded panels stay
-- visible in a project that has no data instead of disappearing — the
-- behaviour the desktop host was explicitly built around.
--
-- Deliberately runs against a root with no map at all: "nothing to show" is
-- the case with two hosts and no test, and the one a passing scan never
-- exercises.

return function(H)
  local eq, ok = H.eq, H.ok
  local api = require("documentation.core.api")

  local nowhere = { root = "/definitely/not/a/repository", out_dir = "docs/map" }

  -- ------------------------------------------------------------- routes
  ok(type(api.routes) == "table", "api: routes is a table")
  for _, name in ipairs({ "telemetry", "telemetry/snapshots", "loaded", "loaded/snapshots" }) do
    ok(type(api.routes[name]) == "function", "api: route " .. name .. " exists")
  end

  -- ------------------------------------------------- every route answers
  for name in pairs(api.routes) do
    local res, err = api.answer(name, nowhere, nil)
    eq(err, nil, "api: " .. name .. " does not error on a root with no map")
    ok(type(res) == "table", "api: " .. name .. " answers with a table")
    eq(res.available, false, "api: " .. name .. " reports available=false with no map")
    ok(type(res.reason) == "string" and res.reason ~= "", "api: " .. name .. " states a reason")
  end

  -- An unknown route is an error, not an empty answer: a host that asked
  -- for a route this build does not have must find out, rather than render
  -- an empty panel that looks like "no data".
  local bad, bad_err = api.answer("no-such-route", nowhere, nil)
  eq(bad, nil, "api: an unknown route returns no result")
  ok(type(bad_err) == "string", "api: an unknown route explains itself")
  ok(bad_err:find("telemetry", 1, true) ~= nil, "api: the error names the routes that do exist")

  -- --------------------------------------------------------- decode_param
  eq(api.decode_param(nil), nil, "decode_param: nil stays nil")
  eq(api.decode_param(""), nil, "decode_param: empty is nil, not an empty name")
  eq(api.decode_param("plain"), "plain", "decode_param: an ordinary name is unchanged")
  eq(api.decode_param("two+words"), "two words", "decode_param: + is a space")
  eq(api.decode_param("a%20b"), "a b", "decode_param: %20 is a space")
  -- The ordering property, and the reason it is written down: `%2B` decodes
  -- to a literal `+`, which a decoder that expanded `+` first would then
  -- corrupt into a space.
  eq(api.decode_param("a%2Bb"), "a+b", "decode_param: %2B survives as a literal +")
end
