---@meta
---@module 'documentation.mcp.@types'
--- Types for the MCP server layer, split across `mcp/protocol.lua` (JSON-RPC
--- dispatch) and `mcp/tools.lua` (the tool catalogue).

---One server instance, bound to one installed handle.
---@class Documentation.Mcp.Server
---@field handle Documentation.Handle
---@field name string
---@field out_dir? string Repo-relative output directory — the one piece of `Documentation.Opts` a tool call needs that `handle` does not carry. See `mcp/tools.lua`'s `docmap_checklist`.
---@field initialized boolean Set by the `initialized` notification; informational only — see `mcp/protocol.lua`'s `request` for why nothing is gated on it.

---@class Documentation.Mcp.ToolCtx
---@field out_dir? string Repo-relative output directory, for excluding the generated map from history walks. Only `docmap_checklist` uses this today.

return {}
