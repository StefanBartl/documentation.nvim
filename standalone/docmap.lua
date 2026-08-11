---@module 'standalone.docmap'
--- Neovim-free CLI entry point — the MVP scoped in `docs/ROADMAP/FEATURES.md`
--- ("standalone CLI, parser-less MVP"): the module tree, require graph and
--- every check/renderer that does not need per-function facts, running under
--- plain `lua`/`luajit`, no Neovim process anywhere. Deliberately mirrors
--- `scripts/gen_map.lua` (same `ensure()` dependency search, same
--- `documentation.config.build`/`documentation.core.cli.run` call shape) —
--- read that file first if this one looks unfamiliar; the difference is only
--- in how the Neovim-only bits (`vim.uv.cwd`, `vim.opt.runtimepath`,
--- `vim.cmd("cq ...")`) get replaced.
---
---   lua standalone/docmap.lua <root> [--source=lua/x] [--repo-url=U]
---                                    [--branch=B] [--check] [--lenient]
---
--- No `--full` (LuaLS enrichment shells out to `lua-language-server` via
--- `vim.system`, an editor-process capability this build does not have) and
--- no `opts.badge`/`opts.pdf` wiring beyond what `core/cli.lua` itself
--- already does — same MVP boundary `vim_shim.lua`'s header documents.
---
--- **Function-level data is no longer part of that boundary.** With a
--- `lua-tree-sitter` rock installed and `$DOCMAP_TS_DIR` pointing at a
--- directory of compiled grammars, `standalone/treesitter.lua` replaces the
--- inert parser stub and this build produces a byte-identical artifact to
--- `nvim --headless -l scripts/gen_map.lua`. Without either, it degrades to
--- the parser-less MVP exactly as before rather than failing.

require("standalone.vim_shim") -- installs _G.vim before anything requires it

local root = (arg[1] or "."):gsub("\\", "/"):gsub("/+$", "")
if root:sub(1, 1) == "-" then
  io.stderr:write(
    "standalone/docmap.lua: usage: lua standalone/docmap.lua <root> [--source=...] [--check] [--lenient]\n"
  )
  os.exit(2)
end

-- this file lives at <repo>/standalone/docmap.lua; its own repo root is
-- always on package.path so `documentation.*` resolves regardless of the
-- scanned root above (which is normally a *different* directory).
local self_dir = (debug.getinfo(1, "S").source:sub(2):match("(.*)[/\\]")) or "."
local self_root = self_dir .. "/.."

---Put a dependency's `lua/` on `package.path`, if it is not already
---reachable — same three-candidate search `scripts/gen_map.lua#ensure` uses,
---adapted from `vim.opt.runtimepath`/`vim.env` (Neovim-only) to
---`package.path`/`os.getenv`.
---@param modname string
---@param dirname string
local function ensure(modname, dirname)
  if pcall(require, modname) then
    return
  end
  local candidates = {}
  local env_dir = os.getenv(dirname:upper():gsub("[.-]", "_") .. "_DIR")
  if env_dir and env_dir ~= "" then
    candidates[#candidates + 1] = env_dir
  end
  candidates[#candidates + 1] = self_root .. "/.deps/" .. dirname
  candidates[#candidates + 1] = self_root .. "/../" .. dirname
  for _, dir in ipairs(candidates) do
    package.path = dir .. "/lua/?.lua;" .. dir .. "/lua/?/init.lua;" .. package.path
    if pcall(require, modname) then
      return
    end
  end
  io.stderr:write(
    ("standalone/docmap.lua: %s not found (probed require('%s')).\n"):format(dirname, modname)
  )
  io.stderr:write(
    ("  Set %s_DIR, clone it to .deps/%s, or check it out beside this repo.\n"):format(
      dirname:upper():gsub("[.-]", "_"),
      dirname
    )
  )
  os.exit(1)
end

package.path = self_root .. "/lua/?.lua;" .. self_root .. "/lua/?/init.lua;" .. package.path
ensure("lib.nvim.fs.read", "lib.nvim")
ensure("documentation.core.cli", "documentation.nvim")

local argv = {}
-- `--repo-url`/`--branch` are options rather than defaults because this CLI
-- is generic over any root, while `scripts/gen_map.lua` is one repository's
-- own wrapper and can hardcode both. Without them the two produce maps that
-- differ in `meta.repo_url` — correct on each side, and an apples-to-oranges
-- comparison when checking that this build is byte-faithful to a Neovim run.
local source, repo_url, branch
for i = 2, #arg do
  local a = arg[i]
  local src = a:match("^%-%-source=(.+)$")
  local url = a:match("^%-%-repo%-url=(.+)$")
  local br = a:match("^%-%-branch=(.+)$")
  if src then
    source = src
  elseif url then
    repo_url = url
  elseif br then
    branch = br
  else
    argv[#argv + 1] = a
  end
end

local opts = require("documentation.config").build(root, {
  source = source, -- nil: config.build auto-detects, same as scripts/gen_map.lua's callers that omit it
  repo_url = repo_url,
  branch = branch,
  layers = {
    {
      from = "documentation.core",
      to = "documentation.editor",
      why = "the pipeline has to stay runnable without an editor — see docs/ROADMAP/PORTABILITY.md",
    },
    {
      from = "documentation.core",
      to = "documentation.bindings",
      why = "the pipeline knows nothing about commands or keys",
    },
    {
      from = "documentation.core",
      to = "documentation.core.lang",
      why = "language backends are reached through core/lang_registry.lua, never directly",
    },
  },
})

local code = require("documentation.core.cli").run(opts, argv)
os.exit(code)
