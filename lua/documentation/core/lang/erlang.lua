---@module 'documentation.core.lang.erlang'
--- Erlang, registered as a language backend — the twenty-second.
---
--- **The export list again, and this time it carries arity.** Haskell's
--- `module Foo (add) where` names a function; Erlang's `-export([add/2]).`
--- names a function *at a particular arity*, and `add/2` and `add/3` are
--- genuinely different functions that can be exported independently. So the
--- export set is keyed by `name/arity`, and a function's arity has to be
--- counted from its clause head to ask the question at all — the only
--- backend of the twenty-two where the *number* of parameters is part of a
--- declaration's identity rather than a detail of it.
---
--- **`-compile(export_all).` publishes everything**, and it is the third
--- shape of "everything is exported" this tool has met after Haskell's
--- missing list and Python's missing `__all__`. It is deprecated and still
--- widespread in older code, so ignoring it would report a whole module as
--- private.
---
--- **EDoc is a comment convention with a tool behind it.** `%% @doc` above a
--- function, `%% @doc` above `-module` for the module itself. Unlike Elixir's
--- attributes it is not a value the compiler keeps — Erlang's own
--- documentation lives in comments, which is why EDoc had to be written as a
--- separate program.
---
--- **A declaration is two nodes again**, as in Haskell: `-spec add(integer(),
--- integer()) -> integer().` is a `spec` and `add(X, Y) -> X + Y.` is a
--- `fun_decl`, with the EDoc block above the spec when there is one and above
--- the function when there is not. Both are looked at.

local M = {}

M.name = "erlang"

M.grammar = "erlang"

---@type string[]
M.extensions = { "erl", "hrl" }

---`-module(name).` names the module, from the language.
M.module_tag = false

---@type string[]
M.line_comments = { "%" }

---Erlang has no block comment at all.
---@type { [1]: string, [2]: string }[]
M.block_comments = {}

---**EDoc has `@param`-shaped tags but almost nobody writes them**, and the
---contract Erlang really uses is `-spec`, which names *types* rather than
---parameters — Haskell's and Elixir's problem for the third time. Eighth
---language to declare it.
M.param_docs = false

---@param filename string
---@return boolean
function M.is_source(filename)
  return filename:match("%.erl$") ~= nil or filename:match("%.hrl$") ~= nil
end

---Where this backend's sources live under `root`, or `nil`.
---
---`src/` is what rebar3 and every OTP application use; `include/` holds the
---`.hrl` headers beside it.
---@param root string
---@return string?
function M.detect_source(root)
  local uv = vim.uv or vim.loop

  ---@param dir string
  ---@param depth integer
  ---@return boolean
  local function holds_erl(dir, depth)
    local fd = uv.fs_scandir(dir)
    if not fd then
      return false
    end
    local subdirs = {}
    while true do
      local name, kind = uv.fs_scandir_next(fd)
      if not name then
        break
      end
      if kind ~= "directory" and M.is_source(name) then
        return true
      end
      if kind == "directory" and name:sub(1, 1) ~= "." and name ~= "_build" then
        subdirs[#subdirs + 1] = dir .. "/" .. name
      end
    end
    if depth > 0 then
      for _, sub in ipairs(subdirs) do
        if holds_erl(sub, depth - 1) then
          return true
        end
      end
    end
    return false
  end

  for _, candidate in ipairs({ "src", "apps", "lib" }) do
    if holds_erl(root .. "/" .. candidate, 2) then
      return candidate
    end
  end
  if holds_erl(root, 1) then
    return "."
  end
  return nil
end

---@param path string
---@return string?
local function read(path)
  local fd = io.open(path, "rb")
  if not fd then
    return nil
  end
  local src = fd:read("*a")
  fd:close()
  return src
end

---@param src string
---@return TSNode?
local function parse(src)
  local ok, parser = pcall(vim.treesitter.get_string_parser, src, M.grammar)
  if not ok or not parser then
    return nil
  end
  local ok_parse, trees = pcall(function()
    return parser:parse()
  end)
  if not ok_parse or not trees or not trees[1] then
    return nil
  end
  return trees[1]:root()
end

---@param node TSNode
---@param src string
---@return string
local function text_of(node, src)
  local _, _, sbyte = node:start()
  local _, _, ebyte = node:end_()
  return src:sub(sbyte + 1, ebyte)
end

---@param node TSNode
---@param kind string
---@return TSNode?
local function child_of(node, kind)
  for child in node:iter_children() do
    if child:type() == kind then
      return child
    end
  end
  return nil
end

---Every `%%` comment run, keyed by the row it ends on.
---
---A run counts as documentation when any of its lines carries an EDoc tag
---(`@doc`, `@spec`, `@since`) or when it sits directly above a declaration —
---the second half because a great deal of real Erlang documents with plain
---`%%` prose and no tag at all, which is the lesson C taught.
---@param root TSNode
---@param src string
---@return table<integer, string[]>
local function comment_runs(root, src)
  local rows = {}
  local function walk(node)
    if node:type() == "comment" then
      local srow = node:start()
      local body = text_of(node, src):match("^%%+%s?(.*)$")
      if body then
        rows[srow] = (body:gsub("[\r%s]+$", ""))
      end
      return
    end
    for child in node:iter_children() do
      walk(child)
    end
  end
  walk(root)

  local by_row = {}
  for row in pairs(rows) do
    if rows[row + 1] == nil then
      local top = row
      while rows[top - 1] ~= nil do
        top = top - 1
      end
      local lines = {}
      for r = top, row do
        -- `@doc` opens the prose rather than being part of it; the other
        -- EDoc tags are recognised so their text stays out.
        local line = rows[r]
        local doc = line:match("^@doc%s*(.*)$")
        if doc then
          lines[#lines + 1] = doc
        elseif line:match("^@%a") then
          -- `@since`, `@author`, `@equiv` and the rest: dropped.
        else
          lines[#lines + 1] = line
        end
      end
      while lines[1] == "" do
        table.remove(lines, 1)
      end
      while lines[#lines] == "" do
        table.remove(lines)
      end
      if #lines > 0 then
        by_row[row] = lines
      end
    end
  end
  return by_row
end

---@param runs table<integer, string[]>
---@param row integer 0-based row of the documented declaration.
---@return string
local function doc_above(runs, row)
  local lines = runs[row - 1]
  return lines and table.concat(lines, "\n") or ""
end

---@param path string
---@return Documentation.Header
function M.parse_header(path)
  local empty = { module = nil, summary = "", body = "", tags = {} }
  local src = read(path)
  if not src then
    return empty
  end
  local root = parse(src)
  if not root then
    return empty
  end

  local module, decl = nil, nil
  for child in root:iter_children() do
    if child:type() == "module_attribute" then
      decl = child
      local atom = child_of(child, "atom")
      module = atom and text_of(atom, src) or nil
      break
    end
  end
  if not decl then
    return empty
  end

  local runs = comment_runs(root, src)
  local prose = doc_above(runs, decl:start())
  if prose == "" and not module then
    return empty
  end
  return {
    module = module,
    summary = require("documentation.core.scan").split_summary(prose),
    body = prose,
    tags = {},
  }
end

---@param path string
---@return Documentation.FunctionInfo[], Documentation.RawCall[], Documentation.RawRequire[], Documentation.SymbolInfo[], table[], Documentation.EndpointSpec[], integer, Documentation.BindingSpec[]
function M.scan_file(path)
  local src = read(path)
  if not src then
    return {}, {}, {}, {}, {}, {}, 0, {}
  end
  local _, newlines = src:gsub("\n", "")
  local lines = #src == 0 and 0 or (newlines + (src:sub(-1) == "\n" and 0 or 1))

  local root = parse(src)
  if not root then
    return {}, {}, {}, {}, {}, {}, lines, {}
  end

  local runs = comment_runs(root, src)
  local split = require("documentation.core.scan").split_summary
  local fns, requires, symbols = {}, {}, {}

  -- **Keyed by `name/arity`, because that is what Erlang exports.** `add/2`
  -- and `add/3` are different functions and can be exported independently,
  -- so a set of bare names would publish both whenever either was listed.
  local exported, export_all = {}, false
  -- The row a `-spec` sat on, per name, so the EDoc above the spec reaches
  -- the definition below it — Haskell's two-node shape again.
  local spec_doc, spec_row = {}, {}

  for child in root:iter_children() do
    local kind = child:type()

    if kind == "export_attribute" then
      for entry in child:iter_children() do
        if entry:type() == "fa" then
          local atom = child_of(entry, "atom")
          local arity = child_of(entry, "arity")
          if atom then
            local n = arity and text_of(arity, src):match("(%d+)") or "0"
            exported[text_of(atom, src) .. "/" .. n] = true
          end
        end
      end
    elseif kind == "compile_options_attribute" or kind == "attribute" then
      -- `-compile(export_all).` — deprecated, still widespread, and it
      -- publishes everything. The third shape of "everything is exported"
      -- here, after Haskell's missing list and Python's missing `__all__`.
      if text_of(child, src):match("export_all") then
        export_all = true
      end
    elseif kind == "pp_include" or kind == "pp_include_lib" then
      local str = child_of(child, "string")
      if str then
        local target = text_of(str, src):match('^"(.*)"$')
        if target then
          -- `-include("x.hrl")` names a file beside this one;
          -- `-include_lib("app/include/x.hrl")` names one in another
          -- application, which is external by construction.
          if kind == "pp_include" and target:sub(1, 1) ~= "/" then
            target = "./" .. target
          end
          requires[#requires + 1] = { module = target, line = child:start() + 1 }
        end
      end
    elseif kind == "pp_define" then
      local lhs = child_of(child, "macro_lhs")
      if lhs then
        symbols[#symbols + 1] = {
          name = (text_of(lhs, src):gsub("%s+", "")),
          kind = "constant",
          detail = (text_of(child, src):gsub("%s+", " ")):sub(1, 60),
          summary = split(doc_above(runs, child:start())),
          line = child:start() + 1,
        }
      end
    elseif kind == "spec" then
      local atom = child_of(child, "atom")
      if atom then
        local name = text_of(atom, src)
        spec_doc[name] = doc_above(runs, child:start())
        spec_row[name] = child:start()
      end
    elseif kind == "fun_decl" then
      local clause = child_of(child, "function_clause")
      if clause then
        local atom = child_of(clause, "atom")
        if atom then
          local name = text_of(atom, src)
          -- Arity from the clause head: the parenthesised argument list.
          local args = child_of(clause, "expr_args") or child_of(clause, "arguments")
          local arity, names = 0, {}
          if args then
            for a in args:iter_children() do
              local ak = a:type()
              if ak ~= "(" and ak ~= ")" and ak ~= "," then
                arity = arity + 1
                names[#names + 1] = (text_of(a, src):gsub("%s+", " "))
              end
            end
          end
          local prose = spec_doc[name]
          if not prose or prose == "" then
            prose = doc_above(runs, child:start())
          end
          local row = spec_row[name] or child:start()
          fns[#fns + 1] = {
            name = name,
            signature = name .. "/" .. arity,
            line = row + 1,
            line_end = child:end_() + 1,
            summary = split(prose),
            body = prose,
            params = {},
            returns = {},
            internal = not export_all and not exported[name .. "/" .. arity],
            see = {},
            overload = {},
            todo = {},
            bug = {},
            test = {},
          }
          local _ = names
        end
      end
    end
  end

  return fns, {}, requires, symbols, {}, {}, lines, {}
end

require("documentation.core.lang_registry").register(M.name, M)

return M
