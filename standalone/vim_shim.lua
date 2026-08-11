---@module 'standalone.vim_shim'
--- A closed-scope polyfill of the small `vim.*` surface documentation.nvim's
--- `core/*.lua` pipeline (and the two `lib.nvim.fs.*` helpers it calls into,
--- `read`/`collect_recursive`) actually touches during a **parser-less**
--- scan/check/render pass — see `docs/ROADMAP/PORTABILITY.md` and
--- `docs/ROADMAP/FEATURES.md`'s "standalone CLI, MVP" entry for how this list
--- was derived (grep against every real `vim.*` call site under `core/`,
--- doc-comment mentions excluded).
---
--- NOT a general-purpose Neovim polyfill — it implements exactly the
--- following, nothing more, and is expected to grow only when a new `core/`
--- call site needs it (checked, not guessed):
---
---   vim.trim, vim.split, vim.tbl_map, vim.tbl_extend, vim.tbl_deep_extend,
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

-- ---------------------------------------------------------------- stdlib

---@param s string
---@return string
function vim.trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

---Plain (non-pattern) split — every real call site under `core/` splits on
---a literal separator (`"\n"`) with `plain = true`, so that is all this
---implements; a Lua-pattern separator is deliberately not supported.
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
    local start_idx, end_idx = s:find(sep, pos, true)
    if not start_idx then
      out[#out + 1] = s:sub(pos)
      break
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

---@param behavior "force"|"keep"|"error"
---@param ... table
---@return table
function vim.tbl_extend(behavior, ...)
  local out = {}
  for _, t in ipairs({ ... }) do
    for k, v in pairs(t) do
      if out[k] == nil or behavior == "force" then
        out[k] = v
      elseif behavior == "error" and out[k] ~= nil then
        error("tbl_extend: key already exists: " .. tostring(k))
      end
    end
  end
  return out
end

---@param behavior "force"|"keep"|"error"
---@param ... table
---@return table
function vim.tbl_deep_extend(behavior, ...)
  local function merge(dst, src)
    for k, v in pairs(src) do
      if type(v) == "table" and type(dst[k]) == "table" then
        merge(dst[k], v)
      elseif dst[k] == nil or behavior == "force" then
        dst[k] = v
      elseif behavior == "error" and dst[k] ~= nil then
        error("tbl_deep_extend: key already exists: " .. tostring(k))
      end
    end
  end
  local out = {}
  for _, t in ipairs({ ... }) do
    merge(out, t)
  end
  return out
end

---@param dst table
---@param src table
---@return table dst
function vim.list_extend(dst, src)
  for _, v in ipairs(src) do
    dst[#dst + 1] = v
  end
  return dst
end

---@param v any
---@return any
function vim.deepcopy(v)
  if type(v) ~= "table" then
    return v
  end
  local out = {}
  for k, val in pairs(v) do
    out[vim.deepcopy(k)] = vim.deepcopy(val)
  end
  return out
end

-- ------------------------------------------------------------------ json

vim.NIL = dkjson.null or setmetatable({}, {
  __tostring = function()
    return "null"
  end,
})

vim.json = {}

---@param value any
---@return string
function vim.json.encode(value)
  -- dkjson.encode on a bare scalar (what core/json.lua's own M.encode ever
  -- delegates here — see that module's header) already produces the same
  -- shape vim.json.encode does: numbers as-is, correctly quoted/escaped
  -- strings, true/false/null.
  return (dkjson.encode(value))
end

---@param s string
---@param opts { luanil?: { object?: boolean, array?: boolean } }|nil
---@return any
function vim.json.decode(s, opts)
  opts = opts or {}
  local obj, _, err = dkjson.decode(s, 1, opts.luanil and opts.luanil.object and vim.NIL or nil)
  if err then
    error(err, 0)
  end
  return obj
end

-- -------------------------------------------------------------------- fs

vim.fn = {}

---@param path string
---@return integer 1 if `path` is a directory, 0 otherwise
function vim.fn.isdirectory(path)
  return lfs.attributes(path, "mode") == "directory" and 1 or 0
end

---Only the `":t"` (tail/basename) modifier — the one real call site
---(`documentation.config`'s own `title` default) never uses another.
---@param path string
---@param mods string
---@return string
function vim.fn.fnamemodify(path, mods)
  if mods == ":t" then
    return (path:gsub("[/\\]+$", ""):match("[^/\\]+$")) or path
  end
  error('standalone vim_shim: vim.fn.fnamemodify only implements ":t", got ' .. tostring(mods), 0)
end

vim.fs = {}

---@param path string
---@return string
function vim.fs.dirname(path)
  local parent = path:match("^(.*)[/\\][^/\\]+[/\\]?$")
  return parent or "."
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
---@return boolean ok
function uv.fs_mkdir(path, _mode)
  -- `lfs.mkdir` has no mode parameter (POSIX permission bits are not a
  -- concern for a docs artifact directory); `lib.nvim.fs.mkdirp` treats a
  -- false return the same as EEXIST would (checks fs_stat next), so the
  -- "already exists" case does not need distinguishing here either.
  local ok = lfs.mkdir(path)
  return ok == true
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
