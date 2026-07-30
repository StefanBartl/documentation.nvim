---@module 'documentation.bindings.progress'
--- Progress indicator for the `:DocMap` subcommands that take real time.
---
--- Lives in `bindings/` on purpose. `core/` must not touch the UI — that rule is
--- what keeps the pipeline runnable with no editor attached (see
--- `usrcmds/generate.lua`'s note on `report_timing`), and an indicator is UI.
--- So the long operations stay UI-free internally and the command layer, which
--- already owns `ctx.notify`, wraps them from the outside.
---
--- `lib.nvim` is an optional dependency here: without it `create` returns nil
--- and every call site's `if handle then` guard skips the indicator. Style comes
--- from `ctx.cfg.progress_style`.
---
--- ## Why the call sites have to wait a particular way
---
--- `lib.nvim.progress` wraps its delay guard in `vim.schedule_wrap`, and the
--- `"statusline"` style schedules its `:redrawstatus`. Scheduled callbacks do
--- not run until the main loop is free, so a handle created around a blocking
--- call is only ever *visible* if that call yields the loop. Measured against a
--- 2s child process, counting samples where the handle was actually published:
---
---   `vim.fn.system`/`systemlist`   0
---   `vim.system(...):wait()`       0
---   `vim.system` + `vim.wait`     62
---
--- (A bare `vim.uv` timer ticks in all three — libuv is not the constraint,
--- `vim.schedule` is.) So a call site wrapping work in one of the first two
--- forms would get an indicator that never appears. `core/luals.lua` already
--- waits via `spawn_capture` + `vim.wait`; `usrcmds/churn.lua` was moved onto
--- the same pattern for exactly this reason.

local M = {}

local ok_progress, progress_mod = pcall(require, "lib.nvim.progress")

---Starts a progress handle, or returns nil when lib.nvim isn't installed.
---@param ctx Documentation.Bindings.Ctx
---@param text string Initial message, shown after the "[documentation]" title
---@param total integer|nil Total unit count, when the operation is countable
---@return table|nil
function M.create(ctx, text, total)
  if not ok_progress then
    return nil
  end
  local handle = progress_mod.create({
    title = "[documentation]",
    style = (ctx.cfg and ctx.cfg.progress_style) or "auto",
  })
  handle:update({ text = text, current = total and 0 or nil, total = total })
  return handle
end

return M
