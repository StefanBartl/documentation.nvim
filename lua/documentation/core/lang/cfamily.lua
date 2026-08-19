---@module 'documentation.core.lang.cfamily'
--- C and C++, shared. `c.lua` and `cpp.lua` register; the work is here.
---
--- Same arrangement as `ecma.lua` and for the same reason: two languages
--- that differ in what they can express and agree almost entirely on how a
--- function, a comment and an include look.
---
--- **The problem `docs/ROADMAP/IDEAS/MULTILANG.md` Phase 5 warned about,
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
---@return userdata?
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
---@param root userdata
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
---@param blocks table<integer, string>
---@param row integer
---@return string?
local function doc_above(blocks, row)
  for r = row - 1, math.max(row - 3, 0), -1 do
    if blocks[r] then
      return blocks[r]
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
---@param node userdata
---@return userdata?
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
---@param decl userdata
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
---@param node userdata
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
    local fns, requires = {}, {}

    ---@param node userdata the declaration or definition
    ---@param decl userdata the `function_declarator` inside it
    ---@param internal boolean
    local function record(node, decl, internal)
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
        see = parsed.see,
        overload = {},
        todo = parsed.todo,
        bug = {},
        test = {},
      }
    end

    ---The access specifier currently in force inside a class body.
    ---
    ---C++ makes this positional: everything after `private:` is private
    ---until the next specifier, and a `class` starts private while a
    ---`struct` starts public. Tracked while walking rather than looked up,
    ---because there is nothing on the member node itself to look up.
    local access = nil

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
          record(node, decl, is_static(node, src) or access == "private" or access == "protected")
        end
        -- A definition's body holds statements, not declarations worth
        -- reporting; walking into it would find a function-pointer local
        -- and call it a function.
        return
      elseif kind == "declaration" or kind == "field_declaration" then
        -- The prototype case, and the whole declaration-vs-definition
        -- decision: a header's prototypes are its published surface, a
        -- source file's are duplicates of the bodies below them.
        if header_file then
          local decl = nil
          for child in node:iter_children() do
            decl = decl or function_declarator(child)
          end
          if decl then
            record(node, decl, is_static(node, src) or access == "private" or access == "protected")
          end
        end
        return
      elseif kind == "class_specifier" or kind == "struct_specifier" then
        local outer = access
        access = kind == "class_specifier" and "private" or "public"
        for child in node:iter_children() do
          walk(child)
        end
        access = outer
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

    return fns, {}, requires, {}, {}, {}, lines, {}
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
