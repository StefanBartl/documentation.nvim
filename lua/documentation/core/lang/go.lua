---@module 'documentation.core.lang.go'
--- Go, registered as a language backend — the twelfth.
---
--- **The one language here where visibility is a fact about spelling.** An
--- identifier is exported if and only if its first letter is upper case. Not
--- a keyword, not a tag, not a convention somebody could ignore: the compiler
--- enforces it. That makes Go's visibility the *cheapest and most reliable*
--- of the eleven — cheaper than `pub`, because there is nothing to look up,
--- and more reliable than `@internal`, because nobody can be wrong about it.
---
--- **And the language with the least to check, which was predicted and is
--- worth confirming.** `docs/ROADMAP/IDEAS/MULTILANG.md` costed Go as the
--- "worst fit" of the five it analysed: godoc has *no tag vocabulary at
--- all*. There is no `@param`, no `@returns`, no `@throws` — a doc comment is
--- the plain comment block above a declaration and nothing more. So this is
--- the third backend to declare `param_docs = false`, and the first to do it
--- for a reason that is neither "no parameter list" (assembly) nor "the
--- language documents the declaration as a whole" (Zig): **Go has parameters
--- and documents them nowhere.**
---
--- Which leaves exactly one checkable claim, and godoc really does make it:
--- **a doc comment begins with the name of the thing it documents.** That is
--- the whole of the convention, it is machine-checkable, and no check in this
--- tool tests it yet. Recorded here rather than built, because a new check is
--- a decision about what fails somebody's CI.
---
--- **A package is a directory, not a file**, which is a shape only Lua's
--- `init.lua` came near and neither matches. Every `.go` file in a directory
--- declares the same `package`, so the package name is *not* a unique module
--- name — three files would claim it. The path stays the identity
--- (`module_tag = false`, `module` unset), and the package name is recorded
--- as the file's summary source instead: the comment above `package foo` is
--- Go's only file-level documentation, and by convention a package's real
--- prose lives in whichever file carries it.
---
--- **`_test.go` files are scanned like any other source.** Deliberately: Go
--- puts tests beside the code by design rather than in a separate tree, and a
--- map that dropped them would be missing a third of a typical repository —
--- including the examples, which in Go are documentation that compiles.

local M = {}

M.name = "go"

M.grammar = "go"

---@type string[]
M.extensions = { "go" }

---The import path is the identity, and it is derived from the directory
---rather than declared in the file. Nothing tag-shaped can be missing.
M.module_tag = false

---@type string[]
M.line_comments = { "//" }

---`/* */` exists and is used for package documentation in older code, so it
---is declared even though `//` is what modern Go writes.
---@type { [1]: string, [2]: string }[]
M.block_comments = { { "/*", "*/" } }

---**godoc has no per-parameter form at all** — no `@param`, no `:param:`, no
---`<param>`. A Go doc comment is prose above a declaration and that is the
---entire convention. Judging Go functions by whether they document each
---parameter would report every well-documented Go project as undocumented,
---which is the wrongness `param_docs` exists to prevent.
---
---Third language to declare this, and the first for this reason: assembly
---has no parameter list, Zig documents the declaration as a whole, and Go
---has parameters and documents them nowhere.
M.param_docs = false

---@param filename string
---@return boolean
function M.is_source(filename)
  return filename:match("%.go$") ~= nil
end

---Where this backend's sources live under `root`, or `nil`.
---
---The root first, and that is not the usual order: Go's own layout
---convention puts `main.go` and the primary package at the repository root,
---with `cmd/` and `internal/` beside it. A `src/` directory is the exception
---in Go, not the rule — it is what other ecosystems taught people to expect.
---@param root string
---@return string?
function M.detect_source(root)
  local uv = vim.uv or vim.loop

  local function holds_go(dir)
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

  -- `go.mod` at the root is the strongest signal a tree is a Go module, and
  -- it sits beside the sources rather than above them.
  if uv.fs_stat(root .. "/go.mod") and holds_go(root) then
    return "."
  end
  for _, candidate in ipairs({ "cmd", "internal", "pkg", "src" }) do
    if holds_go(root .. "/" .. candidate) then
      return candidate
    end
  end
  if holds_go(root) then
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

---Every `//` comment run in the file, keyed by the row it ends on.
---
---Every comment counts, and that is Go's own rule rather than a relaxation:
---godoc has no doc sigil — there is no `///` or `/**` to distinguish
---documentation from a note — so the comment block immediately above a
---declaration *is* its documentation, and any rule stricter than that would
---find nothing in any Go project ever written.
---
---The cost of that is the cost C's plain-comment rule has, and Go pays it
---more cheaply: a commented-out declaration would still be attached to the
---next one down, but Go's formatter and its unused-import error make
---commented-out code far rarer than in C.
---@param root userdata
---@param src string
---@return table<integer, string[]>
local function comment_runs(root, src)
  local by_row = {}
  local function walk(node)
    if node:type() == "comment" then
      local srow = node:start()
      local text = text_of(node, src)
      local body = text:match("^//%s?(.*)$")
      if not body then
        -- A `/* … */` block, which older package documentation uses. Kept
        -- whole; its interior lines are not separately addressable.
        body = text:match("^/%*+%s*(.-)%s*%*/$")
        if body then
          by_row[node:end_()] = { body }
        end
        return
      end
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

---The comment run directly above `row`, joined as prose.
---@param runs table<integer, string[]>
---@param row integer 0-based row of the documented declaration.
---@return string
local function doc_above(runs, row)
  local lines = runs[row - 1]
  if not lines then
    return ""
  end
  -- Directive comments are not prose. `//go:build`, `//go:generate` and
  -- `//nolint` sit exactly where documentation sits and mean something to a
  -- tool rather than to a reader; keeping them would make the summary of many
  -- files a build constraint.
  local kept = {}
  for _, line in ipairs(lines) do
    if not line:match("^go:") and not line:match("^nolint") and not line:match("^%+build") then
      kept[#kept + 1] = line
    end
  end
  while kept[1] == "" do
    table.remove(kept, 1)
  end
  while kept[#kept] == "" do
    table.remove(kept)
  end
  return table.concat(kept, "\n")
end

---Whether a Go identifier is unexported.
---
---**Capitalisation is the whole of Go's visibility system.** An identifier is
---exported if its first letter is upper case, and the compiler enforces it —
---so this is a fact rather than an inference, and the only one of the twelve
---backends that needs no keyword, no tag and no export list to answer.
---
---A name starting with `_` or a digit cannot be exported either; `%u` answers
---all three cases at once by asking only whether the first character *is* an
---upper-case letter.
---
---**`in_test` is the second half, and it is also a compiler fact rather than
---a convention.** A `_test.go` file is never part of the importable package:
---`go build` excludes it entirely, so nothing declared there can be reached
---from anywhere else, whatever its spelling. Without this, Go's own naming
---requirement for tests (`TestXxx`, `BenchmarkXxx`, `ExampleXxx` — all
---necessarily capitalised) makes every test function look like published API.
---
---**Measured, because the size of the distortion is the argument.** Against
---`spf13/cobra`: 184 exported functions in the sources and **289 more** in
---the tests, so the published surface looked two and a half times its real
---size. Documentation coverage was worse — 75% of the source functions are
---documented and 7% of the test ones, which averaged to 38% and would have
---described a well-documented library as a mediocre one.
---
---The tests stay in the map. Go puts them beside the code by design, and
---they are worth seeing; they simply stop claiming to be API.
---@param name string
---@param in_test boolean Whether the declaring file is a `_test.go` file.
---@return boolean
local function is_internal(name, in_test)
  if in_test then
    return true
  end
  return name:sub(1, 1):match("%u") == nil
end

---The parameter names a `parameter_list` declares.
---
---`x, y int` is one `parameter_declaration` with two identifiers, so the
---names are collected per declaration rather than one per child — a shape
---no other language here has.
---@param node userdata?
---@param src string
---@return string[]
local function param_names(node, src)
  local out = {}
  if not node then
    return out
  end
  for decl in node:iter_children() do
    local kind = decl:type()
    if kind == "parameter_declaration" or kind == "variadic_parameter_declaration" then
      local named = false
      for child in decl:iter_children() do
        if child:type() == "identifier" then
          out[#out + 1] = text_of(child, src)
          named = true
        end
      end
      if not named then
        -- `func f(int, string)` is legal Go: the types are declared and the
        -- parameters are unnamed. Recorded as the type rather than skipped,
        -- so the arity in the signature stays true.
        out[#out + 1] = (text_of(decl, src):gsub("%s+", " "))
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

  local clause = child_of(root, "package_clause")
  if not clause then
    return empty
  end

  local runs = comment_runs(root, src)
  local prose = doc_above(runs, clause:start())
  if prose == "" then
    return empty
  end

  -- **No module name, and the reason is the package/directory shape.** A Go
  -- package is a directory: every `.go` file in it declares the same
  -- `package foo`, so using that as a module name would have three files
  -- claiming one identity. The path is the identity instead, exactly as with
  -- Zig, C and assembly — reached here by a different route, and the only one
  -- of the four where the name genuinely exists and still cannot be used.
  return {
    module = nil,
    summary = require("documentation.core.scan").split_summary(prose),
    body = prose,
    tags = {},
  }
end

---This backend returns call sites — the fifth of the twenty-three to do so,
---and the first outside Lua and the ECMA family. See
---`Documentation.LangBackend.emits_calls`.
M.emits_calls = true

---**A Go package is a directory, and that is the whole reason this field
---exists.** Every `.go` file in one directory shares a single scope, so an
---unqualified `double(n)` may name a function declared in a *sibling file*
---with nothing at the call site to say so. Go declares no `module_file`, so
---those siblings are separate IR nodes — and a file-scoped resolver would
---therefore miss the majority of a Go call graph, not an edge case at its
---margin. Measured before being built: in a three-file fixture, two of the
---three call sites were exactly this shape.
M.call_scope = "package"

---Every call site, attributed to the function whose span contains it.
---
---The same query and the same two-input shape `core/calls.lua`'s own
---`M.extract` uses for Lua and `core/lang/ecma.lua` uses for JavaScript —
---verified against a real Go parse rather than assumed by analogy: a bare
---call's `function` field is an `identifier` (`double(n)`) and a qualified
---one is a `selector_expression` whose text reconstructs as `other.Bump`.
---Both are meaningful text for the language-agnostic resolver, so no Go
---branch is needed there.
---
---**`other.Bump` does not resolve yet, and that is deliberate rather than
---missed.** A Go import path is absolute against the module graph
---(`github.com/acme/other`), so placing it inside this tree would need
---`go.mod`'s module line — a build file, not a source one — or a
---suffix-match on the path, which is a guess. `parse_header`'s own comment
---already takes that position for the require edge; the call edge takes it
---for the same reason. The callee text is emitted regardless, so the day the
---module line is read, nothing here changes.
---@param root userdata
---@param src string
---@param ranges { name: string, srow: integer, erow: integer }[] 0-based rows.
---@return Documentation.RawCall[]
local function extract_calls(root, src, ranges)
  local out = {}
  local ok, query =
    pcall(vim.treesitter.query.parse, "go", "(call_expression function: (_) @callee) @call")
  if not ok then
    return out
  end
  for id, node in query:iter_captures(root, src) do
    if query.captures[id] == "callee" then
      local srow = node:range()
      local callee = vim.treesitter.get_node_text(node, src)
      -- A multi-line callee carries a newline that matches no resolver
      -- pattern — skipped here so `calls.lua` never has to special-case one,
      -- exactly as the Lua and ECMA extractors already do.
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
  local split = require("documentation.core.scan").split_summary
  local fns, requires, symbols = {}, {}, {}

  -- Read once rather than per declaration: it is a property of the file.
  local in_test = path:match("_test%.go$") ~= nil

  ---The receiver type of a method, without its pointer star.
  ---@param node userdata
  ---@return string?
  local function receiver_type(node)
    local list = child_of(node, "parameter_list")
    if not list then
      return nil
    end
    local decl = child_of(list, "parameter_declaration")
    if not decl then
      return nil
    end
    for child in decl:iter_children() do
      local kind = child:type()
      if kind == "type_identifier" then
        return text_of(child, src)
      end
      if kind == "pointer_type" then
        local inner = child_of(child, "type_identifier")
        if inner then
          return text_of(inner, src)
        end
      end
      if kind == "generic_type" then
        local inner = child_of(child, "type_identifier")
        if inner then
          return text_of(inner, src)
        end
      end
    end
    return nil
  end

  ---@param spec userdata `import_spec`
  local function record_import(spec)
    local lit = child_of(spec, "interpreted_string_literal") or child_of(spec, "raw_string_literal")
    if not lit then
      return
    end
    local target = text_of(lit, src):match('^"(.*)"$') or text_of(lit, src):match("^`(.*)`$")
    if target then
      -- Recorded as written. A Go import path is absolute against the module
      -- graph — `github.com/x/y/z` — so it names a package outside this tree
      -- unless the tree *is* that module, and resolving it would need
      -- `go.mod`'s module line, which is a build file rather than a source
      -- one. The same position C takes on `#include <stdio.h>`.
      requires[#requires + 1] = { module = target, line = spec:start() + 1 }
    end
  end

  for top in root:iter_children() do
    local kind = top:type()

    if kind == "import_declaration" then
      local list = child_of(top, "import_spec_list")
      if list then
        for spec in list:iter_children() do
          if spec:type() == "import_spec" then
            record_import(spec)
          end
        end
      else
        local spec = child_of(top, "import_spec")
        if spec then
          record_import(spec)
        end
      end
    elseif kind == "function_declaration" or kind == "method_declaration" then
      local owner = kind == "method_declaration" and receiver_type(top) or nil
      -- A method's name is a `field_identifier`; a function's is an
      -- `identifier`. The receiver's own `parameter_list` comes first, so a
      -- method's parameters are the *second* one.
      local name_node = kind == "method_declaration" and child_of(top, "field_identifier")
        or child_of(top, "identifier")
      if name_node then
        local bare = text_of(name_node, src)
        local qualified = owner and (owner .. "." .. bare) or bare
        local params_node = nil
        local seen_receiver = kind ~= "method_declaration"
        for child in top:iter_children() do
          if child:type() == "parameter_list" then
            if seen_receiver then
              params_node = child
              break
            end
            seen_receiver = true
          end
        end
        local names = param_names(params_node, src)
        local prose = doc_above(runs, top:start())
        fns[#fns + 1] = {
          name = qualified,
          signature = qualified .. "(" .. table.concat(names, ", ") .. ")",
          line = top:start() + 1,
          line_end = top:end_() + 1,
          summary = split(prose),
          body = prose,
          params = {},
          returns = {},
          -- The method's own name decides, not its receiver's: an exported
          -- type routinely carries unexported methods.
          internal = is_internal(bare, in_test),
          see = {},
          overload = {},
          todo = {},
          bug = {},
          test = {},
        }
      end
    elseif kind == "type_declaration" then
      for spec in top:iter_children() do
        if spec:type() == "type_spec" then
          local name_node = child_of(spec, "type_identifier")
          if name_node then
            local body = nil
            for child in spec:iter_children() do
              local ck = child:type()
              if ck ~= "type_identifier" and ck ~= "type_parameter_list" then
                body = ck
              end
            end
            local prose = doc_above(runs, top:start())
            local type_name = text_of(name_node, src)
            symbols[#symbols + 1] = {
              name = type_name,
              kind = "table",
              detail = (body or "type"):gsub("_type$", ""),
              summary = split(prose),
              line = top:start() + 1,
            }

            -- **An interface's methods are its whole content**, and it is
            -- the one construct in any language whose entire purpose is to
            -- declare a published surface — the lesson C# taught by getting
            -- the same thing backwards. A `method_elem` has no body and no
            -- receiver, so it is not a `method_declaration` and would be
            -- missed by the branch above; listing the interface as a bare
            -- symbol would show its name and nothing it promises.
            local iface = child_of(spec, "interface_type")
            if iface then
              for elem in iface:iter_children() do
                if elem:type() == "method_elem" then
                  local mname = child_of(elem, "field_identifier")
                  if mname then
                    local bare = text_of(mname, src)
                    local mprose = doc_above(runs, elem:start())
                    fns[#fns + 1] = {
                      name = type_name .. "." .. bare,
                      signature = type_name
                        .. "."
                        .. bare
                        .. "("
                        .. table.concat(param_names(child_of(elem, "parameter_list"), src), ", ")
                        .. ")",
                      line = elem:start() + 1,
                      line_end = elem:end_() + 1,
                      summary = split(mprose),
                      body = mprose,
                      params = {},
                      returns = {},
                      internal = is_internal(bare, in_test),
                      see = {},
                      overload = {},
                      todo = {},
                      bug = {},
                      test = {},
                    }
                  end
                end
              end
            end
          end
        end
      end
    elseif kind == "const_declaration" or kind == "var_declaration" then
      for spec in top:iter_children() do
        local sk = spec:type()
        if sk == "const_spec" or sk == "var_spec" then
          local prose = doc_above(runs, top:start())
          for child in spec:iter_children() do
            if child:type() == "identifier" then
              symbols[#symbols + 1] = {
                name = text_of(child, src),
                kind = sk == "const_spec" and "constant" or "binding",
                detail = (text_of(spec, src):gsub("%s+", " ")):sub(1, 60),
                summary = split(prose),
                line = spec:start() + 1,
              }
            end
          end
        end
      end
    end
  end

  -- Ranges from the functions just produced rather than a second walk: they
  -- already carry the span, 1-based, and `extract_calls` wants 0-based —
  -- which is one subtraction, against re-deriving what is in hand.
  local ranges = {}
  for _, fn in ipairs(fns) do
    if fn.line and fn.line_end then
      ranges[#ranges + 1] = { name = fn.name, srow = fn.line - 1, erow = fn.line_end - 1 }
    end
  end

  return fns, extract_calls(root, src, ranges), requires, symbols, {}, {}, lines, {}
end

require("documentation.core.lang_registry").register(M.name, M)

return M
