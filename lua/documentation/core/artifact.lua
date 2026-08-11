---@module 'documentation.core.artifact'
--- Reading a generated `module_map.json` back into an in-memory IR.
---
--- This logic used to live in `editor/browse/source.lua` and is unchanged —
--- it moved here because it is not editor work. Nothing in it touches a
--- buffer, a window or a command; it reads a file and reshapes a table. It
--- had to move because the standalone build needs exactly this and the layer
--- rule (`core` may not reach `editor`, see `standalone/docmap.lua`'s own
--- `layers` config) correctly forbids reaching back for it. `source.lua`
--- still exposes the same three names and now delegates here, so every
--- existing caller keeps working.
---
--- The alternative — a second copy of `rehydrate` in the standalone half —
--- would have been ten easy lines and two places for the artifact's shape to
--- drift apart. This codebase has already paid for that class of bug once
--- (`telemetry_join`'s own header documents the two-key-spaces defect); one
--- owner per shape is the rule that prevents it.

local M = {}

---Normalize a repo root the same way `documentation.editor.registry` does,
---so a handle installed there and an artifact read here agree on the key.
---@param root string
---@return string
function M.norm_root(root)
  return (tostring(root or ""):gsub("\\", "/"):gsub("/+$", ""))
end

---Where a project's generated artifact lives.
---@param opts table Needs `root`, optionally `out_dir`.
---@return string
function M.artifact_path(opts)
  return M.norm_root(opts.root) .. "/" .. (opts.out_dir or "docs/map") .. "/module_map.json"
end

---Turn a decoded artifact into the in-memory IR shape every reader expects.
---
---The two are deliberately *not* the same document. `docmap.to_json` writes
---`nodes` as an array in walk order — that is what makes the file
---byte-deterministic, since a JSON object's key order would not be — and
---carries no `order` key, because the array *is* the order. In memory,
---`ir.nodes` is a map keyed by id and `ir.order` is the walk. Rehydrating
---here means the rest of the program reads one shape regardless of whether
---the IR came off disk or out of a live handle.
---@param doc table Decoded artifact.
---@return Documentation.IR
function M.rehydrate(doc)
  local nodes, order = {}, {}
  for i, n in ipairs(doc.nodes or {}) do
    nodes[n.id] = n
    order[i] = n.id
  end
  doc.nodes = nodes
  doc.order = order
  doc.edges = doc.edges or {}
  return doc
end

---Decode an artifact's text into an IR, or nil if it is not one.
---
---`luanil` matters here, it is not a style choice: the artifact writes a
---literal `null` for every absent optional field (`module`, `parent`,
---`types_detail`, …). Without it those decode to `vim.NIL`, which is a
---*truthy* userdata — so `node.module or node.name` would render
---"userdata: 0x…" and `types_detail == nil` (the "LuaLS never ran" signal)
---would never be true. Dropping the keys instead restores exactly the
---in-memory semantics.
---@param content string
---@return Documentation.IR|nil
function M.decode(content)
  if type(content) ~= "string" or content == "" then
    return nil
  end
  local ok, doc = pcall(vim.json.decode, content, { luanil = { object = true, array = true } })
  if not ok or type(doc) ~= "table" or type(doc.nodes) ~= "table" then
    return nil
  end
  return M.rehydrate(doc)
end

---The map as it stands on disk right now — whatever the last generation
---wrote, committed or not.
---
---Absence is a normal outcome, not an error: a project that has never been
---generated simply has none, and every caller already has to say so rather
---than fail.
---@param opts table
---@return Documentation.IR|nil
function M.load(opts)
  local read = require("lib.nvim.fs.read")
  return M.decode(read(M.artifact_path(opts)) or "")
end

return M
