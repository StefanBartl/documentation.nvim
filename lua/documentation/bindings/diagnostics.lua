---@module 'documentation.bindings.diagnostics'
--- Publishes `Documentation.Finding[]` as native `vim.diagnostic` entries —
--- the roadmap item's own "Linting/LSP-Diagnostic" half, not previously
--- built: findings have only ever reached a reader through the
--- `:DocMap check` quickfix list.
---
--- Lives in `bindings/`, not `core/`, for the same reason `progress.lua`
--- does: `vim.diagnostic` is UI, and `core/` must stay runnable with no
--- editor attached (`docs/ROADMAP/PORTABILITY.md`). `core/check.lua` produces
--- `Documentation.Finding[]` knowing nothing about how — or whether — it
--- is displayed; this module is one of (now) two consumers that decide.
---
--- **File-level granularity only, matching the quickfix list's own
--- existing precedent, not a new limitation this module introduces.**
--- `Documentation.Finding` carries no `line` field at all — only `node`
--- (a whole file) and a free-text `message`. Checked before writing this:
--- `bindings/usrcmds/generate.lua`'s own `M.check` sets `filename` for its
--- quickfix items but never `lnum` either. A diagnostic here lands on the
--- buffer's first line, the same way an existing quickfix jump already
--- does — real per-line precision for the handful of checks that
--- internally already know one (`dead-function`, `param-name-mismatch`,
--- ...) is a genuine, separate future improvement to `Documentation.Finding`
--- itself, deliberately not bundled into this pass.
---
--- `info`-severity findings map to `vim.diagnostic.severity.HINT` and are
--- shown — the quickfix list drops them entirely
--- (`if f.severity ~= "info"`), but `vim.diagnostic` has a fourth,
--- deliberately unobtrusive tier quickfix never had reason to use, and
--- throwing that away would waste it rather than use it.

local M = {}

local NS = vim.api.nvim_create_namespace("documentation.nvim")

---@type table<Documentation.Severity, integer>
local SEVERITY = {
  error = vim.diagnostic.severity.ERROR,
  warn = vim.diagnostic.severity.WARN,
  info = vim.diagnostic.severity.HINT,
}

-- Every buffer this module has ever set a diagnostic on, per root —
-- `vim.diagnostic.set()` *replaces* the whole set for a buffer/namespace
-- pair, not merges into it, so a node whose last finding just got fixed
-- has to be explicitly set to an empty list, not merely left out of this
-- pass's own loop, or its diagnostic would linger forever.
---@type table<string, table<integer, boolean>>
local tracked_bufs = {}

---Publish the handle's current findings onto every already-open, loaded
---buffer that has one — never opens or loads a buffer itself, since a
---diagnostic on a buffer nobody has open is invisible and not worth the
---cost of loading one just to set it. Safe to call as often as needed:
---`ensure_diagnostics` below calls this both on buffer open and on every
---`on_change`, and re-publishing unchanged data is a cheap no-op as far as
---`vim.diagnostic` itself is concerned.
---@param root string
---@param handle Documentation.Handle
function M.publish(root, handle)
  ---@type table<string, Documentation.Finding[]>
  local by_node = {}
  for _, f in ipairs(handle.findings()) do
    if f.node then
      local list = by_node[f.node]
      if not list then
        list = {}
        by_node[f.node] = list
      end
      list[#list + 1] = f
    end
  end

  tracked_bufs[root] = tracked_bufs[root] or {}
  local seen_this_pass = {}

  for node_id, findings in pairs(by_node) do
    local node = handle.node(node_id)
    local source = node and node.source
    if source then
      local bufnr = vim.fn.bufnr(root .. "/" .. source)
      if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
        seen_this_pass[bufnr] = true
        tracked_bufs[root][bufnr] = true

        local diagnostics = {}
        for _, f in ipairs(findings) do
          diagnostics[#diagnostics + 1] = {
            lnum = 0,
            col = 0,
            severity = SEVERITY[f.severity] or vim.diagnostic.severity.WARN,
            message = ("[%s] %s"):format(f.check, f.message),
            source = "documentation.nvim",
          }
        end
        vim.diagnostic.set(NS, bufnr, diagnostics)
      end
    end
  end

  -- Clear every buffer this pass did not touch — its finding is gone.
  for bufnr in pairs(tracked_bufs[root]) do
    if not seen_this_pass[bufnr] then
      vim.diagnostic.set(NS, bufnr, {})
      tracked_bufs[root][bufnr] = nil
    end
  end
end

return M
