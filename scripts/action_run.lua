---@module 'scripts.action_run'
--- The runner behind the GitHub Action (`action.yml` at this repository's
--- root) — `nvim --headless -l scripts/action_run.lua [--check] [...]`.
---
--- **Why this exists at all, given `scripts/gen_map.lua`.** `gen_map.lua` is
--- *this repository's own* entry point: `docs/REUSE.md` tells an adopter to
--- copy it and edit the options table at the bottom, because that table is
--- where a repository's own layout lives. The action's whole promise is that
--- nothing has to be copied — so it needs the same file with the options
--- table replaced by inputs. That is this.
---
--- **Why not `standalone/docmap.lua`, which already takes a root and a set
--- of flags.** Measured, not assumed: it requires `standalone/vim_shim.lua`
--- unconditionally, which requires `lfs`, so it does not run under
--- `nvim --headless -l` at all. And even if it did, the parser-less
--- standalone build produces a *different* map than a Neovim run — which is
--- fatal for a `--check` action specifically, since `--check` compares byte
--- for byte against what the adopter's own `:DocMap` committed. This
--- repository's own CI says the same thing about its `standalone` job: full
--- byte-parity against a Neovim run stays a local gate.
---
--- **Everything past the options is `core/cli.run`**, unchanged and shared
--- with `gen_map.lua`, so `--check`, `--lenient`, `--full`, `--sarif=`,
--- `--exclude=` and `--languages=` all behave here exactly as they are
--- documented. This file adds no flag of its own; the action passes them
--- through verbatim.
---
--- Inputs arrive as environment variables rather than arguments, so the
--- argument list stays purely `cli.run`'s:
---
---   DOCMAP_ACTION_ROOT      the repository to map (default: cwd)
---   DOCMAP_ACTION_PLUGIN    documentation.nvim's own checkout
---   DOCMAP_ACTION_LIB       lib.nvim's checkout
---   DOCMAP_ACTION_SOURCE    opts.source, `,`-separated for several roots
---   DOCMAP_ACTION_TITLE     opts.title
---   DOCMAP_ACTION_OUT_DIR   opts.out_dir
---   DOCMAP_ACTION_REPO_URL  opts.repo_url
---   DOCMAP_ACTION_BRANCH    opts.branch
---
--- Every one is optional except the two checkouts: an unset input means
--- "let `config.build` derive it", which is the same thing omitting it from
--- an options table means. An empty string is treated as unset, because that
--- is what an omitted `with:` key becomes by the time it reaches here — a
--- distinction that does not exist in YAML and must not be invented in Lua.

---@param name string
---@return string?
local function env(name)
  local value = vim.env[name]
  if value == nil or value == "" then
    return nil
  end
  return value
end

local plugin_root = env("DOCMAP_ACTION_PLUGIN")
local lib_root = env("DOCMAP_ACTION_LIB")
if not plugin_root then
  io.stderr:write("action_run: DOCMAP_ACTION_PLUGIN is not set\n")
  os.exit(1)
end

-- Prepended by hand, in this order, because a headless `nvim -l` has no
-- plugin manager and an empty runtimepath — the same lesson
-- `scripts/generate_one_headless.lua`'s header records learning in CI rather
-- than locally, where a developer's own `init.lua` hides it.
vim.opt.runtimepath:prepend(plugin_root)
if lib_root then
  vim.opt.runtimepath:append(lib_root)
end

if not pcall(require, "lib.nvim.fs.read") then
  io.stderr:write(
    "action_run: lib.nvim is not reachable. It is a hard dependency of the\n"
      .. "engine; the action checks it out and passes DOCMAP_ACTION_LIB.\n"
  )
  os.exit(1)
end

local root = env("DOCMAP_ACTION_ROOT") or vim.uv.cwd()
root = (tostring(root):gsub("\\", "/"):gsub("/+$", ""))

---`opts.source` as `config.build` wants it: one string, or a list.
---
---Comma-separated rather than newline-separated, matching the `--languages`
---flag's own reading and for the same reason — a directory name can contain
---a space and a newline is awkward in a YAML scalar, while a comma in a
---source directory name is not a case anyone has.
---@return string|string[]|nil
local function source()
  local raw = env("DOCMAP_ACTION_SOURCE")
  if not raw then
    return nil
  end
  local list = {}
  for part in raw:gmatch("[^,]+") do
    local trimmed = part:match("^%s*(.-)%s*$")
    if trimmed ~= "" then
      list[#list + 1] = trimmed
    end
  end
  if #list == 0 then
    return nil
  end
  -- A single entry stays a plain string, so a one-root repository produces
  -- byte-identical output to the same run configured by hand — `scan.lua`
  -- treats one-element lists and plain strings alike, and the artifact
  -- records `meta.source` from whichever it was given.
  return #list == 1 and list[1] or list
end

local opts = require("documentation.config").build(root, {
  source = source(),
  title = env("DOCMAP_ACTION_TITLE"),
  out_dir = env("DOCMAP_ACTION_OUT_DIR"),
  repo_url = env("DOCMAP_ACTION_REPO_URL"),
  branch = env("DOCMAP_ACTION_BRANCH"),
})

-- **No `layers`, no `extra_checks`, and that is deliberate.** Both are
-- repository-specific policy: a layer rule is a claim about one tree's own
-- architecture, and an extra check is code. Neither can be expressed as an
-- action input without inventing a configuration language, and a repository
-- that wants them has outgrown "adopt it in three lines" — it should copy
-- `scripts/gen_map.lua` as `docs/REUSE.md` describes. The action covers the
-- case it is for and says so rather than half-covering the next one.
local code = require("documentation.core.cli").run(opts, _G.arg or {})
vim.cmd("cq " .. code)
