---@module 'documentation.core.find'
--- Resolve a user-typed name to a node id.
---
--- One function, in its own file, and the reason is the layering rule rather
--- than tidiness. This lived on `command.lua` — the editor half — while
--- `tagfiles.lua` reached across for it, which made the core depend on the
--- editor for a lookup that touches nothing but the IR. The
--- `documentation.core` → `documentation.editor` layer rule found it the
--- moment it was declared, which is the entire point of declaring it.

local M = {}

---Three ways, in order of how specific they are: a declared `@module` path, a
---raw node id, and — for a **namespace**, a directory with no `init.lua` and
---therefore no `@module` at all — the module path its location implies. That
---last one is not a nicety: `lua/lib/nvim/fs` is a namespace, so
---`:DocMap graph deps lib.nvim.fs` found nothing until it was added, and
---namespaces are precisely the aggregation points a dependency graph is
---interesting at.
---@param ir Documentation.IR
---@param name string
---@param lua_root string
---@return string? node_id
function M.node(ir, name, lua_root)
  local check = require("documentation.core.check")
  local fallback
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.module == name or id == name then
      return id
    end
    if not fallback and not node.module then
      if check.expected_module(node.path .. "/init.lua", lua_root) == name then
        fallback = id
      end
    end
  end
  return fallback
end

return M
