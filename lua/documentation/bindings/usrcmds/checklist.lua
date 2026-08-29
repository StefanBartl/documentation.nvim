---@module 'documentation.bindings.usrcmds.checklist'
--- `:DocMap checklist [all]` — the hand-verified ledger, things needing a
--- re-read first.
---
--- Not an Analysis panel, and it cannot become one for the same reason
--- `churn` cannot: the verdict is derived from `git log`, and git data would
--- make the committed artifact invalidate itself on the very commit that
--- embedded it, since `--check` byte-compares. The *ledger* does bake into
--- `module_map.json` (it is just parsed Markdown); only this verdict is
--- live. Same wall the History tab hit.
---
--- Defaults to showing only what needs attention — stale and unverified
--- items. `:DocMap checklist all` lists everything, including items that are
--- current, which is the "is this ledger healthy" view rather than the "what
--- do I do now" one.

local list = require("lib.nvim.ui.list")

local M = {}

---@internal
---The configured `git log` ceiling, in ms.
---
---One key behind three call sites: `churn`, this checklist pass and the MCP
---tool all bound themselves by the same two minutes, written out three times.
---@param cfg table|nil  # A resolved config, when the caller already has one.
---@return integer
local function git_log_timeout(cfg)
  if type(cfg) == "table" and type(cfg.git_log_timeout_ms) == "number" then
    return cfg.git_log_timeout_ms
  end
  local ok, defaults = pcall(require, "documentation.config.DEFAULTS")
  local n = ok and type(defaults) == "table" and defaults.git_log_timeout_ms or nil
  return type(n) == "number" and n > 0 and n or 120000
end

---@internal
---@param ms integer
---@return string
local function timed_out_msg(ms)
  return ("git log did not finish within %ds"):format(math.floor(ms / 1000))
end

---Collect `path -> ISO commit dates` for every path in the repository.
---
---One `git log` for the whole tree rather than one per cited path: a ledger
---with fifty items would otherwise spawn fifty processes, and the whole-tree
---walk is the same shape `usrcmds/churn.lua` already runs and already found
---acceptable.
---
---Only the subprocess lives here; the parsing is `core/checklist.lua`'s
---`parse_history`, shared with the serve tier's `/api/checklist` route, which
---runs git a different way and would otherwise carry a second copy of it.
---@param cwd string
---@param out_dir string Excluded: in a repo that commits its own map, it is touched by nearly every commit.
---@param cb fun(dates: table<string, string[]>|nil, err: string|nil) called on the main loop
---@param cfg table|nil The resolved config, for `git_log_timeout_ms`.
---@return nil
local function commit_dates(cwd, out_dir, cb, cfg)
  local cmd = {
    "git",
    "log",
    "--no-merges",
    "--format=%x1e%cs",
    "--name-only",
    "--",
    ".",
    (":(exclude)%s"):format(out_dir),
  }

  -- `git log` over a repository's full history is the slow part of this
  -- command. It used to be pumped with `vim.wait(120000, ...)`, which keeps the
  -- loop running (that is why the progress handle was visible at all) but still
  -- holds input for the whole run. The result is delivered through `cb` now, so
  -- nothing is held at all; the ceiling moves to vim.system's own timeout.
  local timeout = git_log_timeout(cfg)
  vim.system(cmd, { cwd = cwd, text = true, timeout = timeout }, function(proc)
    -- vim.system callbacks run off the main loop; the caller touches quickfix,
    -- notify and :copen.
    vim.schedule(function()
      if not proc then
        cb(nil, timed_out_msg(timeout))
        return
      end
      if proc.code ~= 0 then
        local stderr = vim.trim(proc.stderr or "")
        -- A timeout kill surfaces as a non-zero exit with no stderr; keep the
        -- old wording for that case so the message stays recognisable.
        cb(nil, stderr ~= "" and ("git log failed: " .. stderr) or timed_out_msg(timeout))
        return
      end
      cb(require("documentation.core.checklist").parse_history(proc.stdout or ""), nil)
    end)
  end)
end

---@param status Documentation.Checklist.Status
---@return string
local function describe(status)
  local item = status.item
  if status.state == "stale" then
    return ("STALE  %s — %d commit(s) to %s since %s"):format(
      item.text,
      status.commits,
      item.ref,
      item.verified
    )
  end
  if status.state == "unverified" then
    return ("UNVERIFIED  %s — cites %s, never verified"):format(item.text, item.ref)
  end
  if status.state == "uncited" then
    return ("UNCITED  %s — no @ref, so it can never be flagged"):format(item.text)
  end
  return ("ok  %s — %s unchanged since %s"):format(item.text, item.ref, item.verified)
end

---Where a quickfix entry should jump to.
---
---The **cited source line**, not the checklist line, whenever there is one:
---the point of a stale flag is to send someone to the code they need to
---re-read. A `- [ ]` line in a Markdown file is where you go to *record* the
---answer, which is the second step, not the first. Items with no citation
---fall back to the ledger line, since there is nowhere else to go.
---@param cfg Documentation.Opts
---@param status Documentation.Checklist.Status
---@return string filename
---@return integer lnum
local function target(cfg, status)
  local item = status.item
  if item.ref then
    return cfg.root .. "/" .. item.ref, item.ref_line or 1
  end
  return cfg.root .. "/" .. item.file, item.line
end

---@param ctx Documentation.Bindings.Ctx
---@param arg string Everything after "checklist" — "all", or "".
function M.run(ctx, arg)
  local want_all = vim.trim(arg or "") == "all"
  local ir = ctx.handle.ir()
  local ledger = ir.checklist

  if not ledger then
    ctx.notify.info(
      "No checklist in this repository. Create docs/CHECKLIST/*.md (or docs/CHECKLIST.md) "
        .. "— see docs/CHECKLIST_FORMAT.md."
    )
    return
  end

  local progress = require("documentation.bindings.progress").create(ctx, "reading history")
  -- commit_dates() is asynchronous now, so everything that needs the history
  -- moved into its callback. The command returns immediately; the progress
  -- handle stays up until the callback closes it.
  commit_dates(ctx.cfg.root, ctx.cfg.out_dir or "docs/map", function(dates, err)
    if progress then
      progress:finish(err or "history read")
    end
    if not dates then
      ctx.notify.warn(err or "could not read history")
      return
    end

    local checklist = require("documentation.core.checklist")
    local statuses = checklist.status(ledger, dates)

    local items = {}
    local stale, unverified = 0, 0
    for _, status in ipairs(statuses) do
      if status.state == "stale" then
        stale = stale + 1
      elseif status.state == "unverified" then
        unverified = unverified + 1
      end

      if want_all or status.state == "stale" or status.state == "unverified" then
        local filename, lnum = target(ctx.cfg, status)
        items[#items + 1] = {
          filename = filename,
          lnum = lnum,
          col = 1,
          text = describe(status),
          -- `E` only for stale: an unverified item is a gap in the ledger, not
          -- a claim that has gone wrong, and marking both the same way would
          -- make the one that matters harder to pick out.
          type = status.state == "stale" and "E" or "W",
        }
      end
    end

    if #items == 0 then
      ctx.notify.info(
        ("Checklist clean: %d item(s), %d verified against a citation, nothing stale."):format(
          ledger.total,
          ledger.cited
        )
      )
      return
    end

    list.qf(
      items,
      ("docmap checklist: %d stale, %d unverified, %d total"):format(
        stale,
        unverified,
        ledger.total
      )
    )
    ctx.notify.info(
      ("%d stale, %d unverified, of %d item(s)."):format(stale, unverified, ledger.total)
    )
  end, ctx.cfg)
end

return M
