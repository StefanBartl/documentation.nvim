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
