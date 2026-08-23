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
  -- Built with explicit indices, not a `{a, b, c}` literal fed to `ipairs`:
  -- the environment-variable candidate is `nil` whenever it is unset — the
  -- normal case for CI, which relies on the `.deps/<dirname>` candidate
  -- below instead — and a table literal with `nil` in its first slot makes
  -- `ipairs` stop immediately without ever inspecting the slots after it,
  -- silently skipping every other candidate regardless of whether the
  -- directory actually exists.
  local candidates = {}
  local env_dir = vim.env[dirname:upper():gsub("[.-]", "_") .. "_DIR"]
  if env_dir and env_dir ~= "" then
    candidates[#candidates + 1] = env_dir
  end
  candidates[#candidates + 1] = root .. "/.deps/" .. dirname
  candidates[#candidates + 1] = vim.fs.dirname(root) .. "/" .. dirname
  for _, dir in ipairs(candidates) do
    if vim.fn.isdirectory(dir) == 1 then
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

local opts = require("documentation.config").build(root, {
  source = "lua/documentation",
  title = "documentation.nvim",
  out_dir = "docs/map",
  repo_url = "https://github.com/StefanBartl/documentation.nvim",
  branch = "main",

  -- **`layers` is not here any more.** It lives in `.docmap.json` at the
  -- repository root, and that move is what this file is now an example of:
  -- an architecture rule is a fact about the *tree*, so every host that maps
  -- the tree should get it — this script, the standalone binary, the GitHub
  -- Action, `docmap-desktop`. Stated here it reached exactly one of the
  -- four, and `standalone/docmap.lua` had a hand-kept copy of the same three
  -- rules to make up half the difference.
  --
  -- What stays here is what genuinely belongs to *this invocation*. See
  -- `config/file.lua` for the split and docs/REUSE.md for what to copy.
})

local code = require("documentation.core.cli").run(opts, _G.arg or {})

-- `docs/BINDINGS.md`, generated from the same tables that drive the plugin.
--
-- Written here rather than by `cli.run` because it is *this repository's* own
-- documentation, not an artifact of the pipeline: another plugin pointing
-- docmap at its own tree wants a module map, not a page describing
-- `:DocBrowse`'s keys — unlike `layers`, which moved to `.docmap.json`
-- precisely because it *is* a fact about the tree that every host should
-- get.
--
-- Skipped under `--check`, which must write nothing — the hook and CI both run
-- it that way, and a "verify" that rewrites a file is not a verify. A stale
-- BINDINGS.md is caught by the spec instead, which asserts every bound key
-- appears in the rendered output.
local checking = false
for _, a in ipairs(_G.arg or {}) do
  if a == "--check" then
    checking = true
  end
end

if not checking then
  local ok_bindings, rendered = pcall(function()
    return require("documentation.bindings.docs").render()
  end)
  if ok_bindings then
    local path = opts.root .. "/docs/BINDINGS.md"
    local fd = io.open(path, "wb")
    if fd then
      fd:write(rendered)
      fd:close()
      io.stdout:write("wrote docs/BINDINGS.md\n")
    end
  else
    io.stderr:write("could not render docs/BINDINGS.md: " .. tostring(rendered) .. "\n")
  end
end

vim.cmd("cq " .. code)
