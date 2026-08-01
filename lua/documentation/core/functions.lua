---@module 'documentation.core.functions'
--- Extracts per-function documentation from a Lua source file via
--- `vim.treesitter`, not `lua-language-server --doc`.
---
--- `--doc` only surfaces symbols reachable through a `@class`/`@alias` type
--- graph — verified against real `doc.json` output (see `luals.lua`'s own
--- header for the same discipline applied there): an ordinary
--- `function M.foo(...)` in a module with no aggregate `@class` declaration
--- for its exports simply does not appear. Retrofitting every module with a
--- redundant aggregate class (duplicating what `---@param`/`---@return`
--- already say above each function) was rejected — two places asserting the
--- same signature is a drift risk, not a shortcut.
---
--- `vim.treesitter` is already bundled with Neovim and already a lib.nvim
--- dependency (`lib.nvim.treesitter`), so this adds nothing new to the "just
--- vim and itself" principle. It is also more robust than a regex/line
--- scanner would have been: a `--` inside a string literal or a multi-line
--- signature are ordinary AST nodes here, not special cases.
---
--- Deliberately narrow, same as `scan.lua`: only the three function shapes
--- that make up this repo's actual public surface are recognized —
--- `function M.foo(...)`, `local function foo(...)`, `M.foo = function(...)`.
--- Anonymous/nested callback functions are not documented units and are not
--- scanned.

local M = {}

-- Two patterns, matched via iter_matches (not iter_captures): the two forms
-- put @fname before or after @fdef in source order depending on which one
-- matched (`M.baz = function(...)` names the target before the function
-- keyword; `function M.bar(...)` does the reverse) — iter_captures' flat,
-- position-ordered stream cannot be regrouped from that alone, verified by
-- a real query run that showed the name arriving before @fdef for the
-- assignment form. iter_matches groups every capture belonging to one match
-- together regardless of source order, which is what correct grouping needs.
local FN_QUERY = vim.treesitter.query.parse(
  "lua",
  [[
  (function_declaration
    name: (_) @fname
    parameters: (parameters) @params) @fdef

  (assignment_statement
    (variable_list name: (_) @fname)
    (expression_list
      value: (function_definition parameters: (parameters) @params) @fdef))
]]
)

local COMMENT_QUERY = vim.treesitter.query.parse("lua", "(comment) @comment")

--- Cyclomatic complexity (McCabe): one decision point each for
--- if/elseif/while/for/repeat, plus one for every `and`/`or` (a short-
--- circuit boolean operator is a branch the same way an `if` is — the
--- reader has to consider both outcomes). `x and 1 or 2` matches twice
--- (once for the inner `and`, once for the outer `or`), which is correct:
--- that is two real decision points, not one, verified against
--- `vim.treesitter.get_node_text` on a real nested and/or expression.
--- Complexity itself is `1 + capture count`, computed per function over
--- `def_node`'s own subtree — including nested anonymous closures inside
--- it (a callback body's branches are branches the enclosing function's
--- reader still has to follow, and docmap does not scan the closure as its
--- own unit in the first place).
local COMPLEXITY_QUERY = vim.treesitter.query.parse(
  "lua",
  [[
  [
    (if_statement)
    (elseif_statement)
    (while_statement)
    (for_statement)
    (repeat_statement)
  ] @branch

  (binary_expression "and") @branch
  (binary_expression "or") @branch
]]
)

---@param def_node TSNode
---@param src string
---@return integer
local function cyclomatic_complexity(def_node, src)
  local n = 1
  for _ in COMPLEXITY_QUERY:iter_captures(def_node, src) do
    n = n + 1
  end
  return n
end

--- Structural fingerprint of a function body, for the copy-paste detector in
--- [`duplicates.lua`](duplicates.lua).
---
--- The sequence of treesitter node *types* over the definition's whole
--- subtree, in tree order — never their text. Two functions differing only in
--- identifier and literal names produce the same fingerprint, which is the
--- entire point: a copy-paste is normally renamed on the way in, so a detector
--- that only found byte-identical bodies would find the one case nobody
--- ships. This is the "type-2 clone" of the copy-paste-detection literature,
--- which is also what PMD's CPD reports by default.
---
--- Anonymous nodes are included, deliberately: an operator *is* an anonymous
--- child (`(binary_expression "and")`), so skipping them would make `a + b`
--- and `a - b` one shape. Their type is the operator text itself, which
--- carries no identifier name, so including them costs nothing and keeps
--- arithmetic apart.
---
--- Hashed rather than stored: the raw sequence runs to thousands of characters
--- per function and the artifact is committed and reviewed. Two independent
--- hashes rather than one, because a collision here does not degrade the
--- answer, it *fabricates* one — "these two functions are identical" is a
--- claim, and the rule in this plugin is that a wrong answer is worse than a
--- missing one. Two 31-bit hashes put the birthday probability over a few
--- thousand functions far below the chance of any other bug in this file.
--- Multiply-and-add rather than FNV's xor, so the arithmetic stays inside a
--- double's exact-integer range with no bitwise library.
---@param def_node TSNode
---@return string shape
---@return integer size Node count — the knob the detector thresholds on.
local function shape_of(def_node)
  local h1, h2 = 0, 0
  local size = 0

  local stack = { def_node }
  while #stack > 0 do
    local node = table.remove(stack)
    local t = node:type()
    size = size + 1
    for i = 1, #t do
      local c = t:byte(i)
      h1 = (h1 * 131 + c) % 2147483647
      h2 = (h2 * 8191 + c) % 2147483629
    end
    -- Pushed in reverse so they pop left to right: sibling order is part of
    -- the structure, and a fingerprint blind to it would call `a() b()` and
    -- `b() a()` the same function.
    for i = node:child_count() - 1, 0, -1 do
      stack[#stack + 1] = node:child(i)
    end
  end

  return ("%x-%x"):format(h1, h2), size
end

---True when `node` is not nested inside another function's body — a query
---match alone can't tell `local function put(s) ... end` declared at module
---scope from an identically-shaped helper closure nested inside `M.to_json`;
---only walking the ancestor chain can. Verified against a real two-level
---nested `local function` tree: the inner one's parent chain is
---`function_declaration -> block -> function_declaration -> chunk`, so
---hitting a second function-shaped ancestor before `chunk` means "nested."
---@param node TSNode
---@return boolean
local function is_top_level(node)
  local p = node:parent()
  while p do
    local t = p:type()
    if t == "chunk" then
      return true
    end
    if t == "function_declaration" or t == "function_definition" then
      return false
    end
    p = p:parent()
  end
  return false
end

---Split `"type rest..."` into `(type, rest)`, respecting `{}`/`()`/`<>`
---nesting so a type like `table<string, string>` or an anonymous
---`{ a: string, b: integer }` is not cut at the comma/space inside it.
---@param s string
---@return string type_text
---@return string rest
local function split_type(s)
  local depth = 0
  for i = 1, #s do
    local c = s:sub(i, i)
    if c == "{" or c == "(" or c == "<" then
      depth = depth + 1
    elseif c == "}" or c == ")" or c == ">" then
      depth = depth - 1
    elseif c == " " and depth <= 0 then
      return s:sub(1, i - 1), (s:sub(i + 1):gsub("^%s+", ""))
    end
  end
  return s, ""
end

---Parse one already-assembled `---@tag rest` line's `rest` as `param`.
---
---LuaLS accepts the optional-marker `?` on either the name (`name? type`) or
---the type (`name type?`) — this repo's own real usage, verified by grep
---(`---@param node_id string?`, `---@param opts Documentation.Opts?`), is
---consistently the *type*-suffixed form, not the name-suffixed one the spec
---leads with. Both are recognized so this doesn't silently miss the form
---the codebase actually uses.
---@param rest string
---@return Documentation.ParamInfo
local function parse_param(rest)
  local name, tail = rest:match("^(%S+)%s*(.*)$")
  name = name or rest
  local optional = false
  if name:sub(-1) == "?" then
    optional = true
    name = name:sub(1, -2)
  end
  local ty, desc = split_type(tail or "")
  if ty:sub(-1) == "?" then
    optional = true
    ty = ty:sub(1, -2)
  end
  return { name = name, type = ty, optional = optional, desc = desc }
end

---@param rest string
---@return Documentation.ReturnInfo
local function parse_return(rest)
  local ty, tail = split_type(rest)
  local name, desc = tail:match("^([%a_][%w_]*)%s*(.*)$")
  if not name then
    desc = tail
  end
  return { type = ty, name = name, desc = desc or "" }
end

---Split `s` on top-level commas, respecting `{}/()/<>` nesting the same way
---`split_type` respects it for a single space — reused below for both an
---overload's parameter list and its return-type list, which share the
---identical "comma-separated, nesting-aware" shape.
---@param s string
---@return string[] chunks Trimmed; empty input yields an empty array, not `{""}`.
local function split_commas(s)
  local chunks = {}
  local depth, start = 0, 1
  for i = 1, #s do
    local c = s:sub(i, i)
    if c == "{" or c == "(" or c == "<" then
      depth = depth + 1
    elseif c == "}" or c == ")" or c == ">" then
      depth = depth - 1
    elseif c == "," and depth <= 0 then
      chunks[#chunks + 1] = vim.trim(s:sub(start, i - 1))
      start = i + 1
    end
  end
  local last = vim.trim(s:sub(start))
  if last ~= "" then
    chunks[#chunks + 1] = last
  end
  return chunks
end

---Parse one `---@overload rest` line's `rest` — a LuaCATS function-type
---literal, `fun(a: T, b: U): R1, R2` — into the same param/return shape the
---primary signature uses, so an overload renders through the exact same
---list markup as the function it belongs to instead of a second visual
---language for one tag.
---
---Falls back to `params = {}, returns = {}` (raw text preserved) rather than
---erroring when `rest` does not start with `fun(` or its parens do not
---balance: an `@overload` value is free-form text someone typed, and a shape
---this does not recognize should degrade to "shown as written" rather than
---aborting the whole doc-block parse over one line.
---@param rest string Text after `---@overload `, e.g. `fun(x: string): boolean`.
---@return Documentation.OverloadInfo
local function parse_overload(rest)
  local body = rest:match("^fun%s*%((.*)$")
  if not body then
    return { raw = rest, params = {}, returns = {} }
  end

  -- The opening `(` was already consumed by the match above, so `depth`
  -- starts at 1 — one level inside `fun(` — and the scan below looks for
  -- where it returns to 0, which is that `(`'s matching close. Nesting is
  -- tracked so a parameter type like `table<string, string>` or a nested
  -- `fun(cb: fun(x: integer))` does not end the scan early.
  local depth, close = 1, nil
  for i = 1, #body do
    local c = body:sub(i, i)
    if c == "(" or c == "{" or c == "<" then
      depth = depth + 1
    elseif c == ")" or c == "}" or c == ">" then
      depth = depth - 1
      if depth == 0 then
        close = i
        break
      end
    end
  end
  if not close then
    return { raw = rest, params = {}, returns = {} }
  end

  local params = {}
  for _, chunk in ipairs(split_commas(body:sub(1, close - 1))) do
    -- `name: type` is the documented shape; a bare `type` with no name is
    -- also legal LuaCATS inside a `fun()` parameter list (an anonymous
    -- positional parameter), so a chunk with no top-level `:` is not a
    -- parse failure — the whole chunk is the type instead.
    local name, ty = chunk:match("^%s*([%w_%.%?]+)%s*:%s*(.-)%s*$")
    if not name then
      name, ty = "_", chunk
    end
    local optional = false
    if name:sub(-1) == "?" then
      optional = true
      name = name:sub(1, -2)
    end
    params[#params + 1] = { name = name, type = ty, optional = optional, desc = "" }
  end

  local returns = {}
  local return_text = vim.trim((body:sub(close + 1):gsub("^%s*:%s*", "")))
  for _, chunk in ipairs(split_commas(return_text)) do
    returns[#returns + 1] = { type = chunk, name = nil, desc = "" }
  end

  return { raw = rest, params = params, returns = returns }
end

---Strip a comment node's `--`/`---` prefix and one leading space.
---@param line string
---@return string
local function strip_comment(line)
  return (line:gsub("^%-%-%-?%s?", ""))
end

---Parse a function's assembled doc-comment block (top-to-bottom, `---`
---prefix already stripped by the caller) into the tagged fields.
---@param raw_lines string[] Full comment lines, `---` prefix intact.
---@return { summary: string, params: Documentation.ParamInfo[], returns: Documentation.ReturnInfo[], generic: string[], deprecated: string?, async: boolean, nodiscard: boolean, internal: boolean, see: string[], overload: string[], todo: string[], bug: string[], test: string[], example: string?, since: string? }
local function parse_doc_block(raw_lines)
  local prose = {}
  local params, returns, generic, see, overload = {}, {}, {}, {}, {}
  -- Arrays, not single strings: Doxygen's equivalent commands collect one
  -- list entry per occurrence, and a function with two open todos has two
  -- todos — folding them into one string would silently drop the second.
  -- `@see`/`@overload` already establish the repeatable-tag shape here.
  local todo, bug, test = {}, {}, {}
  local deprecated, since, example
  local async, nodiscard, internal = false, false, false
  local in_example = false
  local seen_tag = false

  for _, raw in ipairs(raw_lines) do
    local tag, rest = raw:match("^%-%-%-@(%a+)%s*(.*)$")
    if tag then
      seen_tag = true
      in_example = (tag == "example")
      if tag == "param" then
        params[#params + 1] = parse_param(rest)
      elseif tag == "return" then
        returns[#returns + 1] = parse_return(rest)
      elseif tag == "generic" then
        for name in rest:gmatch("[%w_]+") do
          generic[#generic + 1] = name
        end
      elseif tag == "deprecated" then
        deprecated = rest
      elseif tag == "async" then
        async = true
      elseif tag == "nodiscard" then
        nodiscard = true
      elseif tag == "internal" then
        internal = true
      elseif tag == "see" then
        for target in rest:gmatch("[^,]+") do
          see[#see + 1] = vim.trim(target)
        end
      elseif tag == "overload" then
        overload[#overload + 1] = parse_overload(rest)
      elseif tag == "todo" then
        todo[#todo + 1] = rest
      elseif tag == "bug" then
        bug[#bug + 1] = rest
      elseif tag == "test" then
        test[#test + 1] = rest
      elseif tag == "since" then
        since = rest
      elseif tag == "example" then
        example = rest ~= "" and rest or nil
      end
    elseif in_example then
      local line = strip_comment(raw)
      example = example and (example .. "\n" .. line) or line
    elseif not seen_tag then
      prose[#prose + 1] = strip_comment(raw)
    end
  end

  local summary = require("documentation.core.scan").split_summary(table.concat(prose, "\n"))

  return {
    summary = summary,
    params = params,
    returns = returns,
    generic = generic,
    deprecated = deprecated,
    async = async,
    nodiscard = nodiscard,
    internal = internal,
    see = see,
    overload = overload,
    todo = todo,
    bug = bug,
    test = test,
    example = example,
    since = since,
  }
end

---Scan `path` for documented top-level functions, and — from the same read
---and the same parse — the raw call sites and `require` occurrences the graph
---stages need.
---
---The three come back together rather than from three entry points because
---they share the two expensive steps: reading the file and parsing it. An
---earlier shape had `deps` and `calls` each open the file themselves, which
---tripled the scan's I/O and doubled its treesitter work for data that was
---already sitting in scope here.
---
---Both extra returns are *unresolved*: a call site's callee is raw text and a
---require is a raw module path, because neither can be turned into a node id
---without the whole IR. `docmap.deps.build` and `docmap.calls.build` do that
---afterwards.
---@param path string Absolute path to a `.lua` file.
---@return Documentation.FunctionInfo[] functions
---@return Documentation.RawCall[] calls
---@return Documentation.RawRequire[] requires
---@return Documentation.SymbolInfo[] symbols
---@return integer lines
function M.scan_file(path)
  local fd = io.open(path, "rb")
  if not fd then
    return {}, {}, {}, {}, 0
  end
  local src = fd:read("*a")
  fd:close()

  -- `require` extraction is pure text and does not depend on the parse, so it
  -- happens before the early-outs below: a file treesitter cannot parse still
  -- has readable dependencies, and dropping them would silently punch a hole
  -- in the require graph rather than in just the function list.
  local requires = require("documentation.core.deps").extract_source(src)

  -- Counted here rather than by a separate read: this is the one place the
  -- whole file is already in memory, and `stats.lines` is otherwise a second
  -- full pass over every file in the tree.
  -- An empty file has no lines; the trailing-newline term would otherwise
  -- report 1 for a file with nothing in it.
  local _, newlines = src:gsub("\n", "")
  local lines = #src == 0 and 0 or (newlines + (src:sub(-1) == "\n" and 0 or 1))

  local ok, parser = pcall(vim.treesitter.get_string_parser, src, "lua")
  if not ok then
    return {}, {}, requires, {}, lines
  end
  local ok_parse, trees = pcall(function()
    return parser:parse()
  end)
  if not ok_parse or not trees or not trees[1] then
    return {}, {}, requires, {}, lines
  end
  local root = trees[1]:root()

  ---@type { row: integer, erow: integer, text: string }[]
  local comments = {}
  for id, node in COMMENT_QUERY:iter_captures(root, src) do
    if COMMENT_QUERY.captures[id] == "comment" then
      local srow, _, erow = node:range()
      local text = vim.treesitter.get_node_text(node, src)
      if text:match("^%-%-%-") then
        comments[#comments + 1] = { row = srow, erow = erow, text = text }
      end
    end
  end

  -- Capture ids are looked up by name rather than assumed positional
  -- (1/2/3): `query.captures[id] -> name` is the documented contract, the
  -- reverse is not guaranteed to match declaration order.
  local id_by_name = {}
  for id, name in ipairs(FN_QUERY.captures) do
    id_by_name[name] = id
  end

  ---@type { name_node: TSNode, params_node: TSNode, def_node: TSNode }[]
  local defs = {}
  for _, match in FN_QUERY:iter_matches(root, src) do
    local name_nodes = match[id_by_name.fname]
    local params_nodes = match[id_by_name.params]
    local def_nodes = match[id_by_name.fdef]
    local name_node = name_nodes and name_nodes[1]
    local params_node = params_nodes and params_nodes[1]
    local def_node = def_nodes and def_nodes[1]
    if name_node and params_node and def_node and is_top_level(def_node) then
      defs[#defs + 1] = { name_node = name_node, params_node = params_node, def_node = def_node }
    end
  end

  table.sort(comments, function(a, b)
    return a.row < b.row
  end)

  ---For a function starting at `frow`, collect the contiguous run of
  ---`---`-comments immediately above it, in original top-to-bottom order.
  ---@param frow integer 0-based row the function definition starts on.
  ---@return string[]
  local function doc_block_above(frow)
    local block = {}
    local want_row = frow - 1
    for i = #comments, 1, -1 do
      local c = comments[i]
      if c.erow == want_row then
        table.insert(block, 1, c.text)
        want_row = c.row - 1
      elseif c.erow < want_row then
        break
      end
    end
    return block
  end

  local out = {}
  ---@type { name: string, srow: integer, erow: integer }[]
  local ranges = {}
  for _, def in ipairs(defs) do
    if def.name_node and def.params_node then
      local name = vim.treesitter.get_node_text(def.name_node, src)
      local params_text = vim.treesitter.get_node_text(def.params_node, src)
      local frow, _, feorow = def.def_node:range()
      local raw_lines = doc_block_above(frow)

      -- Kept alongside the doc info, not derived later: this is the only place
      -- the definition's node — and therefore its end row — is in scope, and
      -- `docmap.calls` needs the span to attribute a call site to its caller.
      ranges[#ranges + 1] = { name = name, srow = frow, erow = feorow }

      -- Undocumented functions (no ---@param/---@return/prose above them)
      -- are real parts of the surface too, just with an empty doc block —
      -- skipping them would make `dead-see-target` and friends blind to
      -- exactly the functions most likely to need a @see fix-up.
      local parsed = parse_doc_block(raw_lines)
      local shape, shape_size = shape_of(def.def_node)

      out[#out + 1] = {
        name = name,
        signature = name .. params_text,
        summary = parsed.summary,
        line = frow + 1,
        -- The same span `ranges` above keeps for `calls.lua`, but published
        -- on the FunctionInfo too: `docmap.history` maps a diff hunk's
        -- changed lines onto whichever function contains them, which needs
        -- the end and not just the start. Derived here rather than later
        -- because this is the only place the definition node is in scope.
        line_end = feorow + 1,
        params = parsed.params,
        returns = parsed.returns,
        generic = parsed.generic,
        deprecated = parsed.deprecated,
        async = parsed.async,
        nodiscard = parsed.nodiscard,
        internal = parsed.internal,
        see = parsed.see,
        overload = parsed.overload,
        todo = parsed.todo,
        bug = parsed.bug,
        test = parsed.test,
        example = parsed.example,
        since = parsed.since,
        -- Computed unconditionally, unlike tested/documented below: this
        -- needs def.def_node, which only exists during this same scan
        -- pass — there is no later "resolve" step that could compute it
        -- from the IR alone the way coverage.resolve/doccoverage.resolve
        -- do, so it is done here or not at all.
        complexity = cyclomatic_complexity(def.def_node, src),
        -- Same reason, same pass: `duplicates.lua` groups by this, but only
        -- the tree can produce it.
        shape = shape,
        shape_size = shape_size,
        -- Set for real by `coverage.resolve`/`doccoverage.resolve` (opt-in,
        -- like tag_links); false here so a caller that never runs either
        -- still gets a real boolean rather than a nil that would need
        -- checking everywhere it's read.
        tested = false,
        documented = false,
      }
    end
  end

  table.sort(out, function(a, b)
    return a.line < b.line
  end)

  -- Deferred-load classification needs the parse, so it happens here rather
  -- than in `extract_source`; `deps` still owns the rule itself.
  require("documentation.core.deps").mark_deferred(root, src, requires)

  local calls_mod = require("documentation.core.calls")
  local calls = calls_mod.extract(root, src, ranges)

  -- How often each name is mentioned in this file, so a function passed
  -- around as a value is not mistaken for an unused one. Counted once for
  -- the whole file rather than per function.
  local ident_counts = calls_mod.identifier_counts(root, src)
  for _, fn in ipairs(out) do
    local bare = fn.name:match("([%w_]+)$") or fn.name
    -- Minus the declaration itself, which is one of the occurrences.
    fn.local_refs = math.max(0, (ident_counts[bare] or 1) - 1)
  end
  local symbols = require("documentation.core.symbols").extract(root, src, doc_block_above)
  return out, calls, requires, symbols, lines
end

return M
