-- scripts/bundle_manifest.lua — every Lua file the standalone build actually
-- loads, as a list a packager can consume.
--
--   lua scripts/bundle_manifest.lua [<root>]          one path per line
--   lua scripts/bundle_manifest.lua [<root>] --report grouped, with a summary
--
-- Run under PUC Lua, not Neovim: the point is the closure of the *standalone*
-- build, and `nvim -l` would load a different set (and a different `vim`).
--
-- ## Why this is measured rather than grepped
--
-- `luastatic` takes a list of `.lua` files. Deriving that list from `require`
-- lines is wrong in both directions here, which is the whole reason this file
-- exists:
--
--   * **Too many.** `lua/documentation` mentions thirteen `lib.nvim` modules;
--     the standalone build loads seven files from five of them. `usercmd`,
--     `ui.kit`, `notify`, `autocmd`, `map`, `debounce` and the rest belong to
--     the editor half, which this entry point never reaches. Bundling them
--     would drag Neovim-only code into a build whose premise is not needing
--     Neovim.
--   * **Too few.** The language backends (`core/lang/js`, `ts`, `tsx`) are
--     reached through `core/lang_registry`, never named at a call site. A
--     grep misses them, and the failure would not be a build error — it would
--     be a binary that silently produces no function-level data for
--     JS/TS files, which looks like a scanner bug.
--
-- So the manifest comes from running the real pipeline and reading
-- `package.loaded` afterwards. It cannot drift from what the build needs,
-- because it *is* what the build needed.
--
-- ## C modules
--
-- Reported separately, because they are a different packaging problem:
-- `luastatic` links Lua sources directly but needs a **static library**
-- (`.a`) for each C module, not the `.so`/`.dll` LuaRocks installs. Those are
-- listed under `-- C modules` in `--report` mode and never emitted as paths,
-- since handing a `.dll` to `luastatic` would fail confusingly.

local root = (arg[1] and not arg[1]:match("^%-%-") and arg[1] or ".")
  :gsub("\\", "/")
  :gsub("/+$", "")
local report = false
for _, a in ipairs(arg) do
  if a == "--report" then
    report = true
  end
end

local self_dir = (debug.getinfo(1, "S").source:sub(2):match("(.*)[/\\]")) or "."
local repo = self_dir .. "/.."

-- `standalone/docmap.lua` requires `standalone.vim_shim` by module name, which
-- only resolves when the repository root is on `package.path`. That happens by
-- accident when this script is run from the repository and not otherwise —
-- and `scripts/package.lua` runs it from a build directory, which is exactly
-- the case that used to fail with a twenty-line "module not found" trace.
package.path = table.concat({
  repo .. "/?.lua",
  repo .. "/?/init.lua",
  package.path,
}, ";")

-- Run the standalone entry point exactly as a user would, into a throwaway
-- directory. `os.exit` is intercepted rather than avoided: `docmap.lua` ends
-- with it, and letting it fire would take this script's own reporting with
-- it — there would be nothing left to read `package.loaded` afterwards,
-- which is the entire purpose of this file. Restored immediately after, and
-- scoped to each call.
---@param scan_root string
---@param argv string[] Extra flags, `--out-dir` included.
local function probe(scan_root, argv)
  -- luacheck: push ignore os
  local real_exit = os.exit
  local exit_code
  os.exit = function(code)
    exit_code = code
    error({ __bundle_exit = true }, 0)
  end

  _G.arg = { scan_root }
  for _, a in ipairs(argv) do
    _G.arg[#_G.arg + 1] = a
  end
  local ok, err = pcall(dofile, repo .. "/standalone/docmap.lua")
  os.exit = real_exit
  -- luacheck: pop

  if not ok and not (type(err) == "table" and err.__bundle_exit) then
    io.stderr:write("bundle_manifest: the standalone build failed:\n  " .. tostring(err) .. "\n")
    os.exit(1)
  end
  if exit_code and exit_code ~= 0 then
    io.stderr:write(("bundle_manifest: the standalone build exited %d\n"):format(exit_code))
    os.exit(1)
  end
end

probe(root, { "--out-dir=.deps/bundle-manifest-probe" })

-- **A second corpus, because the closure depends on what was scanned, not
-- only on how.** The warning further down already covers one half of this:
-- without a parser, modules below `scan_file`'s early return never load.
-- The other half is the *languages* in the measured tree. `core/lang/ecma`
-- requires `core/endpoints` while scanning a `.js`/`.ts`/`.tsx` file, and
-- this repository is pure Lua — so measuring it, even with every grammar
-- present, yields a manifest with no `core/endpoints` in it and a binary
-- that dies with "module not found" the first time anyone points it at a
-- TypeScript project. Found exactly that way.
--
-- Generated rather than checked in: a fixture under `TESTS/` would be read
-- by `coverage.lua`'s own scan of that directory and would start affecting
-- this repository's `fn.tested` numbers, which is a real artifact change to
-- pay for a build detail. `.deps/` is gitignored and is already where this
-- script writes.
local LANG_FIXTURES = {
  ["a.js"] = "/** Adds. */\nexport function add(a, b) {\n  return a + b;\n}\n",
  ["a.ts"] = "/** Adds. */\nexport function add(a: number, b: number): number {\n  return a + b;\n}\n",
  ["a.tsx"] = "/** A box. */\nexport function Box(p: { n: number }) {\n  return <div>{p.n}</div>;\n}\n",
}

-- `os.execute(('mkdir "%s"')...)` was here and looked platform-neutral
-- because `package.config:sub(1,1)` picked the right separator — but the
-- separator was never the problem. cmd.exe's `mkdir` creates every missing
-- parent directory; POSIX `mkdir` creates exactly one and errors on the
-- rest, so this silently only ever worked on Windows. Found running this
-- script under WSL for the first time: `.deps/bundle-manifest-langs/src`
-- has two levels below `.deps/`, and plain `mkdir` refused both.
-- `package.lua`'s own `mkdirp` (line ~90) already solves this the portable
-- way — one `lfs.mkdir` per path component — duplicated here rather than
-- shared, since these are two independent scripts with no common module
-- to hold it.
local lfs = require("lfs")
local langs_root = repo .. "/.deps/bundle-manifest-langs"
local acc = nil
for part in (langs_root .. "/src"):gmatch("[^/]+") do
  acc = acc and (acc .. "/" .. part) or part
  if not acc:match("^%a:$") then
    lfs.mkdir(acc)
  end
end
for name, body in pairs(LANG_FIXTURES) do
  local fd = io.open(langs_root .. "/src/" .. name, "w")
  if fd then
    fd:write(body)
    fd:close()
  end
end

probe(langs_root, { "--source=src", "--out-dir=out" })

-- **A third mode, because the closure depends on what was asked for, not
-- only on what was scanned.** `--api=<route>` short-circuits before
-- `core/cli.run` entirely and reaches modules a scan does not:
-- `core/api`, `core/artifact` and `core/loaded_diff` (measured, not listed
-- from reading the requires — `core/telemetry_join` looks like it belongs
-- on that list and does not, because `config.build` already pulls it).
-- Without this probe the manifest omits them and the binary dies with
-- "module not found" the first time `docmap-desktop`'s host asks for the
-- Telemetry panel. Same shape as the language-fixture case immediately
-- above, and the same reason it is a separate probe rather than a note: a
-- manifest that is *measured* has to measure every mode that ships.
--
-- Every route, not one: they do not share a dependency set (`telemetry`
-- pulls `telemetry_join`, `loaded` pulls `loaded_diff`), so probing one
-- would leave the other's half out with nothing to say so.
for _, route in ipairs({
  "telemetry",
  "telemetry/snapshots",
  "loaded",
  "loaded/snapshots",
  "checklist",
  "commits",
}) do
  probe(root, { "--api=" .. route, "--out-dir=.deps/bundle-manifest-probe" })
end

-- `commit/<sha>` needs a real sha, unlike the fixed-name routes above: on
-- success it requires `core.history` for the diff analysis, which
-- measured (`nvim --headless`, package.loaded before/after) is not pulled
-- in by any of the six routes just probed. `root`'s own `HEAD` is real
-- history that exists in every checkout this script can even run against.
local head_pipe = io.popen('git -C "' .. root .. '" rev-parse HEAD 2>&1', "r")
local head_sha = head_pipe and head_pipe:read("*l")
if head_pipe then
  head_pipe:close()
end
if head_sha and head_sha:match("^%x%x%x%x%x%x%x+$") then
  probe(root, { "--api=commit/" .. head_sha, "--out-dir=.deps/bundle-manifest-probe" })
else
  io.stderr:write(
    "bundle_manifest: could not resolve HEAD in "
      .. root
      .. " to probe --api=commit/<sha>; "
      .. "core.history's closure will not be measured this run.\n"
  )
end

---Collapse `a/b/../c` to `a/c`. `package.searchpath` returns whatever
---template matched, and this script is reached through `scripts/`, so paths
---arrive as `scripts/../standalone/../lua/…` — valid, but not something to
---hand a packager or read in a diff.
---@param p string
---@return string
local function normalize(p)
  p = p:gsub("\\", "/")
  local prev
  repeat
    prev = p
    -- Never collapse a leading `../`, which has no segment to remove.
    p = p:gsub("([^/]+)/%.%./", function(seg)
      return seg == ".." and seg .. "/../" or ""
    end)
  until p == prev
  -- Anchored: an unanchored `%./` also matches the second character of a
  -- leading `../`, turning `../lib.nvim` into `.lib.nvim` — a path that looks
  -- almost right and resolves nowhere.
  return (p:gsub("^%./", ""))
end

---Which bucket a loaded module name belongs to, or nil to ignore it (the
---standard library, and anything else the host happened to preload).
---@param name string
---@return "project"|"lib"|"rock"|nil
local function bucket(name)
  if name:match("^documentation") or name:match("^standalone") then
    return "project"
  end
  if name:match("^lib%.nvim") then
    return "lib"
  end
  if name == "dkjson" then
    return "rock"
  end
  return nil
end

-- Anything loaded from a `.so`/`.dll` is a C module: a static library
-- problem, not a file to hand the packager.
local C_MODULES = { "lfs", "lua_tree_sitter" }

local groups = { project = {}, lib = {}, rock = {} }
local unresolved = {}

for name in pairs(package.loaded) do
  local b = bucket(name)
  if b then
    local path = package.searchpath(name, package.path)
    if path then
      groups[b][#groups[b] + 1] = { name = name, path = normalize(path) }
    else
      unresolved[#unresolved + 1] = name
    end
  end
end

for _, g in pairs(groups) do
  table.sort(g, function(a, b)
    return a.name < b.name
  end)
end
table.sort(unresolved)

local present_c = {}
for _, m in ipairs(C_MODULES) do
  if package.loaded[m] then
    present_c[#present_c + 1] = m
  end
end

-- **Build the manifest in the configuration you intend to ship** — and the
-- closure turns on two independent things, not one.
--
-- *How it was scanned.* `core/functions.lua`'s `scan_file` returns early
-- when no parser is available, so `core/plugins.lua` and `core/symbols.lua`
-- — required from below that point — never load at all.
--
-- *What was scanned.* `core/lang/ecma` requires `core/endpoints` while
-- reading a `.js`/`.ts`/`.tsx` file, and this repository is pure Lua. A
-- manifest measured here with every grammar present still omits it, which
-- is why the probe above also runs over a generated three-language fixture.
--
-- Measured, in this repository: **43 files parser-less, 45 with a grammar
-- reachable, 46 once a JS/TS/TSX corpus is scanned too.**
--
-- None of the three misses is a build error. Each is a binary that dies or
-- goes quiet only on the input the missing module handles — no plugin specs
-- and no module-scope symbols for the first two, and a "module not found"
-- traceback the first time anyone points the binary at a TypeScript project
-- for the third. That last one was found exactly that way, after the build
-- had already been called done. Hence a warning rather than a silent short
-- list.
if not package.loaded.lua_tree_sitter then
  io.stderr:write(
    "bundle_manifest: WARNING — no tree-sitter binding was loaded, so this is the\n"
      .. "  parser-less closure. Modules reached only after a successful parse are\n"
      .. "  absent. For a full-fidelity bundle, install lua-tree-sitter and point\n"
      .. "  $DOCMAP_TS_DIR at a directory of compiled grammars, then re-run.\n"
  )
end

if not report then
  for _, key in ipairs({ "project", "lib", "rock" }) do
    for _, entry in ipairs(groups[key]) do
      print(entry.path)
    end
  end
  os.exit(#unresolved == 0 and 0 or 1)
end

local function section(title, entries)
  print(("-- %s (%d)"):format(title, #entries))
  for _, e in ipairs(entries) do
    print(("   %-52s %s"):format(e.name, e.path))
  end
  print("")
end

print(("-- standalone bundle manifest for %s\n"):format(root))
section("project", groups.project)
section("lib.nvim (only what is really loaded)", groups.lib)
section("pure-Lua rocks", groups.rock)

print(
  ("-- C modules (%d) — need a static library, not the installed .dll/.so"):format(#present_c)
)
for _, m in ipairs(present_c) do
  print("   " .. m)
end
print("")

if #unresolved > 0 then
  print(("-- UNRESOLVED (%d) — loaded but not findable on package.path"):format(#unresolved))
  for _, n in ipairs(unresolved) do
    print("   " .. n)
  end
  print("")
end

print(
  ("-- total Lua files: %d  |  C modules: %d"):format(
    #groups.project + #groups.lib + #groups.rock,
    #present_c
  )
)

os.exit(#unresolved == 0 and 0 or 1)
