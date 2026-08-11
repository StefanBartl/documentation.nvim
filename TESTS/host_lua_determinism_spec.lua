-- TESTS/host_lua_determinism_spec.lua — the artifact must not depend on which
-- Lua rendered it.
--
-- `core/json.lua` exists so that identical input yields identical bytes. That
-- guarantee had a hole nobody could see from inside Neovim: LuaJIT renders an
-- integral float as `100`, PUC Lua 5.3+ as `100.0`, and `--check` byte-compares
-- the result. The first non-Neovim run of the full pipeline
-- (`standalone/docmap.lua` with a real parser) produced a map differing from
-- the Neovim one in exactly those characters and nothing else — which reads as
-- "the map is stale" and fails a pre-commit hook, for a tree nobody touched.
--
-- Two places leaked it, and both are covered here because they fail
-- independently: the encoder, which sees numbers, and `core/quicks.lua`, which
-- bakes them into `detail` strings with `%s` before the encoder ever runs.
--
-- These assertions pass trivially under LuaJIT. That is the point: they are
-- here to fail on the host where the bug is expressible, so the fix cannot
-- quietly regress the next time either file is edited.

return function(H)
  local eq, ok = H.eq, H.ok
  local json = require("documentation.core.json")

  -- An integral value must encode as an integer regardless of whether Lua
  -- calls it a float. `100 / 1` is a float in 5.3+ and an integer-valued
  -- number in LuaJIT; both must serialise as `100`.
  eq(json.encode(100), "100", "json: integer 100")
  eq(json.encode(100 / 1), "100", "json: integral float 100.0 encodes as 100")
  eq(json.encode(0 / 1), "0", "json: integral float 0.0 encodes as 0")
  eq(json.encode(85 / 1), "85", "json: integral float 85.0 encodes as 85")
  eq(json.encode(-7 / 1), "-7", "json: negative integral float encodes without a fraction")

  -- A genuinely fractional value keeps its fraction — the fix must not round.
  ok(
    json.encode(0.5):find("0.5", 1, true) ~= nil,
    "json: a real fraction is preserved, not truncated to an integer"
  )
  ok(
    json.encode(45.25):find("45.25", 1, true) ~= nil,
    "json: a two-decimal fraction survives encoding"
  )

  -- Nested through the container path, which is what the artifact actually
  -- exercises: percentages live inside quicks objects, not at top level.
  eq(
    json.encode({ value = 100 / 1, n = 85 / 1 }),
    '{"n":85,"value":100}',
    "json: integral floats inside an object encode as integers, keys sorted"
  )
  eq(
    json.encode({ 0 / 1, 50 / 1, 100 / 1 }),
    "[0,50,100]",
    "json: integral floats inside an array encode as integers"
  )

  -- Booleans and strings must be untouched by the number branch.
  eq(json.encode(true), "true", "json: booleans still encode as booleans")
  eq(json.encode(false), "false", "json: false is not confused with a number")

  -- The second leak: `quicks.lua` formats `detail` itself. Rather than
  -- reaching into a local, assert on the real `compute` output — a percent
  -- probe whose value is integral must render "100%", never "100.0%".
  local quicks = require("documentation.core.quicks")
  local ir = {
    order = { "lua/x" },
    nodes = {
      ["lua/x"] = {
        id = "lua/x",
        kind = "module",
        name = "x",
        path = "lua/x",
        source = "lua/x/init.lua",
        module = "x",
        summary = "A module with a summary.",
        body = "",
        children = {},
        depth = 0,
        types = {},
        functions = {},
        symbols = {},
        plugins = {},
        endpoints = {},
        requires = {},
        required_by = {},
        requires_external = {},
        stats = {
          files_lua = 1,
          files_md = 0,
          files_other = 0,
          functions = 0,
          lines = 10,
          modules = 1,
          namespaces = 0,
          symbols = 0,
          types = 0,
        },
      },
    },
    root = "lua/x",
    edges = {},
    tag_links = {},
    meta = { counts = { module = 1, namespace = 0, file = 1 } },
  }

  local result = quicks.compute(ir, {}, { root = "/tmp/x", source = "lua/x" })
  local all = {}
  for _, list in ipairs({ result.good or {}, result.bad or {} }) do
    for _, q in ipairs(list) do
      all[#all + 1] = q
    end
  end
  ok(#all > 0, "quicks: the fixture produces at least one verdict to inspect")

  local offenders = {}
  for _, q in ipairs(all) do
    -- `100.0%`, `0.0%` or a bare `85.0` are the exact shapes the PUC-Lua run
    -- emitted. A legitimate fraction like `45.5%` must NOT be flagged, so the
    -- pattern requires the fractional part to be a lone zero.
    if type(q.detail) == "string" and q.detail:match("%d%.0%f[%D]") then
      offenders[#offenders + 1] = ("%s -> %q"):format(q.id, q.detail)
    end
  end
  eq(
    #offenders,
    0,
    "quicks: no detail string carries a `.0` fraction (" .. (offenders[1] or "none") .. ")"
  )
end
