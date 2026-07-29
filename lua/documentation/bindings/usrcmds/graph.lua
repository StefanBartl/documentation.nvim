---@module 'documentation.bindings.usrcmds.graph'
--- `:DocMap graph {deps|calls} [module]` — open the page on a graph view.
---
--- The CLI-side counterpart to right-clicking a box: it answers the same
--- question from where the code is being read, without hunting for the module
--- in the tree once the page is open. `module` is matched against the declared
--- `@module` path first and the node id second, so both "lib.nvim.fs" and
--- "lua/lib/nvim/fs" work.
---
--- No rendering happens here. The page's navigable state is entirely in its URL
--- fragment, so this is `open` with a hash — see `open.lua`.

local M = {}

---@param ctx Documentation.Bindings.Ctx
---@param arg string Everything after "graph" — "{deps|calls} [module]".
function M.run(ctx, arg)
  local kind, target = vim.trim(arg or ""):match("^(%a+)%s*(.-)$")

  -- Bare `:DocMap graph` used to fall through every branch of the old
  -- if-chain and land on the default action, which *regenerates the
  -- artifacts*. A missing argument now says so instead of writing files.
  if not kind or kind == "" then
    ctx.notify.warn(("Usage: :%s graph {deps|calls} [module]"):format(ctx.command_name))
    return
  end
  if kind ~= "deps" and kind ~= "calls" then
    ctx.notify.warn("Unknown graph: " .. kind .. " (expected deps or calls)")
    return
  end

  local ir = ctx.handle.ir()
  local center = ir.root
  if target ~= "" then
    local found = ctx.find_node(ir, target, ctx.cfg.lua_root or "lua")
    if not found then
      ctx.notify.warn("No module matching '" .. target .. "' in the map.")
      return
    end
    center = found
  end

  ctx.open_map(
    ("#tab=hierarchy&center=%s&view=%s&dir=out&depth=2"):format(
      vim.uri_encode(center, "rfc2396"),
      kind
    )
  )
end

return M
