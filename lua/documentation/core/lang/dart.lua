---@module 'documentation.core.lang.dart'
--- Dart, registered as a language backend — the eighteenth.
---
--- **The one language where the leading underscore is a fact.** Lua, the
--- ECMA family and Python all use `_name` as a *convention* — a claim the
--- author makes that nothing enforces. In Dart the compiler enforces it: an
--- identifier beginning with `_` is private to its library and genuinely
--- unreachable from outside, no annotation involved. So Dart's visibility
--- costs nothing to read and cannot be wrong, which puts it beside Go's
--- capitalisation rather than beside Python's habit.
---
--- **`param_docs = false`, the fifth to declare it.** dartdoc is Markdown
--- prose; a parameter is referred to with `[x]` inside a sentence, not
--- documented in a slot. There is no `@param` and no `- Parameter x:`, so
--- judging Dart by per-parameter documentation would report every
--- well-documented package as documenting nothing — the wrongness this field
--- exists to prevent. Nothing is parsed here either, which puts Dart with
--- Zig, Go, Rust and assembly rather than with Ruby, where there was
--- something to show but not to judge.
---
--- **The grammar names doc comments outright.** `documentation_comment` is
--- its own node type, distinct from `comment` — so unlike every other
--- backend here, this one needs no pattern to tell documentation from a
--- note. The `///` and `//` distinction is the parser's, not ours.
---
--- **The top level is flat**, which is a shape nothing else here has: a
--- top-level function is a `function_signature` followed by a sibling
--- `function_body`, and a top-level constant is a `const_builtin`, a
--- `type_identifier` and a `static_final_declaration_list` in a row, ending
--- at a bare `;`. There is no node wrapping any of it. So the walk carries a
--- little state instead of descending — noted here because it looks like an
--- oversight and is not.
---
--- **A `.dart` file is a library**, and the path is the identity. Relative
--- imports name a file and resolve; `package:` and `dart:` name somebody
--- else's library and do not.

local M = {}

M.name = "dart"

M.grammar = "dart"

---@type string[]
M.extensions = { "dart" }

---A Dart library is its file. Nothing tag-shaped can be missing.
M.module_tag = false

---@type string[]
M.line_comments = { "//" }

---@type { [1]: string, [2]: string }[]
M.block_comments = { { "/*", "*/" } }

---**dartdoc has no per-parameter form.** A parameter is referred to as `[x]`
---inside Markdown prose, which is a cross-reference rather than a slot —
---there is nothing to count and nothing to match against a signature.
M.param_docs = false

---@param filename string
---@return boolean
function M.is_source(filename)
  return filename:match("%.dart$") ~= nil
end

---Where this backend's sources live under `root`, or `nil`.
---
---`lib/` is the pub convention and is what every package publishes from —
---required by the tooling rather than merely preferred, since only `lib/` is
---importable by a dependent package.
---@param root string
---@return string?
function M.detect_source(root)
  local uv = vim.uv or vim.loop

  ---@param dir string
  ---@param depth integer
  ---@return boolean
  local function holds_dart(dir, depth)
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
      if kind == "directory" and name:sub(1, 1) ~= "." and name ~= "build" then
        subdirs[#subdirs + 1] = dir .. "/" .. name
      end
    end
    if depth > 0 then
      for _, sub in ipairs(subdirs) do
        if holds_dart(sub, depth - 1) then
          return true
        end
      end
    end
    return false
  end

  for _, candidate in ipairs({ "lib", "src", "bin" }) do
    if holds_dart(root .. "/" .. candidate, 1) then
      return candidate
    end
  end
  if holds_dart(root, 1) then
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

---Every `///` run in the file, keyed by the row it ends on.
---
---**The grammar does the telling-apart.** `documentation_comment` is its own
---node type here, distinct from `comment`, so this needs no pattern to know
---which comments are documentation — the only backend of the eighteen where
---that is true.
---@param root userdata
---@param src string
---@return table<integer, string[]>
local function doc_runs(root, src)
  local by_row = {}
  local function walk(node)
    if node:type() == "documentation_comment" then
      local srow = node:start()
      local body = text_of(node, src):match("^///%s?(.*)$") or ""
      local previous = by_row[srow - 1]
      if previous then
        by_row[srow - 1] = nil
        previous[#previous + 1] = body
        by_row[srow] = previous
      else
        by_row[srow] = { body }
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

---The `///` block above `row`, as prose.
---@param runs table<integer, string[]>
---@param row integer 0-based row of the documented declaration.
---@return string
local function doc_above(runs, row)
  local lines = runs[row - 1]
  if not lines then
    return ""
  end
  local kept = {}
  for _, line in ipairs(lines) do
    kept[#kept + 1] = (line:gsub("%s+$", ""))
  end
  while kept[#kept] == "" do
    table.remove(kept)
  end
  return table.concat(kept, "\n")
end

---Whether a Dart identifier is library-private.
---
---**The compiler enforces this**, which is what separates Dart from every
---other language here that uses a leading underscore. In Lua, JavaScript and
---Python `_name` is a request; in Dart it is unreachable from outside the
---library, full stop. So this is a fact read off the name, in the same class
---as Go's capitalisation rather than as a naming heuristic.
---@param name string
---@return boolean
local function is_internal(name)
  return name:sub(1, 1) == "_"
end

---@param node userdata? `formal_parameter_list`
---@param src string
---@return string[]
local function param_names(node, src)
  local out = {}
  if not node then
    return out
  end
  local function collect(list)
    for child in list:iter_children() do
      local kind = child:type()
      if kind == "formal_parameter" then
        -- The declared name is the last identifier in the parameter: a
        -- `String s` has the type first, and `this.name` has the receiver.
        local last = nil
        for part in child:iter_children() do
          local pk = part:type()
          if pk == "identifier" then
            last = part
          end
        end
        if last then
          out[#out + 1] = text_of(last, src)
        else
          out[#out + 1] = (text_of(child, src):gsub("%s+", " "))
        end
      elseif
        kind == "optional_formal_parameters"
        or kind == "named_formal_parameters"
        or kind == "optional_positional_formal_parameters"
      then
        -- `{named}` and `[positional]` groups nest one level deeper. Dart
        -- uses both heavily, so missing them would drop most of Flutter's
        -- parameters.
        collect(child)
      end
    end
  end
  collect(node)
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

  -- **The file's summary is the first type's**, the answer C#, PHP, Kotlin
  -- and Swift all give. Dart's own `library` directive can carry a doc
  -- comment and almost nobody writes one, so this is the reading that finds
  -- something in a real package.
  --
  -- A license banner is a `//` comment, which the grammar already calls
  -- `comment` rather than `documentation_comment` — so it is skipped without
  -- a rule.
  local runs = doc_runs(root, src)
  local prose = ""
  for child in root:iter_children() do
    local kind = child:type()
    if
      kind == "class_definition"
      or kind == "mixin_declaration"
      or kind == "extension_declaration"
      or kind == "enum_declaration"
    then
      prose = doc_above(runs, child:start())
      break
    end
  end
  if prose == "" then
    return empty
  end
  return {
    module = nil,
    summary = require("documentation.core.scan").split_summary(prose),
    body = prose,
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

  local runs = doc_runs(root, src)
  local split = require("documentation.core.scan").split_summary
  local fns, requires, symbols = {}, {}, {}

  ---@param sig userdata `function_signature`
  ---@param owner string?
  ---@param row integer 0-based row the declaration starts on.
  ---@param owner_kind Documentation.ScopeKind? Which declaration `owner` is, from `record_type`.
  local function record_function(sig, owner, row, owner_kind)
    local name_node = child_of(sig, "identifier")
    if not name_node then
      return
    end
    local bare = text_of(name_node, src)
    local qualified = owner and (owner .. "." .. bare) or bare
    local names = param_names(child_of(sig, "formal_parameter_list"), src)
    local prose = doc_above(runs, row)
    fns[#fns + 1] = {
      name = qualified,
      signature = qualified .. "(" .. table.concat(names, ", ") .. ")",
      line = row + 1,
      line_end = sig:end_() + 1,
      summary = split(prose),
      body = prose,
      params = {},
      returns = {},
      -- The member's own name decides, not its class's: a public class
      -- routinely holds `_helper`.
      internal = is_internal(bare),
      owner = owner,
      owner_kind = owner and (owner_kind or "class") or nil,
      see = {},
      overload = {},
      todo = {},
      bug = {},
      test = {},
    }
  end

  ---@param node userdata `class_definition` and friends.
  local function record_type(node)
    local name_node = child_of(node, "identifier")
    if not name_node then
      return
    end
    local bare = text_of(name_node, src)
    local prose = doc_above(runs, node:start())
    local head = text_of(node, src):sub(1, 60)
    symbols[#symbols + 1] = {
      name = bare,
      kind = "table",
      detail = node:type() == "class_definition"
          and (head:match("%f[%w](abstract)%f[%W]") and "abstract class" or "class")
        or (node:type():gsub("_declaration$", "")),
      summary = split(prose),
      line = node:start() + 1,
    }

    local body = child_of(node, "class_body") or child_of(node, "extension_body")
    if not body then
      return
    end
    -- A `mixin` is a class here: it groups members the same way, and what
    -- makes it a mixin is how it is *used*, which is not this field.
    ---@type Documentation.ScopeKind
    local owner_kind = node:type() == "extension_declaration" and "extension"
      or node:type() == "enum_declaration" and "enum"
      or "class"
    -- **The row a member starts on is not always the row its doc sits above.**
    -- A `method_signature` wraps the `function_signature`, and the doc run
    -- ends one row above the *outer* node — so the outer row is what is
    -- passed down.
    for member in body:iter_children() do
      local mk = member:type()
      if mk == "method_signature" then
        local sig = child_of(member, "function_signature")
        if sig then
          record_function(sig, bare, member:start(), owner_kind)
        end
      elseif mk == "declaration" then
        -- **A `declaration` is three different things**, and reading it as
        -- one costs whichever two are not that. An *abstract* method has no
        -- body, so it is a `declaration` wrapping a `function_signature`
        -- rather than a `method_signature` — and treating it as a field
        -- dropped every member of every abstract class, which is the one
        -- construct whose whole content is its members. The same node also
        -- wraps a `constructor_signature`.
        local inner_sig = child_of(member, "function_signature")
        local ctor = child_of(member, "constructor_signature")
        if inner_sig then
          record_function(inner_sig, bare, member:start(), owner_kind)
          goto continue_member
        elseif ctor then
          local cname = child_of(ctor, "identifier")
          if cname then
            local names = param_names(child_of(ctor, "formal_parameter_list"), src)
            local cprose = doc_above(runs, member:start())
            fns[#fns + 1] = {
              name = bare .. "." .. text_of(cname, src),
              signature = bare
                .. "."
                .. text_of(cname, src)
                .. "("
                .. table.concat(names, ", ")
                .. ")",
              line = member:start() + 1,
              line_end = member:end_() + 1,
              summary = split(cprose),
              body = cprose,
              params = {},
              returns = {},
              internal = is_internal(text_of(cname, src)),
              owner = bare,
              owner_kind = owner_kind,
              see = {},
              overload = {},
              todo = {},
              bug = {},
              test = {},
            }
          end
          goto continue_member
        end
        local list = child_of(member, "initialized_identifier_list")
          or child_of(member, "static_final_declaration_list")
        local id = list
          and (child_of(list, "identifier") or child_of(list, "initialized_identifier"))
        if id and id:type() == "initialized_identifier" then
          id = child_of(id, "identifier")
        end
        if id then
          local mname = text_of(id, src)
          local text = text_of(member, src)
          local mprose = doc_above(runs, member:start())
          symbols[#symbols + 1] = {
            name = bare .. "." .. mname,
            kind = (text:match("%f[%w]final%f[%W]") or text:match("%f[%w]const%f[%W]"))
                and "constant"
              or "binding",
            detail = (text:gsub("%s+", " ")):sub(1, 60),
            summary = split(mprose),
            line = member:start() + 1,
          }
        end
      end
      ::continue_member::
    end
  end

  -- **The top level is flat.** A top-level function is a `function_signature`
  -- with a sibling `function_body`; a top-level constant is `const_builtin`,
  -- `type_identifier` and `static_final_declaration_list` in a row. Nothing
  -- wraps either, so the walk carries state rather than descending — which
  -- looks like an oversight and is the grammar's actual shape.
  local pending_const = false
  local pending_row = nil

  for child in root:iter_children() do
    local kind = child:type()

    if kind == "import_or_export" then
      local text = text_of(child, src)
      local target = text:match("'([^']+)'") or text:match('"([^"]+)"')
      if target then
        -- **Only a relative import names a file in this tree.** `package:`
        -- resolves through the pub cache and `dart:` is the SDK — both are
        -- somebody else's library, and rewriting either would be a guess.
        if
          not target:match("^package:")
          and not target:match("^dart:")
          and target:sub(1, 2) ~= "./"
          and target:sub(1, 3) ~= "../"
        then
          target = "./" .. target
        end
        requires[#requires + 1] = { module = target, line = child:start() + 1 }
      end
    elseif
      kind == "class_definition"
      or kind == "mixin_declaration"
      or kind == "extension_declaration"
      or kind == "enum_declaration"
    then
      record_type(child)
    elseif kind == "function_signature" then
      record_function(child, nil, child:start())
    elseif kind == "const_builtin" or kind == "final_builtin" then
      pending_const = true
      pending_row = child:start()
    elseif kind == "static_final_declaration_list" or kind == "initialized_identifier_list" then
      local decl = child_of(child, "static_final_declaration")
        or child_of(child, "initialized_identifier")
      local id = decl and child_of(decl, "identifier") or child_of(child, "identifier")
      if id then
        local row = pending_row or child:start()
        symbols[#symbols + 1] = {
          name = text_of(id, src),
          kind = pending_const and "constant" or "binding",
          detail = (text_of(child, src):gsub("%s+", " ")):sub(1, 60),
          summary = split(doc_above(runs, row)),
          line = row + 1,
        }
      end
    elseif kind == ";" then
      pending_const = false
      pending_row = nil
    end
  end

  return fns, {}, requires, symbols, {}, {}, lines, {}
end

require("documentation.core.lang_registry").register(M.name, M)

return M
