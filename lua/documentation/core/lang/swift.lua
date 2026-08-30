---@module 'documentation.core.lang.swift'
--- Swift, registered as a language backend — the seventeenth.
---
--- **Documentation as Markdown list items, which is a fourth shape.** This
--- tool has met tag formats (LuaCATS, JSDoc, Javadoc, PHPDoc, KDoc), prose
--- with sections (Python's docstrings), and markup (C#'s XML). Swift is none
--- of them: a doc comment is Markdown, and a parameter is documented by a
--- *bullet* — `- Parameter x: description` — with `- Parameters:` opening an
--- indented list when there are several. It is a real, documented convention
--- with DocC behind it, so it is parsed and it is judged; it simply is not
--- shaped like a tag.
---
--- **Five visibilities and the default is `internal`, which is a fourth
--- answer about silence.** C# says an unmarked member is private, Java says
--- package-private, Kotlin and PHP say public, and Swift says *module-only*.
--- Four languages, four meanings for the same absence — which is why every
--- one of these backends writes its rule out rather than sharing one.
---
--- The order is `open` > `public` > `internal` > `fileprivate` > `private`.
--- `open` and `public` are the published surface; the other three are not,
--- collapsing for the reason Java's `protected` and Rust's `pub(crate)` do:
--- from outside the module, they answer alike.
---
--- **A protocol member is public and carries no modifier**, which makes
--- Swift the sixth language in a row to need that — C#'s interface, Go's
--- interface, Rust's trait, PHP's interface, Kotlin's interface, Swift's
--- protocol. The grammar helps here: a protocol's members are
--- `protocol_function_declaration` nodes, distinct from ordinary functions,
--- so the case cannot be missed by accident the way C#'s was.
---
--- **The path is the identity**, and Swift is unusually clear about why: a
--- module is a *build target*, not a file or a directory. There is no
--- import-by-path at all — `import Foundation` names a module somebody else
--- built — so nothing in a Swift file names another Swift file, and the only
--- honest module name is where the file sits.

local M = {}

M.name = "swift"

M.grammar = "swift"

---@type string[]
M.extensions = { "swift" }

---A Swift module is a build target rather than anything written in a file,
---so nothing tag-shaped can be missing.
M.module_tag = false

---@type string[]
M.line_comments = { "//" }

---@type { [1]: string, [2]: string }[]
M.block_comments = { { "/*", "*/" } }

---`- Parameter x:` names each parameter individually. It is a bullet rather
---than a tag, but it is a documented convention with DocC behind it and
---every Swift project that documents at all uses it — so unlike Ruby's YARD
---or Rust's `# Arguments`, this is the language's own form and is judged as
---such.
M.param_docs = true

---@param filename string
---@return boolean
function M.is_source(filename)
  return filename:match("%.swift$") ~= nil
end

---Where this backend's sources live under `root`, or `nil`.
---
---`Sources/` is SwiftPM's, required rather than preferred — a package
---manifest that does not use it has to say so explicitly. Each target gets a
---directory beneath it, which is why the search goes two levels down before
---giving up.
---@param root string
---@return string?
function M.detect_source(root)
  local uv = vim.uv or vim.loop

  ---@param dir string
  ---@param depth integer
  ---@return boolean
  local function holds_swift(dir, depth)
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
        if holds_swift(sub, depth - 1) then
          return true
        end
      end
    end
    return false
  end

  for _, candidate in ipairs({ "Sources", "Source", "src" }) do
    if holds_swift(root .. "/" .. candidate, 2) then
      return candidate
    end
  end
  if holds_swift(root, 1) then
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

---Every `///` comment run in the file, keyed by the row it ends on.
---
---`///` and `/** */` are both documentation in Swift; `//` alone is a note.
---That distinction is real here — DocC reads one and not the other — so
---unlike C, where the strict rule found nothing and had to be relaxed, it
---costs nothing to honour.
---@param root userdata
---@param src string
---@return table<integer, string[]>
local function doc_runs(root, src)
  local by_row = {}
  local function walk(node)
    local kind = node:type()
    if kind == "comment" or kind == "multiline_comment" then
      local text = text_of(node, src)
      local body = text:match("^///%s?(.*)$")
      if body then
        local srow = node:start()
        local previous = by_row[srow - 1]
        if previous then
          by_row[srow - 1] = nil
          previous[#previous + 1] = body
          by_row[srow] = previous
        else
          by_row[srow] = { body }
        end
      elseif text:match("^/%*%*") then
        local lines = {}
        for line in (text:gsub("^/%*%*", ""):gsub("%*/$", "") .. "\n"):gmatch("([^\n]*)\n") do
          lines[#lines + 1] = (line:gsub("^%s*%*?%s?", ""):gsub("%s+$", ""))
        end
        by_row[node:end_()] = lines
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

---A Swift doc comment, parsed.
---
---**Bullets, not tags.** `- Parameter x: text` documents one parameter;
---`- Parameters:` opens an indented list where each item is `- x: text`;
---`- Returns:` and `- Throws:` document the rest. The leading `-` may also
---be `*` or `+`, because it is Markdown.
---
---A description continued on the following line is joined, which matters
---more here than elsewhere: Markdown wraps freely and a Swift parameter
---description running to two lines is ordinary.
---@param lines string[]?
---@return { summary: string, body: string, params: Documentation.ParamInfo[], returns: Documentation.ReturnInfo[] }
local function parse_doc(lines)
  local empty = { summary = "", body = "", params = {}, returns = {} }
  if not lines or #lines == 0 then
    return empty
  end

  local params, returns, prose = {}, {}, {}
  local current, in_list = nil, false

  for _, raw in ipairs(lines) do
    local line = raw:gsub("%s+$", "")
    local bullet, rest = line:match("^%s*[%-%*%+]%s+(.*)$")

    if bullet ~= nil or rest ~= nil then
      local body = rest or bullet or ""
      local one = body:match("^[Pp]arameter%s+([%w_`]+)%s*:%s*(.*)$")
      if one then
        local name, desc = body:match("^[Pp]arameter%s+([%w_`]+)%s*:%s*(.*)$")
        current = { name = (name:gsub("`", "")), type = "", desc = desc or "" }
        params[#params + 1] = current
        in_list = false
      elseif body:match("^[Pp]arameters%s*:%s*$") then
        -- `- Parameters:` opens an indented list; each item under it is a
        -- parameter rather than prose.
        in_list = true
        current = nil
      elseif body:match("^[Rr]eturns%s*:") then
        current = { type = "", desc = body:match("^[Rr]eturns%s*:%s*(.*)$") or "" }
        returns[#returns + 1] = current
        in_list = false
      elseif body:match("^[Tt]hrows%s*:") or body:match("^[Nn]ote%s*:") then
        -- Recognised so their text stays out of the prose; the IR has no
        -- field for either.
        current = nil
        in_list = false
      elseif in_list then
        local name, desc = body:match("^([%w_`]+)%s*:%s*(.*)$")
        if name then
          current = { name = (name:gsub("`", "")), type = "", desc = desc or "" }
          params[#params + 1] = current
        end
      else
        -- An ordinary Markdown bullet in the prose. Kept, with its marker,
        -- because a list in a description is a list.
        current = nil
        prose[#prose + 1] = line
      end
    elseif current and line:match("%S") then
      current.desc = (current.desc == "" and "" or current.desc .. " ") .. line:gsub("^%s+", "")
    elseif not current then
      if line:match("^%s*$") then
        in_list = false
      end
      prose[#prose + 1] = line
    end
  end

  while prose[1] == "" do
    table.remove(prose, 1)
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
  }
end

---Whether a declaration is outside the published surface.
---
---**Five values, two published.** `open` and `public` are the module's
---surface; `internal`, `fileprivate` and `private` are not — and `internal`
---is the *default*, so a declaration with no modifier is module-only. That
---is a fourth answer to "what does an absent modifier mean", after C#'s
---private, Java's package-private and Kotlin's and PHP's public.
---@param node userdata
---@param src string
---@param inherited boolean? A protocol member's visibility, when inside one.
---@return boolean
local function is_internal(node, src, inherited)
  local mods = child_of(node, "modifiers")
  if not mods then
    if inherited ~= nil then
      return inherited
    end
    return true
  end
  local text = text_of(mods, src)
  if text:match("%f[%w]open%f[%W]") or text:match("%f[%w]public%f[%W]") then
    return false
  end
  if
    text:match("%f[%w]private%f[%W]")
    or text:match("%f[%w]fileprivate%f[%W]")
    or text:match("%f[%w]internal%f[%W]")
  then
    return true
  end
  -- Modifiers that say nothing about visibility (`static`, `final`,
  -- `override`, `@objc`): the default still applies.
  if inherited ~= nil then
    return inherited
  end
  return true
end

---The parameter names a declaration declares.
---
---**The label, not the internal name.** Swift parameters have two: `func
---move(from source: Int)` is called as `move(from:)` and uses `source`
---inside. The label is what a caller writes and what `- Parameter from:`
---documents, so the label is the name — taking the internal one would make
---every two-name parameter in the language fail to match its own
---documentation.
---@param node userdata The declaration; parameters are its direct children.
---@param src string
---@return string[]
local function param_names(node, src)
  local out = {}
  for child in node:iter_children() do
    if child:type() == "parameter" then
      local id = child_of(child, "simple_identifier")
      if id then
        out[#out + 1] = text_of(id, src)
      end
    end
  end
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

  -- **Swift has no file-level doc comment and no module name in the file**,
  -- so the file's summary is the summary of the first type it declares — the
  -- answer C#, PHP and Kotlin all give, and Swift is the one where the
  -- one-type-per-file convention is weakest. It is still the right answer:
  -- a file whose first type is documented is a file a reader has been told
  -- about.
  --
  -- A license banner is a `//` comment and only `///` is read, so it needs
  -- no rule of its own.
  local runs = doc_runs(root, src)
  local first_doc = nil
  for child in root:iter_children() do
    local kind = child:type()
    if
      kind == "class_declaration"
      or kind == "protocol_declaration"
      or kind == "function_declaration"
      or kind == "typealias_declaration"
    then
      first_doc = runs[child:start() - 1]
      break
    end
  end

  local doc = parse_doc(first_doc)
  if doc.summary == "" then
    return empty
  end
  return { module = nil, summary = doc.summary, body = doc.body, tags = {} }
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
  local fns, requires, symbols = {}, {}, {}

  ---@param node userdata
  ---@param owner string?
  ---@param inherited boolean?
  ---@param owner_kind Documentation.ScopeKind? Which declaration `owner` is — read from the keyword by `record_type`, for the same reason `inherited` is passed rather than rediscovered.
  local function record_function(node, owner, inherited, owner_kind)
    local name_node = child_of(node, "simple_identifier")
    if not name_node then
      return
    end
    local bare = text_of(name_node, src)
    local qualified = owner and (owner .. "." .. bare) or bare
    local doc = parse_doc(runs[node:start() - 1])
    local names = param_names(node, src)
    fns[#fns + 1] = {
      name = qualified,
      signature = qualified .. "(" .. table.concat(names, ", ") .. ")",
      line = node:start() + 1,
      line_end = node:end_() + 1,
      summary = doc.summary,
      body = doc.body,
      params = doc.params,
      returns = doc.returns,
      internal = is_internal(node, src, inherited),
      owner = owner,
      owner_kind = owner and (owner_kind or "class") or nil,
      see = {},
      overload = {},
      todo = {},
      bug = {},
      test = {},
    }
  end

  ---@param node userdata `property_declaration`
  ---@param owner string?
  local function record_property(node, owner)
    local pattern = child_of(node, "value_binding_pattern") or node
    local id = child_of(pattern, "pattern") or child_of(node, "pattern")
    local name_node = id and child_of(id, "simple_identifier")
    if not name_node then
      -- Some shapes put the identifier directly under the declaration.
      name_node = child_of(node, "simple_identifier")
    end
    if not name_node then
      return
    end
    local bare = text_of(name_node, src)
    local doc = parse_doc(runs[node:start() - 1])
    local text = text_of(node, src)
    symbols[#symbols + 1] = {
      name = owner and (owner .. "." .. bare) or bare,
      kind = text:match("%f[%w]let%f[%W]") and "constant" or "binding",
      detail = (text:gsub("%s+", " ")):sub(1, 60),
      summary = doc.summary,
      line = node:start() + 1,
    }
  end

  ---@param node userdata A type declaration.
  local function record_type(node)
    local name_node = child_of(node, "type_identifier")
    if not name_node then
      return
    end
    local bare = text_of(name_node, src)
    local doc = parse_doc(runs[node:start() - 1])

    -- `class`, `struct`, `enum`, `actor` and `extension` all parse as
    -- `class_declaration`, so the keyword is read from the text.
    local head = text_of(node, src):sub(1, 100)
    local what = node:type() == "protocol_declaration" and "protocol"
      or head:match("%f[%w](struct)%f[%W]")
      or head:match("%f[%w](enum)%f[%W]")
      or head:match("%f[%w](actor)%f[%W]")
      or head:match("%f[%w](extension)%f[%W]")
      or "class"

    symbols[#symbols + 1] = {
      name = bare,
      kind = "table",
      detail = what,
      summary = doc.summary,
      line = node:start() + 1,
    }

    -- **A protocol member is public and carries no modifier** — the sixth
    -- language in a row to need this. Swift's grammar gives the members
    -- their own node type, so unlike C# the case cannot be missed for want
    -- of noticing it.
    --
    -- **Written as an `if`, and the reason is a Lua trap this session has now
    -- hit twice.** `what == "protocol" and false or nil` evaluates to `nil`,
    -- because `false` is falsy and the `or` branch runs — so every protocol
    -- member fell through to the module-only default and came back internal.
    -- The same shape cost Python every method's visibility a few backends
    -- ago; `nil` and `false` are both unusable as the middle operand.
    local inherited = nil
    if what == "protocol" then
      inherited = false
    end

    -- `actor` has no `Documentation.ScopeKind` of its own: it groups members
    -- exactly as a class does and differs in concurrency, which is not what
    -- this field is about.
    ---@type Documentation.ScopeKind
    local owner_kind = what == "protocol" and "protocol"
      or what == "struct" and "struct"
      or what == "enum" and "enum"
      or what == "extension" and "extension"
      or "class"

    local body = child_of(node, "class_body")
      or child_of(node, "protocol_body")
      or child_of(node, "enum_class_body")
    if body then
      for member in body:iter_children() do
        local mk = member:type()
        if mk == "function_declaration" or mk == "protocol_function_declaration" then
          record_function(member, bare, inherited, owner_kind)
        elseif mk == "property_declaration" or mk == "protocol_property_declaration" then
          record_property(member, bare)
        end
      end
    end
  end

  for child in root:iter_children() do
    local kind = child:type()
    if kind == "import_declaration" then
      local name = child_of(child, "identifier")
      if name then
        -- Recorded as written. Swift has no import-by-path at all: a module
        -- is a build target, so nothing here names another file in this
        -- tree, and every one of these is external by construction.
        requires[#requires + 1] = {
          module = (text_of(name, src):gsub("%s+", "")),
          line = child:start() + 1,
        }
      end
    elseif kind == "class_declaration" or kind == "protocol_declaration" then
      record_type(child)
    elseif kind == "function_declaration" then
      record_function(child, nil, nil)
    elseif kind == "property_declaration" then
      record_property(child, nil)
    end
  end

  return fns, {}, requires, symbols, {}, {}, lines, {}
end

require("documentation.core.lang_registry").register(M.name, M)

return M
