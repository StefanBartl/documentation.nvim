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
    -- Added with the bindings layer, so the split is enforced rather than
    -- being a directory rename nothing checks.
    --
    -- Only this direction. An `editor -> bindings` rule was tried and is
    -- wrong: `browse` requires `bindings.keymaps` for the override rule,
    -- which is a *utility* over key tables rather than part of the command
    -- surface, and the deprecated `editor/command.lua` shim delegates upward
    -- to `bindings.usrcmds` on purpose. Both are intended, so a rule that
    -- flagged them would only teach people to ignore the check.
    {
      from = "documentation.core",
      to = "documentation.bindings",
      why = "the pipeline knows nothing about commands or keys",
    },
    -- Added with `core/lang_registry.lua` (docs/ROADMAP/MULTILANG.md Phase
    -- 0), for the same reason as the two rules above: the walk asks the
    -- registry which language owns a file, and nothing else in `core` may
    -- reach a specific backend directly — that is exactly the coupling a
    -- second language backend would otherwise be tempted to introduce.
    --
    -- The registry itself is not `documentation.core.lang.*` (it is
    -- `documentation.core.lang_registry`, a sibling segment) precisely so
    -- this rule does not also flag the registry's own, legitimate knowledge
    -- of every backend — see that module's header.
    {
      from = "documentation.core",
      to = "documentation.core.lang",
      why = "language backends are reached through core/lang_registry.lua, never directly — see docs/ROADMAP/MULTILANG.md",
    },
  },
})

local code = require("documentation.core.cli").run(opts, _G.arg or {})

-- `docs/BINDINGS.md`, generated from the same tables that drive the plugin.
--
-- Written here rather than by `cli.run` because it is *this repository's* own
-- documentation, not an artifact of the pipeline: another plugin pointing
-- docmap at its own tree wants a module map, not a page describing
-- `:DocBrowse`'s keys. Same reason `layers` above lives here and not in a
-- default.
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
