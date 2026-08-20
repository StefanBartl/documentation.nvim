---@module 'documentation.bindings.usrcmds.untested'
--- `:DocMap untested` — functions this machine has actually run that no spec
--- names, most-run first.
---
--- The bottom-left cell of `runtime-analysis.nvim`'s `IDEAS.md` §1.2:
--- coverage crossed with call counts gives four cells, and this is the one
--- worth a list. *"This ran four thousand times and no spec mentions it"* is a
--- test backlog sorted by evidence, the same shape `dead-function`'s
--- suppression list is a false-positive list sorted by evidence.
---
--- **It repairs `coverage.lua`'s stated blind spot in one direction.** That
--- module derives `tested` from bare-name mentions in the test tree and says
--- outright that a function exercised only indirectly never lights up. It
--- still does not — but a function telemetry watched running is no longer
--- invisible either, so the two blind spots no longer overlap completely.
---
--- **A command rather than a panel or a check**, for two independent reasons
--- that happen to agree. Runtime counts are personal, high-churn data and
--- cannot enter the committed artifact — `--check` byte-compares, so a map
--- carrying them invalidates itself on the commit that embeds it, the same
--- wall `churn` and the History tab hit. And a check would be a verdict that
--- differs between two developers looking at one repository, which
--- `runtime-analysis.nvim`'s `IDEAS.md` §1.5 refuses on its own terms: a
--- warning that appears on one machine and not another is worse than no
--- warning.
---
--- So this reports, and never fails anything.

local M = {}

---@param ctx Documentation.Bindings.Ctx
function M.run(ctx)
  local join = require("documentation.core.telemetry_join")
  local namespace = join.namespace(ctx.cfg)
  if not namespace then
    ctx.notify.info(
      "No telemetry namespace for this tree — set opts.title (or opts.telemetry_namespace)."
    )
    return
  end

  local data = join.load(namespace)
  if not data then
    -- Three causes, one message, because the reader's next step is the same
    -- for all three and naming which one would mean asking three further
    -- questions to find out: not installed, never enabled, nothing recorded.
    ctx.notify.info(
      ("No telemetry recorded for %q — this needs runtime-analysis.nvim collecting "):format(
        namespace
      ) .. "in the sessions that ran this code. Nothing is wrong with the map."
    )
    return
  end

  local ir = ctx.handle.ir()
  local rows = join.untested_hot(ir, data)

  if #rows == 0 then
    -- Deliberately not "everything is tested". Telemetry may have matched no
    -- function at all (nothing wrapped, or wrapped without a module id),
    -- which is a different fact and the more likely one on a tree that has
    -- just switched telemetry on.
    ctx.notify.info(
      ("Nothing telemetry recorded for %q is missing from a spec — "):format(namespace)
        .. "which is also what an unmatched or empty recording looks like."
    )
    return
  end

  local items = {}
  for i, r in ipairs(rows) do
    items[i] = {
      filename = ctx.cfg.root .. "/" .. (r.source or ""),
      -- Line 1, like `churn`: the join is per function name, and the IR
      -- carries a line only for functions it parsed a signature for. Pointing
      -- at the file is honest; pointing at a guessed line is not.
      lnum = 1,
      text = ("%s%s · %d calls, %d this week (yours) · no spec names it"):format(
        (r.module or r.id) .. "." .. r.fn,
        r.internal and " [internal]" or "",
        r.calls,
        r.calls_recent
      ),
    }
  end

  vim.fn.setqflist({}, " ", {
    title = ("docmap untested: %s"):format(namespace),
    items = items,
  })
  vim.cmd("copen")

  local top = rows[1]
  ctx.notify.info(
    ("%d function(s) ran on this machine with no spec naming them — most-run %s (%d calls)"):format(
      #rows,
      (top.module or top.id) .. "." .. top.fn,
      top.calls
    )
  )
end

return M
