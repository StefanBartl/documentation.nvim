-- TESTS/api_surface_spec.lua — the Analysis tab's API-surface panel.
--
-- Asserted against the *rendered page*, the same way `payload_contract_spec`
-- does: what a reader gets is the HTML, and the panel is JavaScript embedded
-- in a Lua string, so there is no intermediate worth testing instead.
--
-- The three things that would break quietly:
--
--   1. **A tool name known in one place and not the other.** `atool` is
--      validated in two separate lists and dispatched in a third. A panel
--      whose button exists and whose state validator rejects it silently
--      falls back to Test coverage, which looks like a click that did
--      nothing.
--   2. **The honest limits disappearing.** "No caller here" is not "unused",
--      and `internal` is a declared fact rather than an inferred one. Both
--      sentences are the feature as much as the table is — a surface panel
--      that overstates what it knows is worse than no panel.
--   3. **`internal` being ignored.** It is the one field that decides what
--      the list even is.

return function(H)
  local eq, ok = H.eq, H.ok
  local docmap = require("documentation")

  local root = vim.fn.tempname()
  vim.fn.mkdir(root .. "/lua/surf", "p")

  local function write(rel, body)
    local path = root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    local fd = assert(io.open(path, "wb"))
    fd:write(body)
    fd:close()
  end

  -- Two modules: `api` publishes `entry` (called from `user`) and `orphan`
  -- (called by nobody), plus `hidden`, which is tagged internal.
  write("lua/surf/api.lua", table.concat({
    "---@module 'surf.api'",
    "--- Published surface.",
    "local M = {}",
    "---Entry point.",
    "---@return nil",
    "function M.entry() end",
    "---Nothing in this tree calls this one.",
    "---@return nil",
    "function M.orphan() end",
    "---An implementation detail.",
    "---@internal",
    "---@return nil",
    "function M.hidden() end",
    "return M",
  }, "\n") .. "\n")
  write("lua/surf/user.lua", table.concat({
    "---@module 'surf.user'",
    "--- Calls into the surface.",
    "local api = require('surf.api')",
    "local M = {}",
    "---Uses the entry point.",
    "---@return nil",
    "function M.go() api.entry() end",
    "return M",
  }, "\n") .. "\n")

  local opts = require("documentation.config").build(root, { source = "lua/surf" })
  local ir, findings = docmap.scan_full(opts)
  local html = docmap.render.html(ir, findings, opts)

  -- 1. The tool is known everywhere it has to be known.
  ok(html:find('data-atool="api"', 1, true), "api panel: the button exists")
  ok(html:find("renderAnalysisApi", 1, true), "api panel: the renderer exists")
  ok(
    html:find('if(atool === "api") return renderAnalysisApi();', 1, true),
    "api panel: it is dispatched"
  )
  -- Both validator lists, which are separate and have drifted before. Counted
  -- rather than merely found: one occurrence would mean only one list knows.
  local seen = 0
  for _ in html:gmatch('=== "api"') do
    seen = seen + 1
  end
  ok(seen >= 3, ("api panel: `api` is accepted everywhere it is checked (%d)"):format(seen))

  -- 2. The honest limits are in the page, verbatim enough to notice removal.
  ok(
    html:find("No caller here does not mean unused", 1, true),
    "api panel: says what a zero in its own column does not mean"
  )
  ok(
    html:find("Internal is declared, never inferred", 1, true),
    "api panel: says what its own filter depends on"
  )

  -- 3. `internal` decides the list. Asserted on the IR the page is built
  -- from, since the rows themselves are produced by JavaScript at view time.
  local api_node
  for _, id in ipairs(ir.order) do
    if ir.nodes[id].module == "surf.api" then
      api_node = ir.nodes[id]
    end
  end
  ok(api_node ~= nil, "api panel: the fixture produced the module it needs")

  local by_name = {}
  for _, fn in ipairs(api_node.functions) do
    by_name[fn.name] = fn
  end
  ok(by_name["M.hidden"] ~= nil, "api panel: the internal function was extracted at all")
  eq(by_name["M.hidden"].internal, true, "api panel: ... and carries the flag the panel filters on")
  eq(by_name["M.entry"].internal, false, "api panel: a published function does not")

  -- 4. The call edge the "Callers here" column counts, and the absence the
  -- column reports as none. Same key shape the panel builds (`to`/`to_fn`).
  local into_entry, into_orphan = 0, 0
  for _, e in ipairs(ir.edges or {}) do
    if e.kind == "call" and e.to == api_node.id and e.from ~= e.to then
      if e.to_fn == "M.entry" then
        into_entry = into_entry + 1
      elseif e.to_fn == "M.orphan" then
        into_orphan = into_orphan + 1
      end
    end
  end
  ok(into_entry > 0, "api panel: a cross-module call is an edge the column can count")
  eq(into_orphan, 0, "api panel: and an unreached function has none")

  vim.fn.delete(root, "rf")
end
