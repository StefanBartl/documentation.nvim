---@module 'documentation.bindings.usrcmds.helptags'
--- `:DocMap helptags` — regenerate this plugin's own `doc/tags`.
---
--- Mostly a convenience for working *on* the plugin: every plugin manager runs
--- `:helptags` on install and update, so a user who installed normally never
--- needs this. A local checkout on `runtimepath` — the way the plugin is
--- developed — has no such step, and `:help documentation.nvim` then fails with
--- a "Sorry, no help for" that looks like the docs are missing rather than
--- unindexed.
---
--- Finds the directory through `nvim_get_runtime_file` rather than by walking
--- up from this file: the answer wanted is "where is the `doc/` Neovim will
--- actually search", which is a runtimepath question, and a path derived from
--- `debug.getinfo` would be right about the checkout and wrong about the
--- installation whenever the two differ.
---
--- `doc/tags` is in `.gitignore` — it is a generated index over committed
--- `.txt` sources, and committing it would put a file in the tree that every
--- clone regenerates differently.

local M = {}

---@param ctx Documentation.Bindings.Ctx
function M.run(ctx)
  local found = vim.api.nvim_get_runtime_file("doc/documentation.txt", false)
  if #found == 0 then
    ctx.notify.warn("Cannot find doc/documentation.txt on the runtimepath.", {
      "This plugin's doc/ directory is not on 'runtimepath'.",
    })
    return
  end

  local doc_dir = vim.fs.dirname(found[1])
  local ok, err = pcall(vim.cmd.helptags, doc_dir)
  if not ok then
    ctx.notify.warn(("Could not write %s/tags: %s"):format(doc_dir, tostring(err)))
    return
  end

  ctx.notify.info(("Wrote %s/tags — :help documentation.nvim"):format(doc_dir))
end

return M
