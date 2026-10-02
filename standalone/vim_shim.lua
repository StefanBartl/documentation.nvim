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
--- and, added for running `rules.nvim`'s engine (and the Neovim-API calls its
--- real rulesets make inside `lua_predicate`s) without an editor — measured by
--- loading that engine and a 430-rule ruleset under this shim, not guessed:
---
---   vim.islist, vim.tbl_contains, vim.env (read-only), vim.log.levels,
---   vim.fn.{filereadable, readfile, getcwd, glob, system, fnamemodify
---   (":t", ":p")}, vim.v.shell_error, vim.fs.{basename, normalize},
---   vim.uv.{os_getenv, os_homedir}.
---
--- Each has cases in `TESTS/fixtures/shim_behavior_cases.lua`, compared against
--- the editor on both interpreters. What is *refused* rather than approximated
--- (`glob` with `nosuf` or a trailing separator, `fnamemodify(":p")` on `~`,
--- `readfile` on a file with NUL bytes, `system` with stdin or on a Lua that
--- cannot report an exit status) raises, and is pinned in
--- `TESTS/shim_behavior_spec.lua`.
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

---Fold the platform's separators to `/`, so one rule covers both.
---@param path string
---@return string
local function to_slashes(path)
  if IS_WINDOWS then
    return (path:gsub("\\", "/"))
  end
  return path
end

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

local BEHAVIORS = { force = true, keep = true, error = true }

---Reject a behavior string the editor would reject.
---
---A misspelled `"forse"` is not a table-merging question, it is a typo — and
---without this it silently means `"keep"`, so the override the caller wrote
---simply does not happen and the old value survives looking deliberate.
---@param behavior string
local function check_behavior(behavior)
  if not BEHAVIORS[behavior] then
    error(('invalid "behavior": %s'):format(tostring(behavior)), 0)
  end
end

---Neovim takes at least two tables and says so when it does not get them.
---Accepting one and quietly returning a copy hides the call-site mistake at
---the only moment anyone would have looked at it.
---@param behavior "force"|"keep"|"error"
---@param ... table
---@return table
function vim.tbl_extend(behavior, ...)
  check_behavior(behavior)
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
  check_behavior(behavior)
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

---Neovim's own definition, key for key: `{}` is a list, and so is any table
---whose keys are exactly `1..n`. A hole or a string key is not.
---
---**Differs from the editor in one place, on purpose and narrowly:** Neovim
---answers `false` for the table `vim.empty_dict()` and for what
---`vim.json.decode("{}")` returns, because both carry a marker metatable. The
---shim has neither marker, so those read as lists. The one caller that meets a
---decoded document (`rules.nvim`'s waivers loader) already asks
---`next(t) ~= nil` first for exactly this reason, and says so.
---@param t any
---@return boolean
function vim.islist(t)
  if type(t) ~= "table" then
    return false
  end
  local j = 1
  for _ in pairs(t) do
    if t[j] == nil then
      return false
    end
    j = j + 1
  end
  return true
end

---`vim.tbl_contains(t, value)` or, with `{ predicate = true }`, whether any
---entry satisfies the function passed as `value`. Walks with `pairs`, as the
---editor does, so it answers for dictionaries too.
---@param t table
---@param value any|fun(v: any): boolean
---@param opts { predicate?: boolean }|nil
---@return boolean
function vim.tbl_contains(t, value, opts)
  if type(t) ~= "table" then
    error("t: expected table, got " .. type(t), 2)
  end
  local predicate = opts and opts.predicate
  for _, v in pairs(t) do
    if predicate then
      if value(v) then
        return true
      end
    elseif v == value then
      return true
    end
  end
  return false
end

---The severity numbers, as Neovim 0.12 defines them. Nothing here logs: it is
---a lookup table, there because a `lib.nvim` module reads
---`vim.log.levels.INFO` at *load* time to fill a config default — and the
---`standalone` build and the engine release both failed on `field 'log'` the
---day that module landed, with no change in this repository at all.
vim.log = {
  levels = { TRACE = 0, DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4, OFF = 5 },
}

---The process environment, read-only. `vim.env.NAME` is `nil` when unset.
---
---Read-only because `os.getenv` has no counterpart for writing in standard
---Lua, and a silent no-op on assignment would be the worst of the options:
---`vim.env.X = "1"` would appear to work and nothing downstream would see it.
vim.env = setmetatable({}, {
  __index = function(_, name)
    return os.getenv(name)
  end,
  __newindex = function(_, name)
    error(("standalone vim_shim: vim.env is read-only (assigning %s)"):format(tostring(name)), 2)
  end,
})

---@param v any
---@param seen table<table, table>|nil
---@return any
local function deepcopy(v, seen)
  if type(v) ~= "table" then
    return v
  end
  if seen then
    if seen[v] then
      return seen[v]
    end
  end
  local out = {}
  if seen then
    seen[v] = out
  end
  for k, val in pairs(v) do
    out[deepcopy(k, seen)] = deepcopy(val, seen)
  end
  return setmetatable(out, getmetatable(v))
end

---A deep copy that preserves sharing, survives cycles, and carries
---metatables — all three of which Neovim's does.
---
---**The cache is not an optimisation.** Without it, a table that reaches
---itself is not copied wrongly, it overflows the stack; and a table reachable
---by two paths becomes two tables, so a later write through one of them stops
---being visible through the other. Neither shows up as a missing name, which
---is why the static contract could not see it.
---
---**The second parameter is Neovim's `noref`, not an internal one.** It was
---the cache for one commit, and `editor/browse/init.lua` calls
---`vim.deepcopy(KEYS, true)` — so the shim raised *attempt to index a boolean*
---on a call the editor answers perfectly well. That is precisely the class of
---defect this file's tests exist to prevent, introduced while fixing another
---one: a signature narrower than the editor's is a behavioural difference too.
---The cache therefore lives in a local helper, out of reach of callers.
---@param orig any
---@param noref boolean|nil When true, every occurrence of a table becomes a
---new copy instead of one shared copy — which also means a cyclic reference
---makes the call fail, exactly as it does in Neovim.
---@return any
function vim.deepcopy(orig, noref)
  return deepcopy(orig, not noref and {} or nil)
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
local function encode_string(s, escape_slash)
  local body = s:gsub(escape_slash and '[%c"\\/\127]' or '[%c"\\\127]', function(c)
    if c == "/" then
      return "\\/"
    end
    local short = STRING_ESCAPE[c]
    if short then
      return short
    end
    local byte = c:byte()
    -- `%c` is whatever `iscntrl` says under the current `LC_CTYPE`, and a
    -- locale where that also covers 0x80-0x9F would match the continuation
    -- bytes of a UTF-8 character and escape them one by one — silently
    -- corrupting exactly the umlaut this function is careful about. Returning
    -- the byte unchanged makes the over-match harmless instead of relying on
    -- the locale being C. (Not reproduced on any locale available here; this
    -- is the cheap way to stop depending on the answer.)
    if byte > 0x7f then
      return c
    end
    return string.format("\\u%04x", byte)
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
  -- The second argument is Neovim's options table, and the one option that
  -- changes the bytes is `escape_slash`. Nothing in this tree passes it, but
  -- accepting the argument and ignoring it is how a shim ends up quietly
  -- disagreeing with the editor — the same shape as `deepcopy`'s `noref`.
  local value, opts = ...
  local escape_slash = opts ~= nil and opts.escape_slash == true
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
    return encode_string(value, escape_slash)
  end
  -- Containers still go to dkjson, and are deliberately *not* compared:
  -- Neovim gives no ordering guarantee for object keys, so "the same output"
  -- is not a thing either side can promise. Nothing in the standalone path
  -- takes this branch — `core/json.lua` handles its own containers — and it
  -- stays only so a caller that did would keep working. `escape_slash` does
  -- not reach it, which is one more reason not to start using it.
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
    -- Setting a field to `nil` during a `pairs` traversal is explicitly
    -- allowed; adding one is not, and nothing here adds.
    if drop and v == vim.NIL then
      value[k] = nil
    elseif type(v) == "table" then
      -- Tested before the call rather than inside it: this walk runs over
      -- every decoded document, and `module_map.json` is ~1.9 MB of mostly
      -- string and number leaves. Recursing into each of those only to
      -- return immediately is one function call per leaf for nothing.
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

---@param path string
---@return integer 1 if `path` is a regular file that can be opened for reading
function vim.fn.filereadable(path)
  if lfs.attributes(path, "mode") ~= "file" then
    return 0
  end
  local fd = io.open(path, "rb")
  if not fd then
    return 0
  end
  fd:close()
  return 1
end

---The lines of a file, the way the editor reads them — and the way is not
---"split on newlines": without the `"b"` flag a CR before an NL is dropped, a
---trailing NL adds no empty last line, and a UTF-8 byte-order mark is removed;
---with it nothing is dropped and a trailing NL *does* add an empty last
---element. `max` keeps the first `max` lines, or the last `-max` for a
---negative one. An unreadable file raises, as `E484` does.
---
---A NUL byte is not translated (the editor stores it as an NL inside the
---line); a file that has one raises here rather than returning lines that
---differ from the editor's.
---@param path string
---@param flags string|nil `"b"` for binary mode
---@param max integer|nil
---@return string[]
function vim.fn.readfile(path, flags, max)
  if flags ~= nil and flags ~= "" and flags ~= "b" then
    error(
      'standalone vim_shim: vim.fn.readfile only implements the "b" flag, got ' .. tostring(flags),
      0
    )
  end
  local fd = io.open(path, "rb")
  if not fd or lfs.attributes(path, "mode") ~= "file" then
    if fd then
      fd:close()
    end
    error("E484: Can't open file " .. tostring(path), 0)
  end
  local data = fd:read("*a") or ""
  fd:close()
  if data:find("\0", 1, true) then
    error(
      "standalone vim_shim: vim.fn.readfile does not translate NUL bytes: " .. tostring(path),
      0
    )
  end

  local binary = flags == "b"
  if not binary and data:sub(1, 3) == "\239\187\191" then
    data = data:sub(4)
  end

  local lines = {}
  local pos = 1
  while true do
    local nl = data:find("\n", pos, true)
    if not nl then
      lines[#lines + 1] = data:sub(pos)
      break
    end
    lines[#lines + 1] = data:sub(pos, nl - 1)
    pos = nl + 1
  end
  -- `"a\nb\n"` split on NL ends in an empty piece. Binary mode keeps it (the
  -- file really does end in a line break); text mode does not care.
  if not binary and lines[#lines] == "" then
    lines[#lines] = nil
  end
  if not binary then
    for i, line in ipairs(lines) do
      -- Only a CR *before an NL*: the last line has none after it, so a CR
      -- that ends the file is content.
      if i < #lines or data:sub(-1) == "\n" then
        lines[i] = (line:gsub("\r$", ""))
      end
    end
  end

  if max ~= nil then
    local out = {}
    if max >= 0 then
      for i = 1, math.min(max, #lines) do
        out[i] = lines[i]
      end
    else
      for i = math.max(1, #lines + max + 1), #lines do
        out[#out + 1] = lines[i]
      end
    end
    return out
  end
  return lines
end

---@return string
function vim.fn.getcwd()
  return (lfs.currentdir())
end

---One glob path segment as a Lua pattern: `*` and `?` stay inside a segment,
---`[abc]`/`[!abc]` are classes, everything else is literal.
---@param seg string
---@return string
local function glob_segment_pattern(seg)
  local out = {}
  local i = 1
  while i <= #seg do
    local c = seg:sub(i, i)
    local close = c == "[" and seg:find("]", i + 2, true) or nil
    if c == "*" then
      out[#out + 1] = "[^/]*"
    elseif c == "?" then
      out[#out + 1] = "[^/]"
    elseif close then
      local body = seg:sub(i + 1, close - 1):gsub("^[!^]", "^"):gsub("%%", "%%%%")
      out[#out + 1] = "[" .. body .. "]"
      i = close
    else
      out[#out + 1] = (c:gsub("%W", "%%%0"))
    end
    i = i + 1
  end
  return "^" .. table.concat(out) .. "$"
end

---`glob(pattern, nosuf, list)`, for the forms a caller here uses: `*`, `?`,
---`[...]` within a segment and `**` for any number of directory levels
---(including none). Measured against the editor on Windows, and each rule
---below is one of its findings:
---
---  * a name starting with `.` matches only a segment that starts with `.`
---    (and that one also yields `.` and `..`), so `*` and `**` skip dotfiles;
---  * matching ignores case on Windows, where the filesystem does;
---  * directories come back without a trailing separator, and so does a file;
---  * `/**` as the last segment lists everything below, not the root itself.
---
---**The order is not specified.** The editor sorts with the platform's file
---name comparison (case-insensitive on Windows), and nothing here depends on
---it; this returns case-folded alphabetical order, which is the same on both
---hosts and equal to the editor's on Windows.
---
---Refused, not guessed: `nosuf = true`, a pattern ending in `/` (the editor
---answers with trailing separators on *files* too), and a backslash in a
---pattern on a host where it is an escape.
---@param pattern string
---@param nosuf boolean|nil
---@param list boolean|nil Return a list instead of a newline-joined string.
---@return string[]|string
function vim.fn.glob(pattern, nosuf, list)
  if nosuf then
    error("standalone vim_shim: vim.fn.glob does not implement nosuf", 0)
  end
  if pattern:sub(-1) == "/" or (IS_WINDOWS and pattern:sub(-1) == "\\") then
    error("standalone vim_shim: vim.fn.glob does not implement a pattern ending in a separator", 0)
  end
  if not IS_WINDOWS and pattern:find("\\", 1, true) then
    error("standalone vim_shim: vim.fn.glob does not implement backslash escapes", 0)
  end

  local folded = IS_WINDOWS
  local slashed = to_slashes(pattern)
  local segments = {}
  for seg in (slashed .. "/"):gmatch("([^/]*)/") do
    segments[#segments + 1] = seg
  end

  -- The literal head (`E:`, the empty first segment of `/abs`, plain
  -- directories) is walked as a path; wildcards start at the first segment
  -- that has one.
  local base = ""
  local first = 1
  if segments[1] == "" and #segments > 1 then
    base, first = "/", 2
  elseif IS_WINDOWS and segments[1]:match("^%a:$") then
    base, first = segments[1] .. "/", 2
  end
  while first < #segments and not segments[first]:find("[*?%[]") do
    base = base .. segments[first] .. "/"
    first = first + 1
  end
  local function join(dir, name)
    if dir == "" then
      return name
    end
    return dir:sub(-1) == "/" and (dir .. name) or (dir .. "/" .. name)
  end

  local out = {}

  ---@param dir string
  ---@return string[] names
  local function entries(dir)
    local names = {}
    -- `stat` on Windows refuses a path with a trailing separator, so it is
    -- dropped for the question (but never from a bare root: `/`, `C:/`).
    local target = dir == "" and "." or dir
    local bare = target
    if #target > 1 and target:sub(-1) == "/" and not target:match("^%a:/$") then
      bare = target:sub(1, -2)
    end
    if lfs.attributes(bare, "mode") ~= "directory" then
      return names
    end
    local ok, iter_fn, dir_obj = pcall(lfs.dir, target)
    if not ok then
      return names
    end
    for name in iter_fn, dir_obj do
      names[#names + 1] = name
    end
    return names
  end

  ---@param dir string
  ---@param i integer
  local function walk(dir, i)
    local seg = segments[i]
    local is_last = i == #segments

    if seg == "**" then
      if is_last then
        for _, name in ipairs(entries(dir)) do
          if name:sub(1, 1) ~= "." then
            local path = join(dir, name)
            out[#out + 1] = path
            if lfs.attributes(path, "mode") == "directory" then
              walk(path, i)
            end
          end
        end
      else
        walk(dir, i + 1)
        for _, name in ipairs(entries(dir)) do
          local path = join(dir, name)
          if name:sub(1, 1) ~= "." and lfs.attributes(path, "mode") == "directory" then
            walk(path, i)
          end
        end
      end
      return
    end

    if not seg:find("[*?%[]") then
      local path = join(dir, seg)
      local mode = lfs.attributes(path, "mode")
      if is_last then
        if mode then
          out[#out + 1] = path
        end
      elseif mode == "directory" then
        walk(path, i + 1)
      end
      return
    end

    local want_dot = seg:sub(1, 1) == "."
    local lua_pat = glob_segment_pattern(folded and seg:lower() or seg)
    for _, name in ipairs(entries(dir)) do
      local hidden = name:sub(1, 1) == "."
      local candidate = folded and name:lower() or name
      if (not hidden or want_dot) and candidate:match(lua_pat) then
        local path = join(dir, name)
        if is_last then
          out[#out + 1] = path
        elseif lfs.attributes(path, "mode") == "directory" and name ~= "." and name ~= ".." then
          walk(path, i + 1)
        end
      end
    end
  end

  walk(base, first)

  table.sort(out, function(a, b)
    local la, lb = a:lower(), b:lower()
    if la ~= lb then
      return la < lb
    end
    return a < b
  end)
  if list then
    return out
  end
  return table.concat(out, "\n")
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

---Make a path absolute, the way `:p` does for the paths this tree passes it:
---a relative one is joined onto the working directory (with `.` and `..`
---resolved, empty components kept), an absolute one is left as written, and
---a directory that exists gets a trailing separator. Measured against the
---editor, including the parts that look like bugs — an absolute path keeps its
---own slashes and only the added separator is native.
---
---`~` and a drive-relative `C:foo` are refused rather than guessed: neither is
---reached by a caller, and both have editor behaviour that differs by host.
---@param path string
---@return string
local function absolute_path(path)
  if path:sub(1, 1) == "~" then
    error('standalone vim_shim: vim.fn.fnamemodify ":p" does not expand "~"', 0)
  end
  local slashed = to_slashes(path)
  if IS_WINDOWS and slashed:match("^%a:[^/]") then
    error('standalone vim_shim: vim.fn.fnamemodify ":p" does not resolve a drive-relative path', 0)
  end

  local sep = IS_WINDOWS and "\\" or "/"
  local full
  if slashed:sub(1, 1) == "/" or (IS_WINDOWS and slashed:match("^%a:/")) then
    full = path
  else
    local parts = {}
    local cwd = to_slashes(lfs.currentdir()):gsub("/+$", "")
    for component in (slashed .. "/"):gmatch("([^/]*)/") do
      if component == ".." then
        parts[#parts] = nil
      elseif component ~= "." then
        parts[#parts + 1] = component
      end
    end
    -- A trailing separator in the input survives as an empty last component.
    full = cwd:gsub("/", sep) .. sep .. table.concat(parts, sep)
    if path == "" then
      full = cwd:gsub("/", sep)
    end
  end

  if lfs.attributes(full, "mode") == "directory" and not full:match("[/\\]$") then
    full = full .. sep
  end
  return full
end

---The `":t"` (tail/basename) and `":p"` (absolute) modifiers — the only ones
---a real call site passes.
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
  elseif mods == ":p" then
    return absolute_path(path)
  end
  error(
    'standalone vim_shim: vim.fn.fnamemodify only implements ":t" and ":p", got ' .. tostring(mods),
    0
  )
end

---The exit status of the last `vim.fn.system`, as in the editor.
vim.v = { shell_error = 0 }

---Run a command and return what it printed, **stderr merged into stdout** as
---the editor's `system()` does with its default `shellredir`. `cmd` is an
---argument list or a string; the list is quoted by `standalone.shell_quote`,
---which refuses what it cannot quote safely rather than quoting it wrongly.
---Sets `vim.v.shell_error`.
---
---**Needs an interpreter whose `file:close()` reports the exit status.** PUC
---Lua 5.2+ does (`true|nil, "exit", code` — measured on 5.4: 128 for a failed
---`git rev-parse`); LuaJIT and 5.1 return a bare `true` for a failure too, so
---there this raises instead of reporting a status it cannot know.
---@param cmd string|string[]
---@param input string|nil Not supported.
---@return string output
function vim.fn.system(cmd, input)
  if input ~= nil then
    error("standalone vim_shim: vim.fn.system does not implement the stdin argument", 0)
  end
  local quote = require("standalone.shell_quote").quote
  local line
  if type(cmd) == "table" then
    local parts = {}
    for i, arg_ in ipairs(cmd) do
      local quoted, err = quote(arg_, IS_WINDOWS)
      if not quoted then
        error("standalone vim_shim: vim.fn.system: " .. err, 0)
      end
      parts[i] = quoted
    end
    line = table.concat(parts, " ")
  else
    line = tostring(cmd)
  end

  -- `cmd /c` strips the first and last quote of a line that starts with one
  -- and holds more of them, which would eat the quoting of `"git" "-C" ...`
  -- and leave `git" "-C" "...` — so on Windows the whole line gets one more
  -- pair, which is the pair `cmd` removes.
  local full = line .. " 2>&1"
  if IS_WINDOWS then
    full = '"' .. full .. '"'
  end
  local fh = io.popen(full, "r")
  if not fh then
    error("standalone vim_shim: vim.fn.system could not start: " .. line, 0)
  end
  local out = fh:read("*a") or ""
  local ok, how, code = fh:close()
  if how == nil then
    error(
      "standalone vim_shim: vim.fn.system cannot see the exit status on this Lua ("
        .. _VERSION
        .. ")",
      0
    )
  end
  vim.v.shell_error = (ok == true) and 0 or (code or 1)
  return out
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

---The last component, as Neovim 0.12 defines it: empty for a path that ends in
---a separator, and on Windows empty for a bare drive (`C:`, `C:/`).
---@param file string|nil
---@return string|nil
function vim.fs.basename(file)
  if file == nil then
    return nil
  end
  if type(file) ~= "string" then
    error("file: expected string, got " .. type(file), 2)
  end
  if IS_WINDOWS then
    file = to_slashes(file)
    if file:match("^%w:/?$") then
      return ""
    end
  end
  return file:match("/$") and "" or file:match("[^/]*$")
end

---Windows prefix and body of a path, as `vim.fs` splits it: `C:/foo` ->
---`C:`, `/foo`; `//server/share/foo` -> `//server/share`, `/foo`. Ported from
---Neovim 0.12's `runtime/lua/vim/fs.lua`, not reinvented — normalising a path
---is exactly the place where a plausible rule and the real one diverge on the
---edges (UNC, device paths, a drive with no slash).
---@param path string
---@return string prefix
---@return string body
---@return boolean valid
local function split_windows_path(path)
  local prefix = ""

  local function match_to_prefix(pattern)
    local match = path:match(pattern)
    if match then
      prefix = prefix .. match
      path = path:sub(#match + 1)
    end
    return match
  end

  local function process_unc_path()
    return match_to_prefix("[^/]+/+[^/]+/+")
  end

  if match_to_prefix("^//[?.]/") then
    local device = match_to_prefix("[^/]+/+")
    if not device or (device:match("^UNC/+$") and not process_unc_path()) then
      return prefix, path, false
    end
  elseif match_to_prefix("^//") then
    if not process_unc_path() then
      return prefix, path, false
    end
  elseif path:match("^%w:") then
    prefix, path = path:sub(1, 2), path:sub(3)
  end

  local trailing_slash = prefix:match("/+$")
  if trailing_slash then
    prefix = prefix:sub(1, -1 - #trailing_slash)
    path = trailing_slash .. path
  end

  return prefix, path, true
end

---Resolve `.` and `..` in a `/`-separated path and drop empty components.
---`..` that would climb above a relative start is kept.
---@param path string
---@return string
local function path_resolve_dot(path)
  local is_absolute = path:sub(1, 1) == "/"
  local out = {}
  for component in (path .. "/"):gmatch("([^/]*)/") do
    if component == "." or component == "" then -- luacheck: ignore 542
      -- skipped
    elseif component == ".." then
      if #out > 0 and out[#out] ~= ".." then
        out[#out] = nil
      elseif is_absolute then -- luacheck: ignore 542
        -- at the root: nothing to climb
      else
        out[#out + 1] = component
      end
    else
      out[#out + 1] = component
    end
  end
  return (is_absolute and "/" or "") .. table.concat(out, "/")
end

---Normalise a path: `~` and `$VAR` expanded, `\` folded to `/` on Windows,
---`.`/`..` resolved, a double slash at the start preserved. Ported from
---Neovim 0.12; see `split_windows_path` for why.
---@param path string
---@param opts { expand_env?: boolean, win?: boolean }|nil
---@return string
function vim.fs.normalize(path, opts)
  opts = opts or {}
  if type(path) ~= "string" then
    error("path: expected string, got " .. type(path), 2)
  end

  local win = opts.win
  if win == nil then
    win = IS_WINDOWS
  end
  local sep = win and "\\" or "/"

  if path == "" then
    return ""
  end

  if path:sub(1, 1) == "~" then
    local home = vim.uv.os_homedir() or "~"
    if home:sub(-1) == sep then
      home = home:sub(1, -2)
    end
    path = home .. path:sub(2)
  end

  if opts.expand_env == nil or opts.expand_env then
    path = path:gsub("%$([%w_]+)", vim.uv.os_getenv)
  end

  if win then
    path = path:gsub("\\", "/")
  end

  local double_slash = path:sub(1, 2) == "//" and path:sub(1, 3) ~= "///"

  local prefix = ""
  if win then
    local valid
    prefix, path, valid = split_windows_path(path)
    if not valid then
      return prefix .. path
    end
    prefix = prefix:gsub("^%a:", string.upper):gsub("/+", "/")
  end

  path = path_resolve_dot(path)
  path = (double_slash and "/" or "") .. prefix .. path
  if path == "" then
    path = "."
  end
  return path
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
  -- Asked first rather than inferred from `lfs.dir` raising: LuaFileSystem
  -- 1.8 raises on a directory it cannot open, 1.9 hands back an iterator that
  -- fails on first use. A shim whose answer depends on which rock is
  -- installed is the failure class the differential exists for, and it was
  -- found by it.
  if lfs.attributes(dir, "mode") ~= "directory" then
    return nil
  end
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

---@param name string
---@return string|nil
function uv.os_getenv(name)
  return os.getenv(name)
end

---libuv's own order: `USERPROFILE` on Windows, `HOME` elsewhere. libuv falls
---back to the password database when the variable is unset; this does not,
---and answers `nil` instead, which the callers here treat as "unknown".
---@return string|nil
function uv.os_homedir()
  local home = os.getenv(IS_WINDOWS and "USERPROFILE" or "HOME")
  if home == nil or home == "" then
    return nil
  end
  return home
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
