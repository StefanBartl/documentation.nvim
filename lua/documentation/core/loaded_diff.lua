---@module 'documentation.core.loaded_diff'
--- Diff loaded-vs-declared — `runtime-analysis.nvim`'s own docs/ROADMAP.md
--- §5.3, "the sharpest form of the static x runtime join" that document
--- names: this tree's own scan knows every function the source
--- *declares*; `runtime-analysis.loaded` knows what is actually on a
--- module's table in *this* Neovim process, right now. The difference in
--- either direction is a real finding — declared but never loaded (dead
--- file, or genuinely lazy), loaded but not declared (generated, wrapped
--- with an extra key, a typo'd export).
---
--- **The one honest limit that shapes everything here**, inherited
--- directly from `runtime-analysis.loaded`'s own: `package.loaded`
--- reflects *this* process. Analyzing a tree that is not itself a live
--- plugin in the session running `:DocBrowse`/`:DocMap` sees nothing
--- loaded at all, which must render as "not loaded in this session",
--- never as "declared but dead" — the identical rule the telemetry join
--- (ECOSYSTEM.md step 8) already states for its own "no data" case.
---
--- **Scope, "record it, don't guess it".** Only `"<table>.<field>"`-shaped
--- declared names (exactly one dot, e.g. `"M.foo"`) are compared — a
--- module's own top-level exported functions, which is exactly the one
--- shape `runtime-analysis.loaded`'s single-level table walk can ever see
--- as a direct field. A file-local declaration (`local function foo`,
--- never exported) is excluded outright, not flagged as "not loaded" —
--- it was never going to be a field of the module table regardless of
--- whether the file loaded. A colon-declared method (`Class:method`) on a
--- nested table the module happens to export is excluded too: it lives
--- one level deeper than this join's single-level walk reaches, and
--- guessing at that nesting is exactly the wrong-answer risk this module
--- exists to avoid — the same reasoning `endpoint_coverage.lua`'s route
--- matching already states for what it deliberately does not attempt.

local M = {}

---@class Documentation.LoadedDiff.Row
---@field id string IR node id
---@field kind "declared_only"|"loaded_only"
---@field name string The bare field name (no table prefix)
---@field declared_name string? The full declared name as written (`declared_only` rows only)
---@field line integer? Declaration line (`declared_only` rows only)

---Bare field name a declared name resolves to, when (and only when) it is
---the one shape a single-level `package.loaded` walk could ever match:
---exactly one dot, no colon. `nil` for everything else — file-local,
---colon methods, or a deeper qualified path.
---@param declared_name string
---@return string? bare
local function exported_field(declared_name)
  if declared_name:find(":", 1, true) then
    return nil
  end
  local prefix, field = declared_name:match("^([%w_]+)%.([%w_]+)$")
  if prefix then
    return field
  end
  return nil
end

---One row per discrepancy across the whole tree — nodes with a real
---module path only; a namespace (no `init.lua`, nothing itself
---`require()`-able) has nothing for `package.loaded` to hold.
---@param ir Documentation.IR
---@return Documentation.LoadedDiff.Row[]? rows `nil` when
---`runtime-analysis.nvim` is not installed at all — distinct from an
---empty list, which means it *is* installed and found no discrepancies.
function M.rows(ir)
  local ok, loaded_mod = pcall(require, "runtime-analysis.loaded")
  if not ok then
    return nil
  end

  local out = {}
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.module and node.kind ~= "namespace" then
      local declared = {} ---@type table<string, { declared_name: string, line: integer }>
      for _, fn in ipairs(node.functions or {}) do
        local field = exported_field(fn.name)
        if field then
          declared[field] = { declared_name = fn.name, line = fn.line }
        end
      end

      local present = loaded_mod.functions(node.module) or {}

      for field, info in pairs(declared) do
        if not present[field] then
          out[#out + 1] = {
            id = id,
            kind = "declared_only",
            name = field,
            declared_name = info.declared_name,
            line = info.line,
          }
        end
      end
      for field in pairs(present) do
        if not declared[field] then
          out[#out + 1] = { id = id, kind = "loaded_only", name = field }
        end
      end
    end
  end

  table.sort(out, function(a, b)
    if a.id ~= b.id then
      return a.id < b.id
    end
    if a.kind ~= b.kind then
      return a.kind < b.kind
    end
    return a.name < b.name
  end)
  return out
end

return M
