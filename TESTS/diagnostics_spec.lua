-- TESTS/diagnostics_spec.lua — `bindings/diagnostics.lua`, which publishes
-- `Documentation.Finding[]` as native `vim.diagnostic` entries.
--
-- Driven end to end, the same "assumed untestable headlessly at first,
-- which was wrong" pattern `docmap_spec.lua`'s own live-watch test and
-- `callhierarchy_spec.lua` both already established: a real
-- `vim.cmd.edit()` fires the real `BufReadPost` autocmd
-- `registry.ensure_diagnostics` installs, then `vim.diagnostic.get()` reads
-- back what actually landed — not a direct call into `diagnostics.publish`.

return function(H)
  local eq, ok = H.eq, H.ok
  local docmap = require("documentation")

  local function dwrite(root, rel, lines)
    local abs = root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "diagnostics spec: fixture must be writable")
    fd:write(table.concat(lines, "\n"))
    fd:close()
    return abs
  end

  local root = H.tmpfile("_diagnostics")
  -- Produces four real findings, checked against the actual scanner output
  -- before writing this assertion rather than guessed: `missing-summary`
  -- (warn — @module present, no description line) plus three `info`-severity
  -- ones that come along for free with a single-file, unreferenced fixture
  -- module — `dead-function` (`unused_helper` is local, never called),
  -- `missing-readme` (no README.md beside it) and `unreferenced-module`
  -- (nothing in this tiny tree requires it). All three `info` findings map
  -- to HINT; only the one `warn` should show as WARN.
  local target = dwrite(root, "lua/demo/c/init.lua", {
    "---@module 'demo.c'",
    "local M = {}",
    "",
    "local function unused_helper()",
    "  return 1",
    "end",
    "",
    "---Exported.",
    "function M.exported()",
    "  return 2",
    "end",
    "",
    "return M",
  })

  local handle = docmap.install({
    root = root,
    source = "lua/demo",
    lua_root = "lua",
    diagnostics = true,
  })

  vim.cmd.edit(vim.fn.fnameescape(target))
  local bufnr = vim.api.nvim_get_current_buf()

  local diags = vim.diagnostic.get(bufnr)
  eq(#diags, 4, "diagnostics: all four real findings for this fixture are published")

  local by_severity = {}
  for _, d in ipairs(diags) do
    by_severity[d.severity] = (by_severity[d.severity] or 0) + 1
  end
  eq(by_severity[vim.diagnostic.severity.WARN], 1, "diagnostics: missing-summary maps to WARN")
  eq(
    by_severity[vim.diagnostic.severity.HINT],
    3,
    "diagnostics: the three info-severity findings map to HINT, not dropped the way quickfix drops them"
  )

  ok(
    (function()
      for _, d in ipairs(diags) do
        if d.message:find("missing-summary", 1, true) then
          return true
        end
      end
      return false
    end)(),
    "diagnostics: the check name is in the message"
  )

  -- --------------------------------------------------------- fix, and clear

  -- Fixes exactly two of the four findings — `missing-summary` (a
  -- description line added) and `dead-function` (`unused_helper` removed).
  -- `missing-readme` and `unreferenced-module` are untouched on purpose:
  -- this fixture is still one file with no README.md and nothing else in
  -- the tiny tree requires it, so those two are expected to remain, and
  -- the point of the assertion is that the *other* two are actually gone —
  -- not merely that the count went down, which `vim.diagnostic.set()`'s
  -- replace-not-merge semantics could satisfy by accident even with a bug
  -- that cleared everything and reset it wrong.
  dwrite(root, "lua/demo/c/init.lua", {
    "---@module 'demo.c'",
    "--- Now documented.",
    "local M = {}",
    "",
    "---Exported.",
    "function M.exported()",
    "  return 2",
    "end",
    "",
    "return M",
  })
  handle.rescan()

  local diags_after = vim.diagnostic.get(bufnr)
  eq(#diags_after, 2, "diagnostics: exactly the two remaining real findings are published")
  local checks_after = {}
  for _, d in ipairs(diags_after) do
    for _, name in ipairs({ "missing-readme", "unreferenced-module" }) do
      if d.message:find(name, 1, true) then
        checks_after[name] = true
      end
    end
    ok(
      not d.message:find("missing-summary", 1, true)
        and not d.message:find("dead-function", 1, true),
      "diagnostics: a fixed finding's diagnostic does not linger"
    )
  end
  ok(checks_after["missing-readme"], "diagnostics: missing-readme (untouched by the fix) remains")
  ok(
    checks_after["unreferenced-module"],
    "diagnostics: unreferenced-module (untouched by the fix) remains"
  )

  -- ------------------------------------------------- scope: outside `source`

  local outsider = dwrite(root, "notes/scratch.lua", { "-- not part of the scanned tree" })
  vim.cmd.edit(vim.fn.fnameescape(outsider))
  local outsider_buf = vim.api.nvim_get_current_buf()
  eq(
    #vim.diagnostic.get(outsider_buf),
    0,
    "diagnostics: a file outside source never gets any, watch or no watch"
  )

  handle.uninstall()
  vim.cmd("silent! %bwipeout!")
end
