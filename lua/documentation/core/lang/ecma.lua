---@module 'documentation.core.lang.ecma'
--- Shared extraction for JavaScript, TypeScript and TSX — the real work
--- behind the three thin registrations in `js.lua`/`ts.lua`/`tsx.lua`, the
--- same relationship `functions.lua` has to `core/lang/lua.lua`. One
--- implementation, parametrized by grammar name, because the three
--- grammars agree on every shape this module actually reads — verified
--- against real parses (see `docs/ROADMAP/IDEAS/MULTILANG.md`'s own warning that
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
---
--- Calls (`extract_calls`) and `local_refs` (`identifier_counts`) are real
--- too, same-file only: a bare call (`helper()`) resolves through
--- `calls.lua`'s own language-agnostic resolver with no changes there at
--- all — it never touched a treesitter node to begin with. Cross-file
--- resolution is not attempted: JS's named imports bind a function
--- directly into scope rather than through an alias-plus-member shape the
--- way `local fs = require(...)` then `fs.read()` does in Lua, and
--- `extract_requires` below does not yet record which names an import
--- bound — a real, separate task, not a small extension of this one. A
--- member-expression call (`obj.method()`) is captured too, but matches no
--- resolver branch and is silently dropped, the same honest degradation an
--- unknown Lua receiver already gets.
---
--- Symbols (`extract_symbols`) are real too: module-scope `const`/`let`/`var`
--- bindings that are neither a function (`as_function` already claims that
--- declarator) nor a `require()` call (`extract_requires` already claims
--- that one), mirroring `documentation.core.symbols`'s own Lua scope and
--- classification (table/constant/binding). Unlike Lua, there is no
--- export-table name to filter out — JS/TS has no single chunk-level
--- "this is the module" return the way `local M = {}` / `return M` is, so
--- every qualifying binding is reported, not just the non-exported ones.

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

-- Parsing the same fixed query string is redundant work per-call -- there
-- are only a handful of grammars (js/ts/tsx), so an LRU keyed on `lang` is
-- effectively a cache of size 1-3 in practice. Reuses lib.nvim's memoizer
-- (already a hard dependency of this repo's core/) rather than hand-rolling
-- another cache table, matching `call_query_cache`/`ident_query_cache`
-- below in spirit but through the shared primitive.
local memo = require("lib.lua.memo")
local parse_complexity_query = memo.fn(function(lang)
  return vim.treesitter.query.parse(lang, COMPLEXITY_PATTERN)
end, { size = 8 })

---@param def_node TSNode
---@param lang string
---@return integer
local function complexity(def_node, lang, src)
  local query = parse_complexity_query(lang)
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
---shared shape is right, not before — see `docs/ROADMAP/IDEAS/MULTILANG.md`.
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
  local snippet, snippet_omitted = require("documentation.core.snippet").extract(src, srow, erow)

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
    is_hook = is_hook_name(name),
    -- Bounded, embeddable tier of `docs/ECOSYSTEM.md` §3.5's hover preview
    -- — shared with the Lua backend via `core/snippet.lua` rather than
    -- reimplemented here, since the bounding rule is a policy decision,
    -- not a per-language fact.
    snippet = snippet,
    snippet_omitted = snippet_omitted,
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

---Collapse a value expression to one short line for display — the same
---policy `documentation.core.symbols`'s own `condense` uses for Lua.
---@param text string
---@return string
local function condense(text)
  local flat = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if #flat > 48 then
    flat = flat:sub(1, 47) .. "…"
  end
  return flat
end

---Classify a module-scope binding's value expression, mirroring
---`documentation.core.symbols`'s own `classify` for Lua. Two shapes are
---excluded (return `nil`), because another stage already owns them:
---
---   arrow_function/function_expression   -> `as_function` already claims
---                                            this declarator as a function
---   require("…") call_expression         -> `extract_requires` already
---                                            models this as a dependency
---
---Verified against a real parse (see this file's own header and
---`docs/ROADMAP/IDEAS/MULTILANG.md`): `object`/`array` literals, `number`/
---`string`/`true`/`false` primitives (JS has no single "boolean" node type —
---`true` and `false` are distinct), `null`/`undefined` (JS-only shapes with
---no Lua equivalent; both fall through to "binding", the same as any other
---unlisted Lua literal would), and anything else (`binary_expression`, a
---bare identifier reference, a non-`require` call) evaluated at load time.
---@param value TSNode
---@param src string
---@return Documentation.SymbolKind? kind
---@return string detail
local function classify_symbol(value, src)
  local ty = value:type()

  if ty == "arrow_function" or ty == "function_expression" then
    return nil, ""
  end
  if ty == "call_expression" then
    local fn = value:field("function")[1]
    if fn and vim.treesitter.get_node_text(fn, src) == "require" then
      return nil, ""
    end
  end

  if ty == "object" or ty == "array" then
    -- Every named child is a real member for either shape: `pair`,
    -- `shorthand_property_identifier` and `spread_element` all count for an
    -- object; an element expression counts for an array. Broader than
    -- Lua's own `count_fields` (which only counts `field` nodes), and
    -- correctly so — JS object literals have more member shapes than Lua
    -- table constructors do, verified against a real parse of `{ a, b, c:
    -- 3, ...rest }` (two `shorthand_property_identifier`s, one `pair`, one
    -- `spread_element`).
    local n = value:named_child_count()
    local noun = ty == "object" and "field" or "element"
    return "table", n > 0 and (n .. " " .. noun .. (n == 1 and "" or "s")) or "empty"
  end
  if ty == "number" or ty == "string" or ty == "true" or ty == "false" then
    return "constant", condense(vim.treesitter.get_node_text(value, src))
  end

  return "binding", condense(vim.treesitter.get_node_text(value, src))
end

---Module-scope symbols from one top-level statement — `documentation.core.
---symbols`'s own scope, extended to JS/TS/TSX. Every `variable_declarator`
---in the statement is considered independently (not just the first, unlike
---`extract_requires`'s accepted narrow gap there), so `const helper = () =>
---{}, CONFIG = {...};` correctly reports only `CONFIG` — `classify_symbol`
---excludes `helper`'s arrow-function value on its own, so there is no
---double-count against `as_function` claiming `helper` from the same
---statement.
---
---No equivalent of Lua's `local M = {}` / `return M` export-table filter is
---applied — JS/TS has no single chunk-level "this is the module" return the
---way a Lua `require()`d file does (see this file's own header on module
---identity), so there is no analogous name to exclude. Every non-function,
---non-`require` module-scope binding is reported.
---@param stmt_node TSNode The original statement — export_statement or the declaration itself — for `leading_jsdoc`'s sibling check.
---@param unwrapped TSNode The declaration, export unwrapped.
---@param src string
---@return Documentation.SymbolInfo[]
local function extract_symbols(stmt_node, unwrapped, src)
  local out = {}
  local ty = unwrapped:type()
  if ty ~= "lexical_declaration" and ty ~= "variable_declaration" then
    return out
  end

  for i = 0, unwrapped:named_child_count() - 1 do
    local decl = unwrapped:named_child(i)
    if decl:type() == "variable_declarator" then
      local name_node = decl:field("name")[1]
      local value_node = decl:field("value")[1]
      if name_node and name_node:type() == "identifier" and value_node then
        local kind, detail = classify_symbol(value_node, src)
        if kind then
          local doc = leading_jsdoc(stmt_node, src)
          local parsed = doc and parse_jsdoc(doc)
          local srow = name_node:range()
          out[#out + 1] = {
            name = vim.treesitter.get_node_text(name_node, src),
            kind = kind,
            detail = detail,
            summary = parsed and parsed.summary or "",
            line = srow + 1,
          }
        end
      end
    end
  end
  return out
end

---Parsed queries are per-grammar (`javascript`/`typescript`/`tsx` each
---produce a distinct query object even for identical query text), so each
---is parsed once per grammar and cached rather than reparsed per file.
---
--- Structurally the same query `calls.lua` parses for Lua's own
--- `function_call name: (_) @callee`: capture every call site's callee
--- expression, whatever shape it is, and let the caller decide what to
--- do with the text. Verified against a real parse: a bare call's
--- `function` field is an `identifier` (`helper()`); a method-shaped
--- call's is a `member_expression` whose text reconstructs as
--- `obj.method` — both are meaningful text for `calls.lua`'s own
--- language-agnostic resolver to try matching, unchanged.
---@param lang string
local call_query = memo.fn(function(lang)
  return vim.treesitter.query.parse(lang, "(call_expression function: (_) @callee) @call")
end, { size = 8 })

---Every call site in the file, attributed to the top-level function
---(`ranges`) whose span contains it — the same two-input shape
---`calls.lua`'s own `M.extract` takes for Lua, so `calls.lua`'s
---language-agnostic `M.build` resolves these with no JS-specific branch:
---a bare callee resolves against this file's own declared functions the
---same way an unqualified Lua call does, and a `head.rest`-shaped callee
---resolves against a require alias exactly the way `fs.read(...)` does
---for a Lua `local fs = require(...)`. A member-expression callee whose
---head is neither — the shape a class instance's `obj.method()` is, with
---no owning-scope model behind it yet (see this file's own header) —
---simply matches nothing in `calls.lua`'s resolver and is silently
---dropped, the same honest degradation an unknown Lua receiver already
---gets there.
---@param root TSNode
---@param src string
---@param lang string
---@param ranges { name: string, srow: integer, erow: integer }[] 0-based rows, mirroring `calls.lua`'s own `defs` shape.
---@return Documentation.RawCall[]
local function extract_calls(root, src, lang, ranges)
  local out = {}
  local query = call_query(lang)
  for id, node in query:iter_captures(root, src) do
    if query.captures[id] == "callee" then
      local srow = node:range()
      local callee = vim.treesitter.get_node_text(node, src)
      -- A multi-line callee (a chained call broken across lines) would
      -- carry a newline into the text and never match any resolver
      -- pattern — skipped here, the same reason `calls.lua`'s own
      -- extraction skips one, so `calls.lua` never has to special-case it.
      if not callee:find("\n") then
        local from_fn
        for _, r in ipairs(ranges) do
          if srow >= r.srow and srow <= r.erow then
            from_fn = r.name
            break
          end
        end
        out[#out + 1] = { callee = callee, from_fn = from_fn, line = srow + 1 }
      end
    end
  end
  return out
end

-- `identifier` only — never `property_identifier`, the node type a
-- member expression's right-hand side gets (verified against the same
-- parse `extract_calls`'s own header describes) — so a `.length`-style
-- property access never inflates a same-named function's count.
---@param lang string
local ident_query = memo.fn(function(lang)
  return vim.treesitter.query.parse(lang, "(identifier) @id")
end, { size = 8 })

---How often each identifier appears in the file, by name — mirrors
---`calls.lua`'s own `M.identifier_counts` for the same reason: a function
---passed as a value (`arr.map(helper)`) is used but has no call site
---naming it, so `extract_calls` alone would miss it.
---@param root TSNode
---@param src string
---@param lang string
---@return table<string, integer>
local function identifier_counts(root, src, lang)
  local counts = {}
  local query = ident_query(lang)
  for id, node in query:iter_captures(root, src) do
    if query.captures[id] == "id" then
      local text = vim.treesitter.get_node_text(node, src)
      counts[text] = (counts[text] or 0) + 1
    end
  end
  return counts
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
---@return Documentation.FunctionInfo[], Documentation.RawRequire[], Documentation.SymbolInfo[]
local function walk(root, src, lang)
  local functions, requires, symbols = {}, {}, {}
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
    if
      stmt:type() == "import_statement"
      or unwrapped:type() == "lexical_declaration"
      or unwrapped:type() == "variable_declaration"
    then
      for _, r in
        ipairs(extract_requires(stmt:type() == "import_statement" and stmt or unwrapped, src))
      do
        requires[#requires + 1] = r
      end
    end
    -- Every declarator in the statement is considered independently — no
    -- `if not fn` guard needed, since `classify_symbol` already excludes a
    -- function-shaped declarator on its own (see `extract_symbols`'s own
    -- header for the multi-declarator case this handles correctly).
    for _, s in ipairs(extract_symbols(stmt, unwrapped, src)) do
      symbols[#symbols + 1] = s
    end
  end
  table.sort(functions, function(a, b)
    return a.line < b.line
  end)
  table.sort(symbols, function(a, b)
    return a.line < b.line
  end)
  return functions, requires, symbols
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

---Conventional source roots for a JS/TS project, in the order a reader
---would look. Not a guess: each is only accepted when it actually holds a
---file this backend claims, so a Lua repository with a `src/` of shell
---scripts is not mistaken for a JavaScript one.
---@type string[]
local ECMA_ROOTS = { "src", "lib", "app", "source" }

---Does `dir` hold a file `claims` accepts, anywhere below it?
---
---Depth-bounded and stops at the first hit: this runs during option
---resolution, before any scan, and "is there evidence of this language here"
---does not need an exhaustive walk to answer. Vendored trees are skipped so
---a `node_modules` full of JavaScript cannot make an unrelated directory
---look like the project's own source.
---@param dir string
---@param claims fun(filename: string): boolean
---@param depth integer
---@return boolean
local function holds_source(dir, claims, depth)
  if depth <= 0 or vim.fn.isdirectory(dir) == 0 then
    return false
  end
  for name, kind in vim.fs.dir(dir) do
    if kind == "file" then
      if claims(name) then
        return true
      end
    elseif kind == "directory" and not require("documentation.core.scan").VENDOR_DIRS[name] then
      if holds_source(dir .. "/" .. name, claims, depth - 1) then
        return true
      end
    end
  end
  return false
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

  local function is_source(filename)
    local ext = filename:match("%.([%w]+)$")
    return ext ~= nil and ext_set[ext] == true
  end

  return {
    name = name,
    grammar = lang,
    -- The list `is_source` closes over below, kept enumerable: the page
    -- needs to know which extensions map to this glossary, and a predicate
    -- cannot be asked that.
    extensions = extensions,
    -- One glossary for all three registrations. `satisfies` in a `.js` file
    -- gets the answer "this is TypeScript, it does not exist here", which is
    -- information rather than an error -- see the glossary's own header.
    glossary = require("documentation.core.lang.glossary.ecma"),
    module_file = module_file,
    module_tag = false,
    is_source = is_source,
    ---`nil` unless one of the conventional roots actually holds a file this
    ---backend claims — see `Documentation.LangBackend.detect_source` on why
    ---answering unconditionally is the bug rather than the feature.
    ---
    ---Falls back to the repository root itself when a file this backend
    ---claims sits directly in it, which is the shape of a small package with
    ---no `src/`. Last resort rather than first guess: scanning from the root
    ---pulls in everything the walk does not skip.
    detect_source = function(root)
      for _, candidate in ipairs(ECMA_ROOTS) do
        if holds_source(root .. "/" .. candidate, is_source, 6) then
          return candidate
        end
      end
      if holds_source(root, is_source, 1) then
        return "."
      end
      return nil
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
        -- Was six values, one short of the contract's seven: `0` landed in
        -- the `endpoints` slot and `lines` came back nil. Only reachable for
        -- an unreadable file, which is why it went unnoticed.
        return {}, {}, {}, {}, {}, {}, 0, {}
      end
      local src = fd:read("*a")
      fd:close()
      local _, newlines = src:gsub("\n", "")
      local lines = #src == 0 and 0 or (newlines + (src:sub(-1) == "\n" and 0 or 1))

      local ok, parser = pcall(vim.treesitter.get_string_parser, src, lang)
      if not ok then
        return {}, {}, {}, {}, {}, {}, lines, {}
      end
      local ok_parse, trees = pcall(function()
        return parser:parse()
      end)
      if not ok_parse or not trees or not trees[1] then
        return {}, {}, {}, {}, {}, {}, lines, {}
      end

      local root = trees[1]:root()
      local functions, requires, symbols = walk(root, src, lang)

      -- Ranges derived from the already-built functions rather than
      -- collected as a separate pass: `line`/`line_end` are already the
      -- right (1-based) span, converting is cheaper than re-walking the
      -- tree to re-derive what `walk` already computed.
      local ranges = {}
      for _, fn in ipairs(functions) do
        ranges[#ranges + 1] = { name = fn.name, srow = fn.line - 1, erow = fn.line_end - 1 }
      end
      local calls = extract_calls(root, src, lang, ranges)

      local ident_counts = identifier_counts(root, src, lang)
      for _, fn in ipairs(functions) do
        -- Minus the declaration itself, which is one of the occurrences —
        -- the same accounting `functions.lua` does for Lua.
        fn.local_refs = math.max(0, (ident_counts[fn.name] or 1) - 1)
      end

      -- Call-based route registrations — Express/Fastify/Koa-shaped, see
      -- `core/endpoints.lua`'s own header for exactly what is recognized.
      -- Given `functions`/`requires` this file's own scan already produced,
      -- for the `documented`/`framework` cross-references.
      local endpoints =
        require("documentation.core.endpoints").extract(root, src, lang, functions, requires)

      -- Fifth slot (`plugins`) is Lua+lazy.nvim-specific, per the shared
      -- `scan_file` contract — see `docs/FRAMEWORK_CONVENTIONS.md`.
      return functions, calls, requires, symbols, {}, endpoints, lines, {}
    end,
  }
end

return M
