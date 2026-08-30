---@module 'documentation.core.lang.python'
--- Python, registered as a language backend — the tenth, and the first of the
--- thirty on the second language list.
---
--- **Three things here are new to this tool, and each one costs a decision
--- the nine before it never had to make.**
---
--- **1. The documentation is not a comment.** Every backend so far read doc
--- prose out of comment nodes. A Python docstring is a *string literal* — the
--- first statement of a module, function or class — which the parser hands
--- back as a `string` node with real content, not as trivia. Two consequences
--- worth stating rather than discovering: the doc block is found by position
--- (first statement) rather than by adjacency (the run above a declaration),
--- and `core/markers.lua` still scans `#` comments and only those, which is
--- correct — a `# TODO:` is a note to a maintainer, a "TODO" inside a
--- docstring is prose the author published on purpose.
---
--- **2. There is no single docstring format**, and this is the first language
--- where the doc convention forks the way assembly's *syntax* did. reST
--- (`:param x:`), Google (`Args:` with an indented block) and NumPy
--- (`Parameters` under a rule of dashes) are all in wide use, and a single
--- repository routinely mixes them. So the style is detected **per
--- docstring**, not per project: a file-wide guess would be wrong for the one
--- function somebody wrote differently, which is exactly the function a
--- reader is looking at when they notice the tool is wrong.
---
--- **3. `__all__` is an export list, and it beats the naming convention.**
--- Python's visibility is the leading underscore — a convention, like Lua's
--- `@internal`, rather than a keyword. But a module that declares `__all__`
--- has stated its published surface outright, and that statement wins in
--- *both* directions: a name in it is public even with an underscore, a name
--- absent from it is internal even without one. Where there is no `__all__`,
--- the underscore is the only evidence there is.
---
--- Dunders (`__init__`, `__repr__`) are excluded from the underscore rule.
--- They begin with two underscores and are the most public thing in a class;
--- treating them as private would hide every constructor in the map.
---
--- **`self` and `cls` are not in the emitted signature, and that is a
--- deliberate reading rather than a transcription.** The signature this map
--- shows is the *call* signature — `Thing.go(n)` is what a caller writes,
--- because the receiver is bound by the attribute access. Keeping `self`
--- would also break the one thing signatures are checked for: no docstring
--- style documents `self`, so every method in every Python project would
--- report an undocumented parameter forever. The same class of wrongness
--- `param_docs = false` fixed for Zig, avoided here at the source instead.
---
--- **Packages are directories with `__init__.py`** — the first `module_file`
--- since Lua's `init.lua`, and the reason that field exists at all rather
--- than being a Lua special case. A directory without one is a namespace,
--- exactly as everywhere else.

local M = {}

M.name = "python"

M.grammar = "python"

---@type string[]
M.extensions = { "py", "pyi" }

---Python's identity is its import path, which is its file path — the same
---answer Zig, C and assembly give, reached by a different route: the import
---system resolves against `sys.path` and package directories, never against
---a tag inside the file.
M.module_tag = false

---A directory owning a module, the Lua `init.lua` shape. `.pyi` is a stub
---file rather than a package marker, so only the real one counts.
M.module_file = "__init__.py"

---`#` and nothing else. **Python has no block comment** — a triple-quoted
---string used as one is a string the interpreter evaluates and throws away,
---which is why this backend reads docstrings out of exactly that node type.
---Declaring `'''` as a block comment here would make `core/markers.lua`
---report every docstring's prose as commented-out code.
---@type string[]
M.line_comments = { "#" }

---@type { [1]: string, [2]: string }[]
M.block_comments = {}

---All three docstring styles name parameters individually, so the strict
---rule applies — unlike Zig and assembly, which declare `false` here.
M.param_docs = true

---@param filename string
---@return boolean
function M.is_source(filename)
  return filename:match("%.py$") ~= nil or filename:match("%.pyi$") ~= nil
end

---Where this backend's sources live under `root`, or `nil`.
---
---`src/` first because a `src` layout puts the package one level down, and
---then the root itself, which is the flat layout most small projects use. A
---directory holding `__init__.py` is a package and therefore a source root
---even when it holds no loose `.py` files of its own.
---@param root string
---@return string?
function M.detect_source(root)
  local uv = vim.uv or vim.loop

  local function holds_python(dir)
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
      -- A package directory counts even when the level above it is empty:
      -- `src/mypkg/__init__.py` with nothing loose in `src/` is the standard
      -- layout, and answering `nil` there would send the walk to the root
      -- and map the test and build files instead.
      if kind == "directory" and uv.fs_stat(dir .. "/" .. name .. "/__init__.py") then
        return true
      end
    end
  end

  for _, candidate in ipairs({ "src", "lib", "source" }) do
    if holds_python(root .. "/" .. candidate) then
      return candidate
    end
  end
  if holds_python(root) then
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

---Remove the indentation a docstring carries because of where it sits.
---
---The same rule `inspect.cleandoc` uses, and it has to be the same one: a
---docstring's second line onward is indented to the function's body, and
---taking it verbatim would make every parsed `Args:` block look like it
---starts eight columns in. The first line is exempt — it begins right after
---the opening quotes and has no indentation to share.
---@param text string
---@return string[]
local function dedent(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    -- **The `\r` comes off here, once, rather than at each consumer.** A
    -- Python file saved with CRLF line endings is ordinary on Windows, and
    -- splitting on `\n` alone leaves a carriage return at the end of every
    -- line — which then survives into any description built by *joining*
    -- lines, because the per-field trim only reaches the ends of the
    -- finished string. Found by the spec, on a Google-style parameter whose
    -- description continued onto a second line.
    lines[#lines + 1] = (line:gsub("\r$", ""))
  end
  while #lines > 0 and lines[#lines]:match("^%s*$") do
    table.remove(lines)
  end

  local common = nil
  for i = 2, #lines do
    if not lines[i]:match("^%s*$") then
      local indent = #(lines[i]:match("^(%s*)"))
      if not common or indent < common then
        common = indent
      end
    end
  end
  if common and common > 0 then
    for i = 2, #lines do
      lines[i] = lines[i]:sub(common + 1)
    end
  end
  if lines[1] then
    lines[1] = lines[1]:gsub("^%s+", "")
  end
  return lines
end

---The docstring of a node whose body is `block`, or of the module itself.
---
---By position rather than by adjacency: a docstring is *the first statement*,
---and anything else in that slot means the thing is undocumented. That is
---Python's own rule — the interpreter stores `__doc__` only when the first
---statement is a string literal — so reading it any other way would credit
---prose the language itself does not.
---@param body userdata The `block` node, or the `module` root.
---@param src string
---@return string[]? lines
local function docstring_of(body, src)
  for child in body:iter_children() do
    local kind = child:type()
    -- `comment` is skipped rather than treated as a wall: a `# type: ignore`
    -- above a docstring is common and does not un-document the function.
    if kind ~= "comment" then
      local str = kind == "string" and child
        or (kind == "expression_statement" and child_of(child, "string"))
      if not str then
        return nil
      end
      local content = child_of(str, "string_content")
      if not content then
        return nil
      end
      return dedent(text_of(content, src))
    end
  end
  return nil
end

---Which of the three conventions a docstring is written in.
---
---**Per docstring, not per project.** One repository mixes them routinely —
---a vendored module, a contributor's habit, a file that predates a style
---guide — and a project-wide guess is wrong exactly on the function somebody
---wrote differently, which is the function a reader is looking at when they
---notice the tool is wrong.
---
---Order matters: reST's `:param` is unambiguous and checked first, then
---NumPy's underlined section (a `Parameters` line followed by dashes), then
---Google's `Args:`. Nothing found is `nil` rather than a default — a
---docstring that is one prose paragraph has no style, and picking one for it
---would mean parsing its prose for parameters that were never written.
---@param lines string[]
---@return "rest"|"numpy"|"google"|nil
local function docstring_style(lines)
  for i, line in ipairs(lines) do
    if line:match("^:param%s") or line:match("^:returns?:") or line:match("^:rtype:") then
      return "rest"
    end
    if line:match("^Parameters%s*$") and lines[i + 1] and lines[i + 1]:match("^%-%-%-+%s*$") then
      return "numpy"
    end
    if line:match("^Returns%s*$") and lines[i + 1] and lines[i + 1]:match("^%-%-%-+%s*$") then
      return "numpy"
    end
    if line:match("^Args:%s*$") or line:match("^Arguments:%s*$") or line:match("^Returns:%s*$") then
      return "google"
    end
  end
  return nil
end

---@param name string
---@param typ string?
---@param desc string
---@return Documentation.ParamInfo
local function param(name, typ, desc)
  return {
    -- **reST escapes the asterisks**, so `**kwargs` is written `\*\*kwargs`
    -- in a `:param` line — and taking that verbatim gives a documented name
    -- that can never match the declared one, which is a `param-name-mismatch`
    -- on every `**kwargs` in every reST-documented project. Unescaped here
    -- because the escape belongs to the markup, not to the name.
    name = (name:gsub("\\", "")),
    type = typ or "",
    desc = (desc or ""):gsub("^%s+", ""):gsub("%s+$", ""),
  }
end

---reST: `:param x: text`, `:param int x: text`, `:returns: text`.
---@param lines string[]
---@return Documentation.ParamInfo[], Documentation.ReturnInfo[], string[]
local function parse_rest(lines)
  local params, returns, prose = {}, {}, {}
  local current = nil
  for _, line in ipairs(lines) do
    local body = line:match("^:param%s+(.+)$")
    if body then
      local head, desc = body:match("^([^:]+):%s*(.*)$")
      if head then
        -- `:param int x:` puts the type first; `:param x:` has none. Split on
        -- the last space so a multi-word type stays with the type.
        local typ, name = head:match("^(.*)%s+([%w_]+)$")
        current = param(name or head, name and typ or nil, desc)
        params[#params + 1] = current
      end
    elseif line:match("^:returns?:") then
      current = { type = "", desc = line:match("^:returns?:%s*(.*)$") or "" }
      returns[#returns + 1] = current
    elseif line:match("^:rtype:") then
      if returns[1] then
        returns[1].type = line:match("^:rtype:%s*(.*)$") or ""
      end
      current = nil
    elseif line:match("^:") then
      -- `:raises:`, `:type:` and the rest: recognised as tags so their text
      -- does not land in the prose, but not modelled — the IR has no field
      -- for them and inventing one per convention is how a doc parser
      -- becomes a doc format.
      current = nil
    elseif current and line:match("^%s") and line:match("%S") then
      current.desc = current.desc .. " " .. line:gsub("^%s+", "")
    elseif not current then
      prose[#prose + 1] = line
    end
  end
  return params, returns, prose
end

---Google: an `Args:` section of `name (type): text`, and a `Returns:`
---section whose body is the description.
---@param lines string[]
---@return Documentation.ParamInfo[], Documentation.ReturnInfo[], string[]
local function parse_google(lines)
  local params, returns, prose = {}, {}, {}
  local section, current = nil, nil
  for _, line in ipairs(lines) do
    local heading = line:match("^(%a[%w ]*):%s*$")
    if heading then
      local key = heading:lower()
      if key == "args" or key == "arguments" or key == "parameters" then
        section = "params"
      elseif key == "returns" or key == "yields" then
        section = "returns"
      else
        -- `Raises:`, `Examples:`, `Note:` — a section this IR has nowhere to
        -- put. Skipped rather than folded into the prose, which would put a
        -- traceback list in the summary line.
        section = "skip"
      end
      current = nil
    elseif section == "params" and line:match("^%s+%S") then
      local head, desc = line:match("^%s+([^:]+):%s*(.*)$")
      if head then
        local name, typ = head:match("^([%w_%*]+)%s*%(([^)]*)%)%s*$")
        current = param(name or head:gsub("%s+$", ""), typ, desc)
        params[#params + 1] = current
      elseif current then
        current.desc = current.desc .. " " .. line:gsub("^%s+", "")
      end
    elseif section == "returns" and line:match("^%s+%S") then
      local typ, desc = line:match("^%s+([%w_%.%[%]]+):%s*(.+)$")
      if typ then
        returns[#returns + 1] = { type = typ, desc = desc }
      elseif returns[1] then
        returns[1].desc = returns[1].desc .. " " .. line:gsub("^%s+", "")
      else
        returns[#returns + 1] = { type = "", desc = line:gsub("^%s+", "") }
      end
    elseif line:match("^%s*$") then
      if section ~= "params" and section ~= "returns" then
        section = nil
      end
      if not section then
        prose[#prose + 1] = line
      end
    elseif not section then
      prose[#prose + 1] = line
    end
  end
  return params, returns, prose
end

---NumPy: a `Parameters` heading underlined with dashes, then `name : type`
---with the description indented beneath it.
---@param lines string[]
---@return Documentation.ParamInfo[], Documentation.ReturnInfo[], string[]
local function parse_numpy(lines)
  local params, returns, prose = {}, {}, {}
  local section, current = nil, nil
  local i = 1
  while i <= #lines do
    local line = lines[i]
    local nxt = lines[i + 1]
    if nxt and nxt:match("^%-%-%-+%s*$") and line:match("^%s*%a") then
      local key = line:gsub("%s+$", ""):lower()
      if key == "parameters" or key == "other parameters" then
        section = "params"
      elseif key == "returns" or key == "yields" then
        section = "returns"
      else
        section = "skip"
      end
      current = nil
      i = i + 2
    else
      if section == "params" and line:match("^%S") then
        local name, typ = line:match("^([%w_%*]+)%s*:%s*(.*)$")
        current = param(name or line:gsub("%s+$", ""), typ, "")
        params[#params + 1] = current
      elseif section == "returns" and line:match("^%S") then
        local name, typ = line:match("^([%w_]+)%s*:%s*(.*)$")
        current = { type = typ or line:gsub("%s+$", ""), desc = "" }
        local _ = name
        returns[#returns + 1] = current
      elseif current and line:match("^%s+%S") then
        current.desc = (current.desc == "" and "" or current.desc .. " ") .. line:gsub("^%s+", "")
      elseif not section and line then
        prose[#prose + 1] = line
      end
      i = i + 1
    end
  end
  return params, returns, prose
end

---A docstring, split into summary, body, parameters and returns.
---@param lines string[]?
---@return { summary: string, body: string, params: Documentation.ParamInfo[], returns: Documentation.ReturnInfo[] }
local function parse_docstring(lines)
  local empty = { summary = "", body = "", params = {}, returns = {} }
  if not lines or #lines == 0 then
    return empty
  end
  local style = docstring_style(lines)
  local params, returns, prose
  if style == "rest" then
    params, returns, prose = parse_rest(lines)
  elseif style == "google" then
    params, returns, prose = parse_google(lines)
  elseif style == "numpy" then
    params, returns, prose = parse_numpy(lines)
  else
    params, returns, prose = {}, {}, lines
  end

  while prose[#prose] and prose[#prose]:match("^%s*$") do
    table.remove(prose)
  end

  -- **A reST section underline is punctuation, not a sentence.** A module
  -- docstring conventionally opens with a title over a rule of `~` or `=`,
  -- and joining the two produced `requests.api ~~~~~~~~~~~~` as the summary
  -- of `psf/requests`' own API module: a heading and its underline read as
  -- one line. Dropped here rather than in `split_summary`, which is shared
  -- and has no business knowing about reST — the same division assembly's
  -- banner filter draws.
  --
  -- Only a line that is *nothing but* rule characters goes, so a docstring
  -- that legitimately draws `----` inside a code sample keeps it.
  local kept = {}
  for _, line in ipairs(prose) do
    if not line:match("^[%-=~%^#%*%+_]+%s*$") then
      kept[#kept + 1] = line
    end
  end
  prose = kept

  local body = table.concat(prose, "\n")
  return {
    summary = require("documentation.core.scan").split_summary(body),
    body = body,
    params = params,
    returns = returns,
  }
end

---The parameter names a `parameters` node declares, minus the receiver.
---
---**`self`/`cls` are dropped here rather than downstream**, for the reason
---the file header gives: the signature this map shows is the call signature,
---and no docstring convention documents the receiver — so keeping it would
---make every method in every Python project report an undocumented
---parameter, forever, in a check that is right about every other language.
---@param node userdata?
---@param src string
---@return string[]
local function param_names(node, src)
  local out = {}
  if not node then
    return out
  end
  for child in node:iter_children() do
    local kind = child:type()
    local name
    if kind == "identifier" then
      name = text_of(child, src)
    elseif kind == "list_splat_pattern" or kind == "dictionary_splat_pattern" then
      local id = child_of(child, "identifier")
      name = id and ((kind == "list_splat_pattern" and "*" or "**") .. text_of(id, src))
    elseif
      kind == "typed_parameter"
      or kind == "default_parameter"
      or kind == "typed_default_parameter"
    then
      -- **A typed splat nests one level deeper**, and missing that dropped
      -- `**kwargs` from every annotated signature. `**kwargs: Unpack[T]`
      -- parses as a `typed_parameter` whose child is the
      -- `dictionary_splat_pattern`, not as a splat carrying a type — so
      -- looking only for a direct `identifier` finds nothing and the
      -- parameter vanishes. Found against `psf/requests`, whose whole
      -- public API is `**kwargs: Unpack[...]`.
      local splat = child_of(child, "list_splat_pattern")
        or child_of(child, "dictionary_splat_pattern")
      if splat then
        local id = child_of(splat, "identifier")
        name = id and ((splat:type() == "list_splat_pattern" and "*" or "**") .. text_of(id, src))
      else
        local id = child_of(child, "identifier")
        name = id and text_of(id, src)
      end
    end
    if name and name ~= "self" and name ~= "cls" then
      out[#out + 1] = name
    end
  end
  return out
end

---Whether `name` is published, given the module's `__all__` (or its absence).
---
---`__all__` wins in both directions where it exists; the leading underscore
---is the evidence where it does not. A dunder is public: `__init__` begins
---with two underscores and is the most-called method in most classes.
---@param name string
---@param exported table<string, boolean>?
---@return boolean
local function is_internal(name, exported)
  local bare = name:match("([^%.]+)$") or name
  if exported then
    return not exported[bare]
  end
  if bare:match("^__.*__$") then
    return false
  end
  return bare:sub(1, 1) == "_"
end

---`__all__ = [...]`, as a set, or `nil` when the module declares none.
---@param root userdata
---@param src string
---@return table<string, boolean>?
local function all_list(root, src)
  for child in root:iter_children() do
    local stmt = child:type() == "expression_statement" and child_of(child, "assignment") or child
    if stmt and stmt:type() == "assignment" then
      local target = child_of(stmt, "identifier")
      if target and text_of(target, src) == "__all__" then
        local seq = child_of(stmt, "list") or child_of(stmt, "tuple")
        if not seq then
          -- `__all__ = other.__all__ + ["x"]` and friends: a real export list
          -- this cannot read. Answering `nil` falls back to the underscore
          -- rule, which is a worse answer than the truth and a much better
          -- one than "this module exports nothing".
          return nil
        end
        local out = {}
        for item in seq:iter_children() do
          if item:type() == "string" then
            local content = child_of(item, "string_content")
            if content then
              out[text_of(content, src)] = true
            end
          end
        end
        return out
      end
    end
  end
  return nil
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
  local doc = parse_docstring(docstring_of(root, src))
  if doc.summary == "" and doc.body == "" then
    return empty
  end
  return {
    -- No module tag: the import path is the file path.
    module = nil,
    summary = doc.summary,
    body = doc.body,
    tags = {},
  }
end

---The require target of an import statement, or `nil`.
---
---**Only the relative forms resolve, and that is Python's own doing.** An
---absolute `import a.b` is looked up along `sys.path`, which depends on how
---the interpreter was started and on installed packages — resolving it
---against this tree would be a guess dressed as an edge. A relative import
---is defined against the file's own package, so `from . import x` really is
---`./x` and `from ..pkg import y` really is `../pkg`, which is the
---vocabulary `deps.resolve_relative` already speaks.
---@param node userdata
---@param src string
---@return string[]
local function import_targets(node, src)
  local kind = node:type()
  local out = {}

  if kind == "import_statement" then
    for child in node:iter_children() do
      if child:type() == "dotted_name" then
        out[#out + 1] = text_of(child, src)
      elseif child:type() == "aliased_import" then
        local name = child_of(child, "dotted_name")
        if name then
          out[#out + 1] = text_of(name, src)
        end
      end
    end
    return out
  end

  if kind ~= "import_from_statement" then
    return out
  end

  local relative = child_of(node, "relative_import")
  if not relative then
    local name = child_of(node, "dotted_name")
    if name then
      out[#out + 1] = text_of(name, src)
    end
    return out
  end

  local prefix = child_of(relative, "import_prefix")
  local dots = prefix and #text_of(prefix, src) or 1
  -- One dot is "this package", two is "the one above", and so on — so the
  -- first dot maps to `./` and every further dot to one `../`.
  local base = dots <= 1 and "./" or ("../"):rep(dots - 1)
  local pkg = child_of(relative, "dotted_name")
  if pkg then
    out[#out + 1] = base .. (text_of(pkg, src):gsub("%.", "/"))
    return out
  end

  -- `from . import a, b` names the *modules*, not a package, so each one is
  -- its own edge.
  for child in node:iter_children() do
    if child:type() == "dotted_name" and child ~= pkg then
      out[#out + 1] = base .. (text_of(child, src):gsub("%.", "/"))
    elseif child:type() == "aliased_import" then
      local name = child_of(child, "dotted_name")
      if name then
        out[#out + 1] = base .. (text_of(name, src):gsub("%.", "/"))
      end
    end
  end
  return out
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

  local exported = all_list(root, src)
  local fns, requires, symbols = {}, {}, {}

  ---@param node userdata `function_definition`
  ---@param owner string? Enclosing class name, for a qualified display name.
  local function record_function(node, owner)
    local name_node = child_of(node, "identifier")
    if not name_node then
      return
    end
    local bare = text_of(name_node, src)
    local qualified = owner and (owner .. "." .. bare) or bare
    local params_node = child_of(node, "parameters")
    local names = param_names(params_node, src)
    local block = child_of(node, "block")
    local doc = parse_docstring(block and docstring_of(block, src) or nil)
    local srow = node:start()
    local erow = node:end_()

    -- A method's visibility is its own name's, not its class's: a public
    -- class can hold `_helper`, and `__all__` lists module-level names,
    -- never methods — so a method is judged by the underscore alone.
    --
    -- **An `if`, not `owner and nil or exported`.** That is what this was
    -- first written as, and it is always wrong for a `nil` middle operand:
    -- `x and nil` is falsy, so the `or` branch runs and every method was
    -- judged against the module's export list instead. The fixture caught it
    -- — `Thing.go` came back internal — and it is the exact
    -- `and`/`or`-return-operands trap the Lua glossary carries an entry for.
    local scope = exported
    if owner then
      scope = nil
    end

    fns[#fns + 1] = {
      name = qualified,
      -- Rebuilt from the parameter names rather than copied from the source,
      -- because the receiver is dropped — see `param_names`. Types are in
      -- the annotation and the map shows them in the body, not here.
      signature = qualified .. "(" .. table.concat(names, ", ") .. ")",
      line = srow + 1,
      line_end = erow + 1,
      summary = doc.summary,
      body = doc.body,
      params = doc.params,
      returns = doc.returns,
      internal = is_internal(bare, scope),
      -- The owner as a fact, beside the owner as a prefix of `name`. Python
      -- has exactly one owning construct, so the kind is a constant here —
      -- see `Documentation.ScopeKind` for why it is recorded anyway.
      owner = owner,
      owner_kind = owner and "class" or nil,
      see = {},
      overload = {},
      todo = {},
      bug = {},
      test = {},
    }
  end

  ---Unwrap `@decorator`-wrapped definitions so a `@property` is still a
  ---function and a `@dataclass` is still a class. The decorator itself is
  ---not modelled — the IR has no field for it, and recording the name
  ---without its meaning would be a list nobody could act on.
  ---@param node userdata
  ---@return userdata
  local function undecorate(node)
    if node:type() ~= "decorated_definition" then
      return node
    end
    for child in node:iter_children() do
      local kind = child:type()
      if kind == "function_definition" or kind == "class_definition" then
        return child
      end
    end
    return node
  end

  for top in root:iter_children() do
    local node = undecorate(top)
    local kind = node:type()

    if kind == "import_statement" or kind == "import_from_statement" then
      for _, target in ipairs(import_targets(node, src)) do
        requires[#requires + 1] = { module = target, line = node:start() + 1 }
      end
    elseif kind == "function_definition" then
      record_function(node, nil)
    elseif kind == "class_definition" then
      local name_node = child_of(node, "identifier")
      local class_name = name_node and text_of(name_node, src)
      local block = child_of(node, "block")
      if class_name and block then
        local doc = parse_docstring(docstring_of(block, src))
        symbols[#symbols + 1] = {
          name = class_name,
          kind = "table",
          detail = "class",
          summary = doc.summary,
          line = node:start() + 1,
        }
        for member in block:iter_children() do
          local m = undecorate(member)
          if m:type() == "function_definition" then
            record_function(m, class_name)
          end
        end
      end
    elseif kind == "expression_statement" or kind == "assignment" then
      local assign = kind == "assignment" and node or child_of(node, "assignment")
      if assign then
        local target = child_of(assign, "identifier")
        local name = target and text_of(target, src)
        -- `__all__` is read as the export list a few lines up; repeating it
        -- as a module constant would put this module's own bookkeeping in
        -- the reader's list of things the module defines.
        if name and name ~= "__all__" then
          local value = nil
          local seen_eq = false
          for child in assign:iter_children() do
            if seen_eq and child:type() ~= "type" then
              value = child
              break
            end
            if child:type() == "=" then
              seen_eq = true
            end
          end
          local vtext = value and text_of(value, src) or ""
          local vkind = value and value:type() or ""
          symbols[#symbols + 1] = {
            name = name,
            kind = (vkind == "dictionary" or vkind == "list" or vkind == "tuple" or vkind == "set")
                and "table"
              or (
                (
                    vkind == "string"
                    or vkind == "integer"
                    or vkind == "float"
                    or vkind == "true"
                    or vkind == "false"
                    or vkind == "none"
                  )
                  and "constant"
                or "binding"
              ),
            detail = (vtext:gsub("%s+", " ")):sub(1, 60),
            summary = "",
            line = assign:start() + 1,
          }
        end
      end
    end
  end

  return fns, {}, requires, symbols, {}, {}, lines, {}
end

require("documentation.core.lang_registry").register(M.name, M)

return M
