---@module 'documentation.core.lang.zig'
--- Zig, registered as a language backend.
---
--- **The closest fit of any language added so far**, and that is why it went
--- first among the ones asked for. Zig's documentation convention is not a
--- comment format bolted onto comments — it is part of the language:
--- `//!` documents the file, `///` documents the declaration below it, and
--- `pub` is visibility rather than a naming convention. Each of those maps
--- onto something this tool already models, so this backend translates
--- rather than approximates.
---
--- Three consequences worth stating, because each is a decision that a
--- future backend for a less convenient language will not get for free:
---
--- * **`module_tag = false`.** A Zig file's identity *is* its path — imports
---   resolve by path — so there is no tag that could be missing and
---   `check.lua`'s `missing-module-tag` would report every file forever.
--- * **`module_file = nil`.** Zig has no directory-owns-a-module convention
---   the way Lua has `init.lua`; every file is its own module. A directory
---   is therefore a namespace and nothing else.
--- * **Visibility is real.** `pub fn` is exported, `fn` is not, and that is
---   a fact from the grammar rather than an inference from a leading
---   underscore.
---
--- `@import` is the require edge. Both forms appear: `@import("std")` names
--- a package and `@import("helper.zig")` names a file, and only the second
--- can resolve to a node in this tree — the first is external, which is
--- exactly the distinction `deps.lua` already draws.

local M = {}

M.name = "zig"

---The tree-sitter grammar this backend parses with. Same name as the
---backend, unlike the three ECMA registrations — stated rather than derived
---for the reason `lang/lua.lua` gives: deriving it works here and is wrong
---there.
M.grammar = "zig"

---Zig documents a declaration with a `///` block and has no per-parameter
---form — no `@param`, by design rather than by omission, the same way it has
---no block comment. So a Zig function is judged on its summary alone; before
---this field existed every one of them scored undocumented forever, however
---carefully written.
M.param_docs = false

---@type string[]
M.extensions = { "zig" }

---A Zig file's identity is its path, so nothing tag-shaped can be missing.
M.module_tag = false

---What opens a comment. Zig has no block comment at all — deliberately, per
---its own language reference — so there is nothing to declare in the second
---field, and `core/markers.lua` needs only the first.
M.line_comments = { "//" }

---@type { [1]: string, [2]: string }[]
M.block_comments = {}

---@param filename string
---@return boolean
function M.is_source(filename)
  return filename:match("%.zig$") ~= nil
end

---Where this backend's sources live under `root`, or `nil`.
---
---`build.zig` sits at the repository root by convention and is a Zig file
---itself, so its presence is the strongest single signal that a tree is a
---Zig project — but it says nothing about where the *sources* are, which is
---why the roots below are still checked in order.
---@param root string
---@return string?
function M.detect_source(root)
  local uv = vim.uv or vim.loop
  local function holds_zig(dir)
    local fd = uv.fs_scandir(dir)
    if not fd then
      return false
    end
    while true do
      local name, kind = uv.fs_scandir_next(fd)
      if not name then
        return false
      end
      if kind ~= "directory" and M.is_source(name) then
        return true
      end
    end
  end

  for _, candidate in ipairs({ "src", "lib", "source" }) do
    if holds_zig(root .. "/" .. candidate) then
      return candidate
    end
  end
  -- A single-file package with `build.zig` and its source beside it, which
  -- is the shape of most small Zig projects.
  if holds_zig(root) then
    return "."
  end
  return nil
end

---Comment text with its marker removed.
---@param line string
---@return string
local function strip(line)
  return (line:gsub("^%s*//[!/]?%s?", ""))
end

---Read a parsed file once and hand back its comment lines by row.
---
---Comments are the only thing this backend needs positionally: a doc block
---is *the run of `///` lines immediately above a declaration*, which cannot
---be answered from the declaration node alone.
---@param root TSNode
---@param src string
---@return table<integer, string> doc  # `///` text by 0-based row
---@return string[] module_doc          # `//!` lines, in order
local function comments(root, src)
  local doc, module_doc = {}, {}
  local function walk(node)
    if node:type() == "comment" then
      local srow, _, sbyte = node:start()
      local _, _, ebyte = node:end_()
      local text = src:sub(sbyte + 1, ebyte)
      if text:match("^%s*//!") then
        module_doc[#module_doc + 1] = strip(text)
      elseif text:match("^%s*///") then
        doc[srow] = strip(text)
      end
      return
    end
    for child in node:iter_children() do
      walk(child)
    end
  end
  walk(root)
  return doc, module_doc
end

---The `///` block directly above `row`, joined.
---@param doc table<integer, string>
---@param row integer
---@return string
local function doc_above(doc, row)
  local lines = {}
  local r = row - 1
  while doc[r] do
    table.insert(lines, 1, doc[r])
    r = r - 1
  end
  return table.concat(lines, "\n")
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
---@return TSNode?, string?
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
  local _, module_doc = comments(root, src)
  if #module_doc == 0 then
    return empty
  end
  local prose = table.concat(module_doc, "\n")
  local summary = require("documentation.core.scan").split_summary(prose)
  return {
    -- No module tag exists in Zig; the path is the identity.
    module = nil,
    summary = summary,
    body = prose,
    tags = {},
  }
end

---Whether a declaration node is exported.
---
---Read off the node's own leading token rather than from its text: `pub`
---inside a doc comment or a string would otherwise make a private function
---look public.
---@param node TSNode
---@param src string
---@return boolean
local function is_pub(node, src)
  local _, _, sbyte = node:start()
  return src:sub(sbyte + 1, sbyte + 4) == "pub "
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

  local doc = comments(root, src)
  local fns, requires, symbols = {}, {}, {}

  local function text(node)
    local _, _, sbyte = node:start()
    local _, _, ebyte = node:end_()
    return src:sub(sbyte + 1, ebyte)
  end

  local function named_child(node, kind)
    for child in node:iter_children() do
      if child:type() == kind then
        return child
      end
    end
    return nil
  end

  local function walk(node)
    local kind = node:type()

    if kind == "function_declaration" then
      local name_node = named_child(node, "identifier")
      if name_node then
        local srow = node:start()
        local params = named_child(node, "parameters")
        local sig = text(name_node) .. (params and text(params) or "()")
        local prose = doc_above(doc, srow)
        fns[#fns + 1] = {
          name = text(name_node),
          signature = sig,
          line = srow + 1,
          summary = require("documentation.core.scan").split_summary(prose),
          body = prose,
          params = {},
          returns = {},
          -- Visibility from the grammar, not from a naming convention.
          internal = not is_pub(node, src),
          see = {},
          overload = {},
          todo = {},
          bug = {},
          test = {},
        }
      end
    elseif
      kind == "variable_declaration"
      and node:parent()
      and node:parent():type() == "source_file"
    then
      -- **Module scope only**, anchored on the parent being the file rather
      -- than by walking ancestors: a `const seen = ...` inside a function
      -- body is an implementation detail, the same line `core/symbols.lua`
      -- draws for Lua by anchoring its query on `(chunk ...)`.
      local name_node = named_child(node, "identifier")
      local whole = text(node)
      -- `const other = @import("other.zig");` is a *dependency*, and the
      -- branch above already emits it as a require edge. Reporting it here
      -- as well would be the same fact in two places, which is the shape
      -- `core/symbols.lua` names as the reason it skips Lua's own
      -- `local fs = require(...)`.
      local is_import = whole:match("@import%s*%(") ~= nil
      if name_node and not is_import then
        local keyword = named_child(node, "const") and "constant" or "binding"
        local prose = doc_above(doc, node:start())
        symbols[#symbols + 1] = {
          name = text(name_node),
          kind = keyword,
          -- The declaration itself, whitespace-collapsed and bounded --
          -- the same 60-character detail every other backend's constants
          -- carry, so one column of the Index tab reads alike across
          -- languages.
          detail = (whole:gsub("%s+", " ")):gsub(";%s*$", ""):sub(1, 60),
          summary = require("documentation.core.scan").split_summary(prose),
          line = node:start() + 1,
        }
      end
    elseif kind == "builtin_function" then
      local raw = text(node)
      local target = raw:match('^@import%("([^"]+)"%)')
      if target then
        requires[#requires + 1] = { module = target, line = node:start() + 1 }
      end
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
