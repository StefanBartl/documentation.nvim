---@module 'documentation.core.lang.ruby'
--- Ruby, registered as a language backend — the fifteenth.
---
--- **Visibility is a positional statement, which this tool has met once
--- before.** `private` is not a modifier on a definition; it is a *method
--- call* that changes the default for everything declared after it, until
--- something changes it back. C++'s `private:` has the same shape and needed
--- the same answer: track it while walking rather than read it off the node,
--- because there is nothing on the node to read. Ruby adds two spellings C++
--- has no equivalent of — `private def foo` marks one definition, and
--- `private :foo` marks one *by name*, possibly long after it was defined —
--- and both are handled, because a class that uses them is not unusual.
---
--- **The naming is Ruby's own.** An instance method is `Widget#add` and a
--- class method is `Widget.build`. That is not decoration: the two are
--- different methods, they can coexist under one name, and every Ruby
--- document ever written distinguishes them exactly this way. Using `::` for
--- both — as C++ and Rust do — would merge two entities the language keeps
--- apart.
---
--- **`param_docs = false`, and this is the first backend to declare it while
--- still parsing parameters.** The distinction is worth stating because it
--- is new: YARD's `@param [Integer] x` is real, common and worth showing, so
--- it is extracted and shown. But YARD is a *gem*, not the language — RDoc,
--- which ships with Ruby, has no per-parameter form at all — so a Ruby
--- project that documents beautifully in RDoc would be reported as
--- documenting no parameters anywhere. **Parse and display; do not judge.**
--- That is a different position from Zig's and Go's, where there was nothing
--- to parse in the first place.
---
--- **The path is the identity.** Ruby has no rule tying a file's name to
--- what it defines — one file can open three classes in two modules, and
--- `require` names a *load path* entry rather than a file relative to the
--- caller. `require_relative` is the one that names a file, and it is the one
--- that resolves.

local M = {}

M.name = "ruby"

M.grammar = "ruby"

---@type string[]
M.extensions = { "rb" }

---Ruby has no tag naming a file's module, and no rule tying a file's name to
---what it defines. Nothing tag-shaped can be missing.
M.module_tag = false

---@type string[]
M.line_comments = { "#" }

---`=begin`/`=end` is Ruby's block comment. Both markers must sit in column
---zero, which `core/markers.lua`'s scanner does not check — the cost is that
---an `=begin` inside a string could open a phantom block, and the benefit is
---that a marker inside a real block comment is found. Real Ruby uses this
---form almost never, so both the cost and the benefit are small.
---@type { [1]: string, [2]: string }[]
M.block_comments = { { "=begin", "=end" } }

---**Parsed but not judged, and Ruby is the first language here where those
---come apart.** YARD's `@param [Integer] x` is real and common, so it is
---extracted and shown. But YARD is a gem rather than the language: RDoc,
---which ships with Ruby, has no per-parameter form at all — so judging Ruby
---by parameter documentation would report a project that documents
---beautifully in RDoc as documenting no parameters anywhere.
---
---Different from Zig, Go, assembly and Rust, where the answer was the same
---but there was nothing to parse to begin with.
M.param_docs = false

---@param filename string
---@return boolean
function M.is_source(filename)
  return filename:match("%.rb$") ~= nil
end

---Where this backend's sources live under `root`, or `nil`.
---
---`lib/` first, and that is not the usual order: it is where every gem puts
---its code, required by the packaging convention rather than merely
---preferred. `app/` is Rails'.
---@param root string
---@return string?
function M.detect_source(root)
  local uv = vim.uv or vim.loop

  ---@param dir string
  ---@param depth integer
  ---@return boolean
  local function holds_rb(dir, depth)
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
        if holds_rb(sub, depth - 1) then
          return true
        end
      end
    end
    return false
  end

  for _, candidate in ipairs({ "lib", "app", "src" }) do
    if holds_rb(root .. "/" .. candidate, 1) then
      return candidate
    end
  end
  if holds_rb(root, 1) then
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

---Every `#` comment run in the file, keyed by the row it ends on.
---
---Every comment counts. Ruby has no doc sigil — RDoc and YARD both read the
---plain comment block above a definition — so a rule stricter than that
---would find nothing in any Ruby project ever written, which is the mistake
---the Doxygen-only rule made about C.
---
---`# frozen_string_literal: true` and `# rubocop:disable` are magic comments
---and tool directives that sit exactly where documentation sits; they are
---dropped for the reason Go's `//go:build` is.
---@param root userdata
---@param src string
---@return table<integer, string[]>
local function comment_runs(root, src)
  local by_row = {}
  local function walk(node)
    if node:type() == "comment" then
      local srow = node:start()
      local body = text_of(node, src):match("^#%s?(.*)$")
      if body then
        local previous = by_row[srow - 1]
        if previous then
          by_row[srow - 1] = nil
          previous[#previous + 1] = body
          by_row[srow] = previous
        else
          by_row[srow] = { body }
        end
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

---The comment run above `row`, parsed as RDoc prose with YARD tags.
---@param runs table<integer, string[]>
---@param row integer 0-based row of the documented definition.
---@return { summary: string, body: string, params: Documentation.ParamInfo[], returns: Documentation.ReturnInfo[], internal: boolean }
local function doc_above(runs, row)
  local empty = { summary = "", body = "", params = {}, returns = {}, internal = false }
  local lines = runs[row - 1]
  if not lines then
    return empty
  end

  local params, returns, prose = {}, {}, {}
  local internal = false
  local current = nil
  for _, raw in ipairs(lines) do
    local line = raw:gsub("%s+$", "")
    -- Magic comments and tool directives sit where documentation sits and
    -- mean something to a tool rather than to a reader.
    if
      line:match("^frozen_string_literal:")
      or line:match("^encoding:")
      or line:match("^rubocop:")
      or line:match("^typed:")
      or line:match("^shareable_constant_value:")
    then
      current = nil
    else
      local tag, rest = line:match("^@(%a[%w_]*)%s*(.*)$")
      if tag then
        tag = tag:lower()
        if tag == "param" or tag == "option" then
          -- `@param [Type] name desc` is YARD's order; `@param name desc`
          -- without a type is equally legal.
          local typ, name, desc = rest:match("^%[([^%]]*)%]%s*([%w_]+)%s*(.*)$")
          if not name then
            name, desc = rest:match("^([%w_]+)%s*(.*)$")
            typ = ""
          end
          if name then
            current = { name = name, type = typ or "", desc = desc or "" }
            params[#params + 1] = current
          else
            current = nil
          end
        elseif tag == "return" then
          local typ, desc = rest:match("^%[([^%]]*)%]%s*(.*)$")
          if not typ then
            typ, desc = "", rest
          end
          current = { type = typ, desc = desc or "" }
          returns[#returns + 1] = current
        elseif tag == "api" then
          -- `@api private` is YARD's way of saying a method is not part of
          -- the published surface even though Ruby's own `private` was not
          -- used — the same authoring-convention layer PHP's `@internal`
          -- sits on.
          internal = rest:match("^private") ~= nil
          current = nil
        else
          current = nil
        end
      elseif current and line ~= "" then
        current.desc = (current.desc == "" and "" or current.desc .. " ") .. line:gsub("^%s+", "")
      elseif not current then
        prose[#prose + 1] = line
      end
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
    internal = internal,
  }
end

---@param node userdata? `method_parameters`
---@param src string
---@return string[]
local function param_names(node, src)
  local out = {}
  if not node then
    return out
  end
  for child in node:iter_children() do
    local kind = child:type()
    if kind == "identifier" then
      out[#out + 1] = text_of(child, src)
    elseif
      kind == "optional_parameter"
      or kind == "keyword_parameter"
      or kind == "splat_parameter"
      or kind == "hash_splat_parameter"
      or kind == "block_parameter"
    then
      local id = child_of(child, "identifier")
      if id then
        local name = text_of(id, src)
        if kind == "splat_parameter" then
          name = "*" .. name
        elseif kind == "hash_splat_parameter" then
          name = "**" .. name
        elseif kind == "block_parameter" then
          name = "&" .. name
        elseif kind == "keyword_parameter" then
          name = name .. ":"
        end
        out[#out + 1] = name
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

  local runs = comment_runs(root, src)
  -- **Ruby has no file-level doc comment**, so the file's summary is the
  -- comment above the first `module` or `class` it opens — which in practice
  -- is the same thing, since a Ruby file conventionally defines one and the
  -- `require` path names it.
  local first = nil
  local function find(node)
    for child in node:iter_children() do
      local kind = child:type()
      if kind == "module" or kind == "class" then
        first = child
        return true
      end
      if kind == "body_statement" or kind == "program" then
        if find(child) then
          return true
        end
      end
    end
    return false
  end
  find(root)
  if not first then
    return empty
  end

  local doc = doc_above(runs, first:start())
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

  local runs = comment_runs(root, src)
  local fns, requires, symbols = {}, {}, {}
  -- Methods by name, so a `private :foo` appearing *after* the definition
  -- can reach back and change it — a shape no other language here has.
  local by_name = {}

  ---@param node userdata `method` or `singleton_method`
  ---@param owner string?
  ---@param internal boolean Current positional visibility.
  ---@param owner_kind Documentation.ScopeKind? `class` or `module` — Ruby's two owning constructs, both of which can hold methods and both of which nest.
  local function record_method(node, owner, internal, owner_kind)
    local name_node = child_of(node, "identifier")
      or child_of(node, "constant")
      or child_of(node, "operator")
    if not name_node then
      return
    end
    local bare = text_of(name_node, src)
    local singleton = node:type() == "singleton_method"
    -- Ruby's own notation: `Widget#add` is the instance method, `Widget.build`
    -- the class method. They are different methods and can share a name.
    local qualified = owner and (owner .. (singleton and "." or "#") .. bare) or bare
    local doc = doc_above(runs, node:start())
    local names = param_names(child_of(node, "method_parameters"), src)
    local entry = {
      name = qualified,
      signature = qualified .. "(" .. table.concat(names, ", ") .. ")",
      line = node:start() + 1,
      line_end = node:end_() + 1,
      summary = doc.summary,
      body = doc.body,
      params = doc.params,
      returns = doc.returns,
      -- A class method declared after `private` is still public: `private`
      -- affects instance methods only, which is a Ruby subtlety worth
      -- getting right rather than approximating.
      internal = (not singleton and internal) or doc.internal,
      owner = owner,
      owner_kind = owner and (owner_kind or "class") or nil,
      see = {},
      overload = {},
      todo = {},
      bug = {},
      test = {},
    }
    fns[#fns + 1] = entry
    by_name[bare] = entry
  end

  ---A `require`/`require_relative` target, or `nil`.
  ---
  ---**Only `require_relative` resolves, and that is Ruby's own doing.**
  ---`require 'json'` searches the load path, which depends on the installed
  ---gems and on how the process was started; `require_relative 'helpers'`
  ---names a file beside this one, which is exactly what
  ---`deps.resolve_relative` can follow.
  ---@param node userdata `call`
  ---@return string?
  local function require_target(node)
    local fn = child_of(node, "identifier")
    if not fn then
      return nil
    end
    local which = text_of(fn, src)
    if which ~= "require" and which ~= "require_relative" then
      return nil
    end
    local args = child_of(node, "argument_list")
    local str = args and child_of(args, "string")
    local content = str and child_of(str, "string_content")
    if not content then
      return nil
    end
    local target = text_of(content, src)
    if which == "require_relative" then
      if target:sub(1, 2) ~= "./" and target:sub(1, 3) ~= "../" then
        target = "./" .. target
      end
      -- Ruby omits the extension; the resolver appends each backend's own.
      return target
    end
    return target
  end

  ---@param body userdata `body_statement`
  ---@param owner string? Enclosing module/class path.
  ---@param owner_kind Documentation.ScopeKind? What `owner` was declared as.
  local function walk_body(body, owner, owner_kind)
    -- **Positional visibility, tracked while walking.** `private` is a call
    -- that changes the default for everything after it; there is nothing on
    -- a definition to read. The same answer C++'s access specifier needed.
    local internal = false

    for child in body:iter_children() do
      local kind = child:type()

      if kind == "identifier" then
        local word = text_of(child, src)
        if word == "private" or word == "protected" then
          internal = true
        elseif word == "public" then
          internal = false
        end
      elseif kind == "method" or kind == "singleton_method" then
        record_method(child, owner, internal, owner_kind)
      elseif kind == "class" or kind == "module" then
        local name_node = child_of(child, "constant") or child_of(child, "scope_resolution")
        if name_node then
          local bare = text_of(name_node, src)
          local nested = owner and (owner .. "::" .. bare) or bare
          local doc = doc_above(runs, child:start())
          symbols[#symbols + 1] = {
            name = nested,
            kind = "table",
            detail = kind,
            summary = doc.summary,
            line = child:start() + 1,
          }
          local inner = child_of(child, "body_statement")
          if inner then
            walk_body(inner, nested, kind == "module" and "module" or "class")
          end
        end
      elseif kind == "assignment" then
        local lhs = child_of(child, "constant")
        if lhs then
          local doc = doc_above(runs, child:start())
          symbols[#symbols + 1] = {
            name = owner and (owner .. "::" .. text_of(lhs, src)) or text_of(lhs, src),
            kind = "constant",
            detail = (text_of(child, src):gsub("%s+", " ")):sub(1, 60),
            summary = doc.summary,
            line = child:start() + 1,
          }
        end
      elseif kind == "call" then
        local target = require_target(child)
        if target then
          requires[#requires + 1] = { module = target, line = child:start() + 1 }
        else
          local fn = child_of(child, "identifier")
          local word = fn and text_of(fn, src)
          if word == "private" or word == "protected" or word == "public" then
            -- Two more spellings, and both are ordinary Ruby.
            --
            -- `private def foo` marks one definition: the `def` is the
            -- call's argument, so it is recorded here with the visibility
            -- forced rather than left to the positional default.
            --
            -- `private :foo` marks a method *by name*, and may appear long
            -- after the definition — which is why methods are indexed by
            -- name above. No other language here can change a declaration's
            -- visibility from somewhere else in the file.
            local args = child_of(child, "argument_list")
            if args then
              for arg in args:iter_children() do
                local ak = arg:type()
                if ak == "method" or ak == "singleton_method" then
                  record_method(arg, owner, word ~= "public")
                elseif ak == "simple_symbol" then
                  local name = text_of(arg, src):gsub("^:", "")
                  local existing = by_name[name]
                  if existing then
                    existing.internal = word ~= "public"
                  end
                end
              end
            else
              -- A bare `private` parsed as a call rather than an identifier.
              internal = word ~= "public"
            end
          elseif word and word:match("^attr_") then
            local args = child_of(child, "argument_list")
            if args then
              local doc = doc_above(runs, child:start())
              for arg in args:iter_children() do
                if arg:type() == "simple_symbol" then
                  local name = text_of(arg, src):gsub("^:", "")
                  symbols[#symbols + 1] = {
                    name = owner and (owner .. "#" .. name) or name,
                    kind = "binding",
                    detail = word,
                    summary = doc.summary,
                    line = child:start() + 1,
                  }
                end
              end
            end
          end
        end
      end
    end
  end

  local function walk_top(node, owner)
    for child in node:iter_children() do
      local kind = child:type()
      if kind == "class" or kind == "module" then
        local name_node = child_of(child, "constant") or child_of(child, "scope_resolution")
        if name_node then
          local bare = text_of(name_node, src)
          local nested = owner and (owner .. "::" .. bare) or bare
          local doc = doc_above(runs, child:start())
          symbols[#symbols + 1] = {
            name = nested,
            kind = "table",
            detail = kind,
            summary = doc.summary,
            line = child:start() + 1,
          }
          local inner = child_of(child, "body_statement")
          if inner then
            walk_body(inner, nested, kind == "module" and "module" or "class")
          end
        end
      elseif kind == "call" then
        local target = require_target(child)
        if target then
          requires[#requires + 1] = { module = target, line = child:start() + 1 }
        end
      elseif kind == "method" or kind == "singleton_method" then
        -- `owner` is nil at true file scope, so a script's bare `def` stays a
        -- free function; `walk_top` is re-entered with one only from inside a
        -- construct that already supplied its kind.
        record_method(child, owner, false)
      end
    end
  end
  walk_top(root, nil)

  return fns, {}, requires, symbols, {}, {}, lines, {}
end

require("documentation.core.lang_registry").register(M.name, M)

return M
