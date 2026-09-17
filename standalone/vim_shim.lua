---@module 'standalone.vim_shim'
--- A closed-scope polyfill of the small `vim.*` surface documentation.nvim's
--- `core/*.lua` pipeline (and the two `lib.nvim.fs.*` helpers it calls into,
--- `read`/`collect_recursive`) actually touches during a **parser-less**
--- scan/check/render pass — see `docs/FEATURE_LOG.md`s "standalone CLI, MVP"
--- entry for how this list
--- was derived (grep against every real `vim.*` call site under `core/`,
--- doc-comment mentions excluded).
---
--- NOT a general-purpose Neovim polyfill — it implements exactly the
--- following, nothing more, and is expected to grow only when a new `core/`
--- call site needs it (checked, not guessed):
---
---   vim.trim, vim.pesc, vim.split, vim.tbl_map, vim.tbl_extend,
---   vim.tbl_deep_extend,
---   vim.list_extend, vim.deepcopy, vim.json.encode/decode, vim.NIL,
---   vim.fs.dir, vim.uv (= vim.loop): fs_stat/fs_scandir/fs_scandir_next/
---   hrtime, vim.treesitter (inert stub — see below).
---
--- **Backed by `luafilesystem` (lfs), not real `luv`.** PORTABILITY.md's own
--- reading was "`vim.uv` → `luv` is close to a rename" — true, and worth
--- reconsidering if this ever needs libuv's actual async model (it does
--- not: a batch CLI scanner is a straight-line synchronous walk, the same
--- shape `lib.nvim.fs.collect_recursive`'s own synchronous `collect()` already
--- has). `lfs` is a smaller, synchronous-only, cross-platform-proven
--- dependency for exactly that shape, with no libuv event-loop machinery
--- this tool never needs. `vim.uv.hrtime()` is approximated with
--- `os.clock()` (CPU time, not wall time) — a cosmetic difference for the
--- scan-stage timing `core/timing.lua` reports, not a correctness one;
--- disclosed here rather than silently assumed equivalent.
---
--- **`vim.treesitter` is an inert stub, not a missing global.** Several
--- `core/*.lua` files call `vim.treesitter.query.parse(lang, pattern)` at
--- module load time (`local CALL_QUERY = vim.treesitter.query.parse(...)` —
--- top-level, unguarded) — if this were nil, `require`ing those modules
--- would fail outright and the whole pipeline would come down with it. Every
--- *use* of the query's results is downstream of `vim.treesitter.
--- get_string_parser`, and every one of those call sites already wraps it in
--- `pcall` (checked: `coverage.lua`, `functions.lua`, `lang/ecma.lua` — all
--- four call sites, not assumed). So `get_string_parser` here simply
--- `error()`s, which those existing `pcall`s already catch and treat exactly
--- like "no parser available" — the same degradation path `opts.luals`'s own
--- absence already exercises. `query.parse` itself must succeed (nothing
--- downstream of it is ever reached without a parser, so its returned stub's
--- `iter_captures`/`iter_matches` are never actually called — they exist only
--- so `query.parse(...)` doesn't error at load time). Net effect, matching
--- PORTABILITY.md's own prediction exactly: the module tree, require graph
--- (minus the deferred/load-time distinction — everything reads as
--- load-time), and every check that doesn't need per-function facts still
--- work; `fn`-level data (functions, calls, complexity, duplicates) comes
--- back empty rather than wrong.

local lfs = require("lfs")
local dkjson = require("dkjson")

if _G.vim then
  return _G.vim -- real Neovim: never shadow the real global
end

local vim = {}

---Whether a backslash is a path separator here.
---
---Neovim asks `has('win32')`; this asks the interpreter what its directory
---separator is. The two agree on every host either of them runs on, and the
---distinction matters because several functions below are *platform*-
---dependent rather than merely path-dependent: `\` separates directories on
---Windows and is an ordinary filename character everywhere else. A shim that
---picks one of the two answers is wrong on the other host, silently — which
---is what `TESTS/shim_behavior_spec.lua` was written to notice.
local IS_WINDOWS = (package.config:sub(1, 1) == "\\")

-- ---------------------------------------------------------------- stdlib

---@param s string
---@return string
function vim.trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

---Escape a string so it matches itself as a Lua pattern.
---
---Neovim's own implementation, which is one `gsub` and worth having exactly
---right: the magic set is `^$()%.[]*+-?`, and the escape character is `%`.
---Getting this subtly wrong -- forgetting `-`, say -- produces a pattern that
---still matches most inputs and silently mismatches a path with a hyphen in
---it, which is the kind of failure that reads as a scanner bug.
---
---**Added 2026-08-20, after a release build failed on it.**
---`core/check.lua`'s test-reference check has called `vim.pesc` since it
---shipped that morning, which works under Neovim and raised "attempt to call
---a nil value" here. Local runs missed it because the `standalone` gate
---skips on a machine with no PUC Lua on `PATH` -- see this file's header on
---why that makes local green worth less than it looks.
---@param s string
---@return string
function vim.pesc(s)
  return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1"))
end

---Split, on a literal separator with `plain = true` and on a Lua **pattern**
---without it — the same rule Neovim applies.
---
---**This used to be plain-only, and that was the quiet kind of wrong.** Every
---call site under `core/` passes `{ plain = true }`, so the restriction cost
---nothing the day it was written; what it cost was a guarantee. A future
---`vim.split(s, "%s+")` would not have raised here — it would have searched
---for the four literal characters `%s+`, found none, and returned the whole
---string as a single element. Under Neovim the same line splits on runs of
---whitespace. A scanner that reads one field where the editor reads five
---does not crash, it under-reports, which is the failure class this build
---has already shipped three times.
---
---The empty-pattern guard is Neovim's too: a separator that can match the
---empty string (`"%s*"`) never advances the cursor, so the loop would spin
---forever rather than return something wrong. Neovim raises there, and so
---does this.
---@param s string
---@param sep string
---@param opts { plain?: boolean, trimempty?: boolean }|nil
---@return string[]
function vim.split(s, sep, opts)
  opts = opts or {}
  local out = {}
  if sep == "" then
    for i = 1, #s do
      out[#out + 1] = s:sub(i, i)
    end
    return out
  end
  local pos = 1
  while true do
    local start_idx, end_idx = s:find(sep, pos, opts.plain == true)
    if not start_idx then
      out[#out + 1] = s:sub(pos)
      break
    end
    if end_idx < start_idx then
      error("Infinite loop detected", 0)
    end
    out[#out + 1] = s:sub(pos, start_idx - 1)
    pos = end_idx + 1
  end
  if opts.trimempty then
    while out[1] == "" do
      table.remove(out, 1)
    end
    while out[#out] == "" do
      table.remove(out)
    end
  end
  return out
end

---@generic T, U
---@param fn fun(v: T): U
---@param t T[]
---@return U[]
function vim.tbl_map(fn, t)
  local out = {}
  for i, v in ipairs(t) do
    out[i] = fn(v)
  end
  return out
end

---Neovim takes at least two tables and says so when it does not get them.
---Accepting one and quietly returning a copy hides the call-site mistake at
---the only moment anyone would have looked at it.
---@param behavior "force"|"keep"|"error"
---@param ... table
---@return table
function vim.tbl_extend(behavior, ...)
  if select("#", ...) < 2 then
    error(
      ("wrong number of arguments (given %d, expected at least 3)"):format(1 + select("#", ...)),
      0
    )
  end
  local out = {}
  for _, t in ipairs({ ... }) do
    for k, v in pairs(t) do
      if out[k] == nil or behavior == "force" then
        out[k] = v
      elseif behavior == "error" and out[k] ~= nil then
        error("key found in more than one map: " .. tostring(k), 0)
      end
    end
  end
  return out
end

---Whether a value is something `tbl_deep_extend` merges *into* rather than
---replaces.
---
---Neovim's rule, and it is not the obvious one: a list is **replaced**
---wholesale, a map is merged, and an empty table counts as a map because it
---is not yet either. The obvious implementation — merge anything that is a
---table on both sides — leaves the tail of the longer list behind, so
---`{ 1, 2, 3 }` overridden by `{ 9 }` comes out as `{ 9, 2, 3 }`: a value no
---caller wrote, that still looks like configuration.
---@param v any
---@return boolean
local function can_merge(v)
  if type(v) ~= "table" then
    return false
  end
  local n = 0
  for k in pairs(v) do
    n = n + 1
    if type(k) ~= "number" then
      return true -- has a non-list key: a map, so mergeable
    end
  end
  if n == 0 then
    return true -- empty: not yet a list, so mergeable
  end
  -- All keys numeric: a list exactly when they are 1..n with no holes.
  for i = 1, n do
    if v[i] == nil then
      return true
    end
  end
  return false
end

---@param behavior "force"|"keep"|"error"
---@param ... table
---@return table
function vim.tbl_deep_extend(behavior, ...)
  local out = {}
  for _, t in ipairs({ ... }) do
    for k, v in pairs(t) do
      if can_merge(out[k]) and can_merge(v) then
        -- A fresh table, never a write through `out[k]`. `out[k]` may still
        -- be a table the *caller* passed — it was assigned by reference on
        -- first sight — so merging in place would reach back out of this
        -- function and edit an argument. Neovim does not, and a caller that
        -- reuses its defaults table would find them rewritten.
        out[k] = vim.tbl_deep_extend(behavior, out[k], v)
      elseif out[k] == nil or behavior == "force" then
        out[k] = v
      elseif behavior == "error" and out[k] ~= nil then
        error("key found in more than one map: " .. tostring(k), 0)
      end
    end
  end
  return out
end

---Append `src[start..finish]` to `dst`, defaulting to all of `src`.
---
---The two bounds are the part that was missing, and their absence was not
---visible from any call site: `vim.list_extend(dst, src, 2, 3)` appended the
---whole of `src` here and a two-element slice under Neovim, with nothing
---raised on either side.
---@param dst table
---@param src table
---@param start integer|nil
---@param finish integer|nil
---@return table dst
function vim.list_extend(dst, src, start, finish)
  for i = start or 1, finish or #src do
    dst[#dst + 1] = src[i]
  end
  return dst
end

---A deep copy that preserves sharing, survives cycles, and carries
---metatables — all three of which Neovim's does.
---
---**The cache is not an optimisation.** Without it, a table that reaches
---itself is not copied wrongly, it overflows the stack; and a table reachable
---by two paths becomes two tables, so a later write through one of them stops
---being visible through the other. Neither shows up as a missing name, which
---is why the static contract could not see it.
---@param v any
---@param seen table<table, table>|nil
---@return any
function vim.deepcopy(v, seen)
  if type(v) ~= "table" then
    return v
  end
  seen = seen or {}
  if seen[v] then
    return seen[v]
  end
  local out = {}
  seen[v] = out
  for k, val in pairs(v) do
    out[vim.deepcopy(k, seen)] = vim.deepcopy(val, seen)
  end
  return setmetatable(out, getmetatable(v))
end

-- ------------------------------------------------------------------ json

vim.NIL = dkjson.null or setmetatable({}, {
  __tostring = function()
    return "null"
  end,
})

vim.json = {}

local STRING_ESCAPE = {
  ['"'] = '\\"',
  ["\\"] = "\\\\",
  ["\b"] = "\\b",
  ["\f"] = "\\f",
  ["\n"] = "\\n",
  ["\r"] = "\\r",
  ["\t"] = "\\t",
}

---A JSON string exactly as Neovim writes one.
---
---Measured against the editor rather than assumed: the five short escapes
---above, `\u00xx` in **lower-case** hex for every other control byte and for
---DEL, `/` left alone, and UTF-8 passed through raw rather than escaped to
---`\uXXXX`.
---
---That last one is why this is written out instead of delegated. The
---artifact is byte-compared — by `map --check` and by a pre-commit hook —
---so a docstring with an umlaut in it escaped one way by the editor and
---another way by the rock is not a cosmetic difference: it is the same
---"the map is stale" report that host-dependent *number* formatting already
---produced once, from a different direction. Delegating left that answer
---up to a dependency nobody here had measured.
---
---The character class avoids an embedded zero byte on purpose: LuaJIT's
---patterns are Lua 5.1's and cannot carry one, and `%z` — 5.1's way of
---saying it — was removed in 5.3. `%c` covers the whole control range
---including NUL on both.
---@param s string
---@return string
local function encode_string(s)
  local body = s:gsub('[%c"\\\127]', function(c)
    return STRING_ESCAPE[c] or string.format("\\u%04x", c:byte())
  end)
  return '"' .. body .. '"'
end

---A JSON number exactly as Neovim writes one.
---
---Two rules, both measured: an integral value that fits a 64-bit integer is
---written without a decimal point (`100.0` -> `100`, `2^53` ->
---`9007199254740992`), and anything else gets the shortest `%g` that reads
---back as the same double — which is how `1/3` comes out as
---`0.3333333333333333` (16 digits) where a plain `%.14g` would truncate it,
---and how `1e20`, too large for the integer rule, stays `1e+20`.
---@param v number
---@return string
local function encode_number(v)
  if v ~= v or v == math.huge or v == -math.huge then
    error("Cannot serialise number: must not be NaN or Infinity", 0)
  end
  if v % 1 == 0 and math.abs(v) < 2 ^ 63 then
    return string.format("%d", v)
  end
  for _, fmt in ipairs({ "%.14g", "%.15g", "%.16g", "%.17g" }) do
    local out = string.format(fmt, v)
    if tonumber(out) == v then
      return out
    end
  end
  return string.format("%.17g", v)
end

---@param ... any The value to encode. Exactly one argument, `nil` included.
---@return string
function vim.json.encode(...)
  -- Varargs so that `encode()` and `encode(nil)` stay two different calls:
  -- the editor answers `null` to the second and raises on the first, and a
  -- plain `function(value)` parameter cannot tell them apart.
  if select("#", ...) == 0 then
    error("expected 1 or 2 arguments", 0)
  end
  local value = ...
  -- Scalars are written here rather than handed to dkjson: they are the only
  -- thing `core/json.lua` ever delegates (that module encodes every container
  -- itself, to get a deterministic key order), they are what ends up in the
  -- byte-compared artifact, and writing them here is what lets
  -- `TESTS/shim_behavior_spec.lua` compare them against the editor without
  -- needing the rock.
  if value == nil or value == vim.NIL then
    return "null"
  end
  local ty = type(value)
  if ty == "boolean" then
    return value and "true" or "false"
  elseif ty == "number" then
    return encode_number(value)
  elseif ty == "string" then
    return encode_string(value)
  end
  -- Containers still go to dkjson, and are deliberately *not* compared:
  -- Neovim gives no ordering guarantee for object keys, so "the same output"
  -- is not a thing either side can promise. Nothing in the standalone path
  -- takes this branch — `core/json.lua` handles its own containers — and it
  -- stays only so a caller that did would keep working.
  return (dkjson.encode(value))
end

---Strip what dkjson adds and Neovim does not, and apply `luanil`.
---
---Two jobs, one walk over a tree that is by construction acyclic:
---
---  * `luanil` sets a JSON null to `nil` — which removes the key from an
---    object and leaves a **hole** in an array, both measured against the
---    editor. Without it the value is a sentinel.
---  * any metatable dkjson may have attached is removed. Neovim hands back
---    plain tables, and a stray `__index` or `__jsontype` is the kind of
---    difference that surfaces three call sites later as an impossible
---    `pairs` result.
---@param value any
---@param drop boolean
---@return any
local function normalize_decoded(value, drop)
  if type(value) ~= "table" then
    return value
  end
  setmetatable(value, nil)
  for k, v in pairs(value) do
    if v == vim.NIL and drop then
      value[k] = nil
    else
      normalize_decoded(v, drop)
    end
  end
  return value
end

---@param s string
---@param opts { luanil?: { object?: boolean, array?: boolean } }|nil
---@return any
function vim.json.decode(s, opts)
  opts = opts or {}
  local luanil = opts.luanil or {}
  -- The null value is passed explicitly and then dealt with above, rather
  -- than leaning on what dkjson does when the argument is omitted. The
  -- version this replaces asked for a sentinel precisely when the caller
  -- had said it wanted nulls *dropped* — inverted, in other words, so every
  -- `luanil` call site in this tree (all of them: artifact.lua,
  -- tagfiles.lua, luals.lua, …) got `vim.NIL` where Neovim gives nothing.
  -- `vim.NIL` is truthy, which `editor/browse/README.md` already calls out
  -- as very easy to mishandle, so the failure would have been a field that
  -- reads as present and renders as garbage.
  local obj, _, err = dkjson.decode(s, 1, vim.NIL)
  if err then
    error(err, 0)
  end
  return normalize_decoded(obj, luanil.object == true or luanil.array == true)
end

-- -------------------------------------------------------------------- fs

vim.fn = {}

---@param path string
---@return integer 1 if `path` is a directory, 0 otherwise
function vim.fn.isdirectory(path)
  return lfs.attributes(path, "mode") == "directory" and 1 or 0
end

---Neovim's own standard directories, reimplemented rather than guessed.
---
---**Why this is here at all**, since nothing in the scan pipeline wants it:
---`runtime-analysis.nvim`'s telemetry store resolves its cache root from
---`vim.fn.stdpath("cache")` at *module load time*, so the `--api=telemetry`
---and `--api=loaded` routes cannot even `require` it without this. That is
---the only reason this exists, and the reason it must be exact: a shim that
---resolves a *different* directory than the running editor would report
---"no telemetry data" for data that is sitting on disk — silent degradation,
---the failure class this build has already paid for once.
---
---Verified against a real `nvim --headless` on this platform rather than
---read off the documentation: on Windows `cache` is `$TEMP/nvim` (not
---`%LOCALAPPDATA%`, which is the intuitive wrong answer), `data` is
---`nvim-data`, `config` is plain `nvim`. Elsewhere the XDG variables win
---when set, with the documented defaults underneath.
---@param what string One of "cache"|"data"|"config"|"state"|"log".
---@return string
function vim.fn.stdpath(what)
  local function env(name, fallback)
    local v = os.getenv(name)
    return (v and v ~= "") and v or fallback
  end

  local base
  if IS_WINDOWS then
    local local_app = env("LOCALAPPDATA", env("USERPROFILE", ".") .. "/AppData/Local")
    base = {
      cache = env("TEMP", env("TMP", local_app .. "/Temp")) .. "/nvim",
      data = local_app .. "/nvim-data",
      config = local_app .. "/nvim",
      -- Neovim keeps both under the data root on Windows.
      state = local_app .. "/nvim-data",
      log = local_app .. "/nvim-data",
    }
  else
    local home = env("HOME", ".")
    local data = env("XDG_DATA_HOME", home .. "/.local/share") .. "/nvim"
    base = {
      cache = env("XDG_CACHE_HOME", home .. "/.cache") .. "/nvim",
      data = data,
      config = env("XDG_CONFIG_HOME", home .. "/.config") .. "/nvim",
      state = env("XDG_STATE_HOME", home .. "/.local/state") .. "/nvim",
      log = env("XDG_STATE_HOME", home .. "/.local/state") .. "/nvim",
    }
  end

  local dir = base[what]
  if not dir then
    error("standalone vim_shim: vim.fn.stdpath does not implement " .. tostring(what), 0)
  end
  return (dir:gsub("\\", "/"))
end

---Fold the platform's separators to `/`, so one rule covers both.
---@param path string
---@return string
local function to_slashes(path)
  if IS_WINDOWS then
    return (path:gsub("\\", "/"))
  end
  return path
end

---Only the `":t"` (tail/basename) modifier — the one real call site
---(`documentation.config`'s own `title` default) never uses another.
---
---**The tail of a path that ends in a separator is empty.** This used to
---strip trailing separators first and then take the last component, which
---turns `"a/b/"` into `"b"` — a name the editor never reports for that path,
---and one that reads perfectly plausibly in a title.
---@param path string
---@param mods string
---@return string
function vim.fn.fnamemodify(path, mods)
  if mods == ":t" then
    return (to_slashes(path):match("[^/]*$")) or ""
  end
  error('standalone vim_shim: vim.fn.fnamemodify only implements ":t", got ' .. tostring(mods), 0)
end

vim.fs = {}

---Everything before the last separator, with the three edges Neovim has and
---the old one-line pattern did not.
---
---The pattern this replaces skipped *past* a trailing separator, so
---`"a/b/"` answered `"a"` — the grandparent — and `"/a"` answered the empty
---string rather than the root. Each is a plausible-looking path, and a
---scanner that files a module under the wrong parent reports a tree nobody
---has.
---@param path string
---@return string
function vim.fs.dirname(path)
  local parent = to_slashes(path):match("^(.*)/[^/]*$")
  if not parent then
    return "."
  elseif parent == "" then
    return "/"
  elseif IS_WINDOWS and parent:match("^%a:$") then
    -- `C:/a` -> `C:/`, not `C:`: the drive root is a directory, the bare
    -- drive letter is a different thing entirely.
    --
    -- **Only on Windows**, and that guard was missing for one CI run. A
    -- drive letter is not a path concept on Linux, where the editor answers
    -- a plain `C:` and treats it as an ordinary directory name — so a shim
    -- applying the rule unconditionally is wrong on exactly the host the
    -- `standalone` gate actually runs on. The differential caught it on its
    -- first run in CI, which is the argument for the differential.
    return parent .. "/"
  end
  return parent
end

---Directory iterator shaped like `vim.fs.dir`: `for name, type in
---vim.fs.dir(dir) do ... end`, `type` one of the `uv` dirent strings this
---codebase actually branches on (`"directory"`/`"file"`; anything else is
---never distinguished by a real call site, checked).
---@param dir string
---@return fun(): string?, string?
function vim.fs.dir(dir)
  local ok, iter_fn, dir_obj = pcall(lfs.dir, dir)
  if not ok then
    return function()
      return nil
    end
  end
  return function()
    local name = iter_fn(dir_obj)
    while name == "." or name == ".." do
      name = iter_fn(dir_obj)
    end
    if not name then
      return nil
    end
    local mode = lfs.attributes(dir .. "/" .. name, "mode")
    return name, mode
  end
end

-- ------------------------------------------------------------ uv / loop

local uv = {}

---@param path string
---@return { type: string }|nil
function uv.fs_stat(path)
  local mode = lfs.attributes(path, "mode")
  if not mode then
    return nil
  end
  return { type = mode }
end

---@param dir string
---@return table|nil handle
function uv.fs_scandir(dir)
  local ok, iter_fn, dir_obj = pcall(lfs.dir, dir)
  if not ok then
    return nil
  end
  return { iter = iter_fn, obj = dir_obj, dir = dir }
end

---@param handle table
---@return string|nil name
---@return string|nil type
function uv.fs_scandir_next(handle)
  local name = handle.iter(handle.obj)
  while name == "." or name == ".." do
    name = handle.iter(handle.obj)
  end
  if not name then
    return nil
  end
  return name, lfs.attributes(handle.dir .. "/" .. name, "mode")
end

---@param path string
---@param _mode integer
---@return boolean|nil ok `true`, or `nil` the way `uv` reports a failure.
function uv.fs_mkdir(path, _mode)
  -- `lfs.mkdir` has no mode parameter (POSIX permission bits are not a
  -- concern for a docs artifact directory); `lib.nvim.fs.mkdirp` treats a
  -- falsy return the same as EEXIST would (checks fs_stat next), so the
  -- "already exists" case does not need distinguishing here either.
  --
  -- `nil` rather than `false` on failure: that is the shape `uv` returns,
  -- and the difference is invisible to every `if not ok` in this tree right
  -- up until someone writes `== false`.
  local made = lfs.mkdir(path)
  return made == true or nil
end

---Approximated with `os.clock()` (process CPU time) — see this file's
---header for why that is an honest, disclosed substitution rather than a
---silent one, and what it costs (cosmetic drift in scan-stage timing only).
---@return number nanoseconds
function uv.hrtime()
  return os.clock() * 1e9
end

vim.uv = uv
vim.loop = uv

-- ------------------------------------------------------------ treesitter

-- See this file's header for why `query.parse` must succeed while
-- `get_string_parser` may safely fail: every real call site already
-- `pcall`s the latter, none guard the former.
local inert_query = {
  iter_captures = function()
    return function()
      return nil
    end
  end,
  iter_matches = function()
    return function()
      return nil
    end
  end,
}

local inert_treesitter = {
  query = {
    parse = function()
      return inert_query
    end,
  },
  get_string_parser = function()
    error("standalone build: no treesitter parser available (parser-less MVP)", 0)
  end,
  get_node_text = function()
    error("standalone build: no treesitter parser available (parser-less MVP)", 0)
  end,
  language = {
    add = function()
      return false
    end,
  },
}

-- A real parser when one is installed and a grammar is reachable, the inert
-- stub above otherwise. The fallback is the point: a machine without the
-- `lua-tree-sitter` rock still gets the parser-less MVP exactly as before,
-- rather than a build that refuses to start. See `standalone/treesitter.lua`
-- for the grammar-resolution rules and for why the API needs translating.
local ok_real, real = pcall(function()
  return require("standalone.treesitter").build()
end)
vim.treesitter = (ok_real and real) or inert_treesitter

_G.vim = vim

return vim
