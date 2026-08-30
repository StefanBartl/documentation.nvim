---@module 'documentation.core.lang.kotlin'
--- Kotlin, registered as a language backend — the sixteenth.
---
--- **Four visibilities, and the default is `public`.** `public`, `internal`,
--- `protected`, `private`, and a declaration with no modifier is public —
--- which puts Kotlin with PHP rather than with C#, whose identical-looking
--- absence means private. Java's default is a *fifth* answer again
--- (package-private). Three languages that look alike on the page and
--- disagree about silence: the rule here is written as *not private, not
--- protected and not internal*, never as *has `public`*, because most Kotlin
--- declares no modifier at all and asking for the keyword would report an
--- entire codebase as unpublished.
---
--- `internal` means "this compilation module", which collapses into
--- not-published for the reason Java's `protected` and Rust's `pub(crate)`
--- do: from outside, it answers like private.
---
--- **KDoc is Javadoc's descendant and parses almost identically**, with one
--- tag no other language here has: `@property name`, which documents a
--- constructor parameter that is also a property. It is read as a parameter,
--- because that is what it is at the point of declaration — and dropping it
--- would leave every `data class` in Kotlin undocumented, since that is the
--- only place their fields are described.
---
--- **A file can hold several top-level declarations and need not be named
--- after any of them**, so `package a.b` plus the file stem is a module name
--- Kotlin does not guarantee. It is still derived and still recorded, for the
--- same reason Java's is: `import a.b.Thing` names a declaration, the
--- compiler resolves it against the package, and a file called `Thing.kt` in
--- package `a.b` really is where `a.b.Thing` lives in every project that
--- follows the convention. Where a project does not, the edge does not
--- resolve — which under-claims rather than pointing somewhere wrong.

local M = {}

M.name = "kotlin"

M.grammar = "kotlin"

---@type string[]
M.extensions = { "kt", "kts" }

---A package declaration is a language construct rather than a documentation
---tag, and a file without one is legal.
M.module_tag = false

---@type string[]
M.line_comments = { "//" }

---@type { [1]: string, [2]: string }[]
M.block_comments = { { "/*", "*/" } }

---KDoc's `@param` names each parameter individually, the same as Javadoc's.
M.param_docs = true

---@param filename string
---@return boolean
function M.is_source(filename)
  return filename:match("%.kt$") ~= nil or filename:match("%.kts$") ~= nil
end

---Where this backend's sources live under `root`, or `nil`.
---
---`src/main/kotlin` is Gradle's layout and is what nearly every Kotlin
---project uses; `src/commonMain/kotlin` is the multiplatform variant. Both
---are checked before the shallower fallbacks, because a `src/` that only
---holds those directories would otherwise answer `nil`.
---@param root string
---@return string?
function M.detect_source(root)
  local uv = vim.uv or vim.loop

  ---@param dir string
  ---@param depth integer
  ---@return boolean
  local function holds_kt(dir, depth)
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
        if holds_kt(sub, depth - 1) then
          return true
        end
      end
    end
    return false
  end

  for _, candidate in ipairs({
    "src/main/kotlin",
    "src/commonMain/kotlin",
    "src/main/java",
    "src",
    "lib",
  }) do
    if holds_kt(root .. "/" .. candidate, 2) then
      return candidate
    end
  end
  if holds_kt(root, 1) then
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

---Every KDoc block in the file, keyed by the row it ends on.
---
---Only `/** … */`. KDoc has tooling behind it (Dokka, the IDE), `/**` is
---what every Kotlin project writes, and a `//` line above a declaration is a
---note rather than documentation — the same position PHP's PHPDoc rule
---takes, and the opposite of the one C had to be given.
---@param root userdata
---@param src string
---@return table<integer, string>
local function doc_blocks(root, src)
  local by_row = {}
  local function walk(node)
    local kind = node:type()
    if kind == "multiline_comment" or kind == "comment" then
      local text = text_of(node, src)
      if text:match("^/%*%*") then
        by_row[node:end_()] = text
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

---A KDoc block, parsed.
---
---Javadoc's shape, with `@property` folded in beside `@param`: in a Kotlin
---`data class` the constructor parameters *are* the properties, and
---`@property name` is where they are described. Reading it as anything but a
---parameter would leave every data class in the language undocumented.
---@param text string?
---@return { summary: string, body: string, params: Documentation.ParamInfo[], returns: Documentation.ReturnInfo[], deprecated: string? }
local function parse_doc(text)
  local empty = { summary = "", body = "", params = {}, returns = {} }
  if not text then
    return empty
  end

  local params, returns, prose = {}, {}, {}
  local deprecated = nil
  local current = nil

  local body = text:gsub("^/%*%*", ""):gsub("%*/$", "")
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do
    local stripped = line:gsub("^%s*%*?%s?", ""):gsub("%s+$", "")
    local tag, rest = stripped:match("^@(%a[%w_]*)%s*(.*)$")
    if tag then
      tag = tag:lower()
      if tag == "param" or tag == "property" then
        local name, desc = rest:match("^([%w_]+)%s*(.*)$")
        if name then
          current = { name = name, type = "", desc = desc or "" }
          params[#params + 1] = current
        else
          current = nil
        end
      elseif tag == "return" then
        current = { type = "", desc = rest }
        returns[#returns + 1] = current
      elseif tag == "deprecated" then
        deprecated = rest ~= "" and rest or "deprecated"
        current = nil
      else
        -- `@throws`, `@see`, `@sample`, `@constructor` and the rest: read as
        -- tags so their text stays out of the prose, not modelled.
        current = nil
      end
    elseif current and stripped ~= "" then
      current.desc = (current.desc == "" and "" or current.desc .. " ") .. stripped:gsub("^%s+", "")
    elseif not current then
      prose[#prose + 1] = stripped
    end
  end

  while prose[1] == "" do
    table.remove(prose, 1)
  end
  while prose[#prose] == "" do
    table.remove(prose)
  end
  local text_body = table.concat(prose, "\n")
  return {
    summary = require("documentation.core.scan").split_summary(text_body),
    body = text_body,
    params = params,
    returns = returns,
    deprecated = deprecated,
  }
end

---Whether a declaration is outside the published surface.
---
---**Written as "not private, not protected, not internal", never as "has
---`public`".** Kotlin's default is public and most declarations carry no
---modifier at all, so asking for the keyword would report an entire codebase
---as unpublished — the mistake C# taught this tool to fear, in the language
---where the same absence means the opposite.
---
---`internal` means "this compilation module" and collapses into
---not-published for the reason Java's `protected` and Rust's `pub(crate)` do:
---from outside, it answers like private.
---@param node userdata
---@param src string
---@return boolean
local function is_internal(node, src)
  local mods = child_of(node, "modifiers")
  if not mods then
    return false
  end
  local text = text_of(mods, src)
  return text:match("%f[%w]private%f[%W]") ~= nil
    or text:match("%f[%w]protected%f[%W]") ~= nil
    or text:match("%f[%w]internal%f[%W]") ~= nil
end

---@param node userdata? `function_value_parameters`
---@param src string
---@return string[]
local function param_names(node, src)
  local out = {}
  if not node then
    return out
  end
  for child in node:iter_children() do
    if child:type() == "parameter" or child:type() == "class_parameter" then
      local id = child_of(child, "simple_identifier")
      if id then
        out[#out + 1] = text_of(id, src)
      end
    end
  end
  return out
end

---The `package a.b` this file declares, or `nil`.
---@param root userdata
---@param src string
---@return string?
local function package_of(root, src)
  local header = child_of(root, "package_header")
  local name = header and child_of(header, "identifier")
  return name and (text_of(name, src):gsub("%s+", "")) or nil
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

  local package = package_of(root, src)
  local stem = path:match("([^/\\]+)%.kts?$")
  local module = (package and stem) and (package .. "." .. stem) or nil

  -- **Kotlin has no file-level doc block**, so the file's summary is the
  -- summary of the first declaration it holds. Unlike C# and PHP, one
  -- declaration per file is a *convention* here rather than a rule — Kotlin
  -- allows several, and top-level functions are ordinary — so this is the
  -- weakest form of that answer among the three. It is still the right one:
  -- a file whose first declaration is documented is a file a reader has been
  -- told about.
  --
  -- A license banner is a `//` comment and only `/**` is read, so it is
  -- skipped without a rule of its own.
  -- **A type first, then a function, and a property only if there is
  -- neither.** The first *declaration* is not the right answer: a file that
  -- opens with `const val MAX = 10` would take "How many." as its summary,
  -- which is true of the constant and says nothing about the file. Kotlin
  -- puts top-level constants above the class they belong to often enough
  -- that this is the common case rather than a corner.
  local blocks = doc_blocks(root, src)
  local first_doc = nil
  local RANK = {
    class_declaration = 1,
    object_declaration = 1,
    type_alias = 1,
    function_declaration = 2,
    property_declaration = 3,
  }
  local best = nil
  for child in root:iter_children() do
    local rank = RANK[child:type()]
    if rank and (not best or rank < best) then
      local doc_text = blocks[child:start() - 1]
      if doc_text then
        best, first_doc = rank, doc_text
        if rank == 1 then
          break
        end
      end
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

  ---@param node userdata `function_declaration`
  ---@param owner string?
  ---@param inherited boolean?
  ---@param owner_kind Documentation.ScopeKind? Which declaration `owner` is. Kotlin parses all four as `class_declaration`, so `record_type` reads the keyword and passes it on rather than having this rediscover it.
  local function record_function(node, owner, inherited, owner_kind)
    local name_node = child_of(node, "simple_identifier")
    if not name_node then
      return
    end
    local bare = text_of(name_node, src)
    local qualified = owner and (owner .. "." .. bare) or bare
    local doc = parse_doc(blocks[node:start() - 1])
    local names = param_names(child_of(node, "function_value_parameters"), src)
    local internal = is_internal(node, src)
    if inherited ~= nil and not child_of(node, "modifiers") then
      internal = inherited
    end
    fns[#fns + 1] = {
      name = qualified,
      signature = qualified .. "(" .. table.concat(names, ", ") .. ")",
      line = node:start() + 1,
      line_end = node:end_() + 1,
      summary = doc.summary,
      body = doc.body,
      params = doc.params,
      returns = doc.returns,
      deprecated = doc.deprecated,
      internal = internal,
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
    local decl = child_of(node, "variable_declaration")
    local id = decl and child_of(decl, "simple_identifier")
    if not id then
      return
    end
    local bare = text_of(id, src)
    local doc = parse_doc(blocks[node:start() - 1])
    local mods = child_of(node, "modifiers")
    local is_const = mods and text_of(mods, src):match("%f[%w]const%f[%W]") ~= nil
    symbols[#symbols + 1] = {
      name = owner and (owner .. "." .. bare) or bare,
      kind = is_const and "constant" or "binding",
      detail = (text_of(node, src):gsub("%s+", " ")):sub(1, 60),
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
    local doc = parse_doc(blocks[node:start() - 1])

    -- `class`, `interface`, `object` and `enum class` all parse as
    -- `class_declaration` here, so the keyword is read from the text rather
    -- than from the node name.
    local head = text_of(node, src):sub(1, 80)
    local what = head:match("%f[%w](interface)%f[%W]")
      or head:match("%f[%w](object)%f[%W]")
      or head:match("%f[%w](enum)%f[%W]")
      or "class"

    symbols[#symbols + 1] = {
      name = bare,
      kind = "table",
      detail = what,
      summary = doc.summary,
      line = node:start() + 1,
    }

    -- **An interface member with no modifier is public and cannot be
    -- private** — the fifth language to need this, after C#, Go, Rust and
    -- PHP. Kotlin allows `private` on an interface member with a body, so
    -- the modifier still wins where it is written; `inherited` only supplies
    -- the default.
    local inherited = what == "interface" and false or nil

    ---@type Documentation.ScopeKind
    local owner_kind = what == "interface" and "interface"
      or what == "object" and "object"
      or what == "enum" and "enum"
      or "class"

    local body = child_of(node, "class_body") or child_of(node, "enum_class_body")
    if body then
      for member in body:iter_children() do
        local mk = member:type()
        if mk == "function_declaration" then
          record_function(member, bare, inherited, owner_kind)
        elseif mk == "property_declaration" then
          record_property(member, bare)
        elseif mk == "companion_object" then
          -- A companion object's members belong to the type in every
          -- practical sense: `Widget.create()` is how they are called.
          local cbody = child_of(member, "class_body")
          if cbody then
            for cm in cbody:iter_children() do
              if cm:type() == "function_declaration" then
                -- Still the type's own scope, not the companion's: `bare` is
                -- what the call site writes, and a second scope named after a
                -- keyword would group members nobody looks for separately.
                record_function(cm, bare, nil, owner_kind)
              elseif cm:type() == "property_declaration" then
                record_property(cm, bare)
              end
            end
          end
        end
      end
    end

    -- A primary constructor's `val`/`var` parameters are properties, and in
    -- a `data class` they are the whole of the type's surface.
    local ctor = child_of(node, "primary_constructor")
    if ctor then
      for param in ctor:iter_children() do
        if param:type() == "class_parameter" then
          local pid = child_of(param, "simple_identifier")
          local ptext = text_of(param, src)
          if pid and (ptext:match("%f[%w]val%f[%W]") or ptext:match("%f[%w]var%f[%W]")) then
            symbols[#symbols + 1] = {
              name = bare .. "." .. text_of(pid, src),
              kind = "binding",
              detail = (ptext:gsub("%s+", " ")):sub(1, 60),
              summary = "",
              line = param:start() + 1,
            }
          end
        end
      end
    end
  end

  for child in root:iter_children() do
    local kind = child:type()
    if kind == "import_list" then
      for header in child:iter_children() do
        if header:type() == "import_header" then
          local name = child_of(header, "identifier")
          if name then
            requires[#requires + 1] = {
              module = (text_of(name, src):gsub("%s+", "")),
              line = header:start() + 1,
            }
          end
        end
      end
    elseif kind == "class_declaration" or kind == "object_declaration" then
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
