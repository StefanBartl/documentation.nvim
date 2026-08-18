---@module 'documentation.bindings.usrcmds.mermaid'
--- `:DocMap mermaid [tree|deps]` — the map as Mermaid source, in a buffer.
---
--- The renderer has existed since `overview.md` needed a graph GitHub would
--- draw without running JavaScript; what was missing was any way to ask for
--- it on its own. `docs/ROADMAP/IDEAS/IDEAS.md` §6.4 is that gap, and it is
--- one command, not a feature: nothing here computes anything
--- `core/render/mermaid.lua` did not already.
---
--- **A scratch buffer, not a file**, exactly as `usrcmds/dot.lua` decided for
--- the same question and for the same reason: the entire output is text, so a
--- buffer is something to yank into a README, `:w` somewhere, or leave open
--- beside the code. Writing a file would invent a path convention this plugin
--- does not need, and shelling out to a renderer would add a "not installed"
--- failure mode to a feature that produces characters.
---
--- Two shapes rather than one, because the two answer different questions and
--- both already exist in the renderer:
---
---   * `tree` (the default) is the module hierarchy, bounded by depth — what
---     `overview.md` embeds.
---   * `deps` is the require graph, collapsed to a depth so the picture stays
---     readable; `render_deps`'s own header explains why it is coarse.

local M = {}

---@param ctx Documentation.Bindings.Ctx
---@param arg string Everything after "mermaid" — "[tree|deps]".
function M.run(ctx, arg)
  local kind = vim.trim(arg or "")
  if kind == "" then
    kind = "tree"
  end
  if kind ~= "tree" and kind ~= "deps" then
    ctx.notify.warn("Unknown graph: " .. kind .. " (expected tree or deps)")
    return
  end

  local ir = ctx.handle.ir()
  local docmap = require("documentation")
  local src = kind == "deps" and docmap.render.mermaid_deps(ir, {})
    or docmap.render.mermaid(ir, nil, {})

  -- Same buffer-reuse dance as `usrcmds/dot.lua`, and for the reason that
  -- module found the hard way: `nvim_buf_set_name` raises on a name
  -- collision, the wrapper swallowed it, and asking the same question twice
  -- produced an unnamed buffer and no message. Reused in place rather than
  -- force-deleted, since the previous buffer may still be visible in another
  -- window.
  local safe_api = require("lib.nvim.safe_api")
  local name = ("docmap-%s.mmd"):format(kind)
  local existing
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if safe_api.is_valid_buffer(b) and vim.fs.basename(vim.api.nvim_buf_get_name(b)) == name then
      existing = b
      break
    end
  end

  local lines = vim.split(src, "\n", { plain = true })

  if existing then
    vim.bo[existing].modifiable = true
    vim.api.nvim_buf_set_lines(existing, 0, -1, false, lines)
    vim.api.nvim_win_set_buf(0, existing)
    ctx.notify.info("Paste it into a README — GitHub renders mermaid fences.")
    return
  end

  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  -- `markdown`, not `mermaid`: the renderer emits a fenced block, so the
  -- buffer's content genuinely is markdown and highlights as such without a
  -- plugin nobody is required to have.
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  pcall(vim.api.nvim_buf_set_name, buf, name)
  ctx.notify.info("Paste it into a README — GitHub renders mermaid fences.")
end

return M
