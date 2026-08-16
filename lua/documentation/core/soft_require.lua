---@module 'documentation.core.soft_require'
--- The one place that probes for an optional dependency, so `pcall(require,
--- "...")` is not hand-rolled at every call site that needs one. Every
--- optional integration this plugin has — `runtime-analysis.nvim`,
--- `pdfport.nvim`, `which-key.nvim`, `mdview.nvim`, and a couple of specific
--- `lib.nvim` submodules (`progress`, `deps.spec`) — goes through `M.probe`
--- instead of its own inline `pcall`.
---
--- Pure Lua, no `vim.api`/`vim.fn` — safe to call from `core/`, which this
--- module itself lives in.
---
--- This does not change *what* callers do with a missing dependency (that
--- stays call-site-specific: some fall back silently, some warn once, some
--- are purely informational — `editor/health.lua`'s three severities are
--- unaffected by this module and read as before). It only removes the
--- duplicated probing logic itself — `core/api.lua` alone used to run the
--- identical `pcall(require, "runtime-analysis.telemetry")` at two separate
--- call sites in the same file.

local M = {}

---@generic T
---@param modname string
---@return T|nil mod `nil` if `modname` could not be required (not installed).
function M.probe(modname)
  local ok, mod = pcall(require, modname)
  if ok then
    return mod
  end
  return nil
end

return M
