---@module 'documentation.bindings.usrcmds.consumers'
--- `:DocMap consumers [dir]` — who actually uses this library.
---
--- Reads every `*/docs/map/module_map.json` under `dir` (the parent of this
--- repository by default, which is where sibling checkouts live) and joins
--- them against this project's own map. See `core/consumers.lua` for the
--- join and, more importantly, for what the result does and does not claim.
---
--- **Committed maps, not live scans.** Each consumer is read as it last
--- committed its artifact — so a project whose map is stale under-reports,
--- and the report says how many maps it managed to read so that number can
--- be sanity-checked against how many were expected. Scanning thirty
--- repositories live instead would take minutes and would still only cover
--- the ones present on this machine.

local M = {}

---@param ctx Documentation.Bindings.Ctx
---@param arg string A directory holding sibling checkouts; defaults to the repository's parent.
function M.run(ctx, arg)
  local root = (ctx.cfg.root:gsub("\\", "/"):gsub("/+$", ""))
  local dir = vim.trim(arg or "")
  if dir == "" then
    dir = vim.fs.dirname(root)
  end
  dir = (dir:gsub("\\", "/"):gsub("/+$", ""))

  if vim.fn.isdirectory(dir) == 0 then
    ctx.notify.warn("Not a directory: " .. dir)
    return
  end

  local consumers = require("documentation.core.consumers")
  local maps, skipped = consumers.load(dir, root)

  if #maps == 0 then
    ctx.notify.warn(
      ("No committed maps found under %s (looked for */docs/map/module_map.json)"):format(dir)
    )
    return
  end

  local index = consumers.index(ctx.handle.ir(), maps)
  local lines = consumers.render(index, ("Consumers of %s"):format(vim.fs.basename(root)))
  if skipped > 0 then
    table.insert(lines, 3, ("%d map(s) could not be read and are not counted."):format(skipped))
  end

  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  pcall(vim.api.nvim_buf_set_name, buf, "docmap-consumers.md")

  ctx.notify.info(
    ("%d used externally, %d internally, %d referenced by nobody (%d maps)"):format(
      index.counts.external,
      index.counts.internal,
      index.counts.unreferenced,
      index.maps
    )
  )
end

return M
