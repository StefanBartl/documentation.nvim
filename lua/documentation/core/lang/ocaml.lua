---@module 'documentation.core.lang.ocaml'
--- OCaml, registered as a language backend — the twenty-third.
---
--- **The export list lives in another file, and that is new.** Haskell states
--- a module's published surface in its own header and Erlang in an
--- `-export` attribute; OCaml states it in a *sibling file*. `widget.mli`
--- lists the `val`s and `type`s that `widget.ml` publishes, and anything not
--- named there is unreachable from outside the module — enforced by the
--- compiler, not by convention.
---
--- So this backend reads a second file to answer a question about the first,
--- which nothing else here does. Two rules follow, and both are the
--- language's rather than ours:
---
--- * **No `.mli` means everything is public.** A module with no interface
---   exposes its whole contents. That is the third time this tool has met
---   "absent means everything" — Haskell's missing export list, Python's
---   missing `__all__`, and now this — and every time, reading it the other
---   way would report a whole module as private.
--- * **The `.mli` is itself a source file** and is scanned like one. It is
---   where a well-kept OCaml project puts its documentation, because that is
---   the file a reader of the library sees. So both halves are mapped, and
---   the `.mli`'s own `val` declarations carry the prose.
---
--- **This is the same question C, Ada and Delphi ask**, and OCaml is the one
--- that answers it cleanly. C's headers-versus-sources split had to be
--- decided *per file* with a rule this tool invented; OCaml's is decided by
--- the language, and the compiler will not let the two disagree.
---
--- **ocamldoc is a tag format** — `(** … @param x … @return … *)` — so
--- `param_docs` is true, unlike the four `param_docs = false` languages of
--- this wave. It is also positional in an unusual way: a doc comment *after*
--- a declaration documents it too, which is how record fields and variant
--- constructors are annotated. That form is not read here, because the IR
--- has no field for a record's members.

local M = {}

M.name = "ocaml"

---The implementation grammar. The interface grammar (`ocaml_interface`) is a
---separate parser for `.mli`, and this backend uses it when reading one —
---see `parse_for`.
M.grammar = "ocaml"

---@type string[]
M.extensions = { "ml", "mli" }

---A module's name is its file stem, capitalised, by the compiler's own rule.
---Nothing tag-shaped can be missing.
M.module_tag = false

---OCaml's only comment is `(* … *)`, and it nests. There is no line comment
---at all — which makes this the first backend of the twenty-three with an
---empty `line_comments`, and means `core/markers.lua` finds its markers
---through the block form alone.
---@type string[]
M.line_comments = {}

---@type { [1]: string, [2]: string }[]
M.block_comments = { { "(*", "*)" } }

---ocamldoc has `@param x`, a real tag naming each parameter.
M.param_docs = true

---@param filename string
---@return boolean
function M.is_source(filename)
  return filename:match("%.ml$") ~= nil or filename:match("%.mli$") ~= nil
end

---Where this backend's sources live under `root`, or `nil`.
---
---`lib/` is what Dune scaffolds for a library and `bin/` for an executable;
---`src/` is the older convention and still common.
---@param root string
---@return string?
function M.detect_source(root)
  local uv = vim.uv or vim.loop

  ---@param dir string
  ---@param depth integer
  ---@return boolean
  local function holds_ml(dir, depth)
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
      if kind == "directory" and name:sub(1, 1) ~= "." and name ~= "_build" then
        subdirs[#subdirs + 1] = dir .. "/" .. name
      end
    end
    if depth > 0 then
      for _, sub in ipairs(subdirs) do
        if holds_ml(sub, depth - 1) then
          return true
        end
      end
    end
    return false
  end

  for _, candidate in ipairs({ "lib", "src", "bin" }) do
    if holds_ml(root .. "/" .. candidate, 1) then
      return candidate
    end
  end
  if holds_ml(root, 1) then
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

---Which grammar a path needs.
---
---**`.ml` and `.mli` are different languages to the parser**, and
---`tree-sitter-ocaml` ships two grammars for exactly that reason: an
---interface holds `val` declarations with no bodies, which the
---implementation grammar cannot parse. This is the only backend of the
---twenty-three that selects between two grammars by extension.
---@param path string
---@return string
local function grammar_for(path)
  return path:match("%.mli$") and "ocaml_interface" or "ocaml"
end

---@param src string
---@param lang string
---@return userdata?
local function parse(src, lang)
  local ok, parser = pcall(vim.treesitter.get_string_parser, src, lang)
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

---Every `(** … *)` doc comment, keyed by the row it ends on.
---
---`(*` is a plain comment and `(**` is documentation — ocamldoc's own rule,
---and one worth honouring strictly because OCaml projects follow it: a
---license banner is `(*` and never `(**`.
---@param root userdata
---@param src string
---@return table<integer, string>
local function doc_blocks(root, src)
  local above, below = {}, {}
  local function walk(node)
    if node:type() == "comment" then
      local text = text_of(node, src)
      if text:match("^%(%*%*") and not text:match("^%(%*%*%)") then
        above[node:end_()] = text
        below[node:start()] = text
      end
      return
    end
    for child in node:iter_children() do
      walk(child)
    end
  end
  walk(root)
  return above, below
end

---An ocamldoc block, parsed.
---@param text string?
---@return { summary: string, body: string, params: Documentation.ParamInfo[], returns: Documentation.ReturnInfo[] }
local function parse_doc(text)
  local empty = { summary = "", body = "", params = {}, returns = {} }
  if not text then
    return empty
  end

  local body = text:gsub("^%(%*%*", ""):gsub("%*%)$", "")
  local params, returns, prose = {}, {}, {}
  local current = nil

  for line in (body .. "\n"):gmatch("([^\n]*)\n") do
    local stripped = line:gsub("^%s+", ""):gsub("[\r%s]+$", "")
    local tag, rest = stripped:match("^@(%a[%w_%-]*)%s*(.*)$")
    if tag then
      tag = tag:lower()
      if tag == "param" then
        local name, desc = rest:match("^([%w_']+)%s*(.*)$")
        if name then
          current = { name = name, type = "", desc = desc or "" }
          params[#params + 1] = current
        else
          current = nil
        end
      elseif tag == "return" or tag == "returns" then
        current = { type = "", desc = rest }
        returns[#returns + 1] = current
      else
        -- `@raise`, `@see`, `@since`, `@author`, `@deprecated`: recognised so
        -- their text stays out of the prose, not modelled.
        current = nil
      end
    elseif current and stripped ~= "" then
      current.desc = (current.desc == "" and "" or current.desc .. " ") .. stripped
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
  }
end

---The module name a path implies: the file stem, capitalised.
---@param path string
---@return string?
local function module_of(path)
  local stem = path:match("([^/\\]+)%.mli?$")
  if not stem then
    return nil
  end
  return stem:sub(1, 1):upper() .. stem:sub(2)
end

---The names a sibling `.mli` publishes, or `nil` when there is none.
---
---**`nil` and an empty set are different answers**, for the third time in
---this tool: no interface means the module exposes everything, an empty
---interface means it exposes nothing. Returning a table for the first would
---report a whole module as private — the reading that has now had to be got
---right for Haskell's missing export list, Python's missing `__all__` and
---this.
---@param path string Path of the `.ml` being scanned.
---@return table<string, boolean>?
local function interface_names(path)
  if path:match("%.mli$") then
    return nil
  end
  local mli = path:gsub("%.ml$", ".mli")
  local src = read(mli)
  if not src then
    return nil
  end
  local root = parse(src, "ocaml_interface")
  if not root then
    return nil
  end
  local out = {}
  local function walk(node)
    local kind = node:type()
    if kind == "value_specification" then
      local name = child_of(node, "value_name")
      if name then
        out[text_of(name, src)] = true
      end
      return
    end
    if kind == "type_definition" then
      for binding in node:iter_children() do
        if binding:type() == "type_binding" then
          local name = child_of(binding, "type_constructor")
          if name then
            out[text_of(name, src)] = true
          end
        end
      end
      return
    end
    for child in node:iter_children() do
      walk(child)
    end
  end
  walk(root)
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
  local root = parse(src, grammar_for(path))
  if not root then
    return empty
  end

  local module = module_of(path)

  -- **The first `(**` block in the file is the module's own**, which is
  -- ocamldoc's rule rather than a stand-in for a first declaration: a
  -- floating doc comment before anything else documents the module. That
  -- makes OCaml one of the few here with a real file-level doc comment,
  -- beside Haskell, Zig, Rust and Go.
  local blocks = doc_blocks(root, src)
  local first_row, first_text = nil, nil
  for row, text in pairs(blocks) do
    if not first_row or row < first_row then
      first_row, first_text = row, text
    end
  end

  -- Only when it floats: a block sitting directly above a declaration
  -- documents *that*, and claiming it twice would put one paragraph in two
  -- places. The same rule assembly needed, decided by position there and
  -- here alike.
  local attached = false
  local function check(node)
    for child in node:iter_children() do
      local kind = child:type()
      if kind ~= "comment" and first_row and child:start() == first_row + 1 then
        attached = true
        return true
      end
      if kind ~= "comment" and child:start() > (first_row or 0) then
        return true
      end
    end
    return false
  end
  check(root)

  local doc = parse_doc(not attached and first_text or nil)
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

  local root = parse(src, grammar_for(path))
  if not root then
    return {}, {}, {}, {}, {}, {}, lines, {}
  end

  local blocks, trailing = doc_blocks(root, src)
  local published = interface_names(path)
  local fns, requires, symbols = {}, {}, {}

  ---Whether a name is outside the module's published surface.
  ---
  ---`published == nil` means there is no `.mli`, which publishes everything.
  ---A `.mli` is itself the published surface, so nothing in one is internal.
  ---@param name string
  ---@return boolean
  local function is_internal(name)
    if published == nil then
      return false
    end
    return not published[name]
  end

  ---The doc block for a declaration: above it, or failing that directly
  ---below it.
  ---
  ---**The trailing form is not a corner case, it is how OCaml interfaces are
  ---written** — and finding that out cost a measurement rather than a
  ---reading. This backend's first version said a doc comment after a
  ---declaration was a rare shape used for record fields and skipped it.
  ---Scanned against `mirage/alcotest`, that found **0 documented `val`s in
  ---50**, because every one of them is written as
  ---
  ---    val to_unescaped_string : t -> string
  ---    (** Get the raw, unescaped string initially passed to [v]. *)
  ---
  ---which is ocamldoc's own convention for interfaces: the signature first,
  ---so the file reads as a list of what the module offers, and the prose
  ---under each one. Reporting a thoroughly documented interface as
  ---undocumented is the mistake the Doxygen-only rule made about C, in a
  ---language where the *position* rather than the punctuation was what got
  ---read wrong.
  ---
  ---Above wins when both exist, and the trailing block must start on the row
  ---immediately after the declaration ends — so a block separated by a blank
  ---line belongs to whatever follows it, not to what came before.
  ---@param node userdata
  ---@return string
  local function doc_above(node)
    return blocks[node:start() - 1] or trailing[node:end_() + 1] or ""
  end

  local function walk(node)
    for child in node:iter_children() do
      local kind = child:type()

      if kind == "open_module" or kind == "include_module" then
        local mpath = child_of(child, "module_path")
        if mpath then
          -- Recorded as written. An OCaml module path names a compilation
          -- unit resolved by Dune against the library's dependencies, so it
          -- matches a node in this tree exactly when the tree defines that
          -- module — which `by_module` answers without a guess here.
          requires[#requires + 1] = {
            module = (text_of(mpath, src):gsub("%s+", "")),
            line = child:start() + 1,
          }
        end
      elseif kind == "value_definition" then
        local doc = parse_doc(doc_above(child))
        for binding in child:iter_children() do
          if binding:type() == "let_binding" then
            local name_node = child_of(binding, "value_name")
            if name_node then
              local name = text_of(name_node, src)
              -- **A `let` with parameters is a function; one without is a
              -- value.** OCaml does not distinguish them syntactically —
              -- `let add x y = …` and `let max_count = 10` are the same
              -- construct — so the presence of parameters is what decides,
              -- exactly as it does in Haskell.
              local params = {}
              for part in binding:iter_children() do
                local pk = part:type()
                if pk == "parameter" then
                  params[#params + 1] = (text_of(part, src):gsub("%s+", " "))
                end
              end
              if #params > 0 then
                fns[#fns + 1] = {
                  name = name,
                  signature = name .. "(" .. table.concat(params, ", ") .. ")",
                  line = child:start() + 1,
                  line_end = child:end_() + 1,
                  summary = doc.summary,
                  body = doc.body,
                  params = doc.params,
                  returns = doc.returns,
                  internal = is_internal(name),
                  see = {},
                  overload = {},
                  todo = {},
                  bug = {},
                  test = {},
                }
              else
                symbols[#symbols + 1] = {
                  name = name,
                  kind = "constant",
                  detail = (text_of(binding, src):gsub("%s+", " ")):sub(1, 60),
                  summary = doc.summary,
                  line = child:start() + 1,
                }
              end
            end
          end
        end
      elseif kind == "value_specification" then
        -- A `.mli`'s own declarations: `val add : int -> int -> int`. This is
        -- the published surface stated outright, and it is where a
        -- well-kept OCaml project puts its documentation.
        local name_node = child_of(child, "value_name")
        if name_node then
          local doc = parse_doc(doc_above(child))
          local name = text_of(name_node, src)
          fns[#fns + 1] = {
            name = name,
            signature = name,
            line = child:start() + 1,
            line_end = child:end_() + 1,
            summary = doc.summary,
            body = doc.body,
            params = doc.params,
            returns = doc.returns,
            internal = false,
            see = {},
            overload = {},
            todo = {},
            bug = {},
            test = {},
          }
        end
      elseif kind == "type_definition" then
        local doc = parse_doc(doc_above(child))
        for binding in child:iter_children() do
          if binding:type() == "type_binding" then
            local name_node = child_of(binding, "type_constructor")
            if name_node then
              symbols[#symbols + 1] = {
                name = text_of(name_node, src),
                kind = "table",
                detail = "type",
                summary = doc.summary,
                line = child:start() + 1,
              }
            end
          end
        end
      elseif kind == "module_definition" then
        local doc = parse_doc(doc_above(child))
        for binding in child:iter_children() do
          if binding:type() == "module_binding" then
            local name_node = child_of(binding, "module_name")
            if name_node then
              symbols[#symbols + 1] = {
                name = text_of(name_node, src),
                kind = "table",
                detail = "module",
                summary = doc.summary,
                line = child:start() + 1,
              }
            end
            walk(binding)
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
