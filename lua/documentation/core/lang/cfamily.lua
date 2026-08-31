---@module 'documentation.core.lang.cfamily'
--- C and C++, shared. `c.lua` and `cpp.lua` register; the work is here.
---
--- Same arrangement as `ecma.lua` and for the same reason: two languages
--- that differ in what they can express and agree almost entirely on how a
--- function, a comment and an include look.
---
--- **The problem Phase 5 of the multi-language work warned about,
--- and the answer taken.** A `.h` prototype and its `.c` body are two nodes
--- describing one function, and `Documentation.FunctionInfo` models one
--- function as one node. Rather than add a `declares`/`defines` edge kind —
--- a schema change every renderer would have to learn — this backend
--- decides *per file* which node is the one worth reporting:
---
--- * In a **header**, a prototype is the function. A header is a published
---   surface, it is the file people read to find out what a library offers,
---   and reporting nothing for it would make the most-read file in a C
---   project the emptiest node on the map.
--- * In a **source file**, only definitions are reported. A forward
---   declaration there is a duplicate of the body below it, and counting
---   both would report a translation unit as twice its own size.
---
--- What this deliberately does not do is *join* the two. `util.h`'s `add`
--- and `util.c`'s `add` are two entries on two nodes, and the map shows the
--- include edge between them. Joining them needs the edge kind Phase 5
--- describes; this is the honest version that fits today's schema, not a
--- substitute for it.
---
--- **There is no module system**, which Phase 5 also called the hardest fit.
--- The answer here is the one Zig already established: the path is the
--- identity, `module_tag = false`, and a directory is a namespace. It costs
--- nothing to be right about C, because C agrees — the preprocessor works on
--- paths, not on names.
---
--- **Doxygen where present, absent where not.** `@param` and `\param` are
--- both accepted (Doxygen takes either, and real trees use both), as are
--- `/** */`, `/*! */`, `///` and `//!`. A tree that never adopted Doxygen
--- degrades to functions with no prose rather than to functions with
--- invented prose — the same way `coverage.lua` degrades on a tree with no
--- tests directory.

local M = {}

---Files whose prototypes are the published surface.
---
---`.h` is shared by C and C++, which is why the decision is made on the
---extension rather than on the backend: a `.h` in a C++ project is still a
---header, and a `.cpp` is still a source file.
local HEADER_EXT = {
  h = true,
  hh = true,
  hpp = true,
  hxx = true,
  ["h++"] = true,
  inc = true,
}

---@param path string
---@return boolean
local function is_header(path)
  local ext = path:match("%.([%w+]+)$")
  return ext ~= nil and HEADER_EXT[ext:lower()] == true
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
---@param grammar string
---@return TSNode?
local function parse(src, grammar)
  local ok, parser = pcall(vim.treesitter.get_string_parser, src, grammar)
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

---Doxygen comment text with its frame removed.
---
---Four openers, because Doxygen accepts four and real trees use all of
---them: `/**`, `/*!`, `///` and `//!`.
---@param raw string
---@return string
local function undecorate(raw)
  -- `[%*!]?`, with the `?`: a plain `/*` opens a documentation block here
  -- too (see `doc_blocks`), and leaving its opener in would put `/* ` at the
  -- front of a third of every C summary.
  local body = raw:gsub("^/%*[%*!]?", ""):gsub("%*/%s*$", "")
  local out = {}
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do
    local cleaned = line:gsub("^%s*//[/!]?%s?", ""):gsub("^%s*%*%s?", ""):gsub("%s+$", "")
    out[#out + 1] = cleaned
  end
  while out[1] == "" do
    table.remove(out, 1)
  end
  while out[#out] == "" do
    table.remove(out)
  end
  return table.concat(out, "\n")
end

---A Doxygen block, split into prose and the tags in it.
---
---`@` and `\` both open a tag. Doxygen has always taken either, and a
---backend that picked one would read half of any given codebase.
---@param raw string
---@return { summary: string, body: string, params: table[], returns: table[], deprecated: string?, see: string[], todo: string[] }
local function parse_doc(raw)
  local text = undecorate(raw)
  local prose, params, returns, see, todo = {}, {}, {}, {}, {}
  local deprecated, brief = nil, nil
  ---The tag a continuation line belongs to, or `nil` inside the prose.
  local current = nil

  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local tag, rest = line:match("^%s*[@\\](%a+)%s*(.*)$")
    if tag == "param" then
      -- `@param[in] name text` — the direction is Doxygen's, and it belongs
      -- to the tag rather than to the parameter's name.
      rest = rest:gsub("^%[[%a,%s]*%]%s*", "")
      local name, desc = rest:match("^([%w_]+)%s*(.*)$")
      if name then
        params[#params + 1] = { name = name, type = "", optional = false, desc = desc or "" }
        current = params[#params]
      end
    elseif tag == "return" or tag == "returns" or tag == "result" then
      returns[#returns + 1] = { type = "", desc = rest }
      current = returns[#returns]
    elseif tag == "brief" or tag == "short" then
      -- The one tag that outranks position: Doxygen's `@brief` *is* the
      -- summary, so a block whose first line is boilerplate still gets the
      -- right one-liner.
      brief = rest
      prose[#prose + 1] = rest
      current = nil
    elseif tag == "deprecated" then
      deprecated = rest
      current = nil
    elseif tag == "see" or tag == "sa" then
      see[#see + 1] = rest
      current = nil
    elseif tag == "todo" then
      todo[#todo + 1] = rest
      current = nil
    elseif tag == "throws" or tag == "throw" or tag == "exception" then
      prose[#prose + 1] = "@throws " .. rest
      current = nil
    elseif tag then
      current = nil
    elseif current and line:match("%S") then
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
    summary = brief or require("documentation.core.scan").split_summary(body),
    body = body,
    params = params,
    returns = returns,
    deprecated = deprecated,
    see = see,
    todo = todo,
  }
end

---Whether a comment is prose rather than code somebody switched off.
---
---The cost of accepting plain comments (see `doc_blocks`) is commented-out
---code, which is ordinary in C and looks like documentation to anything
---that only reads the punctuation. A line ending in `;`, `{` or `}` is the
---cheap tell, and it errs in the safe direction: prose rarely ends that
---way, and code that does not is a line nobody could distinguish from a
---sentence anyway.
---@param text string
---@return boolean
local function looks_like_prose(text)
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local bare = line:gsub("^%s*[/%*]*%s*", ""):gsub("%s+$", "")
    if bare:match("[;{}]$") then
      return false
    end
  end
  return true
end

---Every documentation comment in the tree, by the row it ends on.
---
---A run of `///` lines is several comment nodes in a row, and Doxygen reads
---them as one block — so they are joined here rather than left as the last
---line of a paragraph the author wrote four lines of.
---
---**Plain comments count too, and that is a measured decision.** Doxygen
---recognises only `/**`, `/*!`, `///` and `//!`. Real C mostly uses none of
---them: scanned against `antirez/sds` — 1328 lines, 45 functions, nearly
---every one of them commented — the Doxygen-only rule found **zero**
---summaries, because that codebase writes `/* ... */`. A map that reports a
---thoroughly documented C file as undocumented is wrong about the one thing
---it exists to show. So a comment sitting directly above a declaration is
---that declaration's documentation whatever its punctuation, and
---`looks_like_prose` is the single filter, against commented-out code.
---
---`doxygen` records which blocks are Doxygen-style anyway, because the
---*file* header rule in `parse_header` still demands one: a license banner
---sits at the top of almost every C file and is a summary of nothing.
---@param root TSNode
---@param src string
---@return table<integer, string> blocks
---@return table<integer, boolean> doxygen
local function doc_blocks(root, src)
  local single, blocks, doxygen, single_doxygen = {}, {}, {}, {}
  local function walk(node)
    if node:type() == "comment" then
      local srow, _, sbyte = node:start()
      local erow, _, ebyte = node:end_()
      local text = src:sub(sbyte + 1, ebyte)
      if text:match("^//") then
        if looks_like_prose(text) then
          single[srow] = text
          single_doxygen[srow] = text:match("^///") ~= nil or text:match("^//!") ~= nil
        end
      elseif text:match("^/%*") and looks_like_prose(text) then
        blocks[erow] = text
        doxygen[erow] = text:match("^/%*%*") ~= nil or text:match("^/%*!") ~= nil
      end
      return
    end
    for child in node:iter_children() do
      walk(child)
    end
  end
  walk(root)

  -- Join each run of line-doc comments and key it by its last row, so the
  -- lookup below is the same for both comment styles.
  for row, _ in pairs(single) do
    if not single[row + 1] then
      local lines, r, marked = {}, row, false
      while single[r] do
        table.insert(lines, 1, single[r])
        marked = marked or single_doxygen[r]
        r = r - 1
      end
      blocks[row] = table.concat(lines, "\n")
      doxygen[row] = marked or false
    end
  end
  return blocks, doxygen
end

---The documentation block ending directly above `row`, if any.
---
---Two lines of slack, for the attribute or macro that sits between a
---comment and a declaration often enough to matter (`__attribute__`,
---`EXPORT`, `static inline` split across lines).
---
---**A block is consumed when it is taken.** Same fix and same reason as
---`java.lua`'s: three lines of slack reach past a one-line declaration to
---the next one, so an undocumented `int b;` under a documented `int a;`
---inherited the comment above `a`. A doc block documents one declaration.
---Consuming it says so without this function needing to know what a
---declaration is.
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

---The `function_declarator` inside a declarator subtree, if there is one.
---
---Recursive because a return type wraps it: `int *f(void)` is a
---`pointer_declarator` around the `function_declarator`, and `int **f` is
---two of them. Anything that is not a declarator ends the search rather
---than being walked into, so a function *pointer parameter* does not turn
---its enclosing declaration into a function.
---@param node TSNode
---@return TSNode?
local function function_declarator(node)
  local kind = node:type()
  if kind == "function_declarator" then
    return node
  end
  if
    kind == "pointer_declarator"
    or kind == "reference_declarator"
    or kind == "parenthesized_declarator"
    or kind == "init_declarator"
  then
    for child in node:iter_children() do
      local found = function_declarator(child)
      if found then
        return found
      end
    end
  end
  return nil
end

---The declared name inside a `function_declarator`.
---
---Five node types, because C++ spells a name five ways: a plain
---`identifier`, a member `field_identifier`, a `qualified_identifier`
---(`Thing::go`), a `destructor_name` and an `operator_name`. All five are
---taken as written — `Thing::go` is already the qualified name, so nothing
---needs to be reconstructed from the enclosing scope.
---@param decl TSNode
---@param src string
---@return string?
local function declared_name(decl, src)
  for child in decl:iter_children() do
    local kind = child:type()
    if
      kind == "identifier"
      or kind == "field_identifier"
      or kind == "qualified_identifier"
      or kind == "destructor_name"
      or kind == "operator_name"
    then
      return text_of(child, src)
    end
  end
  return nil
end

---Whether a node has a `static` storage class.
---
---In C this is the whole visibility system: `static` at file scope means
---"this translation unit only", which is exactly what `internal` records.
---@param node TSNode
---@param src string
---@return boolean
local function is_static(node, src)
  for child in node:iter_children() do
    if child:type() == "storage_class_specifier" and text_of(child, src):match("^static") then
      return true
    end
  end
  return false
end

---Build a backend table for one C-family language.
---@param name string
---@param grammar string
---@param extensions string[]
---@param roots string[] Conventional source directories, in order.
---@return table
function M.backend(name, grammar, extensions, roots)
  local ext_set = {}
  for _, e in ipairs(extensions) do
    ext_set[e] = true
  end

  local function is_source(filename)
    local ext = filename:match("%.([%w+]+)$")
    return ext ~= nil and ext_set[ext:lower()] == true
  end

  local backend

  ---@param path string
  ---@return Documentation.Header
  local function parse_header(path)
    local empty = { module = nil, summary = "", body = "", tags = {} }
    local src = read(path)
    if not src then
      return empty
    end
    local root = parse(src, grammar)
    if not root then
      return empty
    end

    -- C has no file-level doc construct, so a `@file` block is just a
    -- comment that happens to sit at the top. Which one that is takes a
    -- rule, not a guess:
    --
    --   * it is the **earliest** doc block in the file, and
    --   * it sits **above the first declaration**, and
    --   * it is **not the block documenting that declaration**.
    --
    -- The third clause is the one that matters. Without it, a header whose
    -- first function carries a `///` line reports that function's summary
    -- as the file's, which is not a weaker answer than none — it is a wrong
    -- one, and it is wrong on exactly the files people read first.
    local blocks, doxygen = doc_blocks(root, src)
    local first = nil
    for child in root:iter_children() do
      local kind = child:type()
      if kind ~= "comment" and kind ~= "preproc_include" then
        first = child
        break
      end
    end
    if not first then
      return empty
    end
    local first_row = first:start()
    local attached = doc_above(blocks, first_row)

    -- Doxygen-style only, unlike the per-declaration lookup: a license
    -- banner opens almost every C file, it is a plain `/* */` block, and it
    -- is a summary of nothing. A file header that wants to be read as one
    -- says so with `/**`, which costs its author one character.
    local earliest_row, earliest = nil, nil
    for row, text in pairs(blocks) do
      if row < first_row and doxygen[row] and (not earliest_row or row < earliest_row) then
        earliest_row, earliest = row, text
      end
    end
    if not earliest or earliest == attached then
      return empty
    end
    local doc = earliest
    local parsed = parse_doc(doc)
    return {
      -- The path is the identity here; see this module's header.
      module = nil,
      summary = parsed.summary,
      body = parsed.body,
      tags = {},
    }
  end

  ---@param path string
  ---@return Documentation.FunctionInfo[], Documentation.RawCall[], Documentation.RawRequire[], Documentation.SymbolInfo[], table[], Documentation.EndpointSpec[], integer, Documentation.BindingSpec[]
  local function scan_file(path)
    local src = read(path)
    if not src then
      return {}, {}, {}, {}, {}, {}, 0, {}
    end
    local _, newlines = src:gsub("\n", "")
    local lines = #src == 0 and 0 or (newlines + (src:sub(-1) == "\n" and 0 or 1))

    local root = parse(src, grammar)
    if not root then
      return {}, {}, {}, {}, {}, {}, lines, {}
    end

    local header_file = is_header(path)
    local blocks = doc_blocks(root, src)
    local fns, requires, symbols = {}, {}, {}

    ---@param node TSNode the declaration or definition
    ---@param decl TSNode the `function_declarator` inside it
    ---@param internal boolean
    ---@param owner string? Enclosing class or struct, when the member is written inside its body.
    ---@param owner_kind Documentation.ScopeKind? `class` or `struct`, from the keyword.
    local function record(node, decl, internal, owner, owner_kind)
      local fname = declared_name(decl, src)
      if not fname then
        return
      end
      local srow, erow = node:start(), node:end_()
      local params_node = child_of(decl, "parameter_list")
      local doc = doc_above(blocks, srow)
      local parsed = doc and parse_doc(doc)
        or { summary = "", body = "", params = {}, returns = {}, see = {}, todo = {} }

      fns[#fns + 1] = {
        name = fname,
        signature = fname .. (params_node and text_of(params_node, src) or "()"),
        line = srow + 1,
        line_end = erow + 1,
        summary = parsed.summary,
        body = parsed.body,
        params = parsed.params,
        returns = parsed.returns,
        deprecated = parsed.deprecated,
        internal = internal,
        -- **Only the enclosing body's owner, never the name's own prefix.**
        -- An out-of-line `void Thing::go() {}` and a namespace-qualified
        -- `void A::f() {}` are written identically, and this backend has no
        -- way to tell a type from a namespace at that point — so the
        -- qualified `name` stays exactly what it was and no owner is
        -- invented for it. In-body members, which is every declaration in a
        -- header, are owned.
        owner = owner,
        owner_kind = owner and owner_kind or nil,
        see = parsed.see,
        overload = {},
        todo = parsed.todo,
        bug = {},
        test = {},
      }
    end

    ---The identifier a non-function declaration binds.
    ---
    ---Dug for rather than read off a fixed child index, because C spells one
    ---idea five ways: `int x`, `int x = 1`, `int *x`, `int x[4]` and
    ---`int (*fn)(void)` are `identifier`, `init_declarator`,
    ---`pointer_declarator`, `array_declarator` and a nest of the last two.
    ---Descending to the first `identifier`/`field_identifier` is right for
    ---all of them and needs no table of shapes to keep current.
    ---
    ---Stops at a `parameter_list`, which is what keeps
    ---`int (*compare)(int a, int b)` from being read as the parameter `a`.
    ---@param node TSNode
    ---@return TSNode?
    local function declared_var_name(node)
      for child in node:iter_children() do
        local kind = child:type()
        if kind == "identifier" or kind == "field_identifier" then
          return child
        end
        if kind ~= "parameter_list" and kind ~= "argument_list" then
          local found = declared_var_name(child)
          if found then
            return found
          end
        end
      end
      return nil
    end

    ---Record one module-scope binding.
    ---@param node TSNode
    ---@param name_node TSNode
    ---@param kind Documentation.SymbolKind
    local function record_symbol(node, name_node, kind)
      local doc = doc_above(blocks, node:start())
      local parsed = doc and parse_doc(doc) or nil
      symbols[#symbols + 1] = {
        name = text_of(name_node, src),
        kind = kind,
        detail = (text_of(node, src):gsub("%s+", " "):gsub(";%s*$", "")):sub(1, 60),
        summary = parsed and parsed.summary or "",
        line = node:start() + 1,
      }
    end

    ---The access specifier currently in force inside a class body.
    ---
    ---C++ makes this positional: everything after `private:` is private
    ---until the next specifier, and a `class` starts private while a
    ---`struct` starts public. Tracked while walking rather than looked up,
    ---because there is nothing on the member node itself to look up.
    local access = nil

    ---The class or struct currently being walked into, tracked exactly as
    ---`access` is and for the same reason: a member declaration carries no
    ---trace of the body it sits in.
    local owner = nil
    ---@type Documentation.ScopeKind?
    local owner_kind = nil

    local function walk(node)
      local kind = node:type()

      if kind == "preproc_include" then
        local quoted = child_of(node, "string_literal")
        local system = child_of(node, "system_lib_string")
        local target = nil
        if quoted then
          target = text_of(quoted, src):match('^"(.*)"$')
        elseif system then
          -- Recorded like any other include. Whether it resolves inside
          -- this tree is `deps.lua`'s question, not this backend's — the
          -- same division `zig.lua` draws for `@import("std")`.
          target = text_of(system, src):match("^<(.*)>$")
        end
        if target then
          requires[#requires + 1] = { module = target, line = node:start() + 1 }
        end
        return
      elseif kind == "function_definition" then
        local decl = nil
        for child in node:iter_children() do
          decl = decl or function_declarator(child)
        end
        if decl then
          record(
            node,
            decl,
            is_static(node, src) or access == "private" or access == "protected",
            owner,
            owner_kind
          )
        end
        -- A definition's body holds statements, not declarations worth
        -- reporting; walking into it would find a function-pointer local
        -- and call it a function.
        return
      elseif kind == "preproc_def" then
        -- **`#define` is C's constant**, and leaving it out would mean the
        -- one idiom every C project uses for a threshold is the one thing
        -- the Index tab cannot show. A function-like macro (`preproc_function_def`)
        -- is deliberately not here: it takes parameters and behaves like a
        -- function, and calling it a constant would be the wrong word in
        -- the one column that has to mean the same thing in all
        -- twenty-three languages.
        local name_node = child_of(node, "identifier")
        if name_node then
          record_symbol(node, name_node, "constant")
        end
        return
      elseif kind == "type_definition" or kind == "enum_specifier" then
        -- A named type, reported the way `go.lua` reports its own
        -- `type_declaration`: `kind = "table"`, because what a reader wants
        -- from this row is "a shape lives here", not its storage class.
        --
        -- **The name is looked for at this node's own level first**, and
        -- that is the whole subtlety: `typedef struct { int x; } Point;`
        -- carries the struct's *members* below it, so a general descent
        -- finds `x` and calls the type `x`. Measured, not guessed — the
        -- first version did exactly that. `typedef int *IntPtr;` still
        -- needs the descent, because the name sits inside a
        -- `pointer_declarator`, so the fallback stays and only its starting
        -- point moved.
        local name_node = child_of(node, "type_identifier")
        if not name_node then
          for child in node:iter_children() do
            local ck = child:type()
            if ck ~= "struct_specifier" and ck ~= "union_specifier" and ck ~= "enum_specifier" then
              name_node = declared_var_name(child) or child_of(child, "type_identifier")
              if name_node then
                break
              end
            end
          end
        end
        if name_node then
          record_symbol(node, name_node, "table")
        end
        return
      elseif kind == "declaration" or kind == "field_declaration" then
        -- The prototype case, and the whole declaration-vs-definition
        -- decision: a header's prototypes are its published surface, a
        -- source file's are duplicates of the bodies below them.
        local decl = nil
        for child in node:iter_children() do
          decl = decl or function_declarator(child)
        end
        if decl then
          if header_file then
            record(
              node,
              decl,
              is_static(node, src) or access == "private" or access == "protected",
              owner,
              owner_kind
            )
          end
          -- A prototype is a function either way, and a function is never
          -- also a symbol -- the same line `core/symbols.lua` draws when it
          -- refuses to report `M.foo = function(...)` twice.
          return
        end

        -- **Everything left is a binding**, which is what was missing: C and
        -- C++ were two of the four backends that reported no module-scope
        -- symbols at all, found by the parity audit rather than by anyone
        -- noticing a gap in one language.
        --
        -- `const` is the constant here, and unlike Java's `static final`
        -- there is nothing else to weigh: a `const int` cannot be
        -- reassigned and that is the whole distinction the column carries.
        -- A `field_declaration` reaches this only inside a class or struct
        -- body, which is C++'s nearest thing to module scope, exactly as
        -- Java's fields are.
        local name_node = declared_var_name(node)
        if name_node then
          local whole = text_of(node, src)
          record_symbol(
            node,
            name_node,
            whole:match("%f[%w]const%f[%W]") and "constant" or "binding"
          )
        end
        return
      elseif kind == "class_specifier" or kind == "struct_specifier" then
        local outer, outer_owner, outer_kind = access, owner, owner_kind
        access = kind == "class_specifier" and "private" or "public"
        -- Saved and restored the same way `access` already is, and for the
        -- same reason: C++ nests these, and an inner class must not leave
        -- its name behind for the members declared after it.
        local name_node = child_of(node, "type_identifier")
        owner = name_node and text_of(name_node, src) or owner
        owner_kind = kind == "class_specifier" and "class" or "struct"
        for child in node:iter_children() do
          walk(child)
        end
        access, owner, owner_kind = outer, outer_owner, outer_kind
        return
      elseif kind == "access_specifier" then
        access = text_of(node, src):match("^(%a+)")
        return
      end

      for child in node:iter_children() do
        walk(child)
      end
    end
    walk(root)

    return fns, {}, requires, symbols, {}, {}, lines, {}
  end

  backend = {
    name = name,
    grammar = grammar,
    extensions = extensions,
    ---The path is the identity: the preprocessor works on paths, not names,
    ---so there is no tag that could be missing.
    module_tag = false,
    line_comments = { "//" },
    block_comments = { { "/*", "*/" } },
    is_source = is_source,

    ---`nil` unless one of the conventional roots actually holds a file this
    ---backend claims — answering unconditionally is the bug rather than the
    ---feature, per `Documentation.LangBackend.detect_source`.
    detect_source = function(root)
      local uv = vim.uv or vim.loop
      local function holds(dir)
        local fd = uv.fs_scandir(dir)
        if not fd then
          return false
        end
        while true do
          local entry, entry_kind = uv.fs_scandir_next(fd)
          if not entry then
            return false
          end
          if entry_kind ~= "directory" and is_source(entry) then
            return true
          end
        end
      end
      for _, candidate in ipairs(roots) do
        if holds(root .. "/" .. candidate) then
          return candidate
        end
      end
      -- A flat project with its sources at the top, which is most small C.
      if holds(root) then
        return "."
      end
      return nil
    end,

    parse_header = parse_header,
    scan_file = scan_file,
  }
  return backend
end

return M
