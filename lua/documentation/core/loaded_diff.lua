---@module 'documentation.core.loaded_diff'
--- Diff loaded-vs-declared with `runtime-analysis.nvim` — the sharpest form
--- of the static x runtime join: this tree.s own scan knows every function the source
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

---The `runtime-analysis.loaded` snapshot prefix this tree resolves to —
---`opts.source`'s dotted form, the same transform `core/check.lua#M.
---expected_module` already applies to every file in the tree, here applied
---once to the root itself. Deliberately not a separate `opts` field the way
---`telemetry_join.M.namespace` has one (`opts.telemetry_namespace`): unlike
---a telemetry namespace, which genuinely can differ from the module prefix
---it wraps (`core/telemetry_self.lua` wraps `main = "documentation"` under
---`namespace = "documentation.nvim"`, two different strings, for this repo
---itself), a loaded snapshot has nothing to name *except* the prefix it was
---taken under — see `runtime-analysis.loaded`'s own snapshot section for
---why it deliberately has no separate namespace argument either. Both sides
---deriving the identical value from `opts.source` independently is what
---lets `:RA loaded snapshot <prefix>` and this reading side agree on one
---without either passing the other a config value to keep in sync.
---@param opts Documentation.Opts
---@return string? prefix `nil` when `opts.source`/`opts.lua_root` do not
---resolve to a dotted prefix at all (an unusual layout with no single
---root module) — the same "no opinion" shape `telemetry_join.M.namespace`
---returns for an unset `opts.title`.
function M.prefix(opts)
  -- Several source roots means there is no single root module to name --
  -- exactly the case this function already answers with `nil` when
  -- `source == lua_root`, reached by a different route.
  local single = require("documentation.config").primary_source(opts)
  if not single then
    return nil
  end
  local source = single:gsub("/+$", "")
  local lua_root = (opts.lua_root or "lua"):gsub("/+$", "")
  -- `source == lua_root` means the whole `lua/` tree is scanned directly —
  -- several top-level modules, no single root to name. The same "more than
  -- one candidate, do not guess" case `M.detect_source` already falls back
  -- to plain `"lua"` for, here answered with "no prefix" instead of a wrong
  -- one (`expected_module` would otherwise strip `lua_root .. "/"` and be
  -- left with nothing to dot, an artifact of the path math, not a real name).
  if source == lua_root then
    return nil
  end
  local check = require("documentation.core.check")
  return check.expected_module(source .. "/init.lua", lua_root)
end

---@internal
---Shared by `M.rows` (live) and `M.rows_from_snapshot` (persisted):
---everything past "how do I get a module's present
---fields" is identical between the two, so this is the one place that
---logic exists.
---@param ir Documentation.IR
---@param present_for fun(module_id: string): table<string, true>?
---@return Documentation.LoadedDiff.Row[]
local function diff(ir, present_for)
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

      local present = present_for(node.module) or {}

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

---One row per discrepancy across the whole tree — nodes with a real
---module path only; a namespace (no `init.lua`, nothing itself
---`require()`-able) has nothing for `package.loaded` to hold.
---@param ir Documentation.IR
---@return Documentation.LoadedDiff.Row[]? rows `nil` when
---`runtime-analysis.nvim` is not installed at all — distinct from an
---empty list, which means it *is* installed and found no discrepancies.
function M.rows(ir)
  local loaded_mod = require("documentation.core.soft_require").probe("runtime-analysis.loaded")
  if not loaded_mod then
    return nil
  end
  return diff(ir, loaded_mod.functions)
end

---The same diff, against a persisted snapshot instead of the live
---`package.loaded` — "cold viewing": a snapshot
---taken in one process (or hours/days earlier in this one), read here
---without needing that process to still be running. `snapshot.modules` is
---already exactly the `module_id -> {field -> true}` shape `M.rows`'s own
---`present_for` callback needs, from `runtime-analysis.loaded.snapshot`'s
---own capture — see that function's header for what it captured and when.
---@param ir Documentation.IR
---@param snapshot { modules: table<string, table<string, true>> } The table `runtime-analysis.loaded.load_snapshot` returns.
---@return Documentation.LoadedDiff.Row[]
function M.rows_from_snapshot(ir, snapshot)
  return diff(ir, function(module_id)
    return snapshot.modules[module_id]
  end)
end

return M
