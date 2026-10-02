-- TESTS/fixtures/shim_behavior_cases.lua — the differential corpus: one set
-- of inputs, run against two implementations of the same surface.
--
-- **Why this file has no `require` in it.** `TESTS/shim_contract_spec.lua`
-- answers what `core/` *calls*; a shim function that exists and behaves
-- differently is invisible to it. Answering behaviour needs the same inputs
-- pushed through both `vim.*` and `standalone/vim_shim.lua` with the outputs
-- compared — and the two runners that do it live in different worlds:
--
--   * `TESTS/shim_behavior_spec.lua` runs inside Neovim, where the real
--     `vim.*` is the oracle and the shim is the candidate. It needs neither
--     PUC Lua nor a rock, so it runs in the always-green `tests` gate —
--     which is the point, because the `standalone` gate skips on most
--     machines and three defects have already walked through that gap.
--   * `standalone/selfcheck_behavior.lua` runs under PUC Lua with the real
--     `lfs` and `dkjson`, and answers the part the first runner cannot:
--     dkjson's own output, a real `lfs`, and Lua 5.4 rather than LuaJIT.
--     It compares against expectations `scripts/ci.lua` writes out of the
--     running Neovim moments earlier — never a committed golden file, which
--     would only rot against the next Neovim version.
--
-- So this file must load under LuaJIT and under PUC Lua 5.4, and must not
-- touch `vim`, `lfs` or `dkjson`. It is data plus the two pure functions
-- both runners need: `canon` (a host-independent rendering of a value) and
-- `evaluate` (run one case against one surface).
--
-- **Adding a case is the cheap part and the point.** A new `vim.*` function
-- in the shim without a case here is a function nobody has compared.

local M = {}

local unpack_ = table.unpack or unpack

-- ---------------------------------------------------------------------
-- Canonical rendering.
--
-- Two implementations agree when their outputs render identically. What
-- "identically" may not depend on is the host, so every step below is
-- pinned rather than delegated:
--
--   * numbers are formatted here, not by `tostring` — LuaJIT renders an
--     integral float as `100` and PUC 5.3+ as `100.0`, which is a real
--     difference this project has already paid for once (`core/json.lua`),
--     but it is *that* gate's finding, already asserted by the standalone
--     artifact check. Letting it surface here too would paint every
--     numeric case red for a reason that has nothing to do with the shim.
--   * strings are escaped here, not by `%q` — 5.1 writes a newline as a
--     backslash followed by a real newline, 5.4 as `\n`.
--   * table keys are sorted, because `pairs` order is not a promise.
--   * repeated tables render as `ref#N`, so both sharing and cycles are
--     visible: `vim.deepcopy` preserves them and a naive copy does not,
--     and the difference is invisible to any renderer that silently
--     re-expands the second visit (or hangs on it).
-- ---------------------------------------------------------------------

---@param n number
---@return string
local function fmt_number(n)
  if n ~= n then
    return "nan"
  elseif n == math.huge then
    return "inf"
  elseif n == -math.huge then
    return "-inf"
  elseif n % 1 == 0 and n < 2 ^ 53 and n > -(2 ^ 53) then
    return string.format("%d", n)
  end
  return string.format("%.14g", n)
end

---@param s string
---@return string
local function fmt_string(s)
  local body = s:gsub('[%c"\\]', function(c)
    return string.format("\\%03d", c:byte())
  end)
  return '"' .. body .. '"'
end

local KEY_RANK = { number = 1, string = 2, boolean = 3 }

---Deterministic key order. Table keys are deliberately not supported: their
---only orderable rendering is an address, which is exactly the kind of
---host-dependence this whole file exists to keep out. No case uses one.
---@param a any
---@param b any
---@return boolean
local function key_lt(a, b)
  local ra, rb = KEY_RANK[type(a)] or 9, KEY_RANK[type(b)] or 9
  if ra ~= rb then
    return ra < rb
  elseif ra == 1 or ra == 2 then
    return a < b
  end
  return tostring(a) < tostring(b)
end

---@param v any
---@param seen table<table, integer>|nil
---@param state { n: integer }|nil
---@return string
function M.canon(v, seen, state)
  seen = seen or {}
  state = state or { n = 0 }
  local t = type(v)
  if v == nil then
    return "nil"
  elseif t == "boolean" then
    return tostring(v)
  elseif t == "number" then
    return fmt_number(v)
  elseif t == "string" then
    return fmt_string(v)
  elseif t ~= "table" then
    -- Functions and userdata have no stable rendering, and no case compares
    -- one: the label says which kind so a mismatch is still readable.
    return "<" .. t .. ">"
  end

  if seen[v] then
    return "ref#" .. seen[v]
  end
  state.n = state.n + 1
  seen[v] = state.n

  local keys = {}
  for k in pairs(v) do
    keys[#keys + 1] = k
  end
  table.sort(keys, key_lt)

  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = M.canon(k, seen, state) .. "=" .. M.canon(v[k], seen, state)
  end
  local out = "{" .. table.concat(parts, ",") .. "}"
  -- Presence only, not identity: `vim.deepcopy` keeps the original
  -- metatable and a plain copy keeps none, which is the difference worth
  -- seeing. Comparing identity would need both sides to share the input
  -- table, which they do not.
  if getmetatable(v) ~= nil then
    out = out .. "+mt"
  end
  return out
end

-- ---------------------------------------------------------------------
-- Running one case against one surface.
--
-- A "surface" is any table shaped like `vim`: the real one under Neovim, or
-- whatever `standalone/vim_shim.lua` returns. Nothing below knows which it
-- has, which is what keeps this a comparison rather than two test suites.
-- ---------------------------------------------------------------------

---@param surface table
---@param path string Dotted, without the leading `vim.` — e.g. `fn.stdpath`.
---@return any
local function resolve(surface, path)
  local cur = surface
  for part in path:gmatch("[^.]+") do
    if type(cur) ~= "table" then
      return nil
    end
    cur = cur[part]
    if cur == nil then
      return nil
    end
  end
  return cur
end

---Substitute the fixture root into an argument.
---
---`<ROOT>` rather than a sentinel table, so the corpus stays plain data that
---serialises and reads the same in both runners.
---
---**Strings only, deliberately.** An earlier version walked tables too, and
---the `deepcopy/cycle` case sent it into a stack overflow before either
---implementation had been called once — the substitution needs exactly the
---cycle handling the thing under test is being asked about. No case puts
---`<ROOT>` inside a table, and the header of each fs case says so by using
---a bare string.
---@param v any
---@param root string
---@return any
local function subst(v, root)
  if type(v) == "string" then
    return (v:gsub("<ROOT>", root))
  end
  return v
end

---@param case table
---@param root string
---@return any[] args
---@return integer n
local function case_args(case, root)
  local args = {}
  -- `argc` for the cases where the *arity* is the question: `f(nil)` and
  -- `f()` are two different calls at the C boundary, and `vim.json.encode`
  -- answers `null` to the first and raises on the second. A table literal
  -- cannot express that difference — `{ nil }` has a length of zero.
  local n = case.argc or (case.args and #case.args or 0)
  for i = 1, n do
    args[i] = subst(case.args[i], root)
  end
  return args, n
end

---Run one case and render the result.
---
---Errors render as the bare word `error`, never the message: Neovim's own
---messages carry a `vim/_core/shared.lua:602:` prefix that changes with the
---version, so comparing them would pin this corpus to one Neovim build. The
---message comes back as the second return value instead, and both runners
---print it when a case mismatches — which is when it is actually useful.
---@param surface table
---@param case table
---@param root string Directory `<ROOT>` expands to.
---@return string canon
---@return string|nil detail
function M.evaluate(surface, case, root)
  local kind = case.kind or "call"
  local fn = resolve(surface, case.path)
  if fn == nil then
    return "missing"
  end

  if kind == "call" then
    local args, n = case_args(case, root)
    local ok, result = pcall(function()
      return fn(unpack_(args, 1, n))
    end)
    if not ok then
      return "error", tostring(result)
    end
    if case.normalize == "slashes" then
      if type(result) == "string" then
        result = (result:gsub("\\", "/"))
      elseif type(result) == "table" then
        -- A list of paths (`glob`): the separators of each, not the table.
        local folded = {}
        for i, v in ipairs(result) do
          folded[i] = type(v) == "string" and (v:gsub("\\", "/")) or v
        end
        result = folded
      end
    end
    if case.sort and type(result) == "table" then
      -- For answers whose *order* the editor does not promise: it sorts file
      -- names with the platform's comparison (case-insensitive on Windows,
      -- byte order on Linux), so two correct implementations can differ.
      table.sort(result)
    end
    return M.canon(result)
  elseif kind == "value" then
    -- Not a call: the thing at `path` *is* the answer (`vim.log.levels`).
    return M.canon(fn)
  elseif kind == "system" then
    -- What matters about a command is what it printed first and how it ended,
    -- and the exit status lives in `vim.v.shell_error`, not in a return value.
    -- Only the first word of the output: the rest is the tool's wording.
    local args = case_args(case, root)
    local ok, out = pcall(fn, args[1])
    if not ok then
      return "error", tostring(out)
    end
    local status = resolve(surface, "v.shell_error")
    return M.canon({
      status = status,
      first_word = type(out) == "string" and out:match("^%w+") or nil,
    })
  elseif kind == "call_mutates" then
    -- The interesting value is the argument the call wrote into, not only
    -- what it returned: `vim.list_extend` returns its destination, and a
    -- candidate that returned a fresh table would otherwise pass.
    -- `case.mutates` says which argument to look at — 1 for
    -- `list_extend(dst, ...)`, 2 for `tbl_deep_extend(behavior, a, b)`,
    -- where the first argument is a string and comparing it would compare
    -- nothing at all.
    local args, n = case_args(case, root)
    local target = args[case.mutates or 1]
    local ok, result = pcall(function()
      return fn(unpack_(args, 1, n))
    end)
    if not ok then
      return "error", tostring(result)
    end
    return M.canon({ returned_target = (result == target), target = target })
  elseif kind == "dir" then
    local args = case_args(case, root)
    local ok, entries = pcall(function()
      local out = {}
      for name, ty in fn(args[1]) do
        out[#out + 1] = tostring(name) .. ":" .. tostring(ty)
      end
      return out
    end)
    if not ok then
      return "error", tostring(entries)
    end
    table.sort(entries)
    return M.canon(entries)
  elseif kind == "scandir" then
    -- Two functions, one behaviour: a handle that cannot be opened and a
    -- handle that is walked to exhaustion are the same question.
    local args = case_args(case, root)
    local next_fn = resolve(surface, case.next_path)
    if next_fn == nil then
      return "missing"
    end
    local ok, entries = pcall(function()
      local handle = fn(args[1])
      if handle == nil then
        return "nil"
      end
      local out = {}
      while true do
        local name, ty = next_fn(handle)
        if not name then
          break
        end
        out[#out + 1] = tostring(name) .. ":" .. tostring(ty)
      end
      table.sort(out)
      return out
    end)
    if not ok then
      return "error", tostring(entries)
    end
    return M.canon(entries)
  elseif kind == "stat_type" then
    -- Only `.type`: real `uv.fs_stat` returns a dozen fields (inode, mtime,
    -- size) that are facts about the disk rather than about the shim, and
    -- `lib.nvim.fs` reads exactly this one.
    local args = case_args(case, root)
    local ok, ty = pcall(function()
      local st = fn(args[1])
      return st and st.type or nil
    end)
    if not ok then
      return "error", tostring(ty)
    end
    return M.canon(ty)
  end

  -- Rendered as an answer rather than raised, so the runners can report which
  -- case is broken. Both of them treat a `missing`/`unknown-kind` answer as a
  -- corpus bug rather than as agreement — two identical `unknown-kind:` lines
  -- compare equal, and a case that agrees with itself checks nothing.
  return "unknown-kind:" .. tostring(kind)
end

-- ---------------------------------------------------------------------
-- Inputs that both sides get to answer.
--
-- Fields:
--   id          stable, sorted, and the key in the expectations file.
--   path        dotted path under `vim`.
--   kind        how to run it — see `M.evaluate`.
--   args        `<ROOT>` in any string expands to the fixture directory.
--   normalize   `"slashes"`: compare paths with `\` folded to `/` (a string,
--               or each string of a list).
--   sort        sort a list answer before comparing it: for results whose
--               order the editor leaves to the platform.
--   needs       `"puc"`: only the PUC runner answers this one (see below).
--   local_only  never written to the expectations file (env-dependent).
--   why         what the case is *for*. Not decoration: several of these
--               were red on first run, and the sentence is the finding.
-- ---------------------------------------------------------------------
M.cases = {
  -- ---------------------------------------------------------------- trim
  { id = "trim/both-ends", path = "trim", args = { "\t x \n" } },
  { id = "trim/inner-kept", path = "trim", args = { " a  b " } },
  { id = "trim/all-whitespace", path = "trim", args = { "   " } },
  { id = "trim/empty", path = "trim", args = { "" } },
  {
    id = "trim/no-whitespace",
    path = "trim",
    args = { "abc" },
    why = "the gsub-chain form returns a second value if a caller forgets the parens",
  },

  -- ---------------------------------------------------------------- pesc
  { id = "pesc/magic-set", path = "pesc", args = { "a-b.c%d[e]" } },
  {
    id = "pesc/hyphen",
    path = "pesc",
    args = { "some-path/with-dashes" },
    why = "a forgotten `-` still matches most inputs and silently mismatches these",
  },
  { id = "pesc/all-magic", path = "pesc", args = { "^$()%.[]*+-?" } },
  { id = "pesc/plain", path = "pesc", args = { "abc" } },

  -- --------------------------------------------------------------- split
  { id = "split/plain-newline", path = "split", args = { "a\nb\nc", "\n", { plain = true } } },
  { id = "split/plain-absent-sep", path = "split", args = { "abc", "|", { plain = true } } },
  { id = "split/plain-leading-sep", path = "split", args = { "/a/b", "/", { plain = true } } },
  { id = "split/plain-multichar", path = "split", args = { "a::b", "::", { plain = true } } },
  { id = "split/plain-empty-sep", path = "split", args = { "abc", "", { plain = true } } },
  {
    id = "split/trimempty-edges",
    path = "split",
    args = { "\n\na\n\nb\n\n", "\n", { plain = true, trimempty = true } },
    why = "trimempty drops empty *edges* only — an inner empty line is content",
  },
  {
    id = "split/no-opts-literal-sep",
    path = "split",
    args = { "a/b/c", "/" },
    why = "every core call site passes plain=true; a future one might not",
  },
  {
    id = "split/pattern-sep",
    path = "split",
    args = { "a.b", "." },
    why = "without opts the separator is a Lua *pattern*; a plain-only shim "
      .. "silently returns a different, plausible-looking answer",
  },
  { id = "split/pattern-quantifier", path = "split", args = { "a,,b", ",+" } },
  {
    id = "split/pattern-empty-match",
    path = "split",
    args = { "a b", "%s*" },
    why = "a pattern that matches the empty string must raise, not spin",
  },

  -- ------------------------------------------------------------- tbl_map
  { id = "tbl_map/list", path = "tbl_map", args = { "<FN:double>", { 1, 2, 3 } } },
  { id = "tbl_map/empty", path = "tbl_map", args = { "<FN:double>", {} } },

  -- ---------------------------------------------------------- tbl_extend
  {
    id = "tbl_extend/force-overwrites",
    path = "tbl_extend",
    args = { "force", { a = 1 }, { a = 2 } },
  },
  {
    id = "tbl_extend/keep-first-wins",
    path = "tbl_extend",
    args = { "keep", { a = 1 }, { a = 2, b = 3 } },
  },
  {
    id = "tbl_extend/error-on-duplicate",
    path = "tbl_extend",
    args = { "error", { a = 1 }, { a = 2 } },
  },
  {
    id = "tbl_extend/three-tables",
    path = "tbl_extend",
    args = { "force", { a = 1 }, { b = 2 }, { c = 3 } },
  },
  {
    id = "tbl_extend/single-table",
    path = "tbl_extend",
    args = { "force", { a = 1 } },
    why = "Neovim requires at least two tables and says so; a shim that "
      .. "quietly returns a copy hides the call-site mistake",
  },
  {
    id = "tbl_extend/invalid-behavior",
    path = "tbl_extend",
    args = { "forse", { a = 1 }, { a = 2 } },
    why = "a misspelled behavior silently means `keep`, so the override the "
      .. "caller wrote never happens and the old value survives looking "
      .. "deliberate",
  },
  { id = "tbl_extend/non-table-argument", path = "tbl_extend", args = { "force", { a = 1 }, "x" } },

  -- ----------------------------------------------------- tbl_deep_extend
  {
    id = "deep_extend/lists-replace",
    path = "tbl_deep_extend",
    args = { "force", { a = { 1, 2, 3 } }, { a = { 9 } } },
    why = "list values are REPLACED, not merged — merging leaves the tail of "
      .. "the longer list behind and reads as corrupted config",
  },
  {
    id = "deep_extend/maps-merge",
    path = "tbl_deep_extend",
    args = { "force", { a = { x = 1, 5 } }, { a = { y = 2 } } },
    why = "a table with any non-list key is merged, so the two rules meet here",
  },
  {
    id = "deep_extend/keep",
    path = "tbl_deep_extend",
    args = { "keep", { a = { x = 1 } }, { a = { x = 9, y = 2 } } },
  },
  {
    id = "deep_extend/empty-dst-table",
    path = "tbl_deep_extend",
    args = { "force", { a = {} }, { a = { 1 } } },
    why = "an empty table is mergeable, a non-empty list is not",
  },
  {
    id = "deep_extend/error-on-duplicate",
    path = "tbl_deep_extend",
    args = { "error", { a = 1 }, { a = 2 } },
  },
  {
    id = "deep_extend/invalid-behavior",
    path = "tbl_deep_extend",
    args = { "forse", { a = 1 }, { b = 2 } },
  },
  {
    id = "deep_extend/does-not-mutate-input",
    path = "tbl_deep_extend",
    kind = "call_mutates",
    mutates = 2,
    args = { "force", { a = { x = 1 } }, { a = { y = 2 } } },
    why = "the first argument is a source, not a destination — writing "
      .. "through it corrupts whatever the caller passed",
  },

  -- --------------------------------------------------------- list_extend
  {
    id = "list_extend/returns-dst",
    path = "list_extend",
    kind = "call_mutates",
    args = { { 1 }, { 2, 3 } },
  },
  {
    id = "list_extend/empty-src",
    path = "list_extend",
    kind = "call_mutates",
    args = { { 1 }, {} },
  },
  {
    id = "list_extend/start-finish",
    path = "list_extend",
    kind = "call_mutates",
    args = { { 1 }, { 2, 3, 4 }, 2, 3 },
    why = "the 4-argument form appends a slice; ignoring the bounds appends "
      .. "the whole list and nothing raises",
  },

  -- ------------------------------------------------------------ deepcopy
  { id = "deepcopy/scalar", path = "deepcopy", args = { 42 } },
  { id = "deepcopy/nested", path = "deepcopy", args = { { a = { b = { 1, 2 } } } } },
  {
    id = "deepcopy/shared-reference",
    path = "deepcopy",
    args = { "<FN:shared>" },
    why = "one table reachable twice must stay one table in the copy",
  },
  {
    id = "deepcopy/cycle",
    path = "deepcopy",
    args = { "<FN:cyclic>" },
    why = "a cycle without a cache is not a wrong answer, it is a stack "
      .. "overflow — and nothing in the static contract can see it",
  },
  {
    id = "deepcopy/metatable",
    path = "deepcopy",
    args = { "<FN:with_mt>" },
    why = "Neovim carries the metatable across; a plain copy drops it",
  },
  {
    id = "deepcopy/noref-true",
    path = "deepcopy",
    args = { "<FN:shared>", true },
    why = "the second argument is Neovim's `noref`: every occurrence becomes "
      .. "its own copy. A shim using that slot for something else raises "
      .. "`attempt to index a boolean` on a call the editor answers",
  },
  { id = "deepcopy/noref-false", path = "deepcopy", args = { "<FN:shared>", false } },
  {
    id = "deepcopy/noref-cycle",
    path = "deepcopy",
    args = { "<FN:cyclic>", true },
    why = "without the cache a cycle cannot terminate — the editor fails here "
      .. "too, and the shim must fail rather than answer",
  },

  -- ---------------------------------------------------------- fs.dirname
  { id = "fs.dirname/simple", path = "fs.dirname", args = { "a/b/c" } },
  { id = "fs.dirname/relative-leaf", path = "fs.dirname", args = { "abc" } },
  {
    id = "fs.dirname/trailing-slash",
    path = "fs.dirname",
    args = { "a/b/" },
    why = "the trailing slash names the directory itself; skipping past it "
      .. "returns the grandparent",
  },
  {
    id = "fs.dirname/root-child",
    path = "fs.dirname",
    args = { "/a" },
    why = "the parent of a root child is the root, not the empty string",
  },
  { id = "fs.dirname/root", path = "fs.dirname", args = { "/" } },
  { id = "fs.dirname/empty", path = "fs.dirname", args = { "" } },
  { id = "fs.dirname/windows-forward", path = "fs.dirname", args = { "C:/a/b" } },
  {
    id = "fs.dirname/drive-child",
    path = "fs.dirname",
    args = { "C:/a" },
    why = "`C:/` on Windows, where a drive root is a directory; a plain `C:` "
      .. "on Linux, where a drive letter is just a directory name",
  },
  {
    id = "fs.dirname/windows-backslash",
    path = "fs.dirname",
    args = { "C:\\a\\b" },
    why = "a backslash is a separator on Windows and an ordinary filename "
      .. "character everywhere else — so the answer is platform-dependent, "
      .. "and a shim that picks one of the two is wrong on the other host",
  },
  { id = "fs.dirname/dotdot", path = "fs.dirname", args = { "a/b/../c" } },
  { id = "fs.dirname/double-separator", path = "fs.dirname", args = { "a//b" } },
  { id = "fs.dirname/dot-prefix", path = "fs.dirname", args = { "./a" } },

  -- ---------------------------------------------------- fn.fnamemodify :t
  { id = "fn.fnamemodify/tail", path = "fn.fnamemodify", args = { "a/b/c.lua", ":t" } },
  { id = "fn.fnamemodify/no-separator", path = "fn.fnamemodify", args = { "abc", ":t" } },
  {
    id = "fn.fnamemodify/trailing-slash",
    path = "fn.fnamemodify",
    args = { "a/b/", ":t" },
    why = "the tail of a path ending in a separator is empty — stripping the "
      .. "slash first invents a name the editor never reports",
  },
  { id = "fn.fnamemodify/slash-only", path = "fn.fnamemodify", args = { "/", ":t" } },
  { id = "fn.fnamemodify/empty", path = "fn.fnamemodify", args = { "", ":t" } },
  {
    id = "fn.fnamemodify/backslash",
    path = "fn.fnamemodify",
    args = { "a\\b", ":t" },
    why = "same platform-dependent separator rule as fs.dirname, measured "
      .. "rather than assumed",
  },
  { id = "fn.fnamemodify/dotfile", path = "fn.fnamemodify", args = { "a/.config", ":t" } },

  -- ----------------------------------------------------------- filesystem
  { id = "fn.isdirectory/directory", path = "fn.isdirectory", args = { "<ROOT>" } },
  { id = "fn.isdirectory/file", path = "fn.isdirectory", args = { "<ROOT>/a.txt" } },
  { id = "fn.isdirectory/missing", path = "fn.isdirectory", args = { "<ROOT>/nope" } },
  { id = "fs.dir/fixture", path = "fs.dir", kind = "dir", args = { "<ROOT>" } },
  { id = "fs.dir/nested", path = "fs.dir", kind = "dir", args = { "<ROOT>/sub" } },
  {
    id = "fs.dir/missing",
    path = "fs.dir",
    kind = "dir",
    args = { "<ROOT>/nope" },
    why = "an unreadable directory yields nothing rather than raising — the "
      .. "scan walks directories it may not be allowed to open",
  },
  {
    id = "uv.fs_scandir/fixture",
    path = "uv.fs_scandir",
    next_path = "uv.fs_scandir_next",
    kind = "scandir",
    args = { "<ROOT>" },
  },
  {
    id = "uv.fs_scandir/missing",
    path = "uv.fs_scandir",
    next_path = "uv.fs_scandir_next",
    kind = "scandir",
    args = { "<ROOT>/nope" },
  },
  { id = "uv.fs_stat/directory", path = "uv.fs_stat", kind = "stat_type", args = { "<ROOT>/sub" } },
  { id = "uv.fs_stat/file", path = "uv.fs_stat", kind = "stat_type", args = { "<ROOT>/a.txt" } },
  { id = "uv.fs_stat/missing", path = "uv.fs_stat", kind = "stat_type", args = { "<ROOT>/nope" } },

  -- ------------------------------------------------------------- stdpath
  -- Env-dependent, so never written to the expectations file — but both
  -- runners read the *same* environment, so the comparison is still real
  -- where it happens (inside Neovim, against the editor's own answer).
  -- `normalize = "slashes"` because the shim returns forward slashes on
  -- purpose and Neovim returns native ones; every consumer in `core/`
  -- normalises before comparing, so the separator is not the finding.
  {
    id = "fn.stdpath/cache",
    path = "fn.stdpath",
    args = { "cache" },
    normalize = "slashes",
    local_only = true,
    why = "the telemetry store resolves its cache root here at module load; "
      .. "a different directory reads as 'no data' for data that is on disk",
  },
  {
    id = "fn.stdpath/data",
    path = "fn.stdpath",
    args = { "data" },
    normalize = "slashes",
    local_only = true,
  },
  {
    id = "fn.stdpath/config",
    path = "fn.stdpath",
    args = { "config" },
    normalize = "slashes",
    local_only = true,
  },
  {
    id = "fn.stdpath/state",
    path = "fn.stdpath",
    args = { "state" },
    normalize = "slashes",
    local_only = true,
  },
  {
    id = "fn.stdpath/log",
    path = "fn.stdpath",
    args = { "log" },
    normalize = "slashes",
    local_only = true,
  },

  -- ------------------------------------------- the rules.nvim engine's surface
  -- What `rules.nvim`'s `engine/` (and the predicates in its real ruleset)
  -- call, measured against that code rather than guessed — see
  -- `docs/ROADMAP/` for L10 P1. Each case below is one question the engine
  -- would otherwise answer differently here than in the editor.

  -- ---------------------------------------------------------------- islist
  { id = "islist/empty", path = "islist", args = { {} } },
  { id = "islist/list", path = "islist", args = { { 1, 2, 3 } } },
  { id = "islist/hole", path = "islist", args = { { 1, nil, 3 } } },
  { id = "islist/dict", path = "islist", args = { { a = 1 } } },
  { id = "islist/mixed", path = "islist", args = { { 1, 2, a = 3 } } },
  { id = "islist/starts-at-two", path = "islist", args = { { [2] = "x", [3] = "y" } } },
  { id = "islist/string", path = "islist", args = { "x" } },
  { id = "islist/nil", path = "islist", args = {}, argc = 1 },

  -- ---------------------------------------------------------- tbl_contains
  { id = "tbl_contains/present", path = "tbl_contains", args = { { "a", "b" }, "b" } },
  { id = "tbl_contains/absent", path = "tbl_contains", args = { { "a", "b" }, "c" } },
  { id = "tbl_contains/empty", path = "tbl_contains", args = { {}, "a" } },
  {
    id = "tbl_contains/dict-values",
    path = "tbl_contains",
    args = { { x = "a" }, "a" },
    why = "it walks values with pairs, so a dictionary answers too",
  },
  {
    id = "tbl_contains/predicate",
    path = "tbl_contains",
    args = { { 1, 2, 3 }, "<FN:is_two>", { predicate = true } },
  },
  {
    id = "tbl_contains/predicate-none",
    path = "tbl_contains",
    args = { { 1, 3 }, "<FN:is_two>", { predicate = true } },
  },
  { id = "tbl_contains/not-a-table", path = "tbl_contains", args = { "x", "x" } },

  -- ------------------------------------------------------------ fs.basename
  { id = "fs.basename/simple", path = "fs.basename", args = { "a/b/c.lua" } },
  { id = "fs.basename/no-separator", path = "fs.basename", args = { "abc" } },
  {
    id = "fs.basename/trailing-slash",
    path = "fs.basename",
    args = { "a/b/" },
    why = "the name of a path that ends in a separator is empty, not `b`",
  },
  { id = "fs.basename/root", path = "fs.basename", args = { "/" } },
  { id = "fs.basename/empty", path = "fs.basename", args = { "" } },
  {
    id = "fs.basename/bare-drive",
    path = "fs.basename",
    args = { "C:" },
    why = "empty on Windows, where it names a drive; `C:` on Linux, where it is a filename",
  },
  { id = "fs.basename/drive-root", path = "fs.basename", args = { "C:/" } },
  { id = "fs.basename/drive-child", path = "fs.basename", args = { "C:/a" } },
  { id = "fs.basename/backslash", path = "fs.basename", args = { "a\\b" } },
  { id = "fs.basename/dotfile", path = "fs.basename", args = { "a/.config" } },
  { id = "fs.basename/nil", path = "fs.basename", args = {}, argc = 1 },
  { id = "fs.basename/number", path = "fs.basename", args = { 5 } },

  -- ----------------------------------------------------------- fs.normalize
  { id = "fs.normalize/dotdot", path = "fs.normalize", args = { "a/b/../c" } },
  { id = "fs.normalize/dot-prefix", path = "fs.normalize", args = { "./a" } },
  { id = "fs.normalize/double-separator", path = "fs.normalize", args = { "a//b" } },
  { id = "fs.normalize/trailing-slash", path = "fs.normalize", args = { "a/b/" } },
  { id = "fs.normalize/only-dot", path = "fs.normalize", args = { "././" } },
  { id = "fs.normalize/empty", path = "fs.normalize", args = { "" } },
  { id = "fs.normalize/root", path = "fs.normalize", args = { "/" } },
  {
    id = "fs.normalize/above-the-root",
    path = "fs.normalize",
    args = { "/../../x" },
    why = "`..` at the root of an absolute path stays at the root",
  },
  {
    id = "fs.normalize/above-a-relative-start",
    path = "fs.normalize",
    args = { "foo/../../bar" },
    why = "a relative path that climbs out of its start keeps the `..`",
  },
  {
    id = "fs.normalize/leading-double-slash",
    path = "fs.normalize",
    args = { "//server/share/x" },
  },
  {
    id = "fs.normalize/triple-slash",
    path = "fs.normalize",
    args = { "///a" },
    why = "two leading slashes mean something, three do not",
  },
  {
    id = "fs.normalize/dollar-unset",
    path = "fs.normalize",
    args = { "$DOCMAP_SHIM_SURELY_UNSET/x" },
  },
  {
    id = "fs.normalize/no-expand-env",
    path = "fs.normalize",
    args = { "$DOCMAP_SHIM_SURELY_UNSET/x", { expand_env = false } },
  },
  -- The `win` option makes the Windows rules testable on every host.
  {
    id = "fs.normalize/win-backslashes",
    path = "fs.normalize",
    args = { "C:\\foo\\..\\bar", { win = true } },
  },
  {
    id = "fs.normalize/win-drive-case",
    path = "fs.normalize",
    args = { "c:/x/y", { win = true } },
  },
  {
    id = "fs.normalize/win-drive-relative",
    path = "fs.normalize",
    args = { "C:foo/../../baz", { win = true } },
  },
  {
    id = "fs.normalize/win-drive-root-dotdot",
    path = "fs.normalize",
    args = { "C:/foo/../../baz", { win = true } },
  },
  {
    id = "fs.normalize/win-unc",
    path = "fs.normalize",
    args = { "\\\\?\\UNC\\server\\share\\foo\\..\\..\\..\\bar", { win = true } },
  },
  {
    id = "fs.normalize/win-unc-share",
    path = "fs.normalize",
    args = { "//server/share/a/../b", { win = true } },
  },
  {
    id = "fs.normalize/posix-keeps-backslash",
    path = "fs.normalize",
    args = { "a\\b/c", { win = false } },
    why = "a backslash is a filename character off Windows, and must survive",
  },
  {
    id = "fs.normalize/home",
    path = "fs.normalize",
    args = { "~/x/../y" },
    normalize = "slashes",
    local_only = true,
    why = "the home directory is environment-dependent; compared in-editor only",
  },

  -- ----------------------------------------------------- fn.fnamemodify :p
  -- Relative inputs are resolved against the working directory, which both
  -- runners and the expectations writer share (the repository root).
  {
    id = "fn.fnamemodify.p/file",
    path = "fn.fnamemodify",
    args = { "<ROOT>/a.txt", ":p" },
    normalize = "slashes",
  },
  {
    id = "fn.fnamemodify.p/directory",
    path = "fn.fnamemodify",
    args = { "<ROOT>/sub", ":p" },
    normalize = "slashes",
    why = "an existing directory gets a trailing separator",
  },
  {
    id = "fn.fnamemodify.p/directory-with-slash",
    path = "fn.fnamemodify",
    args = { "<ROOT>/sub/", ":p" },
    normalize = "slashes",
    why = "and exactly one, not two",
  },
  {
    id = "fn.fnamemodify.p/missing",
    path = "fn.fnamemodify",
    args = { "<ROOT>/nope.lua", ":p" },
    normalize = "slashes",
  },
  {
    id = "fn.fnamemodify.p/relative-file",
    path = "fn.fnamemodify",
    args = { "TESTS/fixtures/shim_fs/a.txt", ":p" },
    normalize = "slashes",
  },
  {
    id = "fn.fnamemodify.p/relative-dotdot",
    path = "fn.fnamemodify",
    args = { "./TESTS/fixtures/../fixtures/shim_fs", ":p" },
    normalize = "slashes",
    why = "`.` and `..` in a relative path are resolved",
  },
  {
    id = "fn.fnamemodify.p/relative-missing",
    path = "fn.fnamemodify",
    args = { "nope/x.lua", ":p" },
    normalize = "slashes",
  },
  {
    id = "fn.fnamemodify.p/empty",
    path = "fn.fnamemodify",
    args = { "", ":p" },
    normalize = "slashes",
    why = "the working directory itself, with its trailing separator",
  },
  {
    id = "fn.fnamemodify.p/double-separator",
    path = "fn.fnamemodify",
    args = { "a//b", ":p" },
    normalize = "slashes",
    why = "empty components are kept, only `.` and `..` are resolved — measured",
  },

  -- ----------------------------------------------------------- fn.getcwd
  { id = "fn.getcwd/cwd", path = "fn.getcwd", args = {}, normalize = "slashes", local_only = true },

  -- ------------------------------------------------------- fn.filereadable
  { id = "fn.filereadable/file", path = "fn.filereadable", args = { "<ROOT>/a.txt" } },
  {
    id = "fn.filereadable/empty-file",
    path = "fn.filereadable",
    args = { "<ROOT>/lines/empty.txt" },
  },
  {
    id = "fn.filereadable/directory",
    path = "fn.filereadable",
    args = { "<ROOT>/sub" },
    why = "a directory exists but is not a readable *file*",
  },
  { id = "fn.filereadable/missing", path = "fn.filereadable", args = { "<ROOT>/nope" } },

  -- --------------------------------------------------------- fn.readfile
  -- The fixtures under `shim_fs/lines/` are byte-exact (`-text` in
  -- `.gitattributes`); each one is a question about line endings.
  { id = "fn.readfile/lf", path = "fn.readfile", args = { "<ROOT>/lines/lf.txt" } },
  {
    id = "fn.readfile/no-trailing-newline",
    path = "fn.readfile",
    args = { "<ROOT>/lines/no_trailing_nl.txt" },
  },
  {
    id = "fn.readfile/crlf",
    path = "fn.readfile",
    args = { "<ROOT>/lines/crlf.txt" },
    why = "a CR before an NL is dropped in text mode",
  },
  {
    id = "fn.readfile/cr-at-eof",
    path = "fn.readfile",
    args = { "<ROOT>/lines/cr_at_eof.txt" },
    why = "a CR that is not before an NL is content",
  },
  { id = "fn.readfile/mixed-eol", path = "fn.readfile", args = { "<ROOT>/lines/mixed_eol.txt" } },
  { id = "fn.readfile/empty", path = "fn.readfile", args = { "<ROOT>/lines/empty.txt" } },
  { id = "fn.readfile/only-newline", path = "fn.readfile", args = { "<ROOT>/lines/only_nl.txt" } },
  {
    id = "fn.readfile/bom",
    path = "fn.readfile",
    args = { "<ROOT>/lines/bom.txt" },
    why = "a UTF-8 byte-order mark is removed in text mode",
  },
  {
    id = "fn.readfile/blank-lines",
    path = "fn.readfile",
    args = { "<ROOT>/lines/blank_lines.txt" },
  },
  { id = "fn.readfile/utf8", path = "fn.readfile", args = { "<ROOT>/lines/utf8.txt" } },
  {
    id = "fn.readfile/binary-lf",
    path = "fn.readfile",
    args = { "<ROOT>/lines/lf.txt", "b" },
    why = "binary mode keeps the empty last element a trailing NL implies",
  },
  { id = "fn.readfile/binary-crlf", path = "fn.readfile", args = { "<ROOT>/lines/crlf.txt", "b" } },
  { id = "fn.readfile/binary-bom", path = "fn.readfile", args = { "<ROOT>/lines/bom.txt", "b" } },
  {
    id = "fn.readfile/binary-empty",
    path = "fn.readfile",
    args = { "<ROOT>/lines/empty.txt", "b" },
  },
  {
    id = "fn.readfile/binary-no-trailing-newline",
    path = "fn.readfile",
    args = { "<ROOT>/lines/no_trailing_nl.txt", "b" },
  },
  {
    id = "fn.readfile/max-first",
    path = "fn.readfile",
    args = { "<ROOT>/lines/blank_lines.txt", "", 2 },
  },
  {
    id = "fn.readfile/max-last",
    path = "fn.readfile",
    args = { "<ROOT>/lines/blank_lines.txt", "", -2 },
  },
  { id = "fn.readfile/max-zero", path = "fn.readfile", args = { "<ROOT>/lines/lf.txt", "", 0 } },
  {
    id = "fn.readfile/max-too-many",
    path = "fn.readfile",
    args = { "<ROOT>/lines/lf.txt", "", 99 },
  },
  {
    id = "fn.readfile/missing",
    path = "fn.readfile",
    args = { "<ROOT>/nope.txt" },
    why = "an unreadable file raises (E484) — callers wrap it, and a quiet empty "
      .. "list would read as an empty ruleset",
  },
  { id = "fn.readfile/directory", path = "fn.readfile", args = { "<ROOT>/sub" } },

  -- -------------------------------------------------------------- fn.glob
  -- `sort`: the editor orders names with the platform's comparison.
  {
    id = "fn.glob/star",
    path = "fn.glob",
    args = { "<ROOT>/*.txt", false, true },
    normalize = "slashes",
    sort = true,
  },
  {
    id = "fn.glob/star-all",
    path = "fn.glob",
    args = { "<ROOT>/*", false, true },
    normalize = "slashes",
    sort = true,
    why = "matches files and directories alike",
  },
  {
    id = "fn.glob/double-star",
    path = "fn.glob",
    args = { "<ROOT>/**/*.txt", false, true },
    normalize = "slashes",
    sort = true,
    why = "`**` is any number of directory levels, including none",
  },
  {
    id = "fn.glob/double-star-last",
    path = "fn.glob",
    args = { "<ROOT>/**", false, true },
    normalize = "slashes",
    sort = true,
    why = "lists everything below, not the root itself",
  },
  {
    id = "fn.glob/one-level",
    path = "fn.glob",
    args = { "<ROOT>/*/*.txt", false, true },
    normalize = "slashes",
    sort = true,
  },
  {
    id = "fn.glob/double-star-then-name",
    path = "fn.glob",
    args = { "<ROOT>/sub/**/c.txt", false, true },
    normalize = "slashes",
    sort = true,
  },
  {
    id = "fn.glob/double-star-from-root",
    path = "fn.glob",
    args = { "<ROOT>/**/c.txt", false, true },
    normalize = "slashes",
    sort = true,
  },
  { id = "fn.glob/no-match", path = "fn.glob", args = { "<ROOT>/nomatch*", false, true } },
  {
    id = "fn.glob/literal-present",
    path = "fn.glob",
    args = { "<ROOT>/a.txt", false, true },
    normalize = "slashes",
  },
  { id = "fn.glob/literal-absent", path = "fn.glob", args = { "<ROOT>/zzz.txt", false, true } },
  {
    id = "fn.glob/question-mark",
    path = "fn.glob",
    args = { "<ROOT>/s?b/*.txt", false, true },
    normalize = "slashes",
    sort = true,
  },
  {
    id = "fn.glob/class",
    path = "fn.glob",
    args = { "<ROOT>/[as]*", false, true },
    normalize = "slashes",
    sort = true,
  },
  {
    id = "fn.glob/skips-dotfiles",
    path = "fn.glob",
    args = { "<ROOT>/sub/*", false, true },
    normalize = "slashes",
    sort = true,
    why = "`*` does not match a name that starts with a dot",
  },
  {
    id = "fn.glob/double-star-skips-dotfiles",
    path = "fn.glob",
    args = { "<ROOT>/sub/**/*.txt", false, true },
    normalize = "slashes",
    sort = true,
  },
  {
    id = "fn.glob/case-of-the-pattern",
    path = "fn.glob",
    args = { "<ROOT>/*.TXT", false, true },
    normalize = "slashes",
    sort = true,
    why = "case-insensitive on Windows and macOS, where the filesystem is; exact on Linux",
  },
  {
    id = "fn.glob/string-form",
    path = "fn.glob",
    args = { "<ROOT>/a.txt" },
    normalize = "slashes",
    why = "without `list` the answer is one newline-joined string",
  },
  -- --------------------------------------------------------------- log
  {
    id = "log.levels/values",
    path = "log.levels",
    kind = "value",
    why = "a lib.nvim module reads vim.log.levels.INFO at load time; a missing "
      .. "or renumbered level fails the whole standalone build, or worse, "
      .. "filters notifications at the wrong severity",
  },

  -- ------------------------------------------------------------- uv.os_*
  { id = "uv.os_getenv/unset", path = "uv.os_getenv", args = { "DOCMAP_SHIM_SURELY_UNSET" } },
  {
    id = "uv.os_homedir/home",
    path = "uv.os_homedir",
    args = {},
    normalize = "slashes",
    local_only = true,
  },

  -- ------------------------------------------------------------ fn.system
  -- `needs = "puc"`: the exit status is only visible on a Lua whose
  -- `file:close()` reports it (PUC 5.2+). LuaJIT cannot tell success from
  -- failure there, so the shim refuses to run under it.
  {
    id = "fn.system/git-version",
    path = "fn.system",
    kind = "system",
    args = { { "git", "--version" } },
    needs = "puc",
  },
  {
    id = "fn.system/git-failure",
    path = "fn.system",
    kind = "system",
    args = { { "git", "rev-parse", "--verify", "no-such-ref-xyzzy" } },
    needs = "puc",
    why = "stderr is merged into the output and the status is non-zero",
  },

  -- -------------------------------------------------------- json, encode
  -- Compared everywhere, because the shim writes scalars itself rather than
  -- handing them to dkjson — and scalars are the whole of what
  -- `core/json.lua` ever delegates, so they are exactly what ends up in the
  -- byte-compared artifact.
  --
  -- Containers are deliberately absent. Neovim gives no ordering guarantee
  -- for object keys, so "the same output" is not something either side can
  -- promise, and a case asserting it would be asserting luck.
  { id = "json.encode/string-plain", path = "json.encode", args = { "abc" } },
  { id = "json.encode/string-quote", path = "json.encode", args = { 'a"b' } },
  { id = "json.encode/string-backslash", path = "json.encode", args = { "a\\b" } },
  { id = "json.encode/string-newline", path = "json.encode", args = { "a\nb" } },
  { id = "json.encode/string-tab", path = "json.encode", args = { "a\tb" } },
  {
    id = "json.encode/string-control",
    path = "json.encode",
    args = { "a\31b" },
    why = "a control byte with no short escape becomes \\u001f — lower-case hex",
  },
  { id = "json.encode/string-nul", path = "json.encode", args = { "a\0b" } },
  { id = "json.encode/string-del", path = "json.encode", args = { "a\127b" } },
  {
    id = "json.encode/string-slash",
    path = "json.encode",
    args = { "a/b" },
    why = "`/` is legal unescaped and Neovim leaves it alone; escaping it is "
      .. "valid JSON and different bytes",
  },
  {
    id = "json.encode/string-utf8",
    path = "json.encode",
    args = { "a\195\164b" },
    why = "a docstring with an umlaut: escaped to \\u00e4 by one encoder and "
      .. "passed through by the other is a byte-different artifact, which "
      .. "reads as 'the map is stale'",
  },
  { id = "json.encode/string-emoji", path = "json.encode", args = { "\240\159\154\128" } },
  {
    id = "json.encode/escape-slash-opt",
    path = "json.encode",
    args = { "a/b", { escape_slash = true } },
    why = "the one option that changes the bytes; accepting the argument and "
      .. "ignoring it is how a shim quietly disagrees with the editor",
  },
  {
    id = "json.encode/escape-slash-off",
    path = "json.encode",
    args = { "a/b", { escape_slash = false } },
  },
  { id = "json.encode/number-integral-float", path = "json.encode", args = { 100.0 } },
  { id = "json.encode/number-zero", path = "json.encode", args = { 0 } },
  { id = "json.encode/number-negative", path = "json.encode", args = { -1 } },
  { id = "json.encode/number-fraction", path = "json.encode", args = { 45.05 } },
  { id = "json.encode/number-half", path = "json.encode", args = { -0.5 } },
  {
    id = "json.encode/number-repeating",
    path = "json.encode",
    args = { 1 / 3 },
    why = "the shortest representation that reads back as the same double is "
      .. "16 digits here; a plain %.14g truncates and loses the value",
  },
  {
    id = "json.encode/number-2pow53",
    path = "json.encode",
    args = { 2 ^ 53 },
    why = "integral and huge: written as an integer, not in exponent form",
  },
  {
    id = "json.encode/number-1e20",
    path = "json.encode",
    args = { 1e20 },
    why = "integral but past the integer rule, so exponent form after all",
  },
  { id = "json.encode/number-tiny", path = "json.encode", args = { 1e-07 } },
  { id = "json.encode/boolean-true", path = "json.encode", args = { true } },
  { id = "json.encode/boolean-false", path = "json.encode", args = { false } },
  { id = "json.encode/nil", path = "json.encode", args = {}, argc = 1 },
  {
    id = "json.encode/no-argument",
    path = "json.encode",
    args = {},
    argc = 0,
    why = "encode(nil) is `null` and encode() is an error — the same corpus "
      .. "entry cannot express both, so the arity is written out",
  },
  {
    id = "json.encode/nan",
    path = "json.encode",
    args = { 0 / 0 },
    why = "not representable in JSON — raising is the answer, a quiet `nan` "
      .. "token in an artifact is not",
  },

  -- -------------------------------------------------------- json, decode
  -- `needs = "puc"` because decoding is still dkjson's, and under Neovim the
  -- shim's `dkjson` is refused rather than faked: a fake forwarding to
  -- `vim.json` would compare `vim.json.decode` with itself and call it
  -- agreement. This is the part of the blind spot that genuinely stays
  -- behind the standalone gate, stated rather than papered over.
  --
  -- No case decodes a null *without* `luanil`: Neovim's `vim.NIL` is
  -- userdata and the shim's is a table, so the two sentinels can never
  -- render alike. Every real call site in this tree passes `luanil`, and
  -- `standalone/vim_shim.lua` says so where `vim.NIL` is defined.
  { id = "json.decode/object", path = "json.decode", args = { '{"a":1,"b":"x"}' }, needs = "puc" },
  { id = "json.decode/array", path = "json.decode", args = { "[1,2,3]" }, needs = "puc" },
  {
    id = "json.decode/nested",
    path = "json.decode",
    args = { '{"a":{"b":[1,2]}}' },
    needs = "puc",
  },
  { id = "json.decode/number", path = "json.decode", args = { "42" }, needs = "puc" },
  {
    id = "json.decode/string-escapes",
    path = "json.decode",
    args = { '"a\\nb\\u001f"' },
    needs = "puc",
  },
  {
    id = "json.decode/luanil-object",
    path = "json.decode",
    args = { '{"a":null,"b":1}', { luanil = { object = true, array = true } } },
    needs = "puc",
    why = "with luanil the null key is absent — the old shim asked dkjson "
      .. "for a sentinel in exactly this case, which is backwards",
  },
  {
    id = "json.decode/luanil-array",
    path = "json.decode",
    args = { '{"a":[1,null,3]}', { luanil = { object = true, array = true } } },
    needs = "puc",
    why = "a null inside an array leaves a hole; it does not shorten the list",
  },
  {
    id = "json.decode/malformed",
    path = "json.decode",
    args = { "{oops" },
    needs = "puc",
    why = "malformed input must raise, not return nil and let the caller "
      .. "carry on with an empty table",
  },
}

-- ---------------------------------------------------------------------
-- The handful of non-scalar inputs, built here rather than written inline:
-- a cycle and a shared reference cannot be expressed as a literal, and a
-- function has no literal form the corpus could carry.
-- ---------------------------------------------------------------------
local BUILDERS = {
  double = function()
    return function(v)
      return v * 2
    end
  end,
  is_two = function()
    return function(v)
      return v == 2
    end
  end,
  shared = function()
    local shared = { tag = "shared" }
    return { a = shared, b = shared }
  end,
  cyclic = function()
    local t = { tag = "cyclic" }
    t.self = t
    return t
  end,
  with_mt = function()
    return setmetatable({ 1, 2 }, { __index = function() end })
  end,
}

---A fresh copy of a table argument, so nothing under test can write through
---to the corpus. No cycle handling and none needed: the two cyclic inputs
---come from `BUILDERS`, which already returns a new object every call.
---@param v any
---@return any
local function fresh(v)
  if type(v) ~= "table" then
    return v
  end
  local out = {}
  for k, val in pairs(v) do
    out[k] = fresh(val)
  end
  return setmetatable(out, getmetatable(v))
end

---Expand the `<FN:name>` placeholders in a case's arguments, and copy the
---literal ones.
---
---Called by each runner for every case, so both sides get a *fresh* object.
---Sharing them would be a silent hole exactly where the corpus is asking
---the sharpest question: `deep_extend/does-not-mutate-input` compares two
---implementations, and an implementation that writes through its first
---argument would have corrupted the other side's input before it ran.
---@param case table
---@return table case A shallow copy of the case, with fresh arguments.
function M.materialize(case)
  if not case.args then
    return case
  end
  local args = {}
  for i = 1, #case.args do
    local v = case.args[i]
    local name = type(v) == "string" and v:match("^<FN:([%w_]+)>$")
    args[i] = name and BUILDERS[name]() or fresh(v)
  end
  local out = {}
  for k, v in pairs(case) do
    out[k] = v
  end
  out.args = args
  return out
end

---Write what `surface` answers for every case that is not `local_only`.
---
---Called by `scripts/ci.lua` with the **real** `vim` of the Neovim that is
---running at that moment, so the PUC runner compares against a live oracle
---rather than a committed golden file. A golden would have to be
---regenerated by hand, would drift with the next Neovim release, and would
---then be evidence of nothing — the same argument `GATES.standalone` already
---makes about reference artifacts.
---@param surface table
---@param root string Directory `<ROOT>` expands to.
---@param out_path string
---@return integer written
function M.write_expectations(surface, root, out_path)
  local fd = assert(io.open(out_path, "wb"))
  local n = 0
  for _, case in ipairs(M.sorted()) do
    if not case.local_only then
      local value = M.evaluate(surface, M.materialize(case), root)
      -- A path the oracle itself does not have is a typo in the corpus, and
      -- the quiet failure mode is the dangerous one: both sides would answer
      -- `missing`, the case would agree with itself, and it would look like
      -- coverage for as long as nobody read it.
      if value == "missing" then
        fd:close()
        error(("case %q names %q, which this Neovim does not have"):format(case.id, case.path), 0)
      elseif value:sub(1, 13) == "unknown-kind:" then
        fd:close()
        error(("case %q has an %s"):format(case.id, value), 0)
      end
      fd:write(case.id, "\t", value, "\n")
      n = n + 1
    end
  end
  fd:close()
  return n
end

---Read back what `write_expectations` wrote.
---@param path string
---@return table<string, string>|nil
---@return string|nil err
function M.read_expectations(path)
  local fd = io.open(path, "rb")
  if not fd then
    return nil, "cannot read expectations file: " .. path
  end
  local out = {}
  for line in fd:lines() do
    local id, value = line:match("^([^\t]+)\t(.*)$")
    if id then
      out[id] = value
    end
  end
  fd:close()
  return out
end

---Cases in a stable order, so both runners walk them identically and a
---failure list reads the same twice in a row.
---@return table[]
function M.sorted()
  local out = {}
  for _, c in ipairs(M.cases) do
    out[#out + 1] = c
  end
  table.sort(out, function(a, b)
    return a.id < b.id
  end)
  return out
end

return M
