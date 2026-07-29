---@module 'documentation.bindings.usrcmds.diff'
--- `:DocMap diff [ref]` — what changed about the tree's *shape* since `ref`.
---
--- The committed artifact is in every commit, so any revision can be compared
--- without generating anything. `git show <ref>:<artifact>` is the whole
--- retrieval; the comparison itself is `documentation.core.diff`, which is pure
--- and therefore also usable from a CI job with no editor involved.

local M = {}

---@param ctx Documentation.Bindings.Ctx
---@param arg string Everything after "diff" — a revision, or "" for HEAD.
function M.run(ctx, arg)
  local ref = vim.trim(arg or "")
  if ref == "" then
    ref = "HEAD"
  end
  local rel = (ctx.cfg.out_dir or "docs/map") .. "/module_map.json"

  local proc = vim
    .system({ "git", "show", ("%s:%s"):format(ref, rel) }, {
      cwd = ctx.cfg.root,
      text = true,
    })
    :wait()
  if proc.code ~= 0 then
    ctx.notify.warn(("Cannot read %s at %s: %s"):format(rel, ref, vim.trim(proc.stderr or "")))
    return
  end

  -- `luanil` for the same reason `browse.source` needs it: the artifact writes
  -- a literal `null` for absent optional fields, and `vim.NIL` is truthy —
  -- without it every one of them reads as present.
  local ok_decode, doc = pcall(vim.json.decode, proc.stdout, {
    luanil = { object = true, array = true },
  })
  if not ok_decode or type(doc) ~= "table" or type(doc.nodes) ~= "table" then
    ctx.notify.warn(("The map at %s is not a readable docmap artifact."):format(ref))
    return
  end

  local before = require("documentation.editor.browse.source").rehydrate(doc)
  local diff_mod = require("documentation.core.diff")
  local result = diff_mod.compare(before, ctx.handle.ir())
  local lines = diff_mod.render(result, before, ctx.handle.ir(), ref)

  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false

  if diff_mod.is_empty(result) then
    ctx.notify.info(("Nothing structural changed since %s."):format(ref))
  else
    ctx.notify.info(
      ("%d module(s), %d function(s), %d dependency change(s) since %s"):format(
        #result.nodes_added + #result.nodes_removed,
        #result.functions_added + #result.functions_removed,
        #result.deps_added + #result.deps_removed,
        ref
      )
    )
  end
end

return M
