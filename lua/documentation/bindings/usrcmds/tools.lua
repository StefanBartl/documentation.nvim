---@module 'documentation.bindings.usrcmds.tools'
--- `:DocMap tools` — this repo's own `lib.nvim.deps` manifest
--- (`docs/install.json`/`docs/INSTALL.md`) into the quickfix list.
---
--- Mirrors `plugins.lua`'s shape exactly: the data already sits on the
--- scanned IR (`ir.tools`, read during `scan_full` — see `core/tools.lua`),
--- so there is no second pass to wait on. A different ecosystem convention
--- from `plugins`, though — not "what does this repo depend on", but "what
--- external CLI tools does it optionally lean on, and why".
---
--- Presence on this host is not part of `ir.tools` (see `core/tools.lua`'s
--- header) and is not probed here either — this command lists what is
--- *declared*, deferring "is it installed" to lib.nvim's own `:Lib deps
--- show`, which already does that live.

local list = require("lib.nvim.ui.list")

local M = {}

---One line per declared tool: bin, required/optional, why, package names.
---@param tool Documentation.Tools.Tool
---@return string
local function describe(tool)
  local pkgs = {}
  for mgr in pairs(tool.pkg) do
    pkgs[#pkgs + 1] = mgr
  end
  table.sort(pkgs)
  return ("%s%s  ·  %s  ·  pkg: %s"):format(
    tool.bin,
    tool.required and "  [required]" or "",
    tool.why,
    table.concat(pkgs, ",")
  )
end

---@param ctx Documentation.Bindings.Ctx
function M.run(ctx)
  local ir = ctx.handle.ir()
  local result = ir.tools

  if not result then
    ctx.notify.info(
      "No lib.nvim.deps manifest found (docs/install.json or docs/INSTALL.md), "
        .. "or lib.nvim.deps is unavailable — see :help documentation-tools."
    )
    return
  end

  if #result.tools == 0 and #result.errors == 0 then
    ctx.notify.info(("%s declares no tools."):format(result.source))
    return
  end

  local items = {}
  for _, tool in ipairs(result.tools) do
    items[#items + 1] = {
      filename = ctx.cfg.root .. "/" .. result.source,
      lnum = 1,
      text = describe(tool),
    }
  end
  for _, e in ipairs(result.errors) do
    items[#items + 1] = {
      filename = ctx.cfg.root .. "/" .. result.source,
      lnum = 1,
      text = ("[invalid entry #%d] %s"):format(e.index, e.message),
    }
  end

  list.qf(items, "docmap tools")

  ctx.notify.info(
    ("%d tool(s) declared in %s%s"):format(
      #result.tools,
      result.source,
      #result.errors > 0
          and ("  ·  %d invalid entr%s"):format(
            #result.errors,
            #result.errors == 1 and "y" or "ies"
          )
        or ""
    )
  )
end

return M
