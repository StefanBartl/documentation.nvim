---@module 'documentation.core.lang.java'
--- Java, registered as a language backend.
---
--- **The first backend whose documentation convention is older than this
--- tool and stricter than its own.** Javadoc is not a comment style people
--- agreed on; it is a format with a tool behind it, which means `@param`,
--- `@return`, `@throws` and `@deprecated` are parsed here rather than
--- guessed — and the parse is closer to `ecma.lua`'s JSDoc than to anything
--- else in this directory, because JSDoc is Javadoc's child.
---
--- Three decisions, each of which the next object-oriented backend will
--- face:
---
--- * **`module_tag = false`, and a module name anyway.** Java does declare
---   its own identity — `package a.b.c;` plus the file's own name is the
---   fully qualified type — so `parse_header` reports `a.b.c.Thing`. But it
---   is a language declaration, not a documentation tag, so there is no
---   `missing-module-tag` to report: a file in the default package is legal
---   Java and `check.lua` must not spend a finding on it.
--- * **`module_file = nil`.** A directory is a package and a package is a
---   namespace, not a module. Java has no `init.lua`, and the closest thing
---   — `package-info.java` — documents the package rather than *being* it.
--- * **Visibility is real, and it is four-valued.** `public` is the
---   published surface; `protected`, package-private and `private` are not.
---   `internal = not public` is therefore a fact from the grammar, and the
---   three non-public cases collapse deliberately: the question this tool
---   asks is "is this part of what other code may call", and from outside
---   the package the answer is the same for all three.
---
--- `import a.b.C;` is the require edge. A static import (`import static
--- a.b.C.m;`) names a member rather than a type, and is recorded by its
--- owning type — the edge is between files, and a member is not one.

local M = {}

M.name = "java"

---The tree-sitter grammar this backend parses with.
M.grammar = "java"

---@type string[]
M.extensions = { "java" }

---Java declares its identity in the language, not in a doc tag, so nothing
---tag-shaped can be missing. See this module's header.
M.module_tag = false

---@type string[]
M.line_comments = { "//" }

---@type { [1]: string, [2]: string }[]
M.block_comments = { { "/*", "*/" } }

---@param filename string
---@return boolean
function M.is_source(filename)
  return filename:match("%.java$") ~= nil
end

---Where this backend's sources live under `root`, or `nil`.
---
---Maven and Gradle both put sources at `src/main/java`, and an Android
---module at `app/src/main/java`. Those are checked before a bare `src`
---because a repository with both has the convention, and the convention is
---the more specific answer.
---@param root string
---@return string?
function M.detect_source(root)
  local uv = vim.uv or vim.loop

  ---Whether any `.java` file lives under `dir`, looking three levels deep.
  ---
  ---Java buries its sources under the package path, so a shallow look at
  ---`src/main/java` finds directories and no files. Bounded rather than
  ---unbounded: three levels reaches `com/example/Thing.java`, which is
  ---enough to answer "is there Java under here" without walking a tree
  ---whose size is the reason this check exists.
  ---@param dir string
  ---@return boolean
  local function holds_java(dir)
    local stack, depth = { dir }, { 0 }
    while #stack > 0 do
      local current, d = table.remove(stack), table.remove(depth)
      local fd = uv.fs_scandir(current)
      if fd then
        while true do
          local name, kind = uv.fs_scandir_next(fd)
          if not name then
            break
          end
          if kind == "directory" then
            if d < 3 then
              stack[#stack + 1] = current .. "/" .. name
              depth[#depth + 1] = d + 1
            end
          elseif M.is_source(name) then
            return true
          end
        end
      end
    end
    return false
  end

  for _, candidate in ipairs({
    "src/main/java",
    "app/src/main/java",
    "src/java",
    "src",
    "java",
  }) do
    if holds_java(root .. "/" .. candidate) then
      return candidate
    end
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

---Javadoc text with its frame removed.
---
---`/**`, the leading `*` of each continuation line and the closing `*/` are
---punctuation of the format rather than content. Removed here so every
---reader below this line sees prose.
---@param raw string
---@return string
local function undecorate(raw)
  local body = raw:gsub("^/%*%*?", ""):gsub("%*/%s*$", "")
  local out = {}
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do
    out[#out + 1] = (line:gsub("^%s*%*%s?", ""):gsub("%s+$", ""))
  end
  -- Blank first and last lines belong to the format, not to the author.
  while out[1] == "" do
    table.remove(out, 1)
  end
  while out[#out] == "" do
    table.remove(out)
  end
  return table.concat(out, "\n")
end

---A Javadoc block, split into prose and the tags below it.
---
---The block tags are the part this must not guess at: `@param name text`
---and `@return text` are a contract Javadoc has enforced for decades, and a
---tool that re-derived parameters from the signature instead would report a
---parameter list nobody wrote a word about as fully documented.
---@param raw string
---@return { summary: string, body: string, params: table[], returns: table[], deprecated: string?, see: string[], todo: string[] }
local function parse_doc(raw)
  local text = undecorate(raw)
  local prose, params, returns, see, todo = {}, {}, {}, {}, {}
  local deprecated = nil
  ---The tag a continuation line belongs to, or `nil` inside the prose.
  local current = nil

  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local tag, rest = line:match("^%s*@(%a+)%s*(.*)$")
    if tag == "param" then
      local name, desc = rest:match("^([%w_$]+)%s*(.*)$")
      if name then
        params[#params + 1] = { name = name, type = "", optional = false, desc = desc or "" }
        current = params[#params]
      end
    elseif tag == "return" or tag == "returns" then
      returns[#returns + 1] = { type = "", desc = rest }
      current = returns[#returns]
    elseif tag == "throws" or tag == "exception" then
      -- Kept as prose rather than given a field of its own: nothing in the
      -- artifact models a thrown type today, and inventing a field the page
      -- cannot render would be a schema change with no reader.
      prose[#prose + 1] = "@throws " .. rest
      current = nil
    elseif tag == "deprecated" then
      deprecated = rest
      current = nil
    elseif tag == "see" then
      see[#see + 1] = rest
      current = nil
    elseif tag == "todo" then
      todo[#todo + 1] = rest
      current = nil
    elseif tag then
      current = nil
    elseif current and line:match("%S") then
      -- A continuation of the tag above, which Javadoc allows and authors
      -- use for anything longer than a phrase.
      current.desc = (current.desc == "" and "" or current.desc .. " ") .. line:gsub("^%s+", "")
    else
      prose[#prose + 1] = line
    end
  end

  while prose[#prose] == "" do
    table.remove(prose)
  end
  local body = table.concat(prose, "\n")
  return {
    summary = require("documentation.core.scan").split_summary(body),
    body = body,
    params = params,
    returns = returns,
    deprecated = deprecated,
    see = see,
    todo = todo,
  }
end

---Every Javadoc block in the tree, by the row it ends on.
---
---Keyed by the *last* row rather than the first: what a block documents is
---the declaration under it, and only its end is a fixed distance away.
---@param root TSNode
---@param src string
---@return table<integer, string>
local function javadoc(root, src)
  local blocks = {}
  local function walk(node)
    local kind = node:type()
    if kind == "block_comment" or kind == "comment" then
      local _, _, sbyte = node:start()
      local erow, _, ebyte = node:end_()
      local text = src:sub(sbyte + 1, ebyte)
      if text:match("^/%*%*") then
        blocks[erow] = text
      end
      return
    end
    if kind == "line_comment" then
      return
    end
    for child in node:iter_children() do
      walk(child)
    end
  end
  walk(root)
  return blocks
end

---The Javadoc block ending directly above `row`, if any.
---
---Directly, with a little slack: an annotation between the block and the
---declaration is common enough (`@Override` above every second method)
---that demanding adjacency would lose most real documentation. Small on
---purpose — annotations belong to the declaration node itself, so the slack
---covers formatting rather than distance.
---
---**A block is consumed when it is taken**, and that is not a refinement:
---without it, three lines of slack reach *past* one declaration to the
---next. Found on fields, where it is immediate — a one-line field two rows
---below a documented one inherited its Javadoc — and latent on methods only
---because a method body puts more than three rows between them. A Javadoc
---block documents exactly one declaration, so taking it twice is always
---wrong, and consuming says that in one line rather than by teaching this
---function what a declaration looks like.
---
---Safe because the walk is depth-first in source order, so blocks are asked
---for in the order they appear. `parse_header` builds its own table and is
---unaffected.
---@param blocks table<integer, string>
---@param row integer
---@return string?
local function doc_above(blocks, row)
  for r = row - 1, math.max(row - 3, 0), -1 do
    if blocks[r] then
      local block = blocks[r]
      blocks[r] = nil
      return block
    end
  end
  return nil
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

---Whether a declaration is `public`.
---
---Read off the `modifiers` node rather than the declaration's text: a
---`private` method whose Javadoc happens to contain the word "public" must
---not count as published, and text matching cannot tell those apart.
---@param node TSNode
---@param src string
---@return boolean
local function is_public(node, src)
  local mods = child_of(node, "modifiers")
  if not mods then
    return false
  end
  for child in mods:iter_children() do
    if text_of(child, src) == "public" then
      return true
    end
  end
  return false
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

  -- The fully qualified name, which Java states outright and most languages
  -- here only imply: `package a.b.c;` plus this file's own stem.
  local package = nil
  for child in root:iter_children() do
    if child:type() == "package_declaration" then
      package = text_of(child, src):match("^package%s+([%w_.]+)")
      break
    end
  end
  local stem = path:match("([^/\\]+)%.java$")
  local module = nil
  if stem then
    module = package and (package .. "." .. stem) or stem
  end

  -- Java has no file-level doc comment, so the Javadoc above the file's
  -- first type is the closest true answer rather than an invented one.
  local blocks = javadoc(root, src)
  local doc = nil
  for child in root:iter_children() do
    local kind = child:type()
    if
      kind == "class_declaration"
      or kind == "interface_declaration"
      or kind == "enum_declaration"
      or kind == "record_declaration"
      or kind == "annotation_type_declaration"
    then
      doc = doc_above(blocks, child:start())
      break
    end
  end
  if not doc then
    return { module = module, summary = "", body = "", tags = {} }
  end
  local parsed = parse_doc(doc)
  return {
    module = module,
    summary = parsed.summary,
    body = parsed.body,
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

  local blocks = javadoc(root, src)
  local fns, requires, symbols = {}, {}, {}

  ---The type a method belongs to, so two `get()` methods in one file are
  ---two names rather than one repeated. Java allows several types per file
  ---and inner types are ordinary, so this is not the rare case it looks
  ---like.
  ---@param node TSNode
  ---@return string? name
  ---@return Documentation.ScopeKind? kind Which of the four declarations it was. A `record` is reported as a `class`: `Documentation.ScopeKind` names constructs that group methods differently, and a record groups them exactly as a class does.
  local function owner(node)
    local parent = node:parent()
    while parent do
      local kind = parent:type()
      if
        kind == "class_declaration"
        or kind == "interface_declaration"
        or kind == "enum_declaration"
        or kind == "record_declaration"
      then
        local name = child_of(parent, "identifier")
        if not name then
          return nil, nil
        end
        return text_of(name, src),
          kind == "interface_declaration" and "interface"
            or kind == "enum_declaration" and "enum"
            or "class"
      end
      parent = parent:parent()
    end
    return nil, nil
  end

  ---@param node TSNode
  ---@param name_node TSNode
  ---@param is_ctor boolean
  local function record(node, name_node, is_ctor)
    local srow = node:start()
    local erow = node:end_()
    local name = text_of(name_node, src)
    local params_node = child_of(node, "formal_parameters")
    local signature = name .. (params_node and text_of(params_node, src) or "()")
    local qualified, owner_kind = owner(node)
    local doc = doc_above(blocks, srow)
    local parsed = doc and parse_doc(doc)
      or { summary = "", body = "", params = {}, returns = {}, see = {}, todo = {} }

    fns[#fns + 1] = {
      -- A constructor is already named after its type; qualifying it would
      -- read `Thing.Thing`.
      name = (qualified and not is_ctor) and (qualified .. "." .. name) or name,
      signature = signature,
      line = srow + 1,
      line_end = erow + 1,
      summary = parsed.summary,
      body = parsed.body,
      params = parsed.params,
      returns = parsed.returns,
      deprecated = parsed.deprecated,
      -- Four visibilities collapse to two; see this module's header.
      internal = not is_public(node, src),
      -- Set for a constructor too, whose `name` above is deliberately *not*
      -- qualified — which is the clearest case in any of these backends for
      -- why the owner has to be its own field rather than a name prefix.
      owner = qualified,
      owner_kind = qualified and owner_kind or nil,
      see = parsed.see,
      overload = {},
      todo = parsed.todo,
      bug = {},
      test = {},
    }
  end

  local function walk(node)
    local kind = node:type()

    if kind == "method_declaration" then
      local name_node = child_of(node, "identifier")
      if name_node then
        record(node, name_node, false)
      end
    elseif kind == "constructor_declaration" then
      local name_node = child_of(node, "identifier")
      if name_node then
        record(node, name_node, true)
      end
    elseif kind == "field_declaration" then
      -- **A Java field is the module-scope binding**, because Java has no
      -- module scope: everything lives in a type, and a type's fields are
      -- what `core/symbols.lua` reports for Lua's `local M = {}` and its
      -- constants. Qualified with the owning type for the same reason the
      -- methods above are — two `MAX` fields in two inner classes are two
      -- symbols, not one repeated.
      --
      -- `static final` is the constant, everything else a binding. That is
      -- the language's own distinction rather than a guess at intent: a
      -- non-final field can be reassigned and a `final` instance field is
      -- per-object state, neither of which is what "constant" means in the
      -- other twenty-two backends.
      local declarator = child_of(node, "variable_declarator")
      local name_node = declarator and child_of(declarator, "identifier")
      if name_node then
        local mods = child_of(node, "modifiers")
        local mod_text = mods and text_of(mods, src) or ""
        local qualified = owner(node)
        local bare = text_of(name_node, src)
        local whole = (text_of(node, src):gsub("%s+", " "):gsub(";%s*$", ""))
        symbols[#symbols + 1] = {
          name = qualified and (qualified .. "." .. bare) or bare,
          kind = (mod_text:match("%f[%w]static%f[%W]") and mod_text:match("%f[%w]final%f[%W]"))
              and "constant"
            or "binding",
          detail = whole:sub(1, 60),
          -- The Javadoc's first sentence, run through the same parser the
          -- methods use rather than taken raw: a field's block carries the
          -- `*` gutter and tags exactly as a method's does, and showing it
          -- unparsed would put a row of asterisks in the Index tab.
          summary = (function()
            local doc = doc_above(blocks, node:start())
            return doc and parse_doc(doc).summary or ""
          end)(),
          line = node:start() + 1,
        }
      end
    elseif kind == "import_declaration" then
      local raw = text_of(node, src)
      -- A static import names a member; the edge is between files, so it is
      -- recorded against the type that owns the member rather than dropped.
      local target = raw:match("^import%s+static%s+([%w_.]+)%.[%w_*]+%s*;")
        or raw:match("^import%s+([%w_.]+)%s*;")
      if target then
        target = target:gsub("%.%*$", "")
        requires[#requires + 1] = { module = target, line = node:start() + 1 }
      end
      return
    end

    for child in node:iter_children() do
      walk(child)
    end
  end
  walk(root)

  return fns, {}, requires, symbols, {}, {}, lines, {}
end

require("documentation.core.lang_registry").register(M.name, M)

return M
