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

local M = {}

---Collect `path -> ISO commit dates` for every path in the repository.
---
---One `git log` for the whole tree rather than one per cited path: a ledger
---with fifty items would otherwise spawn fifty processes, and the whole-tree
---walk is the same shape `usrcmds/churn.lua` already runs and already found
---acceptable. `%cs` is git's own short committer date — `YYYY-MM-DD`, already
---the format `@verified` is written in, so nothing has to parse a date.
---@param cwd string
---@param out_dir string Excluded: in a repo that commits its own map, it is touched by nearly every commit.
---@return table<string, string[]>? dates
---@return string? err
local function commit_dates(cwd, out_dir)
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

  local proc
  vim.system(cmd, { cwd = cwd, text = true }, function(res)
    proc = res
  end)
  local settled = vim.wait(120000, function()
    return proc ~= nil
  end, 20)

  if not settled or not proc then
    return nil, "git log did not finish within 120s"
  end
  if proc.code ~= 0 then
    return nil, "git log failed: " .. vim.trim(proc.stderr or "")
  end

  local dates = {}
  for record in (proc.stdout or ""):gmatch("[^\30]+") do
    local date
    for line in record:gmatch("[^\r\n]+") do
      local text = vim.trim(line)
      if text ~= "" then
        if not date then
          date = text
        else
          local list = dates[text]
          if not list then
            list = {}
            dates[text] = list
          end
          list[#list + 1] = date
        end
      end
    end
  end

  return dates, nil
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
  local dates, err = commit_dates(ctx.cfg.root, ctx.cfg.out_dir or "docs/map")
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

  vim.fn.setqflist({}, " ", {
    title = ("docmap checklist: %d stale, %d unverified, %d total"):format(
      stale,
      unverified,
      ledger.total
    ),
    items = items,
  })
  vim.cmd("copen")
  ctx.notify.info(
    ("%d stale, %d unverified, of %d item(s)."):format(stale, unverified, ledger.total)
  )
end

return M
