---@module 'standalone.treesitter'
--- A real `vim.treesitter` for the standalone build, backed by
--- [`lua-tree-sitter`](https://github.com/xcb-xwii/lua-tree-sitter).
---
--- `vim_shim.lua` ships an *inert* treesitter stub: queries parse into
--- something that yields nothing, so every check and renderer that does not
--- need per-function facts still runs under plain `lua`, and everything that
--- does honestly reports absence. That was the parser-less MVP's boundary.
--- This module is what removes it — the same `core/*.lua` files, unmodified,
--- running against a real parser with no Neovim in the process.
---
--- Returns `nil` when no binding is installed, which is not an error: the
--- caller falls back to the inert stub and the MVP behaves exactly as before.
--- A build without the rock is still a working build, just a smaller one.
---
--- ## Grammars
---
--- A grammar is a shared library exporting `tree_sitter_<lang>`, built with
--- one command against a plain grammar checkout — no tree-sitter CLI, no Node
--- toolchain:
---
---   gcc -O2 -shared -o lua.dll src/parser.c src/scanner.c -Isrc
---
--- Resolution order per language, first hit wins:
---
---   1. `$DOCMAP_TS_<LANG>`  — explicit path to that grammar (LANG uppercased)
---   2. `$DOCMAP_TS_DIR/<lang>.{dll,so,dylib}`
---
--- A language that resolves to nothing makes `get_string_parser` raise, which
--- is already how every call site treats a missing parser — all six `pcall`
--- it and degrade to "no function-level data for this file". So a
--- `DOCMAP_TS_DIR` holding only `lua.so` gives full fidelity for Lua and the
--- MVP's behaviour for JS/TS, rather than failing the run.
---
--- ## Why the API needs translating at all
---
--- `lua-tree-sitter` is a faithful binding of the C API; Neovim's
--- `vim.treesitter` is a Lua-shaped layer over the same thing. The gaps are
--- shape, not capability, and there are exactly four — each verified against
--- a real parser rather than read off documentation, because three of the
--- four are off-by-one or shape questions that guessing gets wrong:
---
---   * **capture ids.** `capture:index()` is 0-based and assigned in order of
---     first appearance in the query source; Neovim's `query.captures` is a
---     1-based array of names. Measured: for `@fname @params @fdef` the
---     indices come back 0, 1, 2 in that order.
---   * **`iter_matches`.** Neovim yields `(pattern, match)` where `match` maps
---     capture id to an *array* of nodes. `match:captures_to_table()` returns
---     a 1-based array of `Capture` objects instead, so the grouping has to be
---     rebuilt here.
---   * **`node:range()`** does not exist; it is four numbers composed from
---     `start_point()`/`end_point()`, whose `Point` has `row()`/`column()`
---     accessors rather than being a tuple.
---   * **`node:field(name)`** does not exist. `child_by_field_name` returns
---     only the first; Neovim returns every child under that field, so this
---     walks `field_name_for_child(i)` (0-based) to collect all of them.
---
--- The two additions are installed **on the binding's own node metatable**
--- rather than by wrapping each node in a Lua table. Wrapping would allocate
--- per node in the hot path of every scan and, worse, break identity: the
--- scanner compares nodes and stores them as table keys, and two wrappers
--- around one node are two different objects. Mutating a third-party
--- metatable is a real liberty, taken deliberately and only additively — both
--- names are absent upstream, so nothing is being overridden.

local M = {}

---Locate a grammar for `lang`, or nil.
---@param lang string
---@return string?
local function grammar_path(lang)
  local explicit = os.getenv("DOCMAP_TS_" .. lang:upper())
  if explicit and explicit ~= "" then
    return explicit
  end
  local dir = os.getenv("DOCMAP_TS_DIR")
  if not dir or dir == "" then
    return nil
  end
  dir = dir:gsub("\\", "/"):gsub("/+$", "")
  for _, ext in ipairs({ "so", "dll", "dylib" }) do
    local candidate = ("%s/%s.%s"):format(dir, lang, ext)
    local fd = io.open(candidate, "rb")
    if fd then
      fd:close()
      return candidate
    end
  end
  return nil
end

---Build the `vim.treesitter` table, or nil when no binding is installed.
---@return table?
function M.build()
  local ok, ts = pcall(require, "lua_tree_sitter")
  if not ok then
    return nil
  end

  -- Additive methods on the binding's own Node metatable. Reached through a
  -- real node rather than a documented registry because the binding exposes
  -- no metatable directly; one throwaway parse at load is cheaper than
  -- guessing at internals.
  local probe_lang, probe_lang_path = nil, nil
  for _, lang in ipairs({ "lua", "javascript", "typescript" }) do
    local path = grammar_path(lang)
    if path then
      probe_lang, probe_lang_path = lang, path
      break
    end
  end
  if not probe_lang_path then
    -- No grammar anywhere: a real parser is installed but has nothing to
    -- parse with, which is indistinguishable in effect from having no
    -- binding. Say so by degrading rather than by raising at load time.
    return nil
  end

  local languages = {}
  ---@param lang string
  ---@return userdata
  local function language(lang)
    local cached = languages[lang]
    if cached ~= nil then
      if cached == false then
        error("standalone build: no grammar for '" .. lang .. "'", 0)
      end
      return cached
    end
    local path = grammar_path(lang)
    if not path then
      languages[lang] = false
      error("standalone build: no grammar for '" .. lang .. "'", 0)
    end
    local ok_load, loaded = pcall(ts.Language.load, path, lang)
    if not ok_load then
      languages[lang] = false
      error(
        "standalone build: grammar for '" .. lang .. "' failed to load: " .. tostring(loaded),
        0
      )
    end
    languages[lang] = loaded
    return loaded
  end

  -- Install `range`/`field` once, on the metatable a real node carries.
  do
    local probe = ts.Parser.new()
    probe:set_language(ts.Language.load(probe_lang_path, probe_lang))
    local node = probe:parse_string(nil, "\n"):root_node()
    local mt = getmetatable(node)
    local index = mt and mt.__index
    if type(index) == "table" then
      if not index.range then
        ---Neovim's four-number range: start row, start column, end row, end
        ---column, all 0-based.
        function index:range()
          local sp, ep = self:start_point(), self:end_point()
          return sp:row(), sp:column(), ep:row(), ep:column()
        end
      end
      if not index.field then
        ---Every child under `name`, not just the first — Neovim's semantics.
        ---@param name string
        ---@return userdata[]
        function index:field(name)
          local out = {}
          for i = 0, self:child_count() - 1 do
            if self:field_name_for_child(i) == name then
              out[#out + 1] = self:child(i)
            end
          end
          return out
        end
      end
      if not index.iter_children then
        ---Neovim yields `(child, field_name)`. Every call site in this
        ---repository uses only the first value, but the second is emitted
        ---anyway: a shim that quietly narrows an API is how the *next* call
        ---site acquires a bug that looks like a scanner defect.
        ---@return fun(): userdata?, string?
        function index:iter_children()
          local i, n = 0, self:child_count()
          return function()
            if i >= n then
              return nil
            end
            local child, field = self:child(i), self:field_name_for_child(i)
            i = i + 1
            return child, field
          end
        end
      end
    end
  end

  ---Capture names by 1-based id, derived from the query source.
  ---
  ---tree-sitter assigns capture ids in order of first appearance, which the
  ---module header records as measured rather than assumed. Derived here
  ---because the binding's `Query` exposes no name list, and cross-checked at
  ---runtime in `iter_captures` below, where `capture:name()` makes the real
  ---answer available for free — a silent divergence would otherwise mis-label
  ---every capture in the scan.
  ---@param pattern string
  ---@return string[]
  local function capture_names(pattern)
    local names, seen = {}, {}
    for name in pattern:gmatch("@([%w_%.]+)") do
      if not seen[name] then
        seen[name] = true
        names[#names + 1] = name
      end
    end
    return names
  end

  local Query = {}
  Query.__index = Query

  ---@param node userdata
  ---@return fun(): integer?, userdata?
  function Query:iter_captures(node)
    local cursor = ts.Query.Cursor.new(self._q, node)
    return function()
      local cap = cursor:next_capture()
      if not cap then
        return nil
      end
      local id = cap:index() + 1
      -- The cross-check the header promises: cheap, and it fires exactly
      -- when the first-appearance assumption would have corrupted the scan.
      local declared = self.captures[id]
      local actual = cap:name()
      if declared ~= actual then
        self.captures[id] = actual
      end
      return id, cap:node()
    end
  end

  ---@param node userdata
  ---@return fun(): integer?, table<integer, userdata[]>?
  function Query:iter_matches(node)
    local cursor = ts.Query.Cursor.new(self._q, node)
    return function()
      local m = cursor:next_match()
      if not m then
        return nil
      end
      local grouped = {}
      for _, cap in ipairs(m:captures_to_table()) do
        local id = cap:index() + 1
        local bucket = grouped[id]
        if not bucket then
          bucket = {}
          grouped[id] = bucket
        end
        bucket[#bucket + 1] = cap:node()
      end
      return m:pattern_index(), grouped
    end
  end

  local treesitter = {
    query = {
      ---@param lang string
      ---@param pattern string
      ---@return table
      parse = function(lang, pattern)
        local q = ts.Query.new(language(lang), pattern)
        return setmetatable({ _q = q, captures = capture_names(pattern) }, Query)
      end,
    },

    ---@param src string
    ---@param lang string
    ---@return table
    get_string_parser = function(src, lang)
      local parser = ts.Parser.new()
      parser:set_language(language(lang))
      return {
        ---Neovim returns a list of trees (one per injected region); this
        ---build never injects, so the list always has exactly one.
        parse = function()
          local tree = parser:parse_string(nil, src)
          return {
            {
              root = function()
                return tree:root_node()
              end,
            },
          }
        end,
      }
    end,

    ---@param node userdata
    ---@param src string
    ---@return string
    get_node_text = function(node, src)
      return src:sub(node:start_byte() + 1, node:end_byte())
    end,

    language = {
      ---@param lang string
      ---@return boolean
      add = function(lang)
        return (pcall(language, lang))
      end,
    },
  }

  return treesitter
end

return M
