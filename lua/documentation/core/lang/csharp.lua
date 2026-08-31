---@module 'documentation.core.lang.csharp'
--- C#, registered as a language backend — the eleventh, and the first whose
--- documentation format is **markup** rather than tags or prose.
---
--- **Three kinds of documentation convention now exist in this tool, and C#
--- is the third.** LuaCATS, JSDoc, Javadoc and Doxygen are *tag* formats: a
--- sigil, a name, a description. Python's docstrings are *prose with
--- sections*. C# is XML — `<summary>`, `<param name="x">`, `<returns>` — a
--- document embedded in a comment, with attributes rather than positions
--- carrying the parameter name. It is also the strictest of the three about
--- what a thing is called: `<param name="x">` states which parameter it
--- documents outright, where Javadoc's `@param x` relies on the first word
--- and a docstring on a section's layout.
---
--- Parsed with patterns rather than an XML parser, and the reason is what
--- these comments actually are: not a document but a *fragment*, frequently
--- unbalanced, with `<see cref="T"/>` and `<c>code</c>` scattered through the
--- prose. A real XML parser would reject half the doc comments in a real C#
--- project as malformed, which is a worse answer than reading the elements
--- that carry meaning and leaving the rest as text.
---
--- **Visibility is four keywords and a default, and the default is the part
--- worth stating — because there are two of them.** `public` is published;
--- `internal`, `protected` and `private` are not. A *class* member with no
--- modifier is **private**, so an unmarked method is not "the author did not
--- say", it is the author saying private by omission. An *interface* member
--- with no modifier is **public**, because an interface is nothing but
--- published surface.
---
--- Missing that second default is not a near miss, and the fixture exists to
--- catch it: applying the class rule everywhere reported every method of
--- every interface as internal — the exact inversion of the truth, on the one
--- construct that exists to declare a published API.
---
--- Four-valued collapsing to two, exactly as Java's did, and for the same
--- reason: from outside the assembly, `internal`, `protected` and `private`
--- answer alike.
---
--- **The namespace gives a fully qualified module name** — `namespace A.B;`
--- plus the file stem — which is the shape `java.lua` established and the
--- second language to offer it. `module_tag` stays `false`: a namespace
--- declaration is a language construct, not a documentation tag, and a file
--- in the global namespace is legal.
---
--- **What `using` cannot do, stated rather than discovered.** A `using`
--- names a *namespace*, not a file — unlike Java's `import a.b.C`, which
--- names a class and therefore a compilation unit. So a `using` recorded here
--- almost never resolves to a node in the scanned tree, and the Deps view of
--- a C# project is mostly external edges. That is the honest reading: the
--- edge C# actually has at file level is a type reference, which needs the
--- resolution pass this pipeline does not run. Recorded as written, the same
--- way C records `#include <stdio.h>`.

local M = {}

M.name = "csharp"

---The grammar is `c_sharp` and the backend is `csharp` — one of the several
---places the two genuinely differ, which is why `grammar` is a field rather
---than derived from `name`.
M.grammar = "c_sharp"

---@type string[]
M.extensions = { "cs" }

---A namespace declaration is a language construct, not a documentation tag,
---and a file in the global namespace is legal — so nothing tag-shaped can be
---missing. The module name is still fully qualified; see `parse_header`.
M.module_tag = false

---@type string[]
M.line_comments = { "//" }

---@type { [1]: string, [2]: string }[]
M.block_comments = { { "/*", "*/" } }

---`<param name="x">` names each parameter individually, so the strict rule
---applies.
M.param_docs = true

---@param filename string
---@return boolean
function M.is_source(filename)
  return filename:match("%.cs$") ~= nil
end

---Where this backend's sources live under `root`, or `nil`.
---
---`src/` first: it is the layout every `dotnet new` template and every
---sizeable repository uses, with the project directory beneath it. The root
---itself is the fallback for a single-project checkout.
---@param root string
---@return string?
function M.detect_source(root)
  local uv = vim.uv or vim.loop

  ---Whether `dir`, or any directory one level inside it, holds a `.cs` file.
  ---One level rather than a full walk: a C# solution puts each project in
  ---its own directory under `src/`, so the extension never appears in `src/`
  ---itself and a shallow check there would answer `nil` for the standard
  ---layout.
  ---@param dir string
  ---@param depth integer
  ---@return boolean
  local function holds_cs(dir, depth)
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
      if kind == "directory" and name:sub(1, 1) ~= "." and name ~= "bin" and name ~= "obj" then
        subdirs[#subdirs + 1] = dir .. "/" .. name
      end
    end
    if depth > 0 then
      for _, sub in ipairs(subdirs) do
        if holds_cs(sub, depth - 1) then
          return true
        end
      end
    end
    return false
  end

  for _, candidate in ipairs({ "src", "source", "lib" }) do
    if holds_cs(root .. "/" .. candidate, 1) then
      return candidate
    end
  end
  if holds_cs(root, 1) then
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

---Every `///` documentation comment in the tree, joined into one block per
---run and keyed by the row the run *ends* on.
---
---Keyed by the last row because that is what a lookup has: a declaration
---knows the row above it, not where the comment run began. The same index
---`cfamily.lua` builds, for the same reason.
---
---`//` alone is not documentation. C# is explicit about this — the compiler
---extracts `///` and ignores `//` — so unlike C, where a plain comment above
---a declaration had to be accepted because real code writes nothing else,
---there is a real convention here and reading only it costs nothing.
---@param root TSNode
---@param src string
---@return table<integer, string[]>
local function doc_blocks(root, src)
  local by_row = {}
  local function walk(node)
    if node:type() == "comment" then
      local srow = node:start()
      local text = text_of(node, src)
      local body = text:match("^///+%s?(.*)$")
      if body then
        -- Each `///` line is its own comment node, so a block is a run of
        -- consecutive rows. Joined by looking one row back rather than by a
        -- second pass.
        local previous = by_row[srow - 1]
        if previous then
          by_row[srow - 1] = nil
          previous[#previous + 1] = body
          by_row[srow] = previous
        else
          by_row[srow] = { body }
        end
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

---The documentation block directly above `row`, or `nil`.
---@param blocks table<integer, string[]>
---@param row integer 0-based row of the documented declaration.
---@return string[]?
local function doc_above(blocks, row)
  return blocks[row - 1]
end

---Strip the XML markup that decorates prose without carrying structure.
---
---`<see cref="Foo"/>` and `<paramref name="x"/>` are references, `<c>` and
---`<code>` are formatting: all of them say something the IR has no field
---for, and leaving the raw tags in would put angle brackets in every
---summary. The *referenced name* is kept, because that is the part a reader
---was meant to see.
---@param text string
---@return string
local function strip_markup(text)
  local out = text
  out = out:gsub('<see%s+cref%s*=%s*"([^"]*)"%s*/?>', "%1")
  out = out:gsub('<paramref%s+name%s*=%s*"([^"]*)"%s*/?>', "%1")
  out = out:gsub('<typeparamref%s+name%s*=%s*"([^"]*)"%s*/?>', "%1")
  out = out:gsub("</?c>", "")
  out = out:gsub("</?code>", "")
  out = out:gsub("</?para>", " ")
  out = out:gsub('<see%s+langword%s*=%s*"([^"]*)"%s*/?>', "%1")
  return (out:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

---A `///` block, read as the XML fragment it is.
---
---**Patterns rather than an XML parser, and it is not a shortcut.** These
---comments are fragments, not documents: unbalanced tags, bare `&`, and
---`<see cref="T"/>` mid-sentence are all ordinary. An XML parser would
---reject a large share of the doc comments in any real C# project, and
---rejecting a comment because its markup is imperfect is a worse answer than
---reading the elements that carry meaning.
---@param lines string[]?
---@return { summary: string, body: string, params: Documentation.ParamInfo[], returns: Documentation.ReturnInfo[] }
local function parse_doc(lines)
  local empty = { summary = "", body = "", params = {}, returns = {} }
  if not lines or #lines == 0 then
    return empty
  end
  local blob = table.concat(lines, "\n")

  local params = {}
  -- `%b<>` is not usable here — the content may itself contain `<see .../>`
  -- — so the closing tag is matched by name instead.
  for name, body in blob:gmatch('<param%s+name%s*=%s*"([^"]*)"%s*>(.-)</param>') do
    params[#params + 1] = { name = name, type = "", desc = strip_markup(body) }
  end

  local returns = {}
  local ret = blob:match("<returns%s*>(.-)</returns>")
  if ret then
    returns[#returns + 1] = { type = "", desc = strip_markup(ret) }
  end

  local summary_block = blob:match("<summary%s*>(.-)</summary>")
  local remarks = blob:match("<remarks%s*>(.-)</remarks>")

  local prose
  if summary_block then
    prose = strip_markup(summary_block)
    if remarks then
      prose = prose .. "\n" .. strip_markup(remarks)
    end
  else
    -- No `<summary>` at all: a `///` comment that is plain prose, which the
    -- compiler would warn about but which people write. Read as prose rather
    -- than discarded — the author documented the thing, just not in the
    -- shape the tool expected, and that is the C lesson.
    local text = blob:gsub("<[^>]*>", " ")
    prose = strip_markup(text)
  end

  local summary = require("documentation.core.scan").split_summary(prose)
  return { summary = summary, body = prose, params = params, returns = returns }
end

---The modifiers on a declaration node, as a set.
---@param node TSNode
---@param src string
---@return table<string, boolean>
local function modifiers(node, src)
  local out = {}
  for child in node:iter_children() do
    if child:type() == "modifier" then
      out[text_of(child, src)] = true
    end
  end
  return out
end

---Whether a declaration is published.
---
---**The absence of a modifier is meaningful, and what it means depends on
---where the declaration sits.** A class member with no access modifier is
---*private* — so an unmarked method is not "the author did not say", it is
---the author saying private by omission. An **interface** member with no
---modifier is *public*, because an interface is nothing but published
---surface; C# 8 allows `private` there and it has to be written out.
---
---Getting that second rule wrong is not a near miss. The first version of
---this function applied the class default everywhere, and every method of
---every interface in every C# project came back internal — the exact
---inversion of the truth, on the one construct that exists to declare a
---published API. Caught by the fixture, which is why the fixture has an
---interface in it.
---
---The four keywords collapse to two for the reason Java's did: from outside
---the assembly, `internal`, `protected` and `private` answer alike.
---@param mods table<string, boolean>
---@param owner_kind string? The declaring type's node kind, when there is one.
---@return boolean
local function is_internal(mods, owner_kind)
  if owner_kind == "interface_declaration" then
    return mods.private == true or mods.internal == true or mods.protected == true
  end
  return not mods.public
end

---The declaration node's own name.
---@param node TSNode
---@param src string
---@return string?
local function name_of(node, src)
  local id = child_of(node, "identifier")
  return id and text_of(id, src)
end

---@param node TSNode `parameter_list`
---@param src string
---@return string[]
local function param_names(node, src)
  local out = {}
  if not node then
    return out
  end
  for child in node:iter_children() do
    if child:type() == "parameter" then
      local id = child_of(child, "identifier")
      if id then
        out[#out + 1] = text_of(id, src)
      end
    end
  end
  return out
end

---The namespace declared in this file, or `nil`.
---
---Both spellings: `namespace A.B;` (file-scoped, the modern default) and
---`namespace A.B { … }` (block). The first is looked for first because it is
---what a new file gets.
---@param root TSNode
---@param src string
---@return string?
---@return TSNode? body The node whose children hold the types.
local function namespace_of(root, src)
  for child in root:iter_children() do
    local kind = child:type()
    if kind == "file_scoped_namespace_declaration" then
      local name = child_of(child, "qualified_name") or child_of(child, "identifier")
      return name and text_of(name, src), root
    end
    if kind == "namespace_declaration" then
      local name = child_of(child, "qualified_name") or child_of(child, "identifier")
      return name and text_of(name, src), child_of(child, "declaration_list")
    end
  end
  return nil, root
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

  local ns = namespace_of(root, src)
  -- `namespace A.B;` plus the file stem, the shape `java.lua` established.
  -- A file with no namespace keeps `nil` rather than being given its bare
  -- stem, which would claim a global-namespace type is a module named after
  -- its file — true of the path, not of the language.
  local stem = path:match("([^/\\]+)%.cs$")
  local module = (ns and stem) and (ns .. "." .. stem) or nil

  -- **C# has no file-level doc comment**, so the file's summary is the
  -- summary of the first type it declares — which in this language is very
  -- nearly the same thing: the one-type-per-file convention is near
  -- universal, and a file's own name is that type's name.
  --
  -- The license banner at the top is a plain `//` comment and is skipped for
  -- free, because only `///` is read here. C needed a Doxygen-style rule to
  -- reach the same place; C# gets it from the language.
  local blocks = doc_blocks(root, src)
  local _, body = namespace_of(root, src)
  local first_doc = nil
  for child in (body or root):iter_children() do
    local kind = child:type()
    if
      kind == "class_declaration"
      or kind == "interface_declaration"
      or kind == "struct_declaration"
      or kind == "record_declaration"
      or kind == "enum_declaration"
    then
      first_doc = doc_above(blocks, child:start())
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

  ---@param node TSNode A member declaration.
  ---@param owner string The declaring type's name.
  ---@param owner_kind string The declaring type's node kind, which decides
  ---what an absent access modifier means.
  local function record_member(node, owner, owner_kind)
    local kind = node:type()
    local mods = modifiers(node, src)
    local doc = parse_doc(doc_above(blocks, node:start()))

    if kind == "method_declaration" or kind == "constructor_declaration" then
      local bare = name_of(node, src)
      if not bare then
        return
      end
      local names = param_names(child_of(node, "parameter_list"), src)
      fns[#fns + 1] = {
        name = owner .. "." .. bare,
        signature = owner .. "." .. bare .. "(" .. table.concat(names, ", ") .. ")",
        line = node:start() + 1,
        line_end = node:end_() + 1,
        summary = doc.summary,
        body = doc.body,
        params = doc.params,
        returns = doc.returns,
        internal = is_internal(mods, owner_kind),
        owner = owner,
        -- `owner_kind` here is the treesitter node kind, which is what
        -- `is_internal` needs; `Documentation.ScopeKind` is the reader's
        -- vocabulary. A `record` groups members exactly as a class does.
        owner_kind = owner_kind == "interface_declaration" and "interface"
          or owner_kind == "struct_declaration" and "struct"
          or owner_kind == "enum_declaration" and "enum"
          or "class",
        see = {},
        overload = {},
        todo = {},
        bug = {},
        test = {},
      }
      return
    end

    if kind == "property_declaration" then
      local bare = name_of(node, src)
      if bare then
        symbols[#symbols + 1] = {
          name = owner .. "." .. bare,
          kind = "binding",
          detail = "property",
          summary = doc.summary,
          line = node:start() + 1,
        }
      end
      return
    end

    if kind == "field_declaration" then
      -- A field's name is inside its declaration, not a direct child: the
      -- node holds a `variable_declaration` with one `variable_declarator`
      -- per name, since `int a, b;` is one field declaration with two names.
      local decl = child_of(node, "variable_declaration")
      if not decl then
        return
      end
      for child in decl:iter_children() do
        if child:type() == "variable_declarator" then
          local bare = name_of(child, src)
          if bare then
            symbols[#symbols + 1] = {
              name = owner .. "." .. bare,
              kind = mods["const"] and "constant" or "binding",
              detail = (text_of(node, src):gsub("%s+", " "):gsub(";%s*$", "")),
              summary = doc.summary,
              line = node:start() + 1,
            }
          end
        end
      end
    end
  end

  ---@param node TSNode A type declaration.
  local function record_type(node)
    local bare = name_of(node, src)
    if not bare then
      return
    end
    local mods = modifiers(node, src)
    local doc = parse_doc(doc_above(blocks, node:start()))
    symbols[#symbols + 1] = {
      name = bare,
      kind = "table",
      detail = node:type():gsub("_declaration$", ""),
      summary = doc.summary,
      line = node:start() + 1,
    }
    local _ = mods
    local body = child_of(node, "declaration_list")
    if body then
      for member in body:iter_children() do
        record_member(member, bare, node:type())
      end
    end
  end

  local function walk(node)
    for child in node:iter_children() do
      local kind = child:type()
      if kind == "using_directive" then
        local name = child_of(child, "qualified_name") or child_of(child, "identifier")
        if name then
          requires[#requires + 1] = { module = text_of(name, src), line = child:start() + 1 }
        end
      elseif
        kind == "class_declaration"
        or kind == "interface_declaration"
        or kind == "struct_declaration"
        or kind == "record_declaration"
        or kind == "enum_declaration"
      then
        record_type(child)
      elseif kind == "namespace_declaration" or kind == "file_scoped_namespace_declaration" then
        -- A block namespace nests its types one level down; a file-scoped one
        -- does not nest at all. Recursing covers both without asking which.
        walk(child)
      elseif kind == "declaration_list" then
        walk(child)
      elseif kind:match("^preproc_") then
        -- **A conditional block is a container, not a leaf.** `#if` wraps
        -- whatever it guards, so a `using` or a type inside one hangs off a
        -- `preproc_if` rather than off the compilation unit — and skipping
        -- those lost three of Serilog's thirty-six usings, silently.
        --
        -- Every branch is walked, including the ones a given build would not
        -- compile. That is deliberate: this map describes a repository, not
        -- one configuration of it, and a type that exists only under
        -- `#if NET8_0_OR_GREATER` is still a type somebody maintains.
        walk(child)
      end
    end
  end
  walk(root)

  return fns, {}, requires, symbols, {}, {}, lines, {}
end

require("documentation.core.lang_registry").register(M.name, M)

return M
