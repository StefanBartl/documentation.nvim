---@module 'documentation.core.lang.haskell'
--- Haskell, registered as a language backend — the twentieth, and the first
--- of wave 2.
---
--- **Visibility lives in the module header, not on the declaration.** This is
--- the shape nineteen backends have not met: `module Acme.Widget (add,
--- maxCount) where` states the module's published surface *once, at the top*,
--- and everything not in that list is private however it is written. There
--- is no keyword at a definition to read — the definition looks identical
--- either way, and the only evidence is a list somewhere above it.
---
--- Two consequences worth stating rather than discovering:
---
--- * **An absent export list means everything is exported.** `module Foo
---   where` publishes every top-level name. So "no list" is the opposite of
---   "no exports", and reading it the other way would report a whole module
---   as private — the same class of inversion C#'s interface default was.
--- * **`Widget(..)` exports a type and all its constructors.** The `(..)` is
---   part of the entry rather than a separate one, so the name has to be
---   taken from the front of the export rather than as the whole of it.
---
--- **Haddock is a node type, not a pattern.** `-- |` parses as `haddock`,
--- distinct from `comment`, which makes Haskell the second backend of the
--- twenty (after Dart) that needs no pattern to tell documentation from a
--- note.
---
--- **A declaration is two nodes.** `add :: Int -> Int -> Int` is a
--- `signature` and `add x y = x + y` is a `function`, and the Haddock block
--- sits above the *signature*. So the doc is looked up from the signature's
--- row and carried to the definition — the only backend here where the
--- documented thing and the defined thing are different nodes.
---
--- **`param_docs = false`.** Haddock can annotate an argument with `-- ^`
--- inside a type signature, but it is rare, optional and positional rather
--- than named — there is no name to match against, because Haskell's type
--- signature has no parameter names in it at all. Judging Haskell by
--- per-parameter documentation would mark down every library in the
--- ecosystem.

local M = {}

M.name = "haskell"

M.grammar = "haskell"

---@type string[]
M.extensions = { "hs", "lhs" }

---A Haskell module names itself in its header, so `module` is filled in from
---the language rather than from the path — but that is a declaration, not a
---documentation tag, and a file without one is legal (it is `Main`).
M.module_tag = false

---@type string[]
M.line_comments = { "--" }

---@type { [1]: string, [2]: string }[]
M.block_comments = { { "{-", "-}" } }

---**Haskell's type signature has no parameter names in it.** `add :: Int ->
---Int -> Int` names types and nothing else, so there is nothing for a
---per-parameter convention to match against. Haddock's `-- ^` can annotate
---an argument positionally, and it is rare and optional. Sixth language to
---declare this, and the first where the *signature* rather than the
---documentation is what makes it impossible.
M.param_docs = false

---@param filename string
---@return boolean
function M.is_source(filename)
  return filename:match("%.hs$") ~= nil or filename:match("%.lhs$") ~= nil
end

---Where this backend's sources live under `root`, or `nil`.
---
---`src/` is what Cabal and Stack both scaffold. `lib/` and the root follow.
---@param root string
---@return string?
function M.detect_source(root)
  local uv = vim.uv or vim.loop

  ---@param dir string
  ---@param depth integer
  ---@return boolean
  local function holds_hs(dir, depth)
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
      if kind == "directory" and name:sub(1, 1) ~= "." and name ~= "dist-newstyle" then
        subdirs[#subdirs + 1] = dir .. "/" .. name
      end
    end
    if depth > 0 then
      for _, sub in ipairs(subdirs) do
        if holds_hs(sub, depth - 1) then
          return true
        end
      end
    end
    return false
  end

  for _, candidate in ipairs({ "src", "lib", "source" }) do
    if holds_hs(root .. "/" .. candidate, 1) then
      return candidate
    end
  end
  if holds_hs(root, 1) then
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

---Every Haddock block, keyed by the row it ends on.
---
---**The grammar does the telling-apart**, as Dart's does: `-- |` is a
---`haddock` node and `--` is a `comment`, so no pattern is needed to know
---which is documentation.
---@param root TSNode
---@param src string
---@return table<integer, string[]>
local function haddocks(root, src)
  -- **A Haddock block is not always one node**, and assuming it is cost this
  -- backend every multi-line module doc on a CRLF file. `-- | first` parses
  -- as `haddock`, and its continuation lines — `--` and `-- more` — come
  -- back as ordinary `comment` nodes: the grammar marks the *opener*, not the
  -- block, and where the split falls depends on the line endings.
  --
  -- So both kinds are collected by row, and a block is whatever consecutive
  -- run of them begins with a `haddock`. A run of plain `--` lines with no
  -- `-- |` at its top is a note and stays out, which is the distinction the
  -- grammar was giving for free and now has to be kept by hand.
  local rows, opens = {}, {}
  local function walk(node)
    local kind = node:type()
    if kind == "haddock" or kind == "comment" then
      local srow, erow = node:start(), node:end_()
      local r = srow
      for line in (text_of(node, src) .. "\n"):gmatch("([^\n]*)\n") do
        if r > erow then
          break
        end
        local body = line:match("^%s*%-%-%s*[|^]?%s?(.*)$")
        if body then
          rows[r] = (body:gsub("[\r%s]+$", ""))
          if kind == "haddock" and r == srow then
            opens[r] = true
          end
        end
        r = r + 1
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
    -- This row ends a run when the row below it carries no comment.
    if rows[row + 1] == nil then
      local top = row
      while rows[top - 1] ~= nil do
        top = top - 1
      end
      if opens[top] then
        local lines = {}
        for r = top, row do
          lines[#lines + 1] = rows[r]
        end
        while lines[#lines] == "" do
          table.remove(lines)
        end
        if #lines > 0 then
          by_row[row] = lines
        end
      end
    end
  end
  return by_row
end

---@param blocks table<integer, string[]>
---@param row integer 0-based row of the documented declaration.
---@return string
local function doc_above(blocks, row)
  local lines = blocks[row - 1]
  if not lines then
    return ""
  end
  return table.concat(lines, "\n")
end

---The names a module's header exports, or `nil` when it exports everything.
---
---**`nil` and an empty set are different answers, and confusing them inverts
---a module.** `module Foo where` with no list publishes *every* top-level
---name; `module Foo () where` publishes none. Returning an empty table for
---the first would report an entire module as private.
---
---`Widget(..)` exports a type and all its constructors, so the name is taken
---from the front of the entry rather than as the whole of it.
---@param root TSNode
---@param src string
---@return table<string, boolean>? exported
---@return string? module
local function exports_of(root, src)
  local header = child_of(root, "header")
  if not header then
    return nil, nil
  end
  -- **The keyword and the name are both called `module` in this grammar**,
  -- and the keyword comes first — so taking the first match returns the
  -- literal string "module" as every file's name. The name is the one that
  -- holds `module_id` children.
  local name_node = nil
  for child in header:iter_children() do
    if child:type() == "module" and child_of(child, "module_id") then
      name_node = child
      break
    end
  end
  local module = name_node and (text_of(name_node, src):gsub("%s+", "")) or nil

  local list = child_of(header, "exports")
  if not list then
    -- No export list at all: everything is exported.
    return nil, module
  end

  local out = {}
  for entry in list:iter_children() do
    if entry:type() == "export" then
      local text = text_of(entry, src)
      -- `Widget(..)`, `Widget(A, B)`, `(<+>)` for an operator, or a bare
      -- name. The leading identifier is the export.
      local name = text:match("^%s*([%w_']+)") or text:match("^%s*%(([^)]+)%)")
      if name then
        out[name] = true
      end
    end
  end
  return out, module
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

  local _, module = exports_of(root, src)
  local blocks = haddocks(root, src)

  -- **The module's own Haddock sits above the `module` keyword**, which is
  -- the closest thing to a file-level doc comment in any of the twenty
  -- backends: it documents the module by construction rather than by
  -- standing in for its first declaration.
  local header = child_of(root, "header")
  local prose = header and doc_above(blocks, header:start()) or ""
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

  local blocks = haddocks(root, src)
  local split = require("documentation.core.scan").split_summary
  local exported = exports_of(root, src)
  local fns, requires, symbols = {}, {}, {}

  ---Whether a top-level name is outside the module's published surface.
  ---
  ---`exported == nil` means the header carried no export list, which
  ---publishes everything — the opposite of an empty list, and the reading
  ---that inverts a module if it is got wrong.
  ---@param name string
  ---@return boolean
  local function is_internal(name)
    if exported == nil then
      return false
    end
    return not exported[name]
  end

  local imports = child_of(root, "imports")
  if imports then
    for imp in imports:iter_children() do
      if imp:type() == "import" then
        local mod = child_of(imp, "module")
        if mod then
          -- Recorded as written. A Haskell import names a module in the
          -- package database, resolved by the build tool against the `.cabal`
          -- file's dependency list — so it is external unless this tree
          -- happens to define the same module, which `by_module` answers
          -- without a guess here.
          requires[#requires + 1] = {
            module = (text_of(mod, src):gsub("%s+", "")),
            line = imp:start() + 1,
          }
        end
      end
    end
  end

  local decls = child_of(root, "declarations")
  if not decls then
    return fns, {}, requires, symbols, {}, {}, lines, {}
  end

  -- **A declaration is two nodes and the doc sits above the first.** `add ::
  -- Int -> Int -> Int` is a `signature`, `add x y = x + y` is a `function`,
  -- and the Haddock block ends one row above the *signature*. So the prose
  -- is collected per name as the signatures go past, and read again when the
  -- definition arrives — the only backend here where the documented node and
  -- the defined node are different.
  local doc_for, sig_row = {}, {}

  for child in decls:iter_children() do
    local kind = child:type()

    if kind == "signature" then
      local var = child_of(child, "variable")
      if var then
        local name = text_of(var, src)
        doc_for[name] = doc_above(blocks, child:start())
        sig_row[name] = child:start()
      end
    elseif kind == "function" or kind == "bind" then
      local var = child_of(child, "variable")
      if var then
        local name = text_of(var, src)
        -- A name may be defined by several equations (Haskell's pattern
        -- matching); the first one is the declaration a reader looks for.
        if not doc_for[name .. "\0seen"] then
          doc_for[name .. "\0seen"] = true
          local prose = doc_for[name] or doc_above(blocks, child:start())
          local row = sig_row[name] or child:start()
          if kind == "bind" and not child_of(child, "patterns") then
            -- `maxCount = 10` binds a value rather than defining a function.
            symbols[#symbols + 1] = {
              name = name,
              kind = "constant",
              detail = (text_of(child, src):gsub("%s+", " ")):sub(1, 60),
              summary = split(prose),
              line = row + 1,
            }
          else
            local patterns = child_of(child, "patterns")
            local names = {}
            if patterns then
              for p in patterns:iter_children() do
                names[#names + 1] = (text_of(p, src):gsub("%s+", " "))
              end
            end
            fns[#fns + 1] = {
              name = name,
              signature = name .. "(" .. table.concat(names, ", ") .. ")",
              line = row + 1,
              line_end = child:end_() + 1,
              summary = split(prose),
              body = prose,
              params = {},
              returns = {},
              internal = is_internal(name),
              see = {},
              overload = {},
              todo = {},
              bug = {},
              test = {},
            }
          end
        end
      end
    elseif
      kind == "data_type"
      or kind == "newtype"
      or kind == "type_synomym"
      or kind == "class"
    then
      local name_node = child_of(child, "name")
      if name_node then
        local name = text_of(name_node, src)
        symbols[#symbols + 1] = {
          name = name,
          kind = "table",
          detail = (kind:gsub("_", " ")),
          summary = split(doc_above(blocks, child:start())),
          line = child:start() + 1,
        }
      end
    end
  end

  return fns, {}, requires, symbols, {}, {}, lines, {}
end

require("documentation.core.lang_registry").register(M.name, M)

return M
