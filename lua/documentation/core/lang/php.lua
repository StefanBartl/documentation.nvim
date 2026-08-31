---@module 'documentation.core.lang.php'
--- PHP, registered as a language backend — the fourteenth.
---
--- **Three require edges, and telling them apart is the point.** `use` is a
--- *namespace* import that binds a name at compile time and loads nothing;
--- `require`/`include` load a *file* at run time; and the two are not
--- alternatives — a PSR-4 project writes `use` everywhere and lets the
--- autoloader do the requiring, while a script or a legacy tree does the
--- opposite. Both are recorded, and both resolve, because they resolve
--- differently: a `use` names a class, and under PSR-4 a class is a file, so
--- `Acme\Other\Thing` matches the module `Acme\Other\Thing` this backend
--- derives for `src/Other/Thing.php`. A `require` names a path and is
--- rewritten to `./`-relative form, exactly as assembly's `%include` is.
---
--- That makes PHP the first language here whose *literal* file-loading
--- construct and whose *symbolic* import both produce edges in the same map.
--- C has only the first, Java and C# only the second.
---
--- **The default visibility is the opposite of C#'s, and stating it is not
--- pedantry.** A PHP method with no modifier is **public**. C# taught this
--- tool that an absent modifier can mean private and that reading it wrong
--- inverts an entire API; PHP is the language where the same absence means
--- the opposite. So the rule here is written as what it is — *not private
--- and not protected* — rather than as "has `public`", which would report
--- every unmarked method in every legacy PHP file as internal.
---
--- **An interface member is public and cannot be otherwise**, which is the
--- fourth time this tool has met that construct: C#'s interface, Go's
--- interface, Rust's trait, now PHP's interface. PHP is the one that says it
--- loudest — writing `private` on an interface method is a fatal error — and
--- it is handled by the same `inherited` argument the other three needed.
---
--- **PHPDoc is a tag format**, the same family as Javadoc and JSDoc, and
--- close enough to JSDoc that the parsing is nearly the same shape. One
--- difference worth carrying: `@param` names the *variable*, sigil and all —
--- `@param int $x` — so the `$` comes off before the name is compared against
--- the signature, or nothing would ever match.
---
--- **`@internal` is a real PHPDoc tag**, and it is honoured: a method marked
--- with it is not published however it is declared. That is the same
--- authoring-convention layer Lua and the ECMA family live on, sitting *over*
--- a language that also has real keywords — the only backend here where both
--- kinds of evidence are available and both are read.

local M = {}

M.name = "php"

M.grammar = "php"

---@type string[]
M.extensions = { "php" }

---A namespace declaration is a language construct rather than a documentation
---tag, and a file in the global namespace is legal — so nothing tag-shaped
---can be missing. The module name is still fully qualified; see
---`parse_header`.
M.module_tag = false

---`//` and `#` both open a line comment in PHP. `#` is listed second because
---it is rarer in modern code and because a `#[Attribute]` in PHP 8 begins
---with it — which `core/markers.lua` will read as a comment and find no
---marker in, costing nothing.
---@type string[]
M.line_comments = { "//", "#" }

---@type { [1]: string, [2]: string }[]
M.block_comments = { { "/*", "*/" } }

---PHPDoc's `@param` names each parameter individually.
M.param_docs = true

---**PHP is the only language here whose source is not code from the first
---byte.** Outside `<?php` a file is text — so `// TODO: x` on its own is
---inline HTML with no comment node in it at all, and a tool that hands this
---backend a bare fragment gets a correct answer to the wrong question.
---
---Found by `backend_contract_spec.lua`, whose whole job is to prove a
---declared comment token *works* rather than that it is present. It probed
---with `"// TODO: proof"` and got nothing — not because the token is wrong,
---but because that string is not PHP. Real callers pass whole files, which
---always carry the tag.
M.code_prelude = "<?php\n"

---@param filename string
---@return boolean
function M.is_source(filename)
  return filename:match("%.php$") ~= nil
end

---Where this backend's sources live under `root`, or `nil`.
---
---`src/` first because PSR-4 and every Composer package use it. `app/` is
---Laravel's, and it is common enough that leaving it out would send the walk
---to the repository root of a large share of real PHP projects.
---@param root string
---@return string?
function M.detect_source(root)
  local uv = vim.uv or vim.loop

  ---@param dir string
  ---@param depth integer
  ---@return boolean
  local function holds_php(dir, depth)
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
      if kind == "directory" and name:sub(1, 1) ~= "." and name ~= "vendor" then
        subdirs[#subdirs + 1] = dir .. "/" .. name
      end
    end
    if depth > 0 then
      for _, sub in ipairs(subdirs) do
        if holds_php(sub, depth - 1) then
          return true
        end
      end
    end
    return false
  end

  for _, candidate in ipairs({ "src", "app", "lib", "source" }) do
    if holds_php(root .. "/" .. candidate, 1) then
      return candidate
    end
  end
  if holds_php(root, 1) then
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
---@return TSNode?
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

---Every PHPDoc block in the file, keyed by the row it ends on.
---
---Only `/** … */`. Unlike C — where the Doxygen-only rule found *zero*
---summaries in a thoroughly commented codebase and had to be relaxed — PHP
---really does have a universal convention: PHPDoc has tooling behind it
---(IDEs, static analysers, generators), `/**` is what every project writes,
---and a `//` line above a method is a note rather than documentation.
---@param root TSNode
---@param src string
---@return table<integer, string>
local function doc_blocks(root, src)
  local by_row = {}
  local function walk(node)
    if node:type() == "comment" then
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

---A PHPDoc block, parsed.
---
---The same tag shape Javadoc and JSDoc use, with one difference that matters:
---`@param int $x The first number.` puts the *type* before the name and the
---name carries its `$`. Stripping the sigil is not cosmetic — the signature
---says `x`, so leaving it would make every documented parameter fail to
---match its own declaration.
---@param text string?
---@return { summary: string, body: string, params: Documentation.ParamInfo[], returns: Documentation.ReturnInfo[], internal: boolean, deprecated: string? }
local function parse_doc(text)
  local empty = { summary = "", body = "", params = {}, returns = {}, internal = false }
  if not text then
    return empty
  end

  local params, returns, prose = {}, {}, {}
  local internal, deprecated = false, nil
  local current = nil

  -- `/**`, the leading ` * ` of each line and the closing `*/` are the block's
  -- frame rather than its content.
  local body = text:gsub("^/%*%*", ""):gsub("%*/$", "")
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do
    local stripped = line:gsub("^%s*%*?%s?", ""):gsub("%s+$", "")
    local tag, rest = stripped:match("^@(%a[%w_%-]*)%s*(.*)$")
    if tag then
      tag = tag:lower()
      if tag == "param" then
        -- `@param type $name desc`, `@param $name desc`, and `@param type
        -- $name` with no description are all written.
        local typ, name, desc = rest:match("^([^%s$]*)%s*%$([%w_]+)%s*(.*)$")
        if name then
          current = { name = name, type = typ or "", desc = desc or "" }
          params[#params + 1] = current
        else
          current = nil
        end
      elseif tag == "return" or tag == "returns" then
        local typ, desc = rest:match("^(%S*)%s*(.*)$")
        current = { type = typ or "", desc = desc or "" }
        returns[#returns + 1] = current
      elseif tag == "internal" then
        internal = true
        current = nil
      elseif tag == "deprecated" then
        deprecated = rest ~= "" and rest or "deprecated"
        current = nil
      else
        -- `@throws`, `@var`, `@see`, `@since`, `@psalm-*`, `@phpstan-*` and
        -- the rest of a vocabulary that grows per static analyser. Recognised
        -- as tags so their text stays out of the prose, not modelled: the IR
        -- has no field for them and inventing one per analyser is how a doc
        -- parser becomes a doc format.
        current = nil
      end
    elseif current and stripped ~= "" then
      -- A continuation line is indented under its tag, and the frame strip
      -- above removes only the single space that follows the `*`. Trimmed
      -- here so joining two lines produces one space rather than four.
      current.desc = (current.desc == "" and "" or current.desc .. " ")
        .. (stripped:gsub("^%s+", ""))
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
    internal = internal,
    deprecated = deprecated,
  }
end

---Whether a declaration is outside the published surface.
---
---**Written as "not private and not protected", never as "has public".** A
---PHP method with no modifier is *public* — the opposite of C#, where the
---same absence means private and where reading it the other way round
---inverted every interface in the language. Asking for the `public` keyword
---here would report every unmarked method in every legacy PHP file as
---internal.
---
---`inherited` covers the construct four languages have now needed it for: an
---interface member is public and cannot be declared otherwise — writing
---`private` there is a fatal error in PHP, not merely unconventional.
---@param node TSNode
---@param src string
---@param inherited boolean? The enclosing type's visibility, when inside an interface.
---@return boolean
local function is_internal(node, src, inherited)
  local vis = child_of(node, "visibility_modifier")
  if not vis then
    if inherited ~= nil then
      return inherited
    end
    return false
  end
  local word = text_of(vis, src):lower()
  return word == "private" or word == "protected"
end

---@param node TSNode? `formal_parameters`
---@param src string
---@return string[]
local function param_names(node, src)
  local out = {}
  if not node then
    return out
  end
  for child in node:iter_children() do
    local kind = child:type()
    if
      kind == "simple_parameter"
      or kind == "variadic_parameter"
      or kind == "property_promotion_parameter"
    then
      local var = child_of(child, "variable_name")
      if var then
        -- The `$` is part of how PHP writes a variable and not part of its
        -- name; the doc block's `@param int $x` loses it too, so the two
        -- agree.
        out[#out + 1] = (text_of(var, src):gsub("^%$", ""))
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

  local ns_node = child_of(root, "namespace_definition")
  local ns = ns_node and child_of(ns_node, "namespace_name")
  local namespace = ns and text_of(ns, src) or nil
  local stem = path:match("([^/\\]+)%.php$")

  -- **Namespace plus file stem, and PSR-4 makes that more than a convention.**
  -- The autoloading standard every modern PHP project follows requires the
  -- class name to match the file name and the namespace to match the
  -- directory — so `src/Other/Thing.php` really is `Acme\Other\Thing`, and a
  -- `use Acme\Other\Thing;` elsewhere really does name this file. That is
  -- what turns PHP's symbolic imports into resolvable edges, which Java's
  -- `import a.b.C` gets for the same reason and C#'s `using` does not.
  local module = (namespace and stem) and (namespace .. "\\" .. stem) or nil

  -- **PHP has no file-level doc block**, so the file's summary is the summary
  -- of the first type it declares — the same answer C# gives, and for the
  -- same reason: one type per file is what PSR-4 requires rather than merely
  -- encourages.
  --
  -- A license banner is a `//` or `/*` comment and only `/**` is read, so it
  -- is skipped without a rule of its own.
  local blocks = doc_blocks(root, src)
  local first_doc = nil
  local function find_first(node)
    for child in node:iter_children() do
      local kind = child:type()
      if
        kind == "class_declaration"
        or kind == "interface_declaration"
        or kind == "trait_declaration"
        or kind == "enum_declaration"
        or kind == "function_definition"
      then
        first_doc = blocks[child:start() - 1]
        return true
      end
      if kind == "namespace_definition" or kind == "compound_statement" then
        if find_first(child) then
          return true
        end
      end
    end
    return false
  end
  find_first(root)

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

  ---@param node TSNode
  ---@param owner string?
  ---@param inherited boolean?
  ---@param owner_kind Documentation.ScopeKind? Which declaration `owner` is, supplied by `record_type` alongside `inherited`.
  local function record_function(node, owner, inherited, owner_kind)
    local name_node = child_of(node, "name")
    if not name_node then
      return
    end
    local bare = text_of(name_node, src)
    local qualified = owner and (owner .. "::" .. bare) or bare
    local doc = parse_doc(blocks[node:start() - 1])
    local names = param_names(child_of(node, "formal_parameters"), src)
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
      -- Two kinds of evidence, and PHP is the only language here that offers
      -- both: the keyword, and PHPDoc's own `@internal`. Either one is
      -- enough to keep a declaration out of the published surface.
      internal = is_internal(node, src, inherited) or doc.internal,
      owner = owner,
      owner_kind = owner and (owner_kind or "class") or nil,
      see = {},
      overload = {},
      todo = {},
      bug = {},
      test = {},
    }
  end

  ---@param node TSNode A type declaration.
  local function record_type(node)
    local name_node = child_of(node, "name")
    if not name_node then
      return
    end
    local bare = text_of(name_node, src)
    local kind = node:type()
    local doc = parse_doc(blocks[node:start() - 1])
    symbols[#symbols + 1] = {
      name = bare,
      kind = "table",
      detail = (kind:gsub("_declaration$", "")),
      summary = doc.summary,
      line = node:start() + 1,
    }

    local body = child_of(node, "declaration_list")
    if not body then
      return
    end
    -- An interface member is public and cannot be declared otherwise; a
    -- class member's absent modifier already means public, so `inherited`
    -- only has to be supplied for the case where the keyword is forbidden.
    local inherited = kind == "interface_declaration" and false or nil
    ---@type Documentation.ScopeKind
    local owner_kind = kind == "interface_declaration" and "interface"
      or kind == "trait_declaration" and "trait"
      or kind == "enum_declaration" and "enum"
      or "class"
    for member in body:iter_children() do
      local mk = member:type()
      if mk == "method_declaration" then
        record_function(member, bare, inherited, owner_kind)
      elseif mk == "const_declaration" or mk == "property_declaration" then
        local doc_member = parse_doc(blocks[member:start() - 1])
        for element in member:iter_children() do
          local ek = element:type()
          if ek == "const_element" or ek == "property_element" then
            local id = child_of(element, "name") or child_of(element, "variable_name")
            if id then
              symbols[#symbols + 1] = {
                name = bare .. "::" .. (text_of(id, src):gsub("^%$", "")),
                kind = ek == "const_element" and "constant" or "binding",
                detail = (text_of(member, src):gsub("%s+", " "):gsub(";%s*$", "")):sub(1, 60),
                summary = doc_member.summary,
                line = member:start() + 1,
              }
            end
          end
        end
      end
    end
  end

  ---A `require`/`include` target, made relative-resolvable.
  ---
  ---Only a literal path is recorded. `require $class . '.php'` is a
  ---computed target and there is nothing honest to write down for it — the
  ---same position `deps.lua` takes on a `require` with no literal in it.
  ---`__DIR__ . '/x.php'` is the idiomatic form and its literal half is what
  ---matters, so the concatenation is read through.
  ---@param text string
  ---@return string?
  local function include_target(text)
    local literal = text:match("'([^']+%.php)'") or text:match('"([^"]+%.php)"')
    if not literal then
      return nil
    end
    literal = literal:gsub("\\", "/")
    -- **`__DIR__ . '/x.php'` is relative, and its slash is a separator.**
    -- Read literally the string is `/x.php`, which would resolve against the
    -- top of the scanned tree — a real file, somewhere else. `__DIR__` names
    -- the including file's own directory, so the leading slash is joining
    -- two halves rather than rooting the path, and this is by far the most
    -- common way a PHP file names a sibling.
    if text:match("__DIR__") or text:match("dirname%s*%(") then
      literal = literal:gsub("^/+", "")
    end
    if literal:sub(1, 2) == "./" or literal:sub(1, 3) == "../" or literal:sub(1, 1) == "/" then
      return literal
    end
    return "./" .. literal
  end

  local function walk(node)
    for child in node:iter_children() do
      local kind = child:type()

      if kind == "namespace_use_declaration" then
        for clause in child:iter_children() do
          if clause:type() == "namespace_use_clause" then
            local name = child_of(clause, "qualified_name") or child_of(clause, "name")
            if name then
              requires[#requires + 1] = {
                module = text_of(name, src),
                line = clause:start() + 1,
              }
            end
          end
        end
      elseif
        kind == "class_declaration"
        or kind == "interface_declaration"
        or kind == "trait_declaration"
        or kind == "enum_declaration"
      then
        record_type(child)
      elseif kind == "function_definition" then
        record_function(child, nil, nil)
      elseif kind == "namespace_definition" then
        walk(child)
      elseif kind == "compound_statement" or kind == "declaration_list" then
        walk(child)
      elseif kind == "expression_statement" then
        local expr = child_of(child, "require_expression")
          or child_of(child, "require_once_expression")
          or child_of(child, "include_expression")
          or child_of(child, "include_once_expression")
        if expr then
          local target = include_target(text_of(expr, src))
          if target then
            requires[#requires + 1] = { module = target, line = child:start() + 1 }
          end
        end
      end
    end
  end
  walk(root)

  return fns, {}, requires, symbols, {}, {}, lines, {}
end

require("documentation.core.lang_registry").register(M.name, M)

return M
