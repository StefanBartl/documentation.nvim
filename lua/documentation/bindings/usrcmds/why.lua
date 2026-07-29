---@module 'documentation.bindings.usrcmds.why'
--- `:DocMap why <a> <b>` — why does A end up pulling in B?
---
--- The question the Deps view can only be walked by hand to answer. The chain
--- goes to the quickfix list rather than to a message, because every hop *is* a
--- location: the edge carries the line the `require` is written on, so each
--- entry jumps straight to the line that creates that link. A message would
--- have been something to read; this is something to act on.

local M = {}

---@param ctx Documentation.Bindings.Ctx
---@param arg string Everything after "why" — "<from> <to>".
function M.run(ctx, arg)
  local a, b = vim.trim(arg or ""):match("^(%S+)%s+(%S+)$")
  if not a then
    ctx.notify.warn("Usage: :" .. ctx.command_name .. " why <from> <to>")
    return
  end

  local ir = ctx.handle.ir()
  local lua_root = ctx.cfg.lua_root or "lua"
  local from_id = ctx.find_node(ir, a, lua_root)
  local to_id = ctx.find_node(ir, b, lua_root)
  if not from_id or not to_id then
    ctx.notify.warn(("No module matching '%s' in the map."):format(from_id and b or a))
    return
  end

  local chain = require("documentation.core.deps").path(ir, from_id, to_id)
  if not chain then
    ctx.notify.info(("%s does not reach %s at all."):format(a, b))
    return
  end
  if #chain == 0 then
    ctx.notify.info("Those are the same module.")
    return
  end

  local items, names = {}, { ir.nodes[from_id].module or from_id }
  local lazy = false
  for _, e in ipairs(chain) do
    local target = ir.nodes[e.to]
    names[#names + 1] = (target.module or e.to) .. (e.deferred and " (lazy)" or "")
    lazy = lazy or e.deferred == true
    items[#items + 1] = {
      filename = ctx.cfg.root .. "/" .. ((ir.nodes[e.from] or {}).source or e.from),
      lnum = e.line or 1,
      col = 1,
      text = ("%s → %s%s"):format(
        (ir.nodes[e.from] or {}).module or e.from,
        target.module or e.to,
        e.deferred and "  (lazy)" or ""
      ),
    }
  end

  vim.fn.setqflist({}, " ", {
    title = ("docmap why: %s → %s"):format(a, b),
    items = items,
  })
  ctx.notify.info(("%d hop%s%s:  %s"):format(
    #chain,
    #chain == 1 and "" or "s",
    -- A path that only exists through a deferred require does not run at load
    -- time, which is usually the difference between "has to go" and "is
    -- fine" — so it is said up front, not buried in the list.
    lazy and ", lazy somewhere" or ", all at load time",
    table.concat(names, " → ")
  ))
  vim.cmd("copen")
end

return M
