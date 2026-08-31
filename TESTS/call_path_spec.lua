-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/call_path_spec.lua — `core/calls.lua`'s `path` and
-- `chain_confidence`: the call-graph traversal behind `:DocMap why`'s second
-- chain.
--
-- Its own file, not a further addition to `docmap_spec.lua` (already near
-- Lua's 200-local ceiling per that file's own header), on the precedent
-- `calls_external_spec.lua` set for a `core/calls.lua` feature.
--
-- What these assertions protect, in order of how quietly each would break:
--
--   1. **The two chains are not the same chain.** `deps.path` walks
--      `require` edges, this walks `call` edges, and the whole point of
--      building the second was that a reader asking "why are A and B
--      connected" usually means the second and was silently handed the
--      first. A fixture where they differ is the only way that stays true.
--   2. **"Loads but never calls" is reachable.** It is the finding the
--      feature exists to surface, and in the require graph alone it looks
--      exactly like a live dependency.
--   3. **A heuristic hop is not laundered into a fact.** `build` marks a
--      bare-name match `"heuristic"`; a chain is only as certain as its
--      least certain link, and reporting anything stronger would waste an
--      afternoon in exactly the place someone is deciding what is safe to
--      delete.

return function(H)
  local eq, ok = H.eq, H.ok
  local scan = require("documentation.core.scan")
  local calls = require("documentation.core.calls")
  local deps = require("documentation.core.deps")

  ---@param root string
  ---@param rel string
  ---@param lines string[]
  local function write(root, rel, lines)
    local abs = root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "call_path spec: fixture must be writable")
    fd:write(table.concat(lines, "\n"))
    fd:close()
  end

  -- A tree where the two graphs genuinely disagree:
  --
  --   requires:  top -> middle -> leaf,  and  top -> unused
  --   calls:     top.run -> middle.step -> leaf.work
  --
  -- `unused` is required by `top` and called by nobody. That is the case the
  -- require graph cannot tell apart from `leaf`.
  local root = H.tmpfile("_call_path")

  write(root, "lua/c/leaf/init.lua", {
    "---@module 'c.leaf'",
    "--- The bottom.",
    "local M = {}",
    "---Does the work.",
    "function M.work(x)",
    "  return x",
    "end",
    "return M",
  })
  write(root, "lua/c/middle/init.lua", {
    "---@module 'c.middle'",
    "--- The middle.",
    'local leaf = require("c.leaf")',
    "local M = {}",
    "---Steps down.",
    "function M.step(x)",
    "  return leaf.work(x)",
    "end",
    "return M",
  })
  write(root, "lua/c/unused/init.lua", {
    "---@module 'c.unused'",
    "--- Required for its side effects, called by nobody.",
    "local M = {}",
    "---Never reached from `top`.",
    "function M.idle()",
    "  return 0",
    "end",
    "return M",
  })
  write(root, "lua/c/top/init.lua", {
    "---@module 'c.top'",
    "--- The entry point.",
    'local middle = require("c.middle")',
    'local _unused = require("c.unused")',
    "local M = {}",
    "---Runs the chain.",
    "function M.run(x)",
    "  return middle.step(x)",
    "end",
    "return M",
  })

  local ir = scan.scan({ root = root, source = "lua/c", lua_root = "lua" })

  do
    -- The chain itself: two hops, function-precise, contiguous. A
    -- reconstruction bug in the parent walk shows up here and nowhere else.
    local chain = calls.path(ir, "lua/c/top", "lua/c/leaf")
    ok(chain, "calls.path: finds a call chain across two hops")
    eq(#chain, 2, "calls.path: ... and it is the shortest one")
    eq(chain[1].from, "lua/c/top", "calls.path: the chain starts at the source module")
    eq(chain[1].from_fn, "M.run", "calls.path: ... and names the calling function")
    eq(chain[1].to, chain[2].from, "calls.path: the chain is contiguous")
    eq(chain[2].to, "lua/c/leaf", "calls.path: and ends at the target")
    eq(chain[2].to_fn, "M.work", "calls.path: naming the function actually reached")
  end

  do
    -- The finding the feature exists for: `top` requires `unused`, so the
    -- require graph reports a live-looking dependency; nothing calls into it,
    -- so the call graph reports nothing. Both halves asserted together,
    -- because either one alone is the answer that misleads.
    ok(deps.path(ir, "lua/c/top", "lua/c/unused"), "loads: the require path exists")
    eq(
      calls.path(ir, "lua/c/top", "lua/c/unused"),
      nil,
      "calls: ... and nothing calls into it — loaded, not used"
    )
  end

  do
    -- Every hop here resolves through a bound alias, which `calls.lua`'s
    -- header lists as an exact shape. If this ever reports "heuristic", the
    -- resolution weakened and the chain's certainty claim went with it.
    local chain = calls.path(ir, "lua/c/top", "lua/c/leaf")
    eq(calls.chain_confidence(chain), "exact", "chain_confidence: all hops resolved exactly")
  end

  do
    -- One heuristic hop makes the whole chain heuristic. Constructed rather
    -- than fixtured: the rule is about the collapse, not about which shape
    -- produced the weak hop.
    eq(
      calls.chain_confidence({
        { confidence = "exact" },
        { confidence = "heuristic" },
        { confidence = "exact" },
      }),
      "heuristic",
      "chain_confidence: a chain is only as certain as its least certain link"
    )
    eq(calls.chain_confidence({}), "exact", "chain_confidence: an empty chain claims nothing weak")
  end

  do
    -- The degenerate and the absent cases, matching `deps.path`'s contract so
    -- the two traversals cannot answer the same shape of question differently.
    eq(
      #calls.path(ir, "lua/c/top", "lua/c/top"),
      0,
      "calls.path: a node reaches itself in zero hops"
    )
    eq(calls.path(ir, "lua/c/leaf", "lua/c/top"), nil, "calls.path: nil when unreachable")
    eq(calls.path(ir, "lua/c/top", "nope"), nil, "calls.path: nil for an unknown node")
    eq(calls.path(ir, "nope", "lua/c/top"), nil, "calls.path: nil for an unknown source")
  end

  do
    -- Direction matters and is not symmetric: `leaf` is reached from `top`,
    -- never the other way. A visited-set bug that let the walk run backwards
    -- would still find "a" path and would be wrong.
    ok(calls.path(ir, "lua/c/middle", "lua/c/leaf"), "calls.path: middle reaches leaf")
    eq(calls.path(ir, "lua/c/middle", "lua/c/top"), nil, "calls.path: ... but not the reverse")
  end
end
