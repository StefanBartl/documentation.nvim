---@module 'documentation.config'
--- Resolving a full `Documentation.Opts` for a repository: the defaults in
--- [`DEFAULTS.lua`](DEFAULTS.lua), what can be derived from `root`, and the
--- merge rule every entry point runs user options through.
---
--- This is the file that used to know one particular repository's layout. It
--- knows none now: `build()` derives everything it can from `root` itself and
--- takes the rest as overrides, which is what lets `:DocMap` work in a checkout
--- nobody configured and lets a plugin pin its own layout in three lines.
---
--- Auto-detection is deliberately shallow — one `lua/<name>` probe, no
--- walking, no guessing at nested trees. A wrong guess that looks confident is
--- worse than an obvious default the user overrides once in their spec.
---
--- Deliberately **not** under `core/`, where it lived until the config/bindings
--- split: `documentation.core` is the pipeline (scan → check → render), and
--- both halves plus the command layer read their options from here. A base
--- module that every layer depends on is not part of any one of them.
--- `documentation.core.config` remains as a deprecated alias.

local DEFAULTS = require("documentation.config.DEFAULTS")

local M = {}

---Every real `Documentation.Opts` field name, for the unknown-key check in
---`M.build` below. Deliberately **not** derived from `DEFAULTS`'s own keys —
---unlike `bindings/keymaps.lua`'s `defaults` list (which genuinely is the
---exhaustive set of valid `spec.id`s), most `Documentation.Opts` fields have
---no non-nil default (`watch`, `keys`, `layers`, `luals`, `calls_heuristic`,
---...) and so have no entry in `DEFAULTS.lua` at all — building "known" from
---`DEFAULTS` here would flag every one of those as an unknown-key typo.
---Transcribed from `lua/documentation/@types/init.lua`'s `Documentation.Opts`
---class; keep in sync when a field is added there.
---@type table<string, true>
local KNOWN_OPTS_KEYS = {
  root = true,
  root_markers = true,
  source = true,
  lua_root = true,
  title = true,
  types_dir = true,
  out_dir = true,
  repo_url = true,
  branch = true,
  extra_checks = true,
  calls_heuristic = true,
  docs_heuristic = true,
  dead_code = true,
  layers = true,
  luals = true,
  luals_timeout_ms = true,
  progress_style = true,
  command_name = true,
  browse_command_name = true,
  keys = true,
  which_key = true,
  debug = true,
  watch = true,
  watch_ms = true,
  callhierarchy = true,
  diagnostics = true,
  mdview = true,
  tag_files = true,
  consumers = true,
  external_repos = true,
  tests_dir = true,
  quicks = true,
  badge = true,
  pdf = true,
  telemetry_namespace = true,
  telemetry = true,
  godbolt = true,
  bindings = true,
  snippet_max_lines = true,
  generate_all = true,
}

---`opts.source` as a list, whatever shape it was written in.
---
---**The one place that knows `source` can be a string or a list.** It became
---a list so a repository with `lua/` beside `src/` could have both walked,
---and `scan.lua` was taught the new shape — but eight other readers were
---not, and every one of them concatenated or `gsub`-ed it. They did not
---fail in the map pipeline, because that is the one path that *was* updated;
---`:checkhealth`, `:DocBrowse`, the file watcher and the LuaLS enrichment
---all broke silently and stayed broken through a green test suite, because
---none of them is exercised by it.
---
---Found by the standalone build, which runs a full scan through code the
---specs never reach. Every consumer now goes through here, so the next shape
---change has one place to update rather than nine.
---@param opts Documentation.Opts
---@return string[] Always at least one entry.
function M.sources(opts)
  local src = opts and opts.source
  if type(src) == "table" then
    return #src > 0 and src or { "lua" }
  end
  return { src or "lua" }
end

---The single source root, when a caller genuinely needs one path.
---
---`nil` when there are several: that is a real answer, not a shortfall.
---A tool that takes one directory — LuaLS, a `@module` prefix, a watcher
---root — has no honest way to pick among three, and picking the first
---silently would make it right about a third of the tree and wrong about the
---rest. Every caller here handles the `nil` by widening (watch the
---repository root) or by declining (no single prefix), which is what they
---already did for the layouts that never had one.
---@param opts Documentation.Opts
---@return string?
function M.primary_source(opts)
  local list = M.sources(opts)
  return #list == 1 and list[1] or nil
end

---Is `a` the same path as `b`, or an ancestor of it?
---@param a string
---@param b string
---@return boolean
local function covers(a, b)
  return a == b or a == "." or b:sub(1, #a + 1) == (a .. "/")
end

---Where `root`'s sources live, asked of the language backends rather than
---assumed — **every** backend, not just the first to answer.
---
---**This function used to be a Lua heuristic and nothing else**, and that
---was a hard failure rather than a limitation: it returned `"lua"` for every
---tree it did not recognise, including trees with no `lua/` directory at
---all, so `scan.lua`'s own `assert` killed the run with
---`source directory not found: <root>/lua`. Measured against a three-file
---JavaScript project, not reasoned about — the engine reads JS/TS, and a
---JavaScript repository could not be scanned at all.
---
---Taking only the first answer was the *second* half of the same mistake,
---and it was quieter: a tree with `lua/` beside `src/` mapped the Lua half
---and never visited the other, with nothing anywhere saying so. Collecting
---every answer is what makes `scan.lua`'s multi-root walk reachable.
---
---Each backend answers for itself or declines (`nil`). The heuristics moved
---with the answers: `core/lang/lua.lua` owns `lua/<plugin>`,
---`core/lang/ecma.lua` owns `src`/`lib`/`app` — and neither claims a
---directory that does not actually hold a file it can read, so a Lua
---repository with a `src/` full of shell scripts is not mistaken for a
---JavaScript one.
---
---**A candidate that contains another is dropped.** Two backends can answer with
---one nested inside the other — Lua saying `lua/thing` while ECMA falls back
---to the repository root because a stray `.js` sits there. Keeping both
---would walk `lua/thing` twice, once on its own and once inside the root,
---and duplicate every node in it. The narrower answer wins, which loses the
---stray file and keeps the map correct; the alternative loses nothing and
---breaks the map, which is the worse trade.
---
---`{"."}` when nothing answers: the repository root, which always exists.
---An honest empty map for a tree this tool cannot read beats an assertion
---naming a directory the user never had — and `scan.lua`'s `VENDOR_DIRS`
---is what keeps that fallback from walking into `node_modules`.
---@param root string Absolute repository root, forward slashes.
---@return string[] sources Relative to `root`, at least one.
function M.detect_source(root)
  local found = {}
  for _, backend in ipairs(require("documentation.core.lang_registry").all()) do
    if backend.detect_source then
      local guess = backend.detect_source(root)
      -- Two backends can name the same directory (`js` and `ts` both live in
      -- `src`); one entry is one walk.
      --
      -- An explicit loop rather than `vim.tbl_contains`, which is **not in
      -- `standalone/vim_shim.lua`**. This module is bundled into the
      -- standalone binary and runs there under PUC Lua with only the shim's
      -- subset of `vim.*`. Found by the packaging step failing, not by a
      -- test: the `standalone` CI gate skips locally when no PUC Lua is on
      -- PATH, so building the binary is the first thing that ever runs this
      -- code under the interpreter it has to survive.
      local already = false
      for _, seen in ipairs(found) do
        if seen == guess then
          already = true
          break
        end
      end
      if guess and not already then
        found[#found + 1] = guess
      end
    end
  end

  local kept = {}
  for _, candidate in ipairs(found) do
    local covered = false
    for _, other in ipairs(found) do
      if other ~= candidate and covers(candidate, other) then
        covered = true
        break
      end
    end
    if not covered then
      kept[#kept + 1] = candidate
    end
  end

  return #kept > 0 and kept or { "." }
end

---Build a full `Documentation.Opts` for `root`, with `overrides` winning over
---every derived default.
---
---`root` is normalised here rather than at each call site: every consumer
---compares it (the registry keys handles on it, `--check` joins it with
---`out_dir`), and a trailing slash or a backslash on Windows would make two
---spellings of the same repository look like two repositories.
---@param root string Absolute repository root.
---@param overrides Documentation.Opts? Merged over the defaults, shallowly.
---@param notify table? A `lib.nvim.notify`-shaped instance (`.warn(msg)`).
---Optional and unused when absent, same dependency-injection shape
---`bindings/keymaps.lua`'s `M.resolve` already takes — this module is a base
---every layer (including the UI-free pipeline) depends on, so it must not
---hard-require `lib.nvim.notify` itself.
---@return Documentation.Opts
function M.build(root, overrides, notify)
  root = (tostring(root):gsub("\\", "/"):gsub("/+$", ""))

  -- Unknown keys are checked *before* the merge below, same reasoning as
  -- `bindings/keymaps.lua`'s own check: a typo'd option silently vanishing
  -- into "not applied" rather than raising is exactly the failure mode a
  -- one-time warning here closes.
  if notify then
    local unknown = {}
    for k in pairs(overrides or {}) do
      if not KNOWN_OPTS_KEYS[k] then
        unknown[#unknown + 1] = tostring(k)
      end
    end
    if #unknown > 0 then
      table.sort(unknown)
      notify.warn(("opts: unrecognized key(s): %s"):format(table.concat(unknown, ", ")))
    end
  end

  ---A copy per call, never `DEFAULTS` itself: the merge below writes into this
  ---table, and mutating the shared defaults would leak one caller's options
  ---into every later `build()` in the process.
  ---@type Documentation.Opts
  local opts = vim.tbl_extend("force", {}, DEFAULTS, {
    root = root,
    source = M.detect_source(root),
    title = vim.fn.fnamemodify(root, ":t"),
  })

  for k, v in pairs(overrides or {}) do
    opts[k] = v
  end

  -- After the merge, not before: an override may have changed `root`, and the
  -- normalisation above would then apply to the wrong value.
  opts.root = (tostring(opts.root):gsub("\\", "/"):gsub("/+$", ""))
  return opts
end

return setmetatable(M, {
  ---`require("documentation.config")(root)` as shorthand for `.build(root)` —
  ---the form `scripts/gen_map.lua` uses.
  __call = function(_, root, overrides)
    return M.build(root, overrides)
  end,
})
