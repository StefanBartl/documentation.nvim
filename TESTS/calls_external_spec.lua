-- TESTS/calls_external_spec.lua — `core/calls.lua`'s `node.calls_external`,
-- the per-node "which functions of an external module did this node
-- actually call, and how often" breakdown behind the Deps view's enriched
-- external boxes.
--
-- Its own file, not a further addition to `docmap_spec.lua` (already near
-- Lua's 200-local ceiling per that file's own header) — mirrors
-- `tools_spec.lua`/`features_spec.lua`'s precedent for a new pipeline
-- feature. Fixture naming (`demo.app` requiring `plenary.async`) matches
-- `docmap_spec.lua`'s own existing external-require fixture on purpose,
-- since that file already establishes `plenary.async`/directory-shape as
-- this suite's running example for "a require outside the tree".

return function(H)
  local eq, ok = H.eq, H.ok
  local scan = require("documentation.core.scan")

  local function write(root, rel, lines)
    local abs = root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "calls_external spec: fixture must be writable")
    fd:write(table.concat(lines, "\n"))
    fd:close()
  end

  -- Every shape `calls.lua`'s header claims resolves internally has an
  -- external counterpart: `fs.read(x)` -> `async.run(x)` (bound alias),
  -- `require("…fs").read(x)` -> `require("plenary.job").new(x)` (inline).
  -- Two calls through the same alias exercise counting, not just presence.
  local root = H.tmpfile("_calls_external")
  write(root, "lua/demo/app/init.lua", {
    "---@module 'demo.app'",
    "--- The app.",
    'local async = require("plenary.async")',
    "local M = {}",
    "---Run it twice.",
    "function M.run(s)",
    "  async.run(s)",
    "  async.run(s)",
    '  require("plenary.job").new(s)',
    "  return s",
    "end",
    "return M",
  })
  -- A second node, requiring the same external module but never calling
  -- into it — `requires_external` still lists it (unchanged behaviour),
  -- `calls_external` must stay empty, not merely small.
  write(root, "lua/demo/quiet/init.lua", {
    "---@module 'demo.quiet'",
    "--- Requires plenary.async for its side effects only.",
    'local _ = require("plenary.async")',
    "local M = {}",
    "---Does nothing with it.",
    "function M.noop() end",
    "return M",
  })

  local ir = scan.scan({ root = root, source = "lua/demo", lua_root = "lua" })
  local app = ir.nodes["lua/demo/app"]
  local quiet = ir.nodes["lua/demo/quiet"]

  ok(app ~= nil, "fixture: demo.app scanned")
  eq(#app.calls_external, 2, "calls_external: one entry per distinct module/member pair")

  local by_key = {}
  for _, c in ipairs(app.calls_external) do
    by_key[c.module .. "#" .. (c.member or "")] = c
  end

  local run = by_key["plenary.async#run"]
  ok(run ~= nil, "calls_external: the aliased call resolves to its real module")
  eq(run.count, 2, "calls_external: two call sites through the same alias count as 2")

  local new_call = by_key["plenary.job#new"]
  ok(new_call ~= nil, "calls_external: the inline require('...').fn(...) shape resolves too")
  eq(new_call.count, 1, "calls_external: inline form counted correctly")

  -- No edge was invented for either — an external call has no node to
  -- point `to`, unlike an internal one.
  local invented = false
  for _, e in ipairs(ir.edges) do
    if e.kind == "call" and (e.to == "plenary.async" or e.to == "plenary.job") then
      invented = true
    end
  end
  ok(not invented, "calls_external: never produces a call edge to a module that isn't a node")

  ok(quiet ~= nil, "fixture: demo.quiet scanned")
  eq(
    #quiet.requires_external,
    1,
    "fixture sanity: demo.quiet's require is still recorded as external"
  )
  eq(
    #quiet.calls_external,
    0,
    "calls_external: a require kept for its side effects alone produces no entries"
  )

  -- Sorted deterministically: module, then member — verified against a
  -- node with more than one external module so the sort actually has
  -- something to prove.
  write(root, "lua/demo/multi/init.lua", {
    "---@module 'demo.multi'",
    "--- Calls into two different external modules.",
    'local job = require("plenary.job")',
    'local async = require("plenary.async")',
    "local M = {}",
    "---Uses both.",
    "function M.run(s)",
    "  async.run(s)",
    "  job.new(s)",
    "  return s",
    "end",
    "return M",
  })
  local ir2 = scan.scan({ root = root, source = "lua/demo", lua_root = "lua" })
  local multi = ir2.nodes["lua/demo/multi"]
  eq(#multi.calls_external, 2, "calls_external: two distinct modules on one node")
  eq(multi.calls_external[1].module, "plenary.async", "calls_external: sorted by module first")
  eq(multi.calls_external[2].module, "plenary.job", "calls_external: ...then the next module")
end
