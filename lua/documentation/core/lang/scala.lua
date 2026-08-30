---@module 'documentation.core.lang.scala'
--- Scala, registered as a language backend — the nineteenth, and the last of
--- the ten in `MULTILANG.md`'s first wave.
---
--- **Qualified visibility, which only Rust has anything like.** Scala writes
--- `private[widgets]` and `protected[api]` — private *to a named scope*
--- rather than absolutely. It is Rust's `pub(crate)`/`pub(in path)` read from
--- the other end: Rust says how far out a thing reaches, Scala says how far
--- in it stays. Both collapse into not-published here for the same reason —
--- from outside, a restriction is a restriction.
---
--- The default is `public`, which puts Scala with Kotlin and PHP rather than
--- with C# or Java, so the rule is written as *not private and not
--- protected* and never as *has `public`* — there is no `public` keyword in
--- Scala at all, so asking for one would report every codebase as
--- unpublished.
---
--- **Scaladoc is Javadoc's descendant** and parses the same way, with one
--- addition worth naming: `@tparam` documents a *type* parameter. It is read
--- as a parameter, because that is what it is — a Scala generic is declared
--- and documented exactly like a value parameter, and dropping it would
--- leave the collection library's most-documented declarations looking bare.
---
--- **A class's constructor parameters are its fields**, the same shape
--- Kotlin's primary constructor has, and they are recorded as symbols for the
--- same reason: in a `case class` they are the whole of the type's surface.
---
--- **`package a.b` plus the file stem** gives a module name Scala does not
--- guarantee — several top-level definitions per file are ordinary, and a
--- file need not be named after any of them. It is still derived and still
--- recorded, for the reason Java's and Kotlin's are: `import a.b.Thing`
--- names a declaration, and in every project that follows the convention it
--- is where that declaration lives. Where a project does not, the edge does
--- not resolve, which under-claims rather than pointing somewhere wrong.

local M = {}

M.name = "scala"

M.grammar = "scala"

---@type string[]
M.extensions = { "scala", "sc" }

---A package clause is a language construct rather than a documentation tag.
M.module_tag = false

---@type string[]
M.line_comments = { "//" }

---@type { [1]: string, [2]: string }[]
M.block_comments = { { "/*", "*/" } }

---Scaladoc's `@param` names each parameter individually, as Javadoc's does.
M.param_docs = true

---@param filename string
---@return boolean
function M.is_source(filename)
  return filename:match("%.scala$") ~= nil or filename:match("%.sc$") ~= nil
end

---Where this backend's sources live under `root`, or `nil`.
---
---`src/main/scala` is sbt's layout and is what nearly every project uses.
---The shallower fallbacks come after it, because a `src/` holding only that
---directory would otherwise answer `nil`.
---@param root string
---@return string?
function M.detect_source(root)
  local uv = vim.uv or vim.loop

  ---@param dir string
  ---@param depth integer
  ---@return boolean
  local function holds_scala(dir, depth)
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
      if kind == "directory" and name:sub(1, 1) ~= "." and name ~= "target" then
        subdirs[#subdirs + 1] = dir .. "/" .. name
      end
    end
    if depth > 0 then
      for _, sub in ipairs(subdirs) do
        if holds_scala(sub, depth - 1) then
          return true
        end
      end
    end
    return false
  end

  for _, candidate in ipairs({ "src/main/scala", "shared/src/main/scala", "src", "core" }) do
    if holds_scala(root .. "/" .. candidate, 2) then
      return candidate
    end
  end
  if holds_scala(root, 1) then
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

---Every Scaladoc block in the file, keyed by the row it ends on.
---
---Only `/** … */`. Scaladoc has a generator behind it and `/**` is what
---every Scala project writes, so the strict rule costs nothing here — the
---same position PHP's and Kotlin's backends take, and the opposite of the
---one C had to be given.
---@param root userdata
---@param src string
---@return table<integer, string>
local function doc_blocks(root, src)
  local by_row = {}
  local function walk(node)
    local kind = node:type()
    if kind == "block_comment" or kind == "comment" then
      local text = text_of(node, src)
      if text:match("^/%*%*") then
        by_row[node:end_()] = text
      end
      return
    end
    for child in node:iter_children() do
      walk(child)
    end
  end
  walk(root)
  return by_row
end

---A Scaladoc block, parsed.
---
---Javadoc's shape. `@tparam` is folded in beside `@param`: a Scala type
---parameter is declared and documented exactly like a value parameter, and
---dropping it would leave the most carefully documented declarations in the
---standard library looking bare.
---@param text string?
---@return { summary: string, body: string, params: Documentation.ParamInfo[], returns: Documentation.ReturnInfo[], deprecated: string? }
local function parse_doc(text)
  local empty = { summary = "", body = "", params = {}, returns = {} }
  if not text then
    return empty
  end

  local params, returns, prose = {}, {}, {}
  local deprecated = nil
  local current = nil

  local body = text:gsub("^/%*%*", ""):gsub("%*/$", "")
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do
    local stripped = line:gsub("^%s*%*?%s?", ""):gsub("%s+$", "")
    local tag, rest = stripped:match("^@(%a[%w_]*)%s*(.*)$")
    if tag then
      tag = tag:lower()
      if tag == "param" or tag == "tparam" then
        local name, desc = rest:match("^([%w_]+)%s*(.*)$")
        if name then
          current = { name = name, type = "", desc = desc or "" }
          params[#params + 1] = current
        else
          current = nil
        end
      elseif tag == "return" then
        current = { type = "", desc = rest }
        returns[#returns + 1] = current
      elseif tag == "deprecated" then
        deprecated = rest ~= "" and rest or "deprecated"
        current = nil
      else
        -- `@throws`, `@see`, `@note`, `@example`, `@group` and the rest of a
        -- vocabulary Scaladoc keeps growing. Recognised so their text stays
        -- out of the prose, not modelled.
        current = nil
      end
    elseif current and stripped ~= "" then
      current.desc = (current.desc == "" and "" or current.desc .. " ") .. stripped:gsub("^%s+", "")
    elseif not current then
      prose[#prose + 1] = stripped
    end
  end

  while prose[1] == "" do
    table.remove(prose, 1)
  end
  while prose[#prose] == "" do
    table.remove(prose)
  end
  local text_body = table.concat(prose, "\n")
  return {
    summary = require("documentation.core.scan").split_summary(text_body),
    body = text_body,
    params = params,
    returns = returns,
    deprecated = deprecated,
  }
end

---Whether a definition is outside the published surface.
---
---**Qualified visibility is the interesting part.** `private[widgets]` is
---private *to a named scope* rather than absolutely — which is Rust's
---`pub(crate)` read from the other end: Rust says how far out a thing
---reaches, Scala says how far in it stays. Both collapse into not-published,
---because from outside a restriction is a restriction.
---
---Written as *not private and not protected*: **Scala has no `public`
---keyword at all**, so asking for one would report every codebase as
---unpublished — the mistake C# taught this tool to fear, in a language where
---the keyword does not even exist.
---@param node userdata
---@param src string
---@param inherited boolean? A trait member's visibility, when inside one.
---@return boolean
local function is_internal(node, src, inherited)
  local mods = child_of(node, "modifiers")
  if not mods then
    -- A bare `private def` may put the keyword directly on the definition
    -- rather than in a `modifiers` node, so the head of the text is checked
    -- as well.
    local head = text_of(node, src):sub(1, 40)
    if head:match("^%s*private") or head:match("^%s*protected") then
      return true
    end
    if inherited ~= nil then
      return inherited
    end
    return false
  end
  local text = text_of(mods, src)
  return text:match("%f[%w]private%f[%W]") ~= nil or text:match("%f[%w]protected%f[%W]") ~= nil
end

---@param node userdata The definition; its parameter list is a child.
---@param src string
---@return string[]
local function param_names(node, src)
  local out = {}
  for list in node:iter_children() do
    local lk = list:type()
    if lk == "parameters" or lk == "class_parameters" then
      for child in list:iter_children() do
        local ck = child:type()
        if ck == "parameter" or ck == "class_parameter" then
          local id = child_of(child, "identifier")
          if id then
            out[#out + 1] = text_of(id, src)
          end
        end
      end
    end
  end
  return out
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

  local clause = child_of(root, "package_clause")
  local name = clause and child_of(clause, "package_identifier")
  local package = name and (text_of(name, src):gsub("%s+", "")) or nil
  local stem = path:match("([^/\\]+)%.scala$") or path:match("([^/\\]+)%.sc$")
  local module = (package and stem) and (package .. "." .. stem) or nil

  -- **The first *type*, not the first definition** — the rule Kotlin's
  -- fixture forced. A top-level `val` above the class is ordinary in Scala
  -- too, and taking its doc block would make the file's summary a sentence
  -- about a constant.
  local blocks = doc_blocks(root, src)
  local first_doc = nil
  for child in root:iter_children() do
    local kind = child:type()
    if
      kind == "class_definition"
      or kind == "object_definition"
      or kind == "trait_definition"
      or kind == "enum_definition"
    then
      first_doc = blocks[child:start() - 1]
      break
    end
  end

  local doc = parse_doc(first_doc)
  if doc.summary == "" and not module then
    return empty
  end
  return { module = module, summary = doc.summary, body = doc.body, tags = {} }
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

  local blocks = doc_blocks(root, src)
  local fns, requires, symbols = {}, {}, {}

  ---@param node userdata `function_definition`
  ---@param owner string?
  ---@param inherited boolean?
  ---@param owner_kind Documentation.ScopeKind? Which definition `owner` is. Passed down like `inherited`: the node kind is `record_type`'s to read, not this one's to rediscover from a parent walk.
  local function record_function(node, owner, inherited, owner_kind)
    local name_node = child_of(node, "identifier") or child_of(node, "operator_identifier")
    if not name_node then
      return
    end
    local bare = text_of(name_node, src)
    local qualified = owner and (owner .. "." .. bare) or bare
    local doc = parse_doc(blocks[node:start() - 1])
    local names = param_names(node, src)
    fns[#fns + 1] = {
      name = qualified,
      signature = qualified .. "(" .. table.concat(names, ", ") .. ")",
      line = node:start() + 1,
      line_end = node:end_() + 1,
      summary = doc.summary,
      body = doc.body,
      params = doc.params,
      returns = doc.returns,
      deprecated = doc.deprecated,
      internal = is_internal(node, src, inherited),
      owner = owner,
      owner_kind = owner and (owner_kind or "class") or nil,
      see = {},
      overload = {},
      todo = {},
      bug = {},
      test = {},
    }
  end

  ---@param node userdata `val_definition` / `var_definition`
  ---@param owner string?
  local function record_value(node, owner)
    local id = child_of(node, "identifier")
    if not id then
      return
    end
    local bare = text_of(id, src)
    local doc = parse_doc(blocks[node:start() - 1])
    symbols[#symbols + 1] = {
      name = owner and (owner .. "." .. bare) or bare,
      kind = node:type() == "val_definition" and "constant" or "binding",
      detail = (text_of(node, src):gsub("%s+", " ")):sub(1, 60),
      summary = doc.summary,
      line = node:start() + 1,
    }
  end

  ---@param node userdata A type definition.
  local function record_type(node)
    local name_node = child_of(node, "identifier") or child_of(node, "type_identifier")
    if not name_node then
      return
    end
    local bare = text_of(name_node, src)
    local kind = node:type()
    local doc = parse_doc(blocks[node:start() - 1])
    local head = text_of(node, src):sub(1, 60)
    symbols[#symbols + 1] = {
      name = bare,
      kind = "table",
      detail = head:match("%f[%w](case class)%f[%W]") and "case class"
        or (kind:gsub("_definition$", "")),
      summary = doc.summary,
      line = node:start() + 1,
    }

    -- **A trait member carries no modifier and is public** — the seventh
    -- language in a row to need this: C#, Go, Rust, PHP, Kotlin, Swift, and
    -- now Scala. Scala's default is public anyway, so this only matters for
    -- the sake of saying so.
    local inherited = nil
    if kind == "trait_definition" then
      inherited = false
    end

    -- A `case class` is a class here for the same reason a Java record is:
    -- it groups its members identically and differs in what the compiler
    -- generates around them.
    ---@type Documentation.ScopeKind
    local owner_kind = kind == "trait_definition" and "trait"
      or kind == "object_definition" and "object"
      or "class"

    -- A class's constructor parameters are its fields, the shape Kotlin's
    -- primary constructor has — and in a `case class` they are the whole of
    -- the type's surface.
    for child in node:iter_children() do
      if child:type() == "class_parameters" then
        for param in child:iter_children() do
          if param:type() == "class_parameter" then
            local pid = child_of(param, "identifier")
            if pid then
              symbols[#symbols + 1] = {
                name = bare .. "." .. text_of(pid, src),
                kind = "binding",
                detail = (text_of(param, src):gsub("%s+", " ")):sub(1, 60),
                summary = "",
                line = param:start() + 1,
              }
            end
          end
        end
      end
    end

    local body = child_of(node, "template_body")
    if body then
      for member in body:iter_children() do
        local mk = member:type()
        if mk == "function_definition" or mk == "function_declaration" then
          record_function(member, bare, inherited, owner_kind)
        elseif mk == "val_definition" or mk == "var_definition" then
          record_value(member, bare)
        end
      end
    end
  end

  for child in root:iter_children() do
    local kind = child:type()
    if kind == "import_declaration" then
      -- The whole dotted path, minus the `import` keyword and any brace
      -- selector: `import a.b.{C, D}` is one edge to `a.b`, the same
      -- reduction Rust's use-list needed.
      local text = text_of(child, src):gsub("^import%s+", ""):gsub("%s+", "")
      text = text:gsub("%.%b{}$", ""):gsub("%._$", "")
      if text ~= "" then
        requires[#requires + 1] = { module = text, line = child:start() + 1 }
      end
    elseif
      kind == "class_definition"
      or kind == "object_definition"
      or kind == "trait_definition"
      or kind == "enum_definition"
    then
      record_type(child)
    elseif kind == "function_definition" then
      record_function(child, nil, nil)
    elseif kind == "val_definition" or kind == "var_definition" then
      record_value(child, nil)
    elseif kind == "package_clause" then
      -- A `package a.b { … }` block nests its definitions one level down.
      local body = child_of(child, "template_body")
      if body then
        for member in body:iter_children() do
          local mk = member:type()
          if
            mk == "class_definition"
            or mk == "object_definition"
            or mk == "trait_definition"
            or mk == "enum_definition"
          then
            record_type(member)
          end
        end
      end
    end
  end

  return fns, {}, requires, symbols, {}, {}, lines, {}
end

require("documentation.core.lang_registry").register(M.name, M)

return M
