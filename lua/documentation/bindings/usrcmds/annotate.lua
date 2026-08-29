---@module 'documentation.bindings.usrcmds.annotate'
--- `:DocMap annotate [--write|--sidecar] [--dry-run]` — scaffold a
--- `---@module` header (and a `---@class`/`---@field` block, when the file
--- returns a table) for every file `missing-module-tag` already flags.
---
--- No flag (or `--dry-run`) previews everything in a scratch buffer and
--- writes nothing — the safe default for a command that edits source files.
--- `--write` splices the header into each file in place; `--sidecar` writes
--- it to `<path>.annot.lua` next to the original instead, for review before
--- merging it in by hand.

local list = require("lib.nvim.ui.list")

local M = {}

---@param arg string
---@return "inline"|"sidecar"|nil write_mode `nil` means dry-run.
---@return string? err
local function parse_flags(arg)
  local write_mode, force_dry_run
  for token in vim.gsplit(vim.trim(arg or ""), "%s+") do
    if token == "--write" then
      write_mode = "inline"
    elseif token == "--sidecar" then
      write_mode = "sidecar"
    elseif token == "--dry-run" then
      force_dry_run = true
    elseif token ~= "" then
      return nil, "Unknown flag: " .. token .. " (expected --write, --sidecar or --dry-run)"
    end
  end
  if force_dry_run then
    write_mode = nil
  end
  return write_mode
end

---Show every plan in a scratch buffer, none of it written anywhere.
---@param plans table[]
local function preview(plans)
  local annotate = require("documentation.core.annotate")
  local lines = {}
  for _, p in ipairs(plans) do
    if #lines > 0 then
      lines[#lines + 1] = ""
    end
    vim.list_extend(lines, annotate.preview_lines(p))
  end

  local safe_api = require("lib.nvim.safe_api")
  local name = "docmap-annotate-preview.lua"
  local existing
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if safe_api.is_valid_buffer(b) and vim.fs.basename(vim.api.nvim_buf_get_name(b)) == name then
      existing = b
      break
    end
  end

  -- Reuse in place rather than force-delete + enew: the previous buffer may
  -- still be visible in another window (e.g. the user split it to compare
  -- runs), and force-deleting a visible buffer swaps that window to an
  -- auto-created empty scratch buffer instead. Asking the same query twice
  -- should just refresh the content the reader is already looking at.
  if existing then
    vim.bo[existing].modifiable = true
    vim.api.nvim_buf_set_lines(existing, 0, -1, false, lines)
    vim.api.nvim_win_set_buf(0, existing)
    return
  end

  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "lua"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  pcall(vim.api.nvim_buf_set_name, buf, name)
end

---@param ctx Documentation.Bindings.Ctx
---@param arg string Everything after "annotate".
function M.run(ctx, arg)
  local write_mode, err = parse_flags(arg)
  if err then
    ctx.notify.warn(err)
    return
  end

  local annotate = require("documentation.core.annotate")
  local ir = ctx.handle.ir()
  local candidates = annotate.candidates(ir)
  if #candidates == 0 then
    ctx.notify.info("Every file already declares ---@module. Nothing to annotate.")
    return
  end

  local root = ctx.cfg.root
  local lua_root = ctx.cfg.lua_root or "lua"
  local plans = {}
  for _, node in ipairs(candidates) do
    local plan = annotate.plan(node, root, lua_root)
    if plan then
      plans[#plans + 1] = plan
    end
  end
  table.sort(plans, function(a, b)
    return a.path < b.path
  end)

  if write_mode == nil then
    preview(plans)
    ctx.notify.info(
      ("%d file(s) missing ---@module — preview only. :DocMap annotate --write to apply, --sidecar for *.annot.lua files instead."):format(
        #plans
      )
    )
    return
  end

  local written, failed = {}, {}
  for _, p in ipairs(plans) do
    local ok, werr = annotate.apply(p, root, write_mode)
    if ok then
      written[#written + 1] = p.path
    else
      failed[#failed + 1] = ("%s: %s"):format(p.path, werr)
    end
  end

  for _, msg in ipairs(failed) do
    ctx.notify.warn(msg)
  end

  if #written > 0 then
    list.qf(
      vim.tbl_map(function(path)
        return { filename = root .. "/" .. path, lnum = 1, text = "annotated" }
      end, written),
      "docmap annotate"
    )
  end

  ctx.notify.info(
    ("%d file(s) annotated (%s)%s. Run :DocMap to refresh the map."):format(
      #written,
      write_mode == "sidecar" and "sidecar *.annot.lua" or "written in place",
      #failed > 0 and (", %d failed"):format(#failed) or ""
    )
  )
end

return M
