---@module 'documentation.core.timing'
--- Per-stage timing for a scan, collected here and *reported* elsewhere.
---
--- The split is the point. `documentation.core` must not notify — that rule is
--- what keeps the pipeline runnable with no editor around it, and it is checked
--- by grep in the audits. So this module only ever *collects*: it records
--- durations into a table and hands it back. Deciding whether a human sees it,
--- and in what form, belongs to `bindings/usrcmds/generate.lua`.
---
--- Off unless `opts.debug` is set. When off, `measure` is a direct call with no
--- clock read and no allocation, so leaving the instrumentation in the pipeline
--- costs nothing on the path everyone actually runs.
---
--- Deliberately coarse: one entry per pipeline stage, not per file and not per
--- function. "Which stage is slow" is the question this answers; anything finer
--- is a profiler's job, and pretending otherwise would produce numbers precise
--- enough to be trusted and too noisy to be right.

local M = {}

---Wall-clock milliseconds. `vim.uv.hrtime` rather than `os.clock`, which on
---some platforms measures CPU time and would under-report a stage that spends
---its time waiting on the filesystem — which is most of them here.
---@return number
local function now_ms()
  return vim.uv.hrtime() / 1e6
end

---@class Documentation.Timing
---@field entries { name: string, ms: number }[] In the order the stages ran.
---@field total_ms number Sum of the entries.
---@field enabled boolean

---A fresh, empty collector.
---@param enabled boolean? Anything falsy makes every `measure` a plain call.
---@return Documentation.Timing
function M.new(enabled)
  return { entries = {}, total_ms = 0, enabled = enabled and true or false }
end

---Run `fn`, recording how long it took under `name`.
---
---Returns whatever `fn` returns, so a call site wraps in place:
---`local ir = timing.measure(t, "scan", function() return M.scan(opts) end)`.
---
---Errors are deliberately **not** caught. A stage that throws is a real
---failure, and swallowing it to record a duration would turn instrumentation
---into a source of bugs — the whole run is about to abort anyway.
---@generic T
---@param t Documentation.Timing?
---@param name string
---@param fn fun(): T
---@return T
function M.measure(t, name, fn)
  if not (t and t.enabled) then
    return fn()
  end
  local started = now_ms()
  local result = fn()
  local ms = now_ms() - started
  t.entries[#t.entries + 1] = { name = name, ms = ms }
  t.total_ms = t.total_ms + ms
  return result
end

---Format a collector as lines, slowest stage marked.
---
---A pure `Documentation.Timing -> string[]`, so the caller decides where the
---lines go — a notification, `:messages`, stdout from the CLI. Returns an
---empty list when timing was off, so a caller needs no second `if`.
---@param t Documentation.Timing?
---@return string[]
function M.lines(t)
  if not (t and t.enabled) or #t.entries == 0 then
    return {}
  end

  local slowest, slowest_ms = nil, -1
  for _, e in ipairs(t.entries) do
    if e.ms > slowest_ms then
      slowest, slowest_ms = e.name, e.ms
    end
  end

  local width = 0
  for _, e in ipairs(t.entries) do
    width = math.max(width, #e.name)
  end

  local out = {}
  for _, e in ipairs(t.entries) do
    local share = t.total_ms > 0 and (100 * e.ms / t.total_ms) or 0
    out[#out + 1] = ("  %-" .. width .. "s  %7.1f ms  %4.1f%%%s"):format(
      e.name,
      e.ms,
      share,
      e.name == slowest and "  <-- slowest" or ""
    )
  end
  out[#out + 1] = ("  %-" .. width .. "s  %7.1f ms"):format("total", t.total_ms)
  return out
end

return M
