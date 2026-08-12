-- scripts/package.lua — build a single-file `docmap` binary.
--
--   lua scripts/package.lua [--out=DIR] [--keep] [--no-run]
--
-- Run under **PUC Lua**, not Neovim. That is not an oversight: `luastatic`
-- is a PUC-Lua program and the C toolchain is required anyway, so this build
-- already needs both. Demanding Neovim on top — for a script whose entire
-- purpose is producing a Neovim-free artifact — would be gratuitous.
--
-- It exists because the first binary was built by hand and the method was
-- written into prose. Prose does not re-run. Each of the four workarounds
-- below was found by running the thing, and every one of them is silent
-- until it bites:
--
--   1. **`luastatic` derives module names from file paths.** Passing
--      `E:/repo/standalone/vim_shim.lua` bundles a module called
--      `E.repos.…​.standalone.vim_shim`, and the binary dies at its first
--      `require`. So this stages a tree whose *relative* paths spell the
--      require names — `documentation/`, `lib/nvim/`, `standalone/`,
--      `dkjson.lua` — and invokes `luastatic` from inside it. `init.lua`
--      works because luastatic's injected searcher tries
--      `lua_bundle[name] or lua_bundle[name .. ".init"]`.
--   2. **It shells out to `nm` without quoting.** Any library path with a
--      space fails, reporting a file that does not exist
--      (`nm: 'C:\Program': No such file`). Static libraries are therefore
--      copied into the build directory first, whose path this script
--      controls.
--   3. **Its C-compiler probe fails on Windows**, even with `CC` set to an
--      absolute `gcc.exe`. It still writes the generated `.c`, so this
--      script ignores luastatic's own link step and compiles that itself.
--   4. **The bundle list must be measured, and in the configuration you
--      intend to ship.** See `scripts/bundle_manifest.lua`; this script
--      calls it rather than reimplementing it, and passes its warning
--      through.
--
-- C modules need a static library, not the `.dll`/`.so` LuaRocks installs.
-- `liblua.a` is mandatory. `lfs` is mandatory for the parser-less build
-- (`gcc -c lfs.c && ar rcs lfs.a lfs.o` — it is one C file). A full-fidelity
-- binary additionally needs `lua_tree_sitter` and `libtree-sitter` built the
-- same way, plus a grammar per language; point `$DOCMAP_STATIC_LIBS` at a
-- directory of `.a` files and every one of them is linked in.
--
-- Environment:
--   $LUA_INCDIR        directory holding lua.h (required)
--   $LUA_LIBA          path to liblua.a       (required)
--   $DOCMAP_STATIC_LIBS  directory of extra .a files to link (required: lfs)
--   $CC                C compiler            (default: cc)

local lfs = require("lfs")

local function die(msg)
  io.stderr:write("package: " .. msg .. "\n")
  os.exit(1)
end

local function env(name, required)
  local v = os.getenv(name)
  if (not v or v == "") and required then
    die(("$%s is not set — see this file's header for what it wants."):format(name))
  end
  return v and v ~= "" and v:gsub("\\", "/"):gsub("/+$", "") or nil
end

local out_dir, keep, run_it = "build", false, true
for _, a in ipairs(arg) do
  local o = a:match("^%-%-out=(.+)$")
  if o then
    out_dir = o:gsub("\\", "/"):gsub("/+$", "")
  elseif a == "--keep" then
    keep = true
  elseif a == "--no-run" then
    run_it = false
  else
    die("unknown option: " .. a)
  end
end

local self_dir = (debug.getinfo(1, "S").source:sub(2):match("(.*)[/\\]")) or "."
local repo = (self_dir .. "/.."):gsub("\\", "/")

local LUA_INCDIR = env("LUA_INCDIR", true)
local LUA_LIBA = env("LUA_LIBA", true)
local STATIC_LIBS = env("DOCMAP_STATIC_LIBS", true)
local CC = os.getenv("CC")
if not CC or CC == "" then
  CC = "cc"
end

---@param path string
local function mkdirp(path)
  -- A POSIX absolute path's leading "/" is a separator to `gmatch`, not
  -- content, so the loop below never sees it and `acc` starts from the
  -- first *component* instead: `mkdirp("/tmp/x")` built "tmp", then
  -- "tmp/x" — real directories, just relative ones, created under
  -- whatever the current directory happened to be instead of under `/`.
  -- Silent on Windows for as long as this script has existed, because
  -- every path there carries a drive letter and never starts with `/`.
  -- Surfaced the first time `--out` was ever handed an absolute Unix path
  -- (`package: cannot write .../stage/documentation/init.lua` — every
  -- parent directory silently existed, just not at the path being
  -- written to).
  local acc = path:sub(1, 1) == "/" and "/" or nil
  for part in path:gmatch("[^/]+") do
    acc = acc and (acc .. (acc:sub(-1) == "/" and "" or "/") .. part) or part
    -- A bare drive letter ("C:") is not a directory to create.
    if not acc:match("^%a:$") then
      lfs.mkdir(acc)
    end
  end
end

---Byte-exact copy. Plain io rather than a shell `cp`/`copy`, so this file
---needs no platform branch for the one operation it does most.
---@param from string
---@param to string
local function copy(from, to)
  local src = io.open(from, "rb")
  if not src then
    die("cannot read " .. from)
  end
  local body = src:read("*a")
  src:close()
  mkdirp(to:match("(.*)/") or ".")
  local dst = io.open(to, "wb")
  if not dst then
    die("cannot write " .. to)
  end
  dst:write(body)
  dst:close()
end

---@param cmd string
---@param label string
local function sh(cmd, label)
  local ok, _, code = os.execute(cmd)
  -- Lua 5.1 returns a number, 5.2+ a boolean plus the code.
  if ok ~= true and ok ~= 0 then
    die(("%s failed (exit %s)\n  %s"):format(label, tostring(code or ok), cmd))
  end
end

local WINDOWS = package.config:sub(1, 1) == "\\"

local function quoted(s)
  return '"' .. s .. '"'
end

---Join already-quoted parts into something `os.execute`/`io.popen` will run.
---
---On Windows this needs an *extra* pair of quotes around the whole line.
---`cmd.exe` strips the first and last quote of a command line, so a quoted
---program path containing spaces — `"C:\Program Files (x86)\Lua\5.4\src\lua.exe"`
---— arrives as `C:\Program Files…`, and it reports `'C:\Program' is not
---recognized`. Which is precisely the defect this script's own header
---criticises `luastatic` for having in its `nm` call; it is an easy one to
---reproduce by accident, and it cost a build here before being fixed.
---@param parts string[]
---@return string
local function cmdline(parts)
  local line = table.concat(parts, " ")
  return WINDOWS and ('"' .. line .. '"') or line
end

-- ---------------------------------------------------------------- manifest

print("== manifest")
-- `arg[-1]` is the interpreter that started this script, and it is the one
-- that must run the manifest too: a different Lua would produce a different
-- closure, which is the exact hazard bundle_manifest.lua warns about.
local INTERP = arg[-1] or "lua"
local manifest_cmd =
  cmdline({ quoted(INTERP), quoted(repo .. "/scripts/bundle_manifest.lua"), quoted(repo) })
local pipe = io.popen(manifest_cmd, "r")
if not pipe then
  die("could not run bundle_manifest.lua")
end
local files = {}
for line in pipe:lines() do
  line = line:gsub("%s+$", "")
  if line:match("%.lua$") then
    files[#files + 1] = line
  end
end
pipe:close()
if #files == 0 then
  die("bundle_manifest.lua produced no files")
end
print(("   %d Lua files"):format(#files))

-- ------------------------------------------------------------ staging tree

print("== staging")
local stage = out_dir .. "/stage"
mkdirp(stage)

---Map a manifest path to the staged relative path whose dots spell the
---module name luastatic will register it under.
---
---Anchored on the *last* occurrence of each marker rather than the start of
---the string, because the manifest yields repo-relative paths when run from
---the repository and absolute ones when run from a build directory — and
---`scripts/package.lua` does the latter.
---
---Returns nil rather than guessing. An earlier version fell through to the
---basename for anything unrecognised, which silently flattened every module
---to `calls`, `check`, `init`… The build still succeeded and produced a
---binary that died at its first `require`, which is the worst possible
---place to find out.
---@param p string
---@return string?
local function staged_name(p)
  local doc = p:match(".*/lua/(documentation/.+)$") or p:match("^lua/(documentation/.+)$")
  if doc then
    return doc
  end
  -- Both sub-namespaces the `lib.nvim` checkout ships live under the same
  -- `lua/lib/` root -- `lua/lib/nvim/...` and `lua/lib/lua/...` are
  -- siblings, not nested. `runtime-analysis.telemetry` requires
  -- `lib.nvim.autocmd`, which requires `lib.lua.lazy` (a pure-Lua utility
  -- with nothing Neovim-specific about it) -- missing the second branch
  -- here meant that module was measured by the manifest but never had
  -- anywhere to stage to, silently dropping `runtime-analysis.telemetry`
  -- out of the bundle even when its own require chain fully resolved.
  local lib = p:match(".*lib%.nvim/lua/(lib/nvim/.+)$") or p:match(".*lib%.nvim/lua/(lib/lua/.+)$")
  if lib then
    return lib
  end
  -- `runtime-analysis.nvim`'s own checkout, mirroring the pattern above:
  -- `bundle_manifest.lua`'s `bucket()` now recognises `runtime-analysis.*`
  -- names as their own group, but recognising them is not staging them --
  -- without this branch every such path fell through to `nil` and the
  -- build would have died with "cannot place ... in the staging tree" the
  -- first time the manifest actually included one, rather than silently
  -- dropping the module the way the *previous*, still-incomplete fix did.
  local ra = p:match(".*runtime%-analysis%.nvim/lua/(runtime%-analysis/.+)$")
  if ra then
    return ra
  end
  local sa = p:match(".*/(standalone/[^/]+%.lua)$") or p:match("^(standalone/[^/]+%.lua)$")
  if sa then
    return sa
  end
  -- A pure-Lua rock installed outside the tree (dkjson) is a single file
  -- whose module name *is* its basename, so it stages at the staging root.
  -- Restricted to a known list so this cannot become the silent catch-all it
  -- was before.
  local base = p:match("([^/]+)$")
  if base == "dkjson.lua" then
    return base
  end
  return nil
end

local staged = {}
for _, f in ipairs(files) do
  local rel = staged_name(f)
  if not rel then
    die("cannot place " .. f .. " in the staging tree")
  end
  -- Same recognition gap `mkdirp` had: a POSIX absolute path (`/tmp/…`, a
  -- rock installed outside the tree on a plain Unix LUA_PATH entry) matches
  -- neither "already absolute" check below without this, so it was treated
  -- as repo-relative and prefixed with `repo .. "/"` — silent on Windows,
  -- where every such rock path already carried a drive letter.
  local abs = (f:match("^%a:") or f:sub(1, 1) == "/") and f or (repo .. "/" .. f)
  copy(abs, stage .. "/" .. rel)
  staged[#staged + 1] = rel
end

-- The entry point is staged separately and on purpose: it is the *main
-- chunk*, reached by `dofile`, so it never appears in `package.loaded` and
-- the manifest is right not to list it. `luastatic` also wants it as its
-- first argument rather than as one more dependency.
local main = "standalone/docmap.lua"
copy(repo .. "/" .. main, stage .. "/" .. main)
print(("   %d staged, entry point %s"):format(#staged + 1, main))

-- --------------------------------------------------------------- libraries

print("== libraries")
local libs = {}
copy(LUA_LIBA, stage .. "/liblua.a")
libs[#libs + 1] = "liblua.a"
for entry in lfs.dir(STATIC_LIBS) do
  if entry:match("%.a$") then
    copy(STATIC_LIBS .. "/" .. entry, stage .. "/" .. entry)
    libs[#libs + 1] = entry
  end
end
if #libs < 2 then
  die(("no .a files in $DOCMAP_STATIC_LIBS (%s) — at least lfs is required"):format(STATIC_LIBS))
end
-- Headers too: LUA_INCDIR is commonly under "Program Files (x86)", and
-- workaround (2) above is about exactly that.
mkdirp(stage .. "/luainc")
for entry in lfs.dir(LUA_INCDIR) do
  if entry:match("%.h$") then
    copy(LUA_INCDIR .. "/" .. entry, stage .. "/luainc/" .. entry)
  end
end
print(("   %s"):format(table.concat(libs, ", ")))

-- ------------------------------------------------------------- generate .c

print("== luastatic")
local cwd = lfs.currentdir():gsub("\\", "/")
-- Same POSIX-absolute-path recognition gap as `mkdirp` and the manifest
-- path mapping above: `--out=/tmp/…` is already absolute, and without the
-- `sub(1,1) == "/"` check this would double-prefix it with `cwd`.
local stage_abs = (stage:match("^%a:") or stage:sub(1, 1) == "/") and stage or (cwd .. "/" .. stage)
lfs.chdir(stage_abs)

-- luastatic's own link step is skipped on purpose (workaround 3): it is only
-- being used as a bundler here, and its failure to find a compiler must not
-- fail this build. The generated `.c` is what matters, so its absence
-- afterwards is the real error.
local ls_parts = { quoted(INTERP), quoted(os.getenv("LUASTATIC") or "luastatic"), quoted(main) }
for _, f in ipairs(staged) do
  ls_parts[#ls_parts + 1] = quoted(f)
end
for _, l in ipairs(libs) do
  ls_parts[#ls_parts + 1] = quoted(l)
end
ls_parts[#ls_parts + 1] = quoted("-Iluainc")
local ls = cmdline(ls_parts)
os.execute(ls)

local generated = "docmap.luastatic.c"
local probe = io.open(generated, "rb")
if not probe then
  lfs.chdir(cwd)
  die("luastatic produced no " .. generated .. "\n  command was:\n  " .. ls)
end
local csize = probe:seek("end")
probe:close()
print(("   %s (%.1f MB)"):format(generated, csize / 1024 / 1024))

-- ----------------------------------------------------------------- compile

print("== compile")
local exe = WINDOWS and "docmap.exe" or "docmap"
local libargs = {}
for _, l in ipairs(libs) do
  libargs[#libargs + 1] = quoted(l)
end
local cc_parts = { quoted(CC), "-O2", "-o", quoted(exe), quoted(generated) }
for _, l in ipairs(libargs) do
  cc_parts[#cc_parts + 1] = l
end
cc_parts[#cc_parts + 1] = "-Iluainc"
cc_parts[#cc_parts + 1] = "-lm"
sh(cmdline(cc_parts), "compiling " .. generated)

local bin = io.open(exe, "rb")
if not bin then
  lfs.chdir(cwd)
  die("no binary produced")
end
local bytes = bin:seek("end")
bin:close()

copy(stage_abs .. "/" .. exe, cwd .. "/" .. out_dir .. "/" .. exe)
lfs.chdir(cwd)
-- `copy()` is plain `io.open`/`io.write`, which does not carry an
-- executable bit through even on a filesystem that has one. gcc already
-- set it on the file this copied *from*; belt-and-braces here rather than
-- assumed, since a filesystem that does not track the bit at all (found:
-- a Windows drive mounted into WSL) makes this a silent no-op rather than
-- an error either way.
if not WINDOWS then
  os.execute(cmdline({ "chmod", "+x", quoted(cwd .. "/" .. out_dir .. "/" .. exe) }))
end
print(("   %s/%s (%.1f MB)"):format(out_dir, exe, bytes / 1024 / 1024))

-- ------------------------------------------------------------------ verify

if run_it then
  print("== verify")
  -- Against this repository, into a throwaway directory. A binary that links
  -- but cannot generate is not a successful build, and that distinction is
  -- exactly what the first hand-built attempt got wrong: it linked fine and
  -- then died at its first `require`.
  sh(
    cmdline({
      quoted(cwd .. "/" .. out_dir .. "/" .. exe),
      quoted(repo),
      "--source=lua/documentation",
      "--out-dir=.deps/package-verify",
    }),
    "running the binary"
  )
  print("   ok — the binary generated a map")
end

if not keep then
  print("== cleanup (--keep to inspect the staging tree)")
end

print("\ndone: " .. out_dir .. "/" .. exe)
