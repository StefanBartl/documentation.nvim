---@module 'documentation.core.telemetry_join'
--- The static x runtime join — ECOSYSTEM.md step 8, `docs/ROADMAP/
--- telemetry-documentation-bridge.md` (in the `lib.nvim` repo) for the full
--- design. This tree's own static analysis (`check.used_keys`) knows which
--- functions have a *caller documentation.nvim can see*; `runtime-analysis.
--- telemetry` knows which functions were *actually entered*. Neither answers
--- the other's blind spot alone: a callback bound as a value, or dynamic
--- dispatch, looks dead to static analysis while telemetry proves it is
--- alive; a function with a real static caller that nothing has exercised in
--- 30 days is a cold path, not a caller documentation.nvim invented.
---
--- **Soft dependency throughout.** `pcall(require, "runtime-analysis.
--- telemetry")` — absent entirely, or telemetry simply never enabled for this
--- namespace, is not an error; every caller of `M.load` must treat `nil` as
--- "no data", never as evidence of anything. Stated plainly in the design
--- doc's own Honest Limits section: absence of runtime data is not evidence
--- of death.
---
--- **Key-matching is "record it, don't guess it".** A telemetry key is
--- whatever the wrap call labelled it (`t.wrap(require("lsp.servers"),
--- "servers")` yields `servers.attach`), which does not line up with this
--- tree's own `module_id .. "#" .. fn.name` IR keys on its own. Only keys
--- `runtime-analysis.telemetry` itself already resolved to a real module path
--- (`Data.modules`, populated by `wrap_loaded()` automatically or a plain
--- `wrap()`'s explicit `opts.module_id`) are ever joined; every other key is
--- dropped here, not guessed at, and never surfaces as "zero calls" for a
--- function it does not actually describe.

local M = {}

---@class Documentation.TelemetryJoin.Row
---@field id string IR node id the function belongs to (the resolved module path)
---@field fn string Function name, the IR node's own `fn.name`
---@field ir_key string `id .. "#" .. fn` — the same key shape `check.used_keys` returns
---@field calls integer
---@field has_static_caller boolean Whether `check.used_keys(ir)` already considers this function used

---Read `namespace`'s telemetry data straight off disk, no live instance
---required — the same `telemetry.load()` a `:DocMap check` run in a fresh
---Neovim session needs, since the tree being analyzed usually has no live
---instance for itself.
---@param namespace string
---@return RA.Telemetry.Data? data `nil` when `runtime-analysis.nvim` is not
---installed, or nothing was ever persisted for `namespace` — the same "no
---opinion" case, never distinguished further by this function since every
---caller already has to treat both as "no data".
function M.load(namespace)
  local ok, telemetry = pcall(require, "runtime-analysis.telemetry")
  if not ok then
    return nil
  end
  local ok_load, data = pcall(telemetry.load, namespace)
  if not ok_load then
    return nil
  end
  return data
end

---`node.module` (dotted, from an `@module` header) to the node itself —
---built once per call rather than once per row.
---
---**Half of a bug fixed 2026-08-10, found by actually curling a real join
---against this tree's own self-instrumentation instead of trusting the code
---read alone.** `Documentation.IR.nodes` is keyed by `node.id`, which
---`core/scan.lua` sets to a *file path* (`local id = rel`) — never the
---dotted form. `runtime-analysis.telemetry`'s `wrap_loaded()` (and
---`telemetry.auto()`, which this tree's own `core/telemetry_self.lua` uses)
---resolves `Data.modules` values to the dotted require-path instead (e.g.
---`"documentation.core.doccoverage"`). A plain `ir.nodes[module_id]` lookup
---never sees those — the two key spaces do not intersect — so every row
---from an auto-instrumented tree silently failed to match, unconditionally.
---This made `:DocBrowse telemetry` (ECOSYSTEM.md step 8) show "no telemetry
---data" for every function regardless of real usage, and
---`M.doc_usage_summary` always report 0/0, on any project using `auto()`/
---`wrap_loaded()` — which is the common case, not an edge one.
---@param ir Documentation.IR
---@return table<string, Documentation.Node> module (dotted) -> node
local function module_index(ir)
  local by_module = {}
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.module then
      by_module[node.module] = node
    end
  end
  return by_module
end

---Every function `data.modules` can resolve to a real node still present in
---`ir`, joined against `check.used_keys(ir)` for the static half.
---
---**Two resolution conventions, tried in order, because both are real.** A
---plain `runtime-analysis.telemetry` `wrap(tbl, label, {module_id=...})`
---call lets the *caller* choose any string, including one that happens to
---equal a real `node.id` directly (`TESTS/browse_telemetry_spec.lua`'s own
---fixture does exactly this) — checked first since it is the more specific,
---already-a-real-key case. `wrap_loaded()`/`telemetry.auto()` resolve to the
---dotted `@module` form instead (`module_index`'s own header has the full
---story of why that needs a second index rather than a second key on the
---same table) — checked second. A telemetry key that matches neither (the
---module was renamed or removed since telemetry last ran, or a `wrap()`
---call with no `module_id` at all) is silently dropped, the same
---"declared but no longer real" case `history` mode already treats as "no
---longer in the map" rather than an error.
---@param ir Documentation.IR
---@param data RA.Telemetry.Data
---@return Documentation.TelemetryJoin.Row[]
function M.rows(ir, data)
  local check = require("documentation.core.check")
  local used = check.used_keys(ir)
  local by_module = module_index(ir)

  local rows = {}
  for key, module_id in pairs(data.modules) do
    local fn_name = key:match("([^.]+)$")
    local node = fn_name and (ir.nodes[module_id] or by_module[module_id])
    if node then
      -- `node.id` (the real, file-path IR key) rather than `module_id`
      -- verbatim: the two coincide for the direct-id convention above but
      -- not for the dotted one, and this is what `used_keys(ir)` is itself
      -- keyed by, and what a `navigate({id=...})` call on the client side
      -- needs to actually find the node.
      local ir_key = node.id .. "#" .. fn_name
      local stats = data.functions[key]
      rows[#rows + 1] = {
        id = node.id,
        fn = fn_name,
        ir_key = ir_key,
        calls = stats and stats.calls or 0,
        has_static_caller = used[ir_key] == true,
      }
    end
  end
  return rows
end

---`M.rows`, indexed by `ir_key` for O(1) lookup — what both the `telemetry`
---browse mode and dead-function suppression actually want, rather than a
---linear scan of the list form per function.
---@param ir Documentation.IR
---@param data RA.Telemetry.Data
---@return table<string, Documentation.TelemetryJoin.Row>
function M.by_key(ir, data)
  local out = {}
  for _, row in ipairs(M.rows(ir, data)) do
    out[row.ir_key] = row
  end
  return out
end

---Two aggregate numbers crossing "documented" (`doccoverage.is_documented`)
---against "actually called" (this join) — the two lines `docs/ROADMAP/
---telemetry-documentation-bridge.md` (lib.nvim) names as the most
---immediately useful reading of the whole join: a maintenance-cost set, and
---a documentation backlog prioritized by evidence of real use rather than
---alphabetically. `@internal` functions are excluded, the same scope
---`doccoverage.summary` already uses — a published-API question, not an
---internals one. Restricted to functions telemetry has an actual row for
---(matched key, real Data): an unmatched or telemetry-absent function is
---"no data" for this pairing exactly as it is everywhere else this join
---appears, never silently folded into either count.
---@param ir Documentation.IR
---@param opts Documentation.Opts
---@return { documented_unused: integer, undocumented_used: integer }? `nil` when no telemetry data is available for `opts` at all.
function M.doc_usage_summary(ir, opts)
  local namespace = M.namespace(opts)
  local data = namespace and M.load(namespace)
  if not data then
    return nil
  end

  local doccoverage = require("documentation.core.doccoverage")
  local by_key = M.by_key(ir, data)

  local documented_unused, undocumented_used = 0, 0
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    for _, fn in ipairs(node.functions) do
      if not fn.internal then
        local row = by_key[id .. "#" .. fn.name]
        if row then
          local documented = doccoverage.is_documented(fn)
          if documented and row.calls == 0 then
            documented_unused = documented_unused + 1
          elseif not documented and row.calls > 0 then
            undocumented_used = undocumented_used + 1
          end
        end
      end
    end
  end
  return { documented_unused = documented_unused, undocumented_used = undocumented_used }
end

---The namespace `opts` joins against — `opts.telemetry_namespace` if set,
---`opts.title` otherwise. Every telemetry instance in this ecosystem is
---namespaced by the plugin's own display name already, so this needs no
---separate opt for the common case; see `Documentation.Opts.
---telemetry_namespace`'s own doc-comment for when the two genuinely differ.
---@param opts Documentation.Opts
---@return string?
function M.namespace(opts)
  return opts.telemetry_namespace or opts.title
end

return M
