---@module 'documentation.core.telemetry_self'
--- Self-instrumentation — this tree wrapping its own `require
--- ("documentation")` aggregate with `runtime-analysis.telemetry`, so the
--- Telemetry mode / dead-function suppression (`telemetry_join.lua`, the
--- *read* side) has something real to read without a caller having to wire
--- runtime-analysis.telemetry up by hand for documentation.nvim itself.
--- This module is the write side of that same pair.
---
--- **Soft dependency, on by default, opt-out.** `pcall(require,
--- "runtime-analysis.telemetry")` — absent entirely, this is a no-op, the
--- same posture every other soft dependency in this codebase already
--- takes (`pdfport.nvim`, `which-key.nvim`, `runtime-analysis.nvim`'s own
--- request-runner integration). When present, self-instrumentation starts
--- automatically the moment `documentation.setup()` runs; `opts.telemetry
--- = false` turns it off — the same `~= false` opt-out shape
--- `opts.which_key` already uses in `editor/browse/init.lua`.
---
--- **Honest limit, inherited from `runtime-analysis.telemetry.auto()`
--- itself.** Only modules already in `package.loaded["documentation.*"]`
--- at the moment this runs are wrapped — `M.setup` is called from the end
--- of `usrcmds.setup()`, after that function's own `config`/`registry`/
--- `browse.open` requires, so it catches a real slice of the tree, not
--- only `documentation/init.lua` itself. Anything only required later
--- (`core/scan`, `render/*`, first touched by an actual `:DocMap` run) is
--- invisible until requested again — `wrap_loaded`'s own doc-comment
--- states this identically for every other consumer of it. `M.setup` is
--- itself idempotent for exactly this reason (a second call before the
--- namespace changes returns the existing instance rather than duplicating
--- it), so a caller wanting fuller coverage is free to call it again
--- later; it costs nothing when nothing new has loaded.

local M = {}

---@type RA.Telemetry.Instance|nil
local instance = nil

---Identical resolution `telemetry_join.namespace` (the read side) already
---uses, duplicated rather than required: a three-line pure-data lookup,
---and pulling in that module here for it would be the wrong direction of
---coupling (the write side depending on the read side's own module).
---@param opts table
---@return string?
local function resolve_namespace(opts)
  return opts.telemetry_namespace or opts.title
end

---Start self-instrumentation for this session. A no-op — returns `nil`,
---never errors — when `opts.telemetry == false`, when runtime-analysis.nvim
---is not installed, or when no namespace can be resolved at all (an
---unusual `opts` with neither `title` nor `telemetry_namespace` set; a
---guessed namespace risks colliding with an unrelated one already on disk,
---which is worse than instrumenting nothing).
---@param opts table `Documentation.Opts`, already resolved by `config.build` (has `.title`)
---@return RA.Telemetry.Instance? instance
function M.setup(opts)
  if opts.telemetry == false then
    return nil
  end
  if instance then
    return instance
  end

  local ok_telemetry, telemetry = pcall(require, "runtime-analysis.telemetry")
  if not ok_telemetry then
    return nil
  end

  local ns = resolve_namespace(opts)
  if not ns then
    return nil
  end

  -- `telemetry.auto()` itself already returns `nil` (rather than erroring)
  -- when `main` ("documentation") is not yet in `package.loaded` — the
  -- normal case never actually reaches that branch here, since this
  -- module is only ever called from code that `require("documentation")`
  -- already pulled in, but the check stays in `auto()`, not duplicated
  -- here.
  instance = telemetry.auto({
    namespace = ns,
    main = "documentation",
    deep = true,
    persist = true,
  })
  return instance
end

---The current self-instrumentation instance, if `M.setup` has created one
---— read by `:checkhealth documentation` to report live status rather than
---only whether runtime-analysis.nvim is installed.
---@return RA.Telemetry.Instance?
function M.instance()
  return instance
end

---Test-only: drop the module-level instance so a spec can call `M.setup`
---again under a fresh namespace without tripping the idempotency guard
---meant for real callers.
function M._reset_for_test()
  instance = nil
end

return M
