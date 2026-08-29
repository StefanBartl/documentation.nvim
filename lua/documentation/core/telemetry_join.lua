---@module 'documentation.core.telemetry_join'
--- The static x runtime join — ECOSYSTEM.md step 8. This tree.s own static
--- analysis (`check.used_keys`) knows which
--- functions have a *caller documentation.nvim can see*; `runtime-analysis.
--- telemetry` knows which functions were *actually entered*. Neither answers
--- the other's blind spot alone: a callback bound as a value, or dynamic
--- dispatch, looks dead to static analysis while telemetry proves it is
--- alive; a function with a real static caller that nothing has exercised in
--- 30 days is a cold path, not a caller documentation.nvim invented.
---
--- **Soft dependency throughout.** `core.soft_require.probe("runtime-analysis.
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
---@field calls integer Every call ever recorded for this key, across every session since `data.started_at`.
---@field calls_recent integer Calls in the last `M.RECENT_DAYS` calendar days, from `data.days`. `0` is a real answer and a different one from `calls == 0`: a function with a large `calls` and a `calls_recent` of zero is a cold path, which is the reading `calls` alone cannot give.
---@field has_static_caller boolean Whether `check.used_keys(ir)` already considers this function used

---How many calendar days `Row.calls_recent` looks back over.
---
---**Seven, because the question it answers is "is this alive", and a week is
---the shortest window that survives a weekend.** A day is noise — a function
---nobody happened to reach on Tuesday is not cold. A month is long enough
---that a path abandoned three weeks ago still reads as busy, which is the
---one wrong answer this number exists to prevent.
---
---Named rather than inlined so the hover, the browse mode and any later
---reader all say the same number, and so changing it is one edit rather than
---a search for `7`.
M.RECENT_DAYS = 7

---Calls recorded for `key` in the last `M.RECENT_DAYS` calendar days.
---
---**Calendar days, from `data.days`' own `YYYY-MM-DD` keys, not a rolling
---timestamp window.** That is what telemetry stores, and reconstructing an
---hour-accurate window from day buckets would be a precision the data does
---not have. Today counts as one of the seven, so a fresh install that has
---only ever run today still reports its calls rather than nothing.
---@param data RA.Telemetry.Data
---@param key string The telemetry key, not the IR key — `data.days` is keyed the way telemetry wrapped it.
---@return integer
local function recent_calls(data, key)
  if type(data.days) ~= "table" then
    return 0
  end
  local total = 0
  local now = os.time()
  for back = 0, M.RECENT_DAYS - 1 do
    -- `os.date` on a shifted timestamp rather than arithmetic on the date
    -- string: this has to be right across a month boundary and a DST
    -- change, and the C library already is.
    local day = os.date("%Y-%m-%d", now - back * 86400)
    local bucket = data.days[day]
    if type(bucket) == "table" and type(bucket[key]) == "number" then
      total = total + bucket[key]
    end
  end
  return total
end

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
  local telemetry = require("documentation.core.soft_require").probe("runtime-analysis.telemetry")
  if not telemetry then
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

---The IR function name behind a telemetry key's last segment.
---
---**The second half of the key-space bug, fixed 2026-08-20 — the same shape
---as the first, in the other half of the key.** `module_index`'s header
---above records how the *module* side was found to be joining two key spaces
---that never intersect. The *function* side had the identical defect and
---survived that fix: a telemetry key's last segment is the table field name
---(`documentation.scan_full`), while `Documentation.FunctionInfo.name` is the
---name **as written** (`M.scan_full`). Building `node.id .. "#" .. field`
---produced `lua/documentation#scan_full`, and `used_keys(ir)` — and every
---consumer that looks a row up by IR key — has `lua/documentation#M.scan_full`.
---
---**So the join silently matched nothing but bare-named locals**, which is a
---small minority of any Lua module: every `function M.foo()` in this
---ecosystem, meaning nearly every exported function there is, came back as
---"no telemetry data". `:DocBrowse telemetry` said so per function,
---`doc_usage_summary` counted both of its numbers far too low, and
---`dead-function`'s telemetry suppression never applied to an export.
---
---Measured rather than reasoned, the same way the first half was: the join
---was run against this repository's own real IR with the telemetry key
---`wrap_loaded()` would actually produce, and asked whether the key it
---emitted was one the IR has. It was not.
---
---**Exact first, then the bare tail.** A node could in principle hold both
---`read` and `M.read`; the exact match is the specific answer and wins. Two
---functions sharing one tail with no exact match is genuinely ambiguous, and
---an ambiguous key is dropped rather than guessed — the same treatment a key
---that resolves to no node at all already gets, and for the same reason:
---attributing somebody's call counts to the wrong function is worse than
---attributing them to nothing.
---@param node Documentation.Node
---@param field string The telemetry key's last segment — the table field name.
---@return string? name The IR's own `fn.name`, or `nil` when nothing matches or several do.
local function resolve_fn_name(node, field)
  local bare_match, bare_count = nil, 0
  for _, fn in ipairs(node.functions or {}) do
    if fn.name == field then
      return fn.name
    end
    if (fn.name:match("([%w_]+)$") or fn.name) == field then
      bare_match, bare_count = fn.name, bare_count + 1
    end
  end
  if bare_count == 1 then
    return bare_match
  end
  return nil
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
    local field = key:match("([^.]+)$")
    local node = field and (ir.nodes[module_id] or by_module[module_id])
    local fn_name = node and resolve_fn_name(node, field)
    if node and fn_name then
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
        calls_recent = recent_calls(data, key),
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

---Per-module call totals, for a ranking that already has its own rows.
---
---**The third axis `churn.lua` says it is missing.** That module ranks by
---change frequency x complexity and its own header calls the product a
---scalarization; what neither factor can say is whether anyone runs the
---module. Complex, churning and hot is a *refactoring* candidate; complex,
---churning and cold is a *deletion* candidate, and today they render
---identically while calling for opposite actions.
---
---Summed over the module's matched functions only. A module whose functions
---were never wrapped contributes no entry at all rather than a zero: "no
---telemetry for this" and "telemetry watched it and saw nothing" are the two
---answers this join keeps apart everywhere else, and the second is the only
---one worth acting on.
---@param ir Documentation.IR
---@param data RA.Telemetry.Data
---@return table<string, { calls: integer, calls_recent: integer, functions: integer }> by IR node id
function M.by_node(ir, data)
  local out = {}
  for _, row in ipairs(M.rows(ir, data)) do
    local acc = out[row.id]
    if not acc then
      acc = { calls = 0, calls_recent = 0, functions = 0 }
      out[row.id] = acc
    end
    acc.calls = acc.calls + row.calls
    acc.calls_recent = acc.calls_recent + row.calls_recent
    acc.functions = acc.functions + 1
  end
  return out
end

---@class Documentation.TelemetryJoin.Untested
---@field id string IR node id
---@field module string? The node's dotted `@module` name, when it has one
---@field source string? Repo-relative path of the file it lives in
---@field fn string Function name
---@field calls integer Every call ever recorded
---@field calls_recent integer Calls in the last `M.RECENT_DAYS` days
---@field internal boolean Whether the function is `@internal` — kept rather than filtered, because a hot internal is a real answer to a different question

---Functions telemetry saw running that no spec names — the bottom-left cell.
---
---`coverage.lua` derives `tested` by counting bare-name mentions in the test
---tree and documents its blind spot: a function exercised only *indirectly*
---never lights up. Crossing that with call counts gives four cells, and this
---returns the one worth a list: **ran, and no spec mentions it**. A test
---backlog sorted by evidence rather than alphabetically.
---
---The other three cells are deliberately not returned. "Tested and called"
---is fine, "tested and never called" is a question about the test rather
---than the code, and "untested and never called" is `dead-function`'s
---territory and has its own suppression rules — producing it here would put
---a second, weaker verdict beside an existing one.
---
---**`calls > 0`, not `calls_recent > 0`.** Recency answers "is this alive";
---this answers "did this ever run without a test watching", and a function
---that ran ten thousand times last month and is quiet this week is exactly
---as untested as it was.
---
---Sorted by total calls, descending, then by key, so two runs over one data
---set produce one order.
---@param ir Documentation.IR
---@param data RA.Telemetry.Data
---@return Documentation.TelemetryJoin.Untested[]
function M.untested_hot(ir, data)
  local by_key = M.by_key(ir, data)
  local out = {}
  for _, id in ipairs(ir.order or {}) do
    local node = ir.nodes[id]
    for _, fn in ipairs((node and node.functions) or {}) do
      local row = by_key[id .. "#" .. fn.name]
      -- `fn.tested` is false both for "no spec names it" and for "coverage
      -- never ran". The second is not distinguishable here and does not need
      -- to be: with no coverage data every function is untested and the list
      -- becomes "everything telemetry saw", which is a true statement about
      -- a tree nobody measured.
      if row and row.calls > 0 and not fn.tested then
        out[#out + 1] = {
          id = id,
          module = node.module,
          source = node.source,
          fn = fn.name,
          calls = row.calls,
          calls_recent = row.calls_recent,
          internal = fn.internal == true,
        }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.calls ~= b.calls then
      return a.calls > b.calls
    end
    if a.id ~= b.id then
      return a.id < b.id
    end
    return a.fn < b.fn
  end)
  return out
end

---Two aggregate numbers crossing "documented" (`doccoverage.is_documented`)
---against "actually called" (this join) — the two most immediately useful
---readings of the whole join: a maintenance-cost set, and
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
