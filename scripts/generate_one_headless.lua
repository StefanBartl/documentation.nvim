---@module 'scripts.generate_one_headless'
--- The subprocess `documentation.editor.generate_all` spawns, once per
--- project — `nvim --headless -l scripts/generate_one_headless.lua`.
---
--- **Why this file exists, rather than `generate_all.lua` inlining a
--- three-line `-c "lua …"` string as its first version did.** Found by
--- letting that version run in CI, not predicted: a bare `nvim --headless`
--- has *no* plugin manager and an empty runtimepath by default, and on a
--- real developer's own machine that is invisible, because their default
--- `nvim --headless` already goes through their real `init.lua` and
--- lazy.nvim — which happens to put `documentation` and `lib.nvim` on the
--- runtimepath anyway. In CI, and for any consumer whose default headless
--- Neovim is genuinely bare, `require("documentation")` inside the
--- spawned subprocess had nothing to resolve against at all. Passed
--- locally, on the one machine that could never have caught it.
---
--- Fixed the same way `scripts/gen_map.lua`/`scripts/mcp_server.lua`
--- already had to: this file puts documentation.nvim's own root (passed
--- via `DOCMAP_GEN_PLUGIN_ROOT` — `generate_all.lua` already knows its own
--- location via `debug.getinfo`, so the subprocess does not need to
--- re-derive it) and `lib.nvim`'s (the same three-candidate search
--- `ensure()` below mirrors from `gen_map.lua`) onto the runtimepath by
--- hand, before requiring anything either depends on.
---
---   DOCMAP_GEN_PLUGIN_ROOT=<documentation.nvim's own repo root>
---   DOCMAP_GEN_ROOT=<the project to generate a map for>
---   DOCMAP_GEN_TITLE=<optional, passed through to generate()'s opts.title>
---   nvim --headless -l scripts/generate_one_headless.lua

local plugin_root = vim.env.DOCMAP_GEN_PLUGIN_ROOT
if not plugin_root or plugin_root == "" then
  io.stderr:write("generate_one_headless: DOCMAP_GEN_PLUGIN_ROOT is not set\n")
  os.exit(1)
end
vim.opt.runtimepath:prepend(plugin_root)

--- Same shape as `scripts/gen_map.lua`'s own `ensure()`, not shared code:
--- that one resolves dependencies *of the repository `root` names*, this
--- one resolves a dependency of `plugin_root` (documentation.nvim's own
--- install location, not necessarily this process's cwd) — different
--- enough in what `root` means to keep separate rather than force one
--- helper to serve both call shapes.
---@param modname string
---@param dirname string
local function ensure(modname, dirname)
  if pcall(require, modname) then
    return
  end
  local candidates = {}
  local env_dir = vim.env[dirname:upper():gsub("[.-]", "_") .. "_DIR"]
  if env_dir and env_dir ~= "" then
    candidates[#candidates + 1] = env_dir
  end
  candidates[#candidates + 1] = plugin_root .. "/.deps/" .. dirname
  candidates[#candidates + 1] = vim.fs.dirname(plugin_root) .. "/" .. dirname
  for _, dir in ipairs(candidates) do
    if vim.fn.isdirectory(dir) == 1 then
      vim.opt.runtimepath:prepend(dir)
      if pcall(require, modname) then
        return
      end
    end
  end
  io.stderr:write(
    ("generate_one_headless: %s not found (probed require('%s')).\n"):format(dirname, modname)
  )
  os.exit(1)
end

ensure("lib.nvim.fs.read", "lib.nvim")
ensure("documentation.core.cli", "documentation.nvim")

local root = vim.env.DOCMAP_GEN_ROOT
if not root or root == "" then
  io.stderr:write("generate_one_headless: DOCMAP_GEN_ROOT is not set\n")
  os.exit(1)
end
local title = vim.env.DOCMAP_GEN_TITLE
if title == "" then
  title = nil
end

local ok, err =
  pcall(require("documentation").generate, { root = root, title = title, luals = true })
if not ok then
  io.stderr:write(tostring(err))
  vim.cmd("cquit!")
end
vim.cmd("qa!")
