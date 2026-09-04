---@module 'documentation.editor.command'
--- **Deprecated alias** for [`documentation.bindings.usrcmds`](../bindings/usrcmds/init.lua).
---
--- The command layer moved out of `editor/` when the bindings layer was split
--- out. `documentation.editor` is the half that touches the running editor's
--- state — the registry, the browser, the server, the health check — while the
--- commands are the *surface* over all of it, and a 700-line if-chain sitting
--- among them was the clearest sign the two were not the same thing. See that
--- module's header for the dispatch rule that replaced the chain.
---
--- Kept because both entries below are published: `docs/pipeline.md` documents
--- `require("documentation.editor.command").setup()`, and `find_node` is called
--- from `browse/init.lua` and from the specs.
---
--- New code should require `documentation.bindings.usrcmds`.

local M = {}

---Resolve a user-typed name to a node id.
---
---Delegates to [`core/find.lua`](../core/find.lua), where it lives: the lookup
---touches nothing but the IR, and `tagfiles.lua` needs it too — a core module
---reaching into the editor half for it is exactly what the
---`documentation.core` layer rule forbids.
---@param ir Documentation.IR
---@param name string
---@param lua_root string
---@return string? node_id
function M.find_node(ir, name, lua_root)
  return require("documentation.core.find").node(ir, name, lua_root)
end

---@param opts Documentation.Opts?
---@return Documentation.Handle
function M.setup(opts)
  return require("documentation.bindings.usrcmds").setup(opts)
end

return M
