---@module 'documentation.core.lang.ecma'
--- Shared extraction for JavaScript, TypeScript and TSX — the real work
--- behind the three thin registrations in `js.lua`/`ts.lua`/`tsx.lua`, the
--- same relationship `functions.lua` has to `core/lang/lua.lua`. One
--- implementation, parametrized by grammar name, because the three
--- grammars agree on every shape this module actually reads — verified
--- against real parses (see `docs/ROADMAP/MULTILANG.md`'s own warning that
--- claims here are task descriptions until checked against something real;
--- this module's shapes *have* been checked, unlike that document's).
---
--- ## Scope, stated narrowly on purpose
---
--- Four function forms: `function name(...) {}`, `const/let name = (...) =>
--- {}`, `const/let name = function(...) {}`, and any of those wrapped in
--- `export` or `export default`. Not covered, and not silently guessed at:
--- class methods, object-literal methods, `module.exports = {...}` (the
--- CommonJS export-object idiom), and generator/IIFE forms. A file using
--- only those contributes no functions, the same honest degradation
--- `functions.lua` gives a Lua file it cannot parse a def out of.
---
--- Imports: ESM `import ... from "..."` (default, named, namespace) and
--- CommonJS `require("...")` assigned to a `const`/`let`. Dynamic
--- `import()` and `require(expr .. var)` are not resolved, matching
--- `deps.lua`'s own stated position that a computed target is not
--- something to guess at.
---
--- Module identity is the file path itself — unlike Lua, nothing here ever
--- sets `Documentation.Header.module`. ESM/CommonJS resolve modules by
--- path, not by an internal tag, so there is no separate "declared name"
--- for `check.lua`'s `module-path-mismatch` to verify against; `check.lua`'s
--- `missing-module-tag` is told not to expect one either, via
--- `Documentation.LangBackend.module_tag = false` on each registration
--- below.
---
--- `complexity`/`shape` are real, computed here, not left as a placeholder:
--- both are structural concepts (decision points; a hash of node *types*)
--- that apply to any grammar, verified against this grammar's own real node
--- names rather than assumed to match Lua's (`elseif_statement`/
--- `repeat_statement` do not exist here; `else if` is a nested
--- `if_statement`, and JS has a `ternary_expression` and `switch_case` Lua
--- has no equivalent of).

local M = {}

---One decision point each for `if`/`while`/`for`/`for-in`-or-`for-of`
---(one node type covers both)/`? :`/`switch case`, plus `&&`/`||`. No
---`elseif` — JS has no such node, `else if` is a nested `if_statement`
---inside an `else_clause`, which this already walks into as part of the
---same subtree.
local COMPLEXITY_PATTERN = [[
[
  (if_statement)
  (while_statement)
  (for_statement)
  (for_in_statement)
  (ternary_expression)
  (switch_case)
] @branch

(binary_expression "&&") @branch
(binary_expression "||") @branch
]]

---@param def_node TSNode
---@param lang string
---@return integer
local function complexity(def_node, lang, src)
  local query = vim.treesitter.query.parse(lang, COMPLEXITY_PATTERN)
  local n = 1
  for _ in query:iter_captures(def_node, src) do
    n = n + 1
  end
  return n
end

---Same algorithm as `functions.lua`'s own `shape_of`: a hash of node
---*types* over the whole subtree, in tree order, never text. Duplicated
---rather than shared — the algorithm itself is language-agnostic (it only
---calls `:type()`/`:child()`), but `functions.lua` does not currently
---expose it as a public function, and this is real, working code rather
---than a refactor of Lua's own path. Unifying the two behind one shared
---helper is worth doing once a second language actually exists to prove the
---shared shape is right, not before — see `docs/ROADMAP/MULTILANG.md`.
---@param def_node TSNode
---@return string shape
---@return integer size
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
    for i = node:child_count() - 1, 0, -1 do
      stack[#stack + 1] = node:child(i)
    end
  end
  return ("%x-%x"):format(h1, h2), size
end

---True for a name shaped like React's own hook convention — the one
---naming rule the whole ecosystem already depends on (it is how
---`eslint-plugin-react-hooks` itself knows what to lint), so recognizing
---it is reading an existing contract, not inventing one. See
---`docs/FRAMEWORK_CONVENTIONS.md` on why a *map* of hooks is the
---underserved half of this and rule-checking is not attempted here.
---@param name string
---@return boolean
local function is_hook_name(name)
  return name:match("^use%u") ~= nil
end

---Parse one JSDoc `/** ... */` block into the same shape `functions.lua`'s
---own doc-block parser produces, so `Documentation.FunctionInfo`'s
---consumers (coverage, doccoverage, the Analysis panels, `--check`) need no
---per-language branch to read it.
---
---Deliberately narrow: `@param`/`@returns`/`@return`/`@deprecated`/
---`@internal`/`@private` only. `@see`/`@overload`/`@todo`/`@bug`/`@test`/
---`@example`/`@since`/`@generic` are real JSDoc-adjacent conventions with
---no parser here yet — left empty/nil/false, the same honest gap
---`core/plugins.lua` leaves `dependencies` at `{}` for a spec it cannot
---read, not a silent wrong answer.
---@param text string Raw comment text, including `/**`/`*/`.
---@return { summary: string, body: string, params: Documentation.ParamInfo[], returns: Documentation.ReturnInfo[], deprecated: string?, internal: boolean }
local function parse_jsdoc(text)
  local inner = text:gsub("^/%*%*?", ""):gsub("%*/$", "")
  local lines = {}
  for line in (inner .. "\n"):gmatch("([^\n]*)\n") do
    -- Strip a leading `*` (JSDoc's per-line convention) and one following
    -- space, if present — not more, since a genuinely indented code sample
    -- inside the block should keep its own indentation.
    lines[#lines + 1] = (line:gsub("^%s*%*%s?", ""))
  end

  local prose = {}
  local params, returns = {}, {}
  local deprecated, internal = nil, false

  for _, line in ipairs(lines) do
    local tag, rest = line:match("^@(%a+)%s*(.*)$")
    if tag == "param" then
      -- `@param {type} name description` — the type is optional, and so is
      -- the brace form; both are real JSDoc usage.
      local typ, name, desc = rest:match("^{([^}]*)}%s*(%S+)%s*(.*)$")
      if not name then
        name, desc = rest:match("^(%S+)%s*(.*)$")
      end
      if name then
        local optional = name:sub(1, 1) == "[" and name:sub(-1) == "]"
        if optional then
          name = name:sub(2, -2):gsub("=.*$", "")
        end
        params[#params + 1] =
          { name = name, type = typ or "", optional = optional, desc = desc or "" }
      end
    elseif tag == "returns" or tag == "return" then
      local typ, desc = rest:match("^{([^}]*)}%s*(.*)$")
      returns[#returns + 1] = { type = typ or "", desc = desc or rest }
    elseif tag == "deprecated" then
      deprecated = rest ~= "" and rest or "deprecated"
    elseif tag == "internal" or tag == "private" then
      internal = true
    elseif not tag then
      prose[#prose + 1] = line
    end
  end

  local prose_text = table.concat(prose, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
  local summary, body = prose_text:match("^(.-[%.!?])%s*\n?\n?(.*)$")
  if not summary then
    summary, body = prose_text, ""
  end

  return {
    summary = summary or "",
    body = (body or ""):gsub("^%s+", ""),
    params = params,
    returns = returns,
    deprecated = deprecated,
    internal = internal,
  }
end

---The JSDoc block immediately preceding `node` (no blank line between the
---comment's last line and `node`'s first), or `nil`.
---@param node TSNode
---@param src string
---@return string?
local function leading_jsdoc(node, src)
  local prev = node:prev_sibling()
  if not prev or prev:type() ~= "comment" then
    return nil
  end
  local text = vim.treesitter.get_node_text(prev, src)
  if not text:match("^/%*%*") then
    -- A `//` line comment or a plain `/* */` block: real, but not JSDoc,
    -- and guessing structure out of free-form prose is the kind of guess
    -- this scanner declines to make elsewhere.
    return nil
  end
  return text
end

---True when `func_node` (an `arrow_function`/`function_expression`/
---`function_declaration`) is itself marked `async` — a real AST fact, not
---a JSDoc tag, since JS's own `async` keyword is authoritative and a tag
---could lie.
---@param func_node TSNode
---@return boolean
local function is_async(func_node)
  for i = 0, func_node:child_count() - 1 do
    if func_node:child(i):type() == "async" then
      return true
    end
  end
  return false
end

---Build one `Documentation.FunctionInfo` from a name node, its function
---node (the thing that is actually `async`/has parameters/a body) and the
---statement node doc-comments attach to.
---@param name_node TSNode
---@param func_node TSNode
---@param stmt_node TSNode Statement-level node `leading_jsdoc` checks siblings of.
---@param src string
---@param lang string Grammar name, for the complexity query — a `TSTree` has
---no `:lang()` of its own in this Neovim's treesitter API (only the parser
---that produced it does), so this is threaded down from `M.backend` rather
---than re-derived from `func_node:tree()`.
---@return Documentation.FunctionInfo
local function build_fn(name_node, func_node, stmt_node, src, lang)
  local name = vim.treesitter.get_node_text(name_node, src)
  local params_node = func_node:field("parameters")[1]
  local params_text = params_node and vim.treesitter.get_node_text(params_node, src) or "()"
  local srow, _, erow = func_node:range()

  local doc = leading_jsdoc(stmt_node, src)
  local parsed = doc and parse_jsdoc(doc)
    or { summary = "", body = "", params = {}, returns = {}, deprecated = nil, internal = false }

  local shape, shape_size = shape_of(func_node)

  return {
    name = name,
    signature = name .. params_text,
    summary = parsed.summary,
    line = srow + 1,
    line_end = erow + 1,
    params = parsed.params,
    returns = parsed.returns,
    generic = {},
    deprecated = parsed.deprecated,
    async = is_async(func_node),
    nodiscard = false,
    local_refs = 0,
    complexity = complexity(func_node, lang, src),
    shape = shape,
    shape_size = shape_size,
    internal = parsed.internal,
    see = {},
    overload = {},
    todo = {},
    bug = {},
    test = {},
    example = nil,
    since = nil,
    tested = false,
    documented = false,
    -- Not a real field on the type today, but harmless to carry; a future
    -- Analysis panel reading it needs no IR change to start from something.
    is_hook = is_hook_name(name),
  }
end

---One `Documentation.RawRequire` per import, from either form.
---@param stmt_node TSNode A top-level statement (import_statement or a lexical_declaration holding a require() call).
---@param src string
---@return Documentation.RawRequire[]
local function extract_requires(stmt_node, src)
  local out = {}
  local srow = stmt_node:range()

  if stmt_node:type() == "import_statement" then
    local source_node = stmt_node:field("source")[1]
    local module = source_node
      and vim.treesitter.get_node_text(source_node, src):gsub("^[\"']", ""):gsub("[\"']$", "")
    if module then
      out[#out + 1] = { module = module, line = srow + 1 }
    end
    return out
  end

  -- CommonJS: `const x = require("y")`, one `variable_declarator` at a
  -- time — a single `const a = require("x"), b = require("y")` is real but
  -- rare enough that only the first declarator being read is an accepted,
  -- narrow gap here, not a silent wrong answer (the second simply does not
  -- appear, the same way an unreadable plugin-spec entry does not).
  for i = 0, stmt_node:child_count() - 1 do
    local child = stmt_node:child(i)
    if child:type() == "variable_declarator" then
      local value = child:field("value")[1]
      if value and value:type() == "call_expression" then
        local fn = value:field("function")[1]
        if fn and vim.treesitter.get_node_text(fn, src) == "require" then
          local args = value:field("arguments")[1]
          local first = args and args:named_child(0)
          if first and first:type() == "string" then
            local content = first:named_child(0)
            local module = content and vim.treesitter.get_node_text(content, src)
            if module then
              out[#out + 1] = { module = module, line = srow + 1 }
            end
          end
        end
      end
    end
  end
  return out
end

---Recognize one top-level statement as a function definition, unwrapping
---`export`/`export default` first (both wrap the same `declaration` field,
---verified against a real parse — there is no separate marker node to
---distinguish them structurally that this cares about).
---@param stmt_node TSNode
---@param src string
---@param lang string
---@return Documentation.FunctionInfo?
local function as_function(stmt_node, src, lang)
  local node = stmt_node
  if node:type() == "export_statement" then
    node = node:field("declaration")[1]
    if not node then
      return nil
    end
  end

  if node:type() == "function_declaration" then
    local name_node = node:field("name")[1]
    if name_node then
      return build_fn(name_node, node, stmt_node, src, lang)
    end
    return nil
  end

  if node:type() == "lexical_declaration" or node:type() == "variable_declaration" then
    for i = 0, node:child_count() - 1 do
      local child = node:child(i)
      if child:type() == "variable_declarator" then
        local value = child:field("value")[1]
        if
          value and (value:type() == "arrow_function" or value:type() == "function_expression")
        then
          local name_node = child:field("name")[1]
          if name_node and name_node:type() == "identifier" then
            return build_fn(name_node, value, stmt_node, src, lang)
          end
        end
      end
    end
  end

  return nil
end

---@param root TSNode
---@param src string
---@param lang string
---@return Documentation.FunctionInfo[], Documentation.RawRequire[]
local function walk(root, src, lang)
  local functions, requires = {}, {}
  for i = 0, root:child_count() - 1 do
    local stmt = root:child(i)
    local fn = as_function(stmt, src, lang)
    if fn then
      functions[#functions + 1] = fn
    end
    local unwrapped = stmt
    if stmt:type() == "export_statement" then
      unwrapped = stmt:field("declaration")[1] or stmt
    end
    if stmt:type() == "import_statement" or unwrapped:type() == "lexical_declaration" then
      for _, r in
        ipairs(extract_requires(stmt:type() == "import_statement" and stmt or unwrapped, src))
      do
        requires[#requires + 1] = r
      end
    end
  end
  table.sort(functions, function(a, b)
    return a.line < b.line
  end)
  return functions, requires
end

---The leading module-level JSDoc block, if the very first statement-level
---sibling of the program root is a comment shaped like one. Used for
---`Documentation.Header.summary`/`body` only — `module` is never set here,
---see this file's own header for why.
---@param root TSNode
---@param src string
---@return Documentation.Header
local function file_header(root, src)
  local first = root:child(0)
  if first and first:type() == "comment" then
    local text = vim.treesitter.get_node_text(first, src)
    if text:match("^/%*%*") then
      local parsed = parse_jsdoc(text)
      return { module = nil, summary = parsed.summary, body = parsed.body, tags = {} }
    end
  end
  return { module = nil, summary = "", body = "", tags = {} }
end

---Build one backend table for `lang` (a `vim.treesitter` language name),
---registered under `name` for the given extensions.
---@param name string
---@param lang string Grammar name passed to `vim.treesitter.get_string_parser`.
---@param extensions string[] Bare extensions this backend claims, e.g. `{"js"}`.
---@param module_file string? See `Documentation.LangBackend.module_file`.
---@return Documentation.LangBackend
function M.backend(name, lang, extensions, module_file)
  local ext_set = {}
  for _, e in ipairs(extensions) do
    ext_set[e] = true
  end

  return {
    name = name,
    module_file = module_file,
    module_tag = false,
    is_source = function(filename)
      local ext = filename:match("%.([%w]+)$")
      return ext ~= nil and ext_set[ext] == true
    end,
    parse_header = function(path)
      local fd = io.open(path, "rb")
      if not fd then
        return { module = nil, summary = "", body = "", tags = {} }
      end
      local src = fd:read("*a")
      fd:close()
      local ok, parser = pcall(vim.treesitter.get_string_parser, src, lang)
      if not ok then
        return { module = nil, summary = "", body = "", tags = {} }
      end
      local ok_parse, trees = pcall(function()
        return parser:parse()
      end)
      if not ok_parse or not trees or not trees[1] then
        return { module = nil, summary = "", body = "", tags = {} }
      end
      return file_header(trees[1]:root(), src)
    end,
    scan_file = function(path)
      local fd = io.open(path, "rb")
      if not fd then
        return {}, {}, {}, {}, {}, 0
      end
      local src = fd:read("*a")
      fd:close()
      local _, newlines = src:gsub("\n", "")
      local lines = #src == 0 and 0 or (newlines + (src:sub(-1) == "\n" and 0 or 1))

      local ok, parser = pcall(vim.treesitter.get_string_parser, src, lang)
      if not ok then
        return {}, {}, {}, {}, {}, lines
      end
      local ok_parse, trees = pcall(function()
        return parser:parse()
      end)
      if not ok_parse or not trees or not trees[1] then
        return {}, {}, {}, {}, {}, lines
      end

      local functions, requires = walk(trees[1]:root(), src, lang)
      -- calls/symbols are real gaps, not silent zeros pretending to be a
      -- resolved answer — see this file's own header.
      return functions, {}, requires, {}, {}, lines
    end,
  }
end

return M
