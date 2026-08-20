---@module 'documentation.core.lang.lua'
--- Lua, registered as a language backend.
---
--- Thin on purpose, and that is the whole design: every real implementation
--- already exists — `scan.lua`'s `parse_header`, `functions.lua`'s
--- `scan_file` — and predates this interface by the entire history of this
--- plugin. This module is the seam between them and
--- `core/lang_registry.lua`, not a second copy of either. A future
--- language's own `core/lang/<name>.lua` is where the real work lives,
--- because there is no pre-existing implementation for it to delegate to.
---
--- Both delegated calls are deferred (`require(...)` inside the function
--- body, not at the top of this file) for the same reason `functions.lua`
--- and `symbols.lua` already defer their own `require("documentation.core.
--- scan")` for `split_summary`: `core/lang_registry.lua`'s `KNOWN_BACKENDS`
--- requires this module (to trigger the registration below) before either
--- delegated call is ever reached, so a top-level require here would be
--- circular. Deferring until the function actually runs — well after every
--- module has finished loading — is the established fix, not a new one.

local M = {}

---The name this backend registers itself under. A field on the module, not
---just the string literal passed to `register` below, because
---`lang_registry.reset()` needs to re-register every known backend by name
---after clearing its tables — `require()` returns this same cached table on
---a second call rather than re-running the file (and the `register` call
---at the bottom with it), so the registry recovers by reading `M.name` off
---the table it already has, not by re-requiring anything.
M.name = "lua"

---A Lua module's canonical dotted name cannot be recovered from its file
---path alone in general — that is the entire reason
---`check.expected_module`/`module-path-mismatch` exist. Explicit `true`
---rather than leaving the field unset, so a reader of this file does not
---have to know the default to see the decision.
M.module_tag = true

---This backend returns call sites, which nineteen of the twenty-three do
---not. Declared so a host can tell "this project has no calls" from "this
---build has no call extraction here" — two facts that look identical on an
---empty panel. See `Documentation.LangBackend.emits_calls`.
M.emits_calls = true

---@param filename string
---@return boolean
function M.is_source(filename)
  return filename:match("%.lua$") ~= nil
end

---The grammar `functions.lua` parses with. The one backend whose grammar
---name happens to equal its own, which is exactly why it must be stated
---rather than derived: deriving it from `M.name` would work here and be
---wrong for all three ECMA backends.
M.grammar = "lua"

M.module_file = "init.lua"

---Enumerable, unlike `is_source` — see the field's own documentation for
---why both exist rather than one deriving the other.
M.extensions = { "lua" }

---What opens a comment here, for `core/markers.lua`.
---
---Stated rather than assumed: a keyword is only a marker if it sits
---inside a comment, and every language draws that line differently.
---`--[[` is listed as a block opener even though `--` already matches it
---as a line opener — the earliest-opener rule in `markers.lua` picks the
---same byte either way, but a multi-line `--[[ ... ]]` region is only
---read to its end if the pair is known.
M.line_comments = { "--" }

---@type { [1]: string, [2]: string }[]
M.block_comments = { { "--[[", "]]" } }

---Keyword explanations for the page's in-place lookup. Required rather than
---inlined for the reason `glossary/lua.lua`'s header gives: it is several
---times this file's size and has nothing to do with scanning.
---
---Deferred like everything else here — `lang_registry`'s `KNOWN_BACKENDS`
---requires this module during registration, and the glossary is only ever
---read by the renderer, long after load.
M.glossary = require("documentation.core.lang.glossary.lua")

---Directory names under `lua/` that are never a plugin's own source root.
---@type table<string, true>
local NOT_SOURCE = { ["@types"] = true, spec = true, tests = true }

---`lua/<single subdirectory>` when `lua/` holds exactly one candidate,
---otherwise plain `lua` — and **`nil` when there is no `lua/` at all**.
---
---Moved here from `config/init.lua`, where it was the *only* answer any tree
---could get. That was fine while Lua was the only backend and became a hard
---failure the moment it was not: a JavaScript repository has no `lua/`, so
---the guess came back `"lua"` anyway and `scan.lua` asserted on a directory
---that does not exist. Measured, not theorised — a three-file JS/TS tree
---died on `source directory not found`.
---
---Neovim plugins almost always have the `lua/<plugin>` shape, and scanning
---`lua` itself instead would put a meaningless extra root node above every
---real module. Several candidates, or none, and `lua` is the honest answer
---rather than picking one arbitrarily.
---@param root string
---@return string?
function M.detect_source(root)
  local lua_dir = root .. "/lua"
  if vim.fn.isdirectory(lua_dir) == 0 then
    return nil
  end

  local found
  for name, kind in vim.fs.dir(lua_dir) do
    if kind == "directory" and not NOT_SOURCE[name] then
      if found then
        return "lua"
      end
      found = name
    end
  end

  return found and ("lua/" .. found) or "lua"
end

---@param path string
---@return Documentation.Header
function M.parse_header(path)
  return require("documentation.core.scan").parse_header(path)
end

---@param path string
---@return Documentation.FunctionInfo[], Documentation.RawCall[], Documentation.RawRequire[], Documentation.SymbolInfo[], table[], Documentation.EndpointSpec[], integer, Documentation.BindingSpec[]
function M.scan_file(path)
  return require("documentation.core.functions").scan_file(path)
end

require("documentation.core.lang_registry").register(M.name, M)

return M
