---@module 'documentation.core.lang.elixir'
--- Elixir, registered as a language backend — the twenty-first.
---
--- **The closest fit in wave 2, and the reason is that documentation is not a
--- comment here — it is a value the compiler keeps.** `@moduledoc "…"` and
--- `@doc "…"` are module attributes: real expressions, evaluated at compile
--- time, stored in the BEAM chunk and readable at runtime through
--- `Code.fetch_docs/1`. Python's docstrings were the first non-comment
--- documentation this tool met; Elixir's are the first the *compiler* takes
--- responsibility for.
---
--- One consequence worth naming: **`@doc false` is a real state**, and it is
--- not the same as absent. It means "this is public and deliberately
--- undocumented" — a hidden function, usually one that exists for another
--- module in the same library. Reading it as documentation prose would put
--- the word `false` in a summary; reading it as *no* documentation would lose
--- the author's statement. It is recorded as internal instead, which is what
--- the author meant.
---
--- **`def` and `defp` are visibility**, plainly, with nothing to infer.
--- `defp` is private to the module and unreachable from outside.
---
--- **Everything in this language is a call**, which makes the backend
--- unusually uniform. `defmodule`, `def`, `defp`, `alias`, `import`, `use`
--- and `@doc` all parse as `call` nodes distinguished only by the identifier
--- at their head — so this walks one node type and dispatches on a name,
--- where every other backend of the twenty-one matches a dozen node kinds.
--- That is Elixir being homoiconic rather than the grammar being lazy.
---
--- **Four import forms, and they mean different things.** `alias` renames,
--- `import` brings functions into scope, `require` makes macros available,
--- `use` invokes another module's `__using__` macro. All four are edges to
--- the same module and all four are recorded as such — the distinction
--- matters to a compiler and not to a dependency graph.

local M = {}

M.name = "elixir"

M.grammar = "elixir"

---@type string[]
M.extensions = { "ex", "exs" }

---`defmodule` names the module, so `module` is filled from the language —
---but that is a declaration rather than a documentation tag.
M.module_tag = false

---@type string[]
M.line_comments = { "#" }

---Elixir has no block comment. A heredoc used as one is a string the
---compiler evaluates, which is exactly why `@moduledoc` works the way it
---does.
---@type { [1]: string, [2]: string }[]
M.block_comments = {}

---**ExDoc has no per-parameter form.** A function's arguments are described
---in the prose of its `@doc`, and the convention for a contract is
---`@spec add(integer, integer) :: integer` — which names *types*, not
---parameters, the same shape that made Haskell's signature unusable for
---this. Seventh language to declare it.
M.param_docs = false

---@param filename string
---@return boolean
function M.is_source(filename)
  return filename:match("%.ex$") ~= nil or filename:match("%.exs$") ~= nil
end

---Where this backend's sources live under `root`, or `nil`.
---
---`lib/` is Mix's, and it is where every Elixir project puts its code —
---`test/` holds `.exs` and is deliberately not preferred over it.
---@param root string
---@return string?
function M.detect_source(root)
  local uv = vim.uv or vim.loop

  ---@param dir string
  ---@param depth integer
  ---@return boolean
  local function holds_ex(dir, depth)
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
        if holds_ex(sub, depth - 1) then
          return true
        end
      end
    end
    return false
  end

  for _, candidate in ipairs({ "lib", "src" }) do
    if holds_ex(root .. "/" .. candidate, 1) then
      return candidate
    end
  end
  if holds_ex(root, 1) then
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
---@return userdata?
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

---@param node userdata
---@param src string
---@return string
local function text_of(node, src)
  local _, _, sbyte = node:start()
  local _, _, ebyte = node:end_()
  return src:sub(sbyte + 1, ebyte)
end

---@param node userdata
---@param kind string
---@return userdata?
local function child_of(node, kind)
  for child in node:iter_children() do
    if child:type() == kind then
      return child
    end
  end
  return nil
end

---The head identifier of a `call`, or `nil`.
---@param node userdata
---@param src string
---@return string?
local function call_name(node, src)
  if node:type() ~= "call" then
    return nil
  end
  local id = child_of(node, "identifier")
  return id and text_of(id, src) or nil
end

---An attribute's name and its argument text, for a `unary_operator` holding
---`@name value`.
---@param node userdata
---@param src string
---@return string? name
---@return string? value
local function attribute(node, src)
  if node:type() ~= "unary_operator" then
    return nil, nil
  end
  local call = child_of(node, "call")
  if not call then
    -- `@moduledoc` with no argument parses as `@` plus a bare identifier.
    local id = child_of(node, "identifier")
    return id and text_of(id, src) or nil, nil
  end
  local name = call_name(call, src)
  local args = child_of(call, "arguments")
  return name, args and text_of(args, src) or nil
end

---The prose inside a `@doc`/`@moduledoc` argument.
---
---**`@doc false` is a state, not a string**, and it is returned as such:
---the author is saying "public and deliberately undocumented", usually for a
---function another module in the same library calls. Reading it as prose
---would put the word `false` in a summary; reading it as absent would lose
---what the author said.
---@param value string?
---@return string prose
---@return boolean hidden
local function doc_text(value)
  if not value then
    return "", false
  end
  local trimmed = value:gsub("^%s+", ""):gsub("%s+$", "")
  if trimmed == "false" then
    return "", true
  end

  -- A heredoc (`"""`) is the usual form; a plain string is legal too.
  local body = trimmed:match('^"""%s*\n(.-)%s*"""$') or trimmed:match('^"(.*)"$') or trimmed
  local lines = {}
  local indent = nil
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do
    line = line:gsub("\r$", "")
    lines[#lines + 1] = line
    if line:match("%S") then
      local n = #(line:match("^(%s*)"))
      if not indent or n < indent then
        indent = n
      end
    end
  end
  if indent and indent > 0 then
    for i, line in ipairs(lines) do
      lines[i] = line:sub(indent + 1)
    end
  end
  while lines[1] == "" do
    table.remove(lines, 1)
  end
  while lines[#lines] == "" do
    table.remove(lines)
  end
  return table.concat(lines, "\n"), false
end

---The name a `def`/`defp` head declares, and its parameter names.
---@param call userdata The `def`/`defp` call.
---@param src string
---@return string? name
---@return string[] params
local function head_of(call, src)
  local args = child_of(call, "arguments")
  if not args then
    return nil, {}
  end
  -- `def add(x, y), do: …` — the head is the first argument, itself a call.
  for child in args:iter_children() do
    local kind = child:type()
    if kind == "call" then
      local name = call_name(child, src)
      local names = {}
      local inner = child_of(child, "arguments")
      if inner then
        for p in inner:iter_children() do
          local pk = p:type()
          if pk == "identifier" then
            names[#names + 1] = text_of(p, src)
          elseif pk ~= "," and pk ~= "(" and pk ~= ")" then
            names[#names + 1] = (text_of(p, src):gsub("%s+", " "))
          end
        end
      end
      return name, names
    end
    if kind == "identifier" then
      -- `def hidden_from_docs, do: 1` — a head with no parameter list.
      return text_of(child, src), {}
    end
    if kind == "binary_operator" then
      -- `def add(x, y) when is_integer(x), do: …` — a guard wraps the head.
      local lhs = child_of(child, "call") or child_of(child, "identifier")
      if lhs then
        if lhs:type() == "identifier" then
          return text_of(lhs, src), {}
        end
        local name = call_name(lhs, src)
        local names = {}
        local inner = child_of(lhs, "arguments")
        if inner then
          for p in inner:iter_children() do
            if p:type() == "identifier" then
              names[#names + 1] = text_of(p, src)
            end
          end
        end
        return name, names
      end
    end
  end
  return nil, {}
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

  for child in root:iter_children() do
    if call_name(child, src) == "defmodule" then
      local args = child_of(child, "arguments")
      local alias = args and child_of(args, "alias")
      local module = alias and (text_of(alias, src):gsub("%s+", "")) or nil

      local body = child_of(child, "do_block")
      local prose = ""
      if body then
        for stmt in body:iter_children() do
          local name, value = attribute(stmt, src)
          if name == "moduledoc" then
            prose = (doc_text(value))
            break
          end
        end
      end
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
  end
  return empty
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

  local split = require("documentation.core.scan").split_summary
  local fns, requires, symbols = {}, {}, {}

  ---@param body userdata `do_block`
  ---@param owner string
  local function walk_module(body, owner)
    -- **`@doc` applies to the next definition**, so it is carried forward
    -- rather than looked up backwards — the only backend here that reads its
    -- documentation *before* the thing it documents rather than above it.
    local pending, pending_hidden = "", false
    -- Elixir defines a function once per clause; the first clause is the
    -- declaration a reader looks for.
    local seen = {}

    for stmt in body:iter_children() do
      local attr, value = attribute(stmt, src)
      if attr == "doc" then
        pending, pending_hidden = doc_text(value)
      elseif attr and attr ~= "moduledoc" and attr ~= "spec" and attr ~= "impl" then
        -- Any other module attribute is a module-scope constant:
        -- `@max_count 10`.
        if value then
          symbols[#symbols + 1] = {
            name = owner .. "." .. attr,
            kind = "constant",
            detail = (value:gsub("%s+", " ")):sub(1, 60),
            summary = "",
            line = stmt:start() + 1,
          }
        end
      else
        local name = call_name(stmt, src)
        if name == "def" or name == "defp" or name == "defmacro" or name == "defmacrop" then
          local fname, params = head_of(stmt, src)
          if fname and not seen[fname] then
            seen[fname] = true
            fns[#fns + 1] = {
              name = owner .. "." .. fname,
              signature = owner .. "." .. fname .. "(" .. table.concat(params, ", ") .. ")",
              line = stmt:start() + 1,
              line_end = stmt:end_() + 1,
              summary = split(pending),
              body = pending,
              params = {},
              returns = {},
              -- `defp` is private, and `@doc false` is the author saying a
              -- public function is not part of the published surface.
              internal = name == "defp" or name == "defmacrop" or pending_hidden,
              -- **Every Elixir function has an owner**, and this is the one
              -- backend where that is the interesting fact rather than the
              -- exception: a `.ex` file routinely holds several `defmodule`s,
              -- so the owner is what separates them. The node is still the
              -- file — see `core/scopes.lua` on what a scope is not.
              owner = owner,
              owner_kind = "module",
              see = {},
              overload = {},
              todo = {},
              bug = {},
              test = {},
            }
          end
          pending, pending_hidden = "", false
        elseif name == "alias" or name == "import" or name == "require" or name == "use" then
          -- Four forms, one edge. `alias` renames, `import` brings functions
          -- into scope, `require` makes macros available, `use` invokes
          -- another module's `__using__` — a distinction the compiler needs
          -- and a dependency graph does not.
          local args = child_of(stmt, "arguments")
          local target = args and child_of(args, "alias")
          if target then
            requires[#requires + 1] = {
              module = (text_of(target, src):gsub("%s+", "")),
              line = stmt:start() + 1,
            }
          end
        elseif name == "defmodule" then
          -- A nested module, which Elixir writes often.
          local args = child_of(stmt, "arguments")
          local alias = args and child_of(args, "alias")
          local inner = child_of(stmt, "do_block")
          if alias and inner then
            local nested = owner .. "." .. text_of(alias, src):gsub("%s+", "")
            symbols[#symbols + 1] = {
              name = nested,
              kind = "table",
              detail = "module",
              summary = "",
              line = stmt:start() + 1,
            }
            walk_module(inner, nested)
          end
        elseif name == "defstruct" then
          symbols[#symbols + 1] = {
            name = owner .. ".__struct__",
            kind = "table",
            detail = "defstruct",
            summary = "",
            line = stmt:start() + 1,
          }
        end
      end
    end
  end

  for child in root:iter_children() do
    if call_name(child, src) == "defmodule" then
      local args = child_of(child, "arguments")
      local alias = args and child_of(args, "alias")
      local body = child_of(child, "do_block")
      if alias and body then
        walk_module(body, (text_of(alias, src):gsub("%s+", "")))
      end
    end
  end

  return fns, {}, requires, symbols, {}, {}, lines, {}
end

require("documentation.core.lang_registry").register(M.name, M)

return M
