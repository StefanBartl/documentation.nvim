---@module 'documentation.bindings.usrcmds.generate'
--- Bare `:DocMap` (regenerate), `:DocMap full` (regenerate with LuaLS
--- enrichment) and `:DocMap check` (verify without writing).
---
--- All three in one file because they are one operation with two switches:
--- rescan the tree, then either write the artifacts or only report. Splitting
--- them further would put `handle.rescan()` in three places and invite the
--- three to drift on how they tally findings.

local M = {}

---Report `opts.debug` timings, if any were collected.
---
---The reporting half of `core/timing.lua`. It lives here because `core` must
---not notify — that rule is what keeps the pipeline runnable with no editor
---around it — so the pipeline collects durations and this decides a human sees
---them.
---
---A no-op without `opts.debug`: `timing.lines` returns an empty list, so
---there is no second condition to keep in sync with the flag.
---@param ctx Documentation.Bindings.Ctx
---@param ir Documentation.IR
local function report_timing(ctx, ir)
  local lines = require("documentation.core.timing").lines(ir.timing)
  if #lines == 0 then
    return
  end
  -- One notification rather than one per stage: a stack of six messages is
  -- something to dismiss, a block is something to read.
  ctx.notify.info("Scan timing (opts.debug):\n" .. table.concat(lines, "\n"))
end

---Rescan and write. `opts.luals` is the `full` variant.
---@param ctx Documentation.Bindings.Ctx
---@param opts { luals: boolean? }?
function M.run(ctx, opts)
  local docmap = require("documentation")
  local luals = opts and opts.luals or false

  local ir, findings = ctx.handle.rescan(luals and { luals = true } or nil)
  local written = docmap.write_artifacts(ir, findings, ctx.cfg)
  local tally = docmap.tally(findings)

  report_timing(ctx, ir)

  if luals then
    ctx.notify.info(
      ("Wrote %d artifacts with LuaLS enrichment (%d modules, %d edges, %d errors)"):format(
        #written,
        ir.meta.counts.module,
        #(ir.edges or {}),
        tally.error
      )
    )
  else
    ctx.notify.info(
      ("Wrote %d artifacts (%d modules, %d errors)"):format(
        #written,
        ir.meta.counts.module,
        tally.error
      )
    )
  end
end

---Rescan and report, writing nothing. What the pre-commit hook runs.
---@param ctx Documentation.Bindings.Ctx
function M.check(ctx)
  local docmap = require("documentation")
  local _, findings = ctx.handle.rescan()
  local tally = docmap.tally(findings)
  local summary = ("%d errors · %d warnings · %d info"):format(
    tally.error,
    tally.warn,
    tally.info
  )

  if tally.error > 0 then
    ctx.notify.warn("Module map drift: " .. summary)
  else
    ctx.notify.info("Module map: " .. summary)
  end

  -- Route the detail through the quickfix list rather than a notification so
  -- findings are navigable instead of scrolling past.
  local items = {}
  for _, f in ipairs(findings) do
    if f.severity ~= "info" then
      items[#items + 1] = {
        filename = ctx.cfg.root .. "/" .. (f.node or ""),
        text = ("[%s] %s: %s"):format(f.severity, f.check, f.message),
        type = f.severity == "error" and "E" or "W",
      }
    end
  end
  vim.fn.setqflist({}, " ", { title = "Module map drift", items = items })
  if #items > 0 then
    vim.cmd("copen")
  end
end

return M
