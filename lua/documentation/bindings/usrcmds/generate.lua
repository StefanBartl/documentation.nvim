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

  -- Indeterminate rather than counted: `rescan` hands back a finished IR, so
  -- there is no per-module tick to report without threading a callback through
  -- the whole pipeline — and that pipeline must not know about the UI. What the
  -- user actually needs here is "still working", which is the `full` variant's
  -- problem: `lua-language-server --doc` over a whole tree is tens of seconds,
  -- and it only becomes visible at all because `core/luals.lua` waits with
  -- `vim.wait` (see bindings/progress.lua).
  local progress = require("documentation.bindings.progress").create(
    ctx,
    luals and "scanning + lua-language-server" or "scanning"
  )

  local ok_rescan, ir, findings = pcall(ctx.handle.rescan, luals and { luals = true } or nil)
  if not ok_rescan then
    -- Close the indicator before re-raising, or a failed scan leaves it stuck
    -- in the statusline for the rest of the session.
    if progress then
      progress:finish("scan failed")
    end
    error(ir, 0)
  end

  local written = docmap.write_artifacts(ir, findings, ctx.cfg)
  local tally = docmap.tally(findings)

  if progress then
    progress:finish(("wrote %d artifacts"):format(#written))
  end

  report_timing(ctx, ir)

  -- Asynchronous (pandoc, via pdfport.nvim) and opt-in, so it is reported
  -- separately from the "wrote N artifacts" notification above rather than
  -- folded into it -- write_artifacts() stays a synchronous, dependency-free
  -- path even with opts.pdf set.
  if ctx.cfg.pdf then
    docmap.write_pdf_artifact(ir, findings, ctx.cfg, function(ok, path_or_err)
      if ok then
        ctx.notify.info(("wrote %s"):format(path_or_err))
      else
        ctx.notify.warn(("overview.pdf not written: %s"):format(path_or_err))
      end
    end)
  end

  -- Naming the tree is not decoration. `:DocMap` resolves its root per
  -- invocation (see `usrcmds/init.lua`'s `buffer_root`), so "Wrote 3
  -- artifacts" without a subject is a report the reader cannot check — and
  -- back when the root was resolved once per session, that missing subject is
  -- precisely what let a `:DocMap` regenerate the *previous* repository twice
  -- and look like it had worked. The label is the repo directory name
  -- (`cfg.title`, derived from `root`), not the whole path: it is the word the
  -- user would use for the project.
  local where = ctx.cfg.title or vim.fn.fnamemodify(ctx.cfg.root, ":t")

  if luals then
    ctx.notify.info(
      ("%s: wrote %d artifacts with LuaLS enrichment (%d modules, %d edges, %d errors)"):format(
        where,
        #written,
        ir.meta.counts.module,
        #(ir.edges or {}),
        tally.error
      )
    )
  else
    ctx.notify.info(
      ("%s: wrote %d artifacts (%d modules, %d errors)"):format(
        where,
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

  -- Named for the same reason `run` names it, and it matters more here: the
  -- pre-commit hook runs this, and "0 errors" about the wrong tree is a green
  -- light nobody earned.
  local where = ctx.cfg.title or vim.fn.fnamemodify(ctx.cfg.root, ":t")

  if tally.error > 0 then
    ctx.notify.warn(("%s: module map drift — %s"):format(where, summary))
  else
    ctx.notify.info(("%s: module map — %s"):format(where, summary))
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
