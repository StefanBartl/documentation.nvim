---@module 'scripts.gen_map'
--- CLI entry point for this repository's own module map.
---
---   nvim --headless -l scripts/gen_map.lua                    # regenerate
---   nvim --headless -l scripts/gen_map.lua --check            # verify, write nothing
---   nvim --headless -l scripts/gen_map.lua --check --lenient  # fail on staleness only
---   nvim --headless -l scripts/gen_map.lua --full             # + LuaLS enrichment
---
--- Thin on purpose: everything that is not this repository's own layout lives
--- in `documentation.core.cli`, so another plugin copies this file verbatim and
--- changes only the options table at the bottom. See docs/REUSE.md.

local root = vim.uv.cwd():gsub("\\", "/"):gsub("/+$", "")
vim.opt.runtimepath:prepend(root)

--- Put a dependency on the runtimepath, if it is not already reachable.
---
--- A headless `nvim -l` run starts with no plugin manager, so nothing beyond
--- `root` is on the rtp — `documentation` and `lib.nvim` both have to be found
--- by hand. Three candidates, in descending order of explicitness: an
--- environment variable (what CI sets), a `.deps/` checkout (what CI clones
--- into), and a sibling checkout (what a local development tree looks like).
---
--- Silent when the module already resolves, so a repository that *is* the
--- dependency — this one, for `documentation` — needs no special case.
---@param modname string A module the dependency provides, used as the probe.
---@param dirname string Repository directory name.
local function ensure(modname, dirname)
  if pcall(require, modname) then
    return
  end
  local candidates = {
    vim.env[dirname:upper():gsub("[.-]", "_") .. "_DIR"],
    root .. "/.deps/" .. dirname,
    vim.fs.dirname(root) .. "/" .. dirname,
  }
  for _, dir in ipairs(candidates) do
    if dir and vim.fn.isdirectory(dir) == 1 then
      vim.opt.runtimepath:prepend(dir)
      if pcall(require, modname) then
        return
      end
    end
  end
  io.stderr:write(("gen_map: %s not found (probed require('%s')).\n"):format(dirname, modname))
  io.stderr:write(
    ("  Set %s_DIR, clone it to .deps/%s, or check it out beside this repo.\n"):format(
      dirname:upper():gsub("[.-]", "_"),
      dirname
    )
  )
  os.exit(1)
end

ensure("lib.nvim.fs.read", "lib.nvim")
ensure("documentation.core.cli", "documentation.nvim")

local opts = require("documentation.core.config").build(root, {
  source = "lua/documentation",
  title = "documentation.nvim",
  out_dir = "docs/map",
  repo_url = "https://github.com/StefanBartl/documentation.nvim",
  branch = "main",

  -- The one rule this repository declares about itself, and the reason
  -- `core/` and `editor/` are directories rather than a convention: the
  -- pipeline has to stay runnable with no editor around it, and nothing but
  -- a check keeps a boundary like that from quietly rotting. `--check` now
  -- fails when a core module requires an editor one.
  --
  -- Deliberately one-directional. The editor half reaching into the core is
  -- the point of the core existing; it is the other direction that costs
  -- something. See docs/PORTABILITY.md.
  layers = {
    {
      from = "documentation.core",
      to = "documentation.editor",
      why = "the pipeline has to stay runnable without an editor — see docs/PORTABILITY.md",
    },
  },
})

local code = require("documentation.core.cli").run(opts, _G.arg or {})
vim.cmd("cq " .. code)
