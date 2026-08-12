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

-- `--capabilities` is recognised in the **root** position, and that is not a
-- style choice.
--
-- Every unrecognised `--flag` *after* the root falls through to
-- `core/cli.run` as an ordinary argv entry. So an older binary asked "do you
-- support X?" that way does not answer — it **generates the map**, writing
-- into the caller's repository and exiting 0 with output that is not JSON.
-- Measured, not imagined: that is exactly what the shipped binary did the
-- first time it was handed `--api=telemetry`, and a viewer polling a panel
-- would have rewritten a user's `docs/map` on every fetch.
--
-- A flag in root position is the one probe that is safe against both
-- versions: an older binary rejects it immediately below, before doing any
-- work, and a newer one answers after its dependencies are on the path. So
-- "this engine has no capabilities" and "this engine is too old" are a
-- single observation, which is what a host actually needs.
local capabilities_only = (root == "--capabilities")

if not capabilities_only and root:sub(1, 1) == "-" then
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

---Same three-candidate search as `ensure()`, but soft: does not exit when
---nothing is found.
---
---**Necessary, not sufficient — measured, not assumed.** `telemetry_join.
---lua`'s own `M.load` already treats "runtime-analysis.nvim is not
---installed" the same as "installed, but nothing was ever collected" —
---`available:false, reason:"no data"` either way — so a missing path here
---reads as a correct-looking answer even when it is not. This call is what
---lets a real checkout be *found* at all; it does not, on its own, make
---`--api=telemetry` succeed against real data. Traced against this
---machine's own real telemetry (63 KB of real collected data,
---`documentation.nvim`'s own self-instrumentation):
---`runtime-analysis.telemetry` itself loads, but its own
---`require("lib.nvim.autocmd")` pulls in `lib.lua.lazy`, a *different*
---`lib.*` sub-namespace than `lib.nvim.*` — and `scripts/bundle_manifest.
---lua`'s `bucket()` only recognises `^lib%.nvim`, so that module is never
---staged into the compiled binary even when the measuring run finds it.
---A full fix needs `bucket()` widened, plus `RUNTIME_ANALYSIS_NVIM_DIR` set
---for the *build's* manifest-measuring step, not just at run time — left
---for a following change rather than guessed at here. Until then this
---degrades exactly the way an absent checkout always has: honestly, with a
---stated reason, never a wrong answer.
---
---`ensure()` above is the wrong shape for this regardless — `lib.nvim`/
---`documentation.nvim` are load-bearing and a missing one should stop the
---build cold; `runtime-analysis.nvim` is optional everywhere else this join
---already runs, and should degrade the same way here, not fail loudly for a
---dependency every other caller treats as soft.
---@param modname string
---@param dirname string
local function ensure_soft(modname, dirname)
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
  -- Silent otherwise, on purpose: telemetry_join.lua already reports "no
  -- data" for this exact case, and that message is correct enough to
  -- stand alone without a second one only visible on stderr.
end

package.path = self_root .. "/lua/?.lua;" .. self_root .. "/lua/?/init.lua;" .. package.path
ensure("lib.nvim.fs.read", "lib.nvim")
ensure("documentation.core.cli", "documentation.nvim")
-- One call, not one per module: both `runtime-analysis.telemetry` and
-- `runtime-analysis.loaded` (loaded/snapshots routes) live in the same
-- checkout, so putting it on package.path once resolves both.
ensure_soft("runtime-analysis.telemetry", "runtime-analysis.nvim")

-- What a host asks before trusting this binary with anything else.
--
-- Answered here rather than parsed out of a `--help` string, and read off
-- `core/api.routes` rather than restated, so a route added there is
-- advertised without this file being told.
if capabilities_only then
  local names = {}
  for name in pairs(require("documentation.core.api").routes) do
    names[#names + 1] = name
  end
  table.sort(names)
  print(require("documentation.core.json").encode({ capabilities = { "api" }, routes = names }))
  os.exit(0)
end

local argv = {}
-- `--repo-url`/`--branch` are options rather than defaults because this CLI
-- is generic over any root, while `scripts/gen_map.lua` is one repository's
-- own wrapper and can hardcode both. Without them the two produce maps that
-- differ in `meta.repo_url` — correct on each side, and an apples-to-oranges
-- comparison when checking that this build is byte-faithful to a Neovim run.
-- `--snapshot=` carries `core.api.answer`'s single optional `param`
-- whatever the chosen route interprets it as — a snapshot name for
-- `telemetry`/`loaded`, a commit count for `commits`, unused otherwise.
-- One flag rather than one per route because exactly one route ever reads
-- it at a time; see each route's own doc comment in `core/api.lua` for
-- which it is.
local source, repo_url, branch, out_dir, api_route, api_snapshot
for i = 2, #arg do
  local a = arg[i]
  local src = a:match("^%-%-source=(.+)$")
  local url = a:match("^%-%-repo%-url=(.+)$")
  local br = a:match("^%-%-branch=(.+)$")
  local out = a:match("^%-%-out%-dir=(.+)$")
  local api = a:match("^%-%-api=(.+)$")
  local snap = a:match("^%-%-snapshot=(.+)$")
  if src then
    source = src
  elseif url then
    repo_url = url
  elseif br then
    branch = br
  elseif out then
    out_dir = out
  elseif api then
    api_route = api
  elseif snap then
    api_snapshot = snap
  else
    argv[#argv + 1] = a
  end
end

local opts = require("documentation.config").build(root, {
  source = source, -- nil: config.build auto-detects, same as scripts/gen_map.lua's callers that omit it
  repo_url = repo_url,
  branch = branch,
  -- `--out-dir` exists for the parity gate in `scripts/ci.lua`: comparing this
  -- build's output against the committed map must not overwrite the committed
  -- map to do it. Left nil, `config.build`'s own default applies as before.
  out_dir = out_dir,
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

-- `--api=<route>`: answer one of the generated page's own `/api/*` routes
-- and print its JSON, instead of generating anything.
--
-- This is what makes the app a real host rather than a viewer. The page
-- already fetches these routes and already handles their answers; what it
-- never had outside Neovim was anything on the other end. `docmap-desktop`
-- runs a small HTTP server that forwards `/api/*` here — Rust is transport
-- only, and the join logic stays in Lua, owned once by `core/api.lua` and
-- shared with `editor/serve.lua`'s in-editor server.
--
-- One route per invocation, deliberately: a request is one question, and a
-- process that answered several would need a protocol to say which answer
-- is which. stdout carries exactly the JSON, so the caller does not have to
-- find where it starts.
if api_route then
  ---One shell-quoted argument. Every value that ever reaches this — a
  ---hardcoded literal, `opts.root`/`opts.out_dir` (config, not request
  ---input), or a sha that `core.api.answer` already ran through
  ---`safe_sha`'s hex-only whitelist before this function is ever called —
  ---cannot contain the metacharacters that make shelling out to a string
  ---dangerous in the first place. Quoted here anyway, as the second lock
  ---on that door rather than the only one.
  ---@param s string
  ---@return string
  local function shell_quote(s)
    return '"' .. tostring(s):gsub('"', '\\"') .. '"'
  end

  local windows = (package.config:sub(1, 1) == "\\")

  ---Run git in `opts.root` via `io.popen` — the standalone build's only
  ---subprocess capability; `vim.system` does not exist outside Neovim.
  ---
  ---**Cannot see the exit code, measured rather than assumed.** Probed on
  ---Windows via Neovim's own embedded LuaJIT as a stand-in — `io.popen` is
  ---a thin wrapper over the platform C library's `popen()`/`_popen()`,
  ---which is the same call regardless of which Lua interpreter drives it,
  ---so the result transfers to PUC Lua 5.4 even though no PUC interpreter
  ---was on this machine to test the shipped binary directly with.
  ---`file:close()` returned `true, nil, nil` for both a genuinely
  ---succeeding *and* a genuinely failing git invocation — there is no exit
  ---status to branch on the way `editor/serve.lua`'s
  ---`vim.system(...):wait().code` can.
  ---
  ---So: stderr is merged into the captured stream (`2>&1`), and output
  ---starting with `fatal:`/`error:`/`usage:` is treated as a failure.
  ---Heuristic, not a guarantee, and named as one rather than pretended to
  ---be exact — but every format string these routes actually request
  ---starts with a sha, a `\31`/`\30` control byte, or `diff --git`, never
  ---with one of those three words, so a real false positive would need a
  ---commit whose *first output byte* happens to look like a git error,
  ---which the formats used here cannot produce.
  ---@param o table
  ---@param args string[]
  ---@return string|nil stdout
  ---@return string|nil err
  local function popen_git(o, args)
    local parts = { "git" }
    for _, a in ipairs(args) do
      parts[#parts + 1] = shell_quote(a)
    end
    local cd = (windows and "cd /d " or "cd ") .. shell_quote(o.root) .. " && "
    local fh = io.popen(cd .. table.concat(parts, " ") .. " 2>&1", "r")
    if not fh then
      return nil, "could not start git"
    end
    local out = fh:read("*a") or ""
    fh:close()
    if out:match("^%s*fatal:") or out:match("^%s*error:") or out:match("^%s*usage:") then
      return nil, (out:gsub("%s+$", ""))
    end
    return out
  end

  opts.git = popen_git

  local api = require("documentation.core.api")
  local result, api_err = api.answer(api_route, opts, api_snapshot)
  if not result then
    io.stderr:write("standalone/docmap.lua: " .. tostring(api_err) .. "\n")
    os.exit(2)
  end
  io.stdout:write(require("documentation.core.json").encode(result) .. "\n")
  os.exit(0)
end

local code = require("documentation.core.cli").run(opts, argv)
os.exit(code)
