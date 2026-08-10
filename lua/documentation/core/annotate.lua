---@module 'documentation.core.annotate'
--- Scaffolds a `---@module` header — and, when the file exports a table, a
--- `---@class` block with one `---@field` per exported name — for every file
--- `check.check_summaries` already flags as `missing-module-tag`. Closes the
--- gap between that finding being reported and it being fixed: today the only
--- path from "the check told me" to "the file says something true" is typing
--- the header by hand.
---
--- Deliberately a starting point, not a finished annotation: types are best
--- guesses (`fun(...)` reconstructed from already-parsed `@param`/`@return`
--- data for functions, the referenced `---@class` name when a field's value
--- already has one, `table`/`any` otherwise) and the one-line summary is a
--- `TODO` for a human to fill in. Generating a *wrong* confident type would
--- be worse than generating an honest placeholder.
---
--- The one hard rule: nothing at or below the module table's own declaration
--- (`local M = {}`) is ever touched. The generated block is inserted
--- immediately *above* that line — or, when it cannot be found, at the very
--- top of the file — never spliced into or after it.

---One candidate's generated block, plus enough of its own source to splice
---it in. `header`/`has_class`/`anchor` are what `preview_lines` reads;
---`apply` additionally needs `lines`/`path` to write the result.
---@class Documentation.AnnotatePlan
---@field node Documentation.Node
---@field path string Repo-relative path to the source file (`node.source`).
---@field module string Dotted module name `---@module` will declare.
---@field header string[] The generated block, one line per entry, no trailing blank line.
---@field anchor integer? 1-based line of `local <ident> = {}`; `nil` when the file has no such line to anchor above (insert at the top instead).
---@field has_class boolean Whether `header` ends in a `---@class`/`---@field` block.
---@field lines string[] The file's own lines, as read for this plan — stale the moment the file changes on disk.

local M = {}

---Every node this file can generate a header for: no `---@module` yet, and a
---real Lua source file backing it (namespaces and non-Lua backends have
---nothing here to scaffold — a namespace node has no file of its own, and a
---language whose module identity is not a `---@module` tag was already
---exempted by `check.check_summaries`'s own `wants_module_tag`).
---@param ir Documentation.IR
---@return Documentation.Node[]
function M.candidates(ir)
  local out = {}
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if
      node.kind ~= "namespace"
      and node.source
      and not node.module
      and node.source:match("%.lua$")
    then
      out[#out + 1] = node
    end
  end
  return out
end

---The identifier a file returns, if it returns a bare local (`return M`) or
---a wrapped one (`return setmetatable(M, ...)`). Same two shapes
---`symbols.lua`'s own `returned_name` recognises, duplicated rather than
---reused because that one runs on a treesitter node and this runs on raw
---lines read for the write path anyway — a second treesitter parse here
---would cost more than the four lines of duplication.
---@param lines string[]
---@return string?
local function export_ident(lines)
  for i = #lines, 1, -1 do
    local line = lines[i]
    local ident = line:match("^return%s+([%a_][%w_]*)%s*$")
      or line:match("^return%s+setmetatable%s*%(%s*([%a_][%w_]*)")
    if ident then
      return ident
    end
  end
  return nil
end

---1-based line number of `local <ident> = {}`, the anchor the generated
---block is inserted above. `nil` when the file returns something other than
---a plain empty-table local — a function, a value built up some other way —
---in which case there is no module table to describe and the caller falls
---back to a bare header at the top of the file.
---@param lines string[]
---@param ident string
---@return integer?
local function table_anchor(lines, ident)
  local pattern = "^local%s+" .. ident:gsub("%W", "%%%1") .. "%s*=%s*%{%s*%}"
  for i, line in ipairs(lines) do
    if line:match(pattern) then
      return i
    end
  end
  return nil
end

---Whether `lines[line1 - 1]` (and the contiguous comment run above it) is a
---`---@class Name` — the shape `check_type_vs_class` also looks for, here
---read straight off raw text instead of `scan.parse_header` because the
---block in question sits above an arbitrary symbol, not at the top of the
---file. Bounded to 20 lines up: a doc comment longer than that above a
---single field is not this generator's problem to solve.
---@param lines string[]
---@param line1 integer 1-based line the symbol/function starts on.
---@return string?
local function class_above(lines, line1)
  for i = line1 - 1, math.max(1, line1 - 20), -1 do
    local line = lines[i]
    if not line then
      break
    end
    local class = line:match("^%s*%-%-%-@class%s+(%S+)")
    if class then
      return class
    end
    if not line:match("^%s*%-%-%-?") then
      break
    end
  end
  return nil
end

---Reconstruct a `fun(...)` type from already-parsed `@param`/`@return`
---data. `any` for a param/return with no declared type — `Documentation.
---FunctionInfo` only has one to reconstruct from *undocumented* functions,
---which is exactly the case this generator exists for.
---@param fn Documentation.FunctionInfo
---@return string
local function fun_type(fn)
  local params = {}
  for _, p in ipairs(fn.params or {}) do
    params[#params + 1] = p.name
      .. (p.optional and "?" or "")
      .. ": "
      .. (p.type ~= "" and p.type or "any")
  end
  local returns = {}
  for _, r in ipairs(fn.returns or {}) do
    returns[#returns + 1] = r.type ~= "" and r.type or "any"
  end
  local sig = "fun(" .. table.concat(params, ", ") .. ")"
  if #returns > 0 then
    sig = sig .. ": " .. table.concat(returns, ", ")
  end
  return sig
end

---One `---@field` line's name and type for a function or symbol already
---known to belong to the exported table (`ident.name`, stripped to `name`).
---@param entry Documentation.FunctionInfo|Documentation.SymbolInfo
---@param is_function boolean
---@param lines string[]
---@return string name
---@return string type
local function field_of(entry, is_function, lines)
  local name = entry.name:match("%.([%w_]+)$") or entry.name
  if is_function then
    return name, fun_type(entry --[[@as Documentation.FunctionInfo]])
  end
  ---@cast entry Documentation.SymbolInfo
  if entry.kind == "table" then
    return name, class_above(lines, entry.line) or "table"
  end
  return name, "any"
end

---Build the generated block and where it goes, for one candidate node.
---Reads the file itself (candidates only ever come from a node that already
---names one), so this is the one place a stale read could happen — always
---call it right before `apply`, never cache the result across edits.
---@param node Documentation.Node
---@param root string
---@param lua_root string
---@return Documentation.AnnotatePlan?
function M.plan(node, root, lua_root)
  local check = require("documentation.core.check")
  local module_name = check.expected_module(node.source, lua_root)
  if not module_name then
    return nil
  end

  local read = require("lib.nvim.fs.read")
  local content = read(root .. "/" .. node.source)
  if not content then
    return nil
  end
  local lines = vim.split(content, "\n", { plain = true, trimempty = false })

  local header = {
    ("---@module '%s'"):format(module_name),
    "--- TODO: one-sentence description of this module.",
  }

  local anchor, has_class = nil, false
  if node.export == "table" then
    local ident = export_ident(lines)
    anchor = ident and table_anchor(lines, ident)
    if anchor and ident then
      local entries = {}
      for _, fn in ipairs(node.functions or {}) do
        if fn.name:sub(1, #ident + 1) == ident .. "." then
          entries[#entries + 1] = { line = fn.line, is_function = true, value = fn }
        end
      end
      for _, sym in ipairs(node.symbols or {}) do
        if sym.name:sub(1, #ident + 1) == ident .. "." then
          entries[#entries + 1] = { line = sym.line, is_function = false, value = sym }
        end
      end
      table.sort(entries, function(a, b)
        return a.line < b.line
      end)

      if #entries > 0 then
        has_class = true
        header[#header + 1] = ""
        header[#header + 1] = ("---@class %s"):format(module_name)
        local seen = {}
        for _, e in ipairs(entries) do
          local name, ty = field_of(e.value, e.is_function, lines)
          if not seen[name] then
            seen[name] = true
            header[#header + 1] = ("---@field %s %s"):format(name, ty)
          end
        end
      end
    end
  end

  return {
    node = node,
    path = node.source,
    module = module_name,
    header = header,
    anchor = anchor,
    has_class = has_class,
    lines = lines,
  }
end

---Preview lines for one plan, for the dry-run scratch buffer: a `-- path`
---separator followed by the generated block, byte-for-byte what `apply`
---would write.
---@param plan Documentation.AnnotatePlan
---@return string[]
function M.preview_lines(plan)
  local out = { ("-- %s"):format(plan.path) }
  vim.list_extend(out, plan.header)
  return out
end

---Write the plan's generated block. `"inline"` splices it above the anchor
---line (or at the top of the file when there is none) in the real file;
---`"sidecar"` writes it to `<path>.annot.lua` next to it instead, touching
---nothing in the original — the review-before-you-commit option the module
---docstring's "starting point, not a finished annotation" is for.
---@param plan Documentation.AnnotatePlan
---@param root string
---@param mode "inline"|"sidecar"
---@return boolean ok
---@return string? err
function M.apply(plan, root, mode)
  local write = require("lib.nvim.fs.write.to_file")
  local abs = root .. "/" .. plan.path

  if mode == "sidecar" then
    local block = table.concat(plan.header, "\n")
      .. "\n\n-- Generated by :DocMap annotate. Review, then move the lines\n"
      .. "-- above into "
      .. plan.path
      .. ", right above `local ... = {}`, and delete this file.\n"
    return write(abs .. ".annot.lua", block)
  end

  local insert_at = plan.anchor or 1
  local out = {}
  for i = 1, insert_at - 1 do
    out[#out + 1] = plan.lines[i]
  end
  vim.list_extend(out, plan.header)
  -- A `---@class`/`---@field` block must sit directly above the line it
  -- describes with no blank line — LuaLS attaches a doc comment to the next
  -- statement immediately, not across a gap. A bare `---@module` block has no
  -- such requirement, so it gets a blank line for readability instead.
  if not plan.has_class then
    out[#out + 1] = ""
  end
  for i = insert_at, #plan.lines do
    out[#out + 1] = plan.lines[i]
  end
  return write(abs, table.concat(out, "\n"))
end

return M
