---@module 'documentation.bindings.usrcmds.dot'
--- `:DocMap dot [deps|calls] [module]` — the graph as Graphviz DOT source.
---
--- Opens the source in a scratch buffer rather than writing a file or shelling
--- out to `dot`. Shelling out would add an external dependency and a "dot not
--- found" failure mode to a feature whose entire output is text; a buffer is
--- something to yank, `:w`, or pipe through `:%!dot -Tsvg` — all of which the
--- user can already do better than a flag could.

local M = {}

---@param ctx Documentation.Bindings.Ctx
---@param arg string Everything after "dot" — "[deps|calls] [module]".
function M.run(ctx, arg)
  local kind, target = vim.trim(arg or ""):match("^(%a*)%s*(.-)$")
  kind = (kind == "" or kind == "deps") and "require" or kind
  if kind ~= "require" and kind ~= "calls" then
    ctx.notify.warn("Unknown graph: " .. kind .. " (expected deps or calls)")
    return
  end

  local ir = ctx.handle.ir()
  local scope
  if target ~= "" then
    scope = ctx.find_node(ir, target, ctx.cfg.lua_root or "lua")
    if not scope then
      ctx.notify.warn("No module matching '" .. target .. "' in the map.")
      return
    end
  end

  local src = require("documentation").render.dot(ir, {
    kind = kind == "calls" and "call" or "require",
    scope = scope,
  })

  -- A name identifies the query, so asking the same one twice should reuse it
  -- rather than fail. `nvim_buf_set_name` *raises* on a collision, and the
  -- error was swallowed by the command wrapper: the second `:DocMap dot`
  -- produced an unnamed buffer and no message at all. Wiping the previous one
  -- first is both the fix and the behaviour one would want — this is a
  -- regenerated scratch view, not a document.
  local name = ("docmap-%s%s.dot"):format(kind, scope and ("-" .. scope:gsub("[^%w]+", "_")) or "")
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.fs.basename(vim.api.nvim_buf_get_name(b)) == name then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end

  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(src, "\n", { plain = true }))
  vim.bo[buf].filetype = "dot"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  pcall(vim.api.nvim_buf_set_name, buf, name)
  ctx.notify.info("Pipe it: :%!dot -Tsvg > graph.svg")
end

return M
