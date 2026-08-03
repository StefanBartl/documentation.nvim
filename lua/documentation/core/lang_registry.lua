---@module 'documentation.core.lang_registry'
--- One entry per supported source language, selected by file extension.
---
--- `scan.lua`'s walk used to hardcode `"%.lua$"`, `"init.lua"`,
--- `M.parse_header` and `require("documentation.core.functions").scan_file`
--- directly — every one of those is a fact about Lua, not about "how a docmap
--- walk works." This registry is the seam: the walk asks it "who scans this
--- filename" and "what marks a directory as a module here" instead of
--- assuming there is only ever one answer.
---
--- **Deliberately named `lang_registry`, not `lang.init`.** A module living
--- inside `documentation.core.lang.*` would trip the very layer rule this
--- registry exists to make enforceable — `documentation.core` must not
--- reach into `documentation.core.lang.*` directly, only through here — and
--- a registry that legitimately knows about every backend is not the
--- violation that rule exists to catch. It sits beside the boundary rather
--- than behind it, the same reason `init.lua` sits outside the
--- `core`/`editor` layer rule: the one thing allowed to cross a boundary
--- lives structurally outside it, not behind an exception written into the
--- rule.
---
--- See `docs/ROADMAP/MULTILANG.md` for the task list this seam is Phase 0
--- of, and `core/lang/lua.lua` for the reference registration — a thin
--- wrapper, not a rewrite: `scan.lua`'s `parse_header` and `functions.lua`'s
--- `scan_file` are unchanged, only which caller reaches them moved.

local M = {}

---Module names to require the first time any backend is needed, purely for
---their self-registration side effect (see `core/lang/lua.lua`'s bottom
---line). **This list — not `scan.lua`, not anything else in `core` — is the
---one place allowed to name a specific backend module.** `scan.lua` used to
---require `core/lang/lua.lua` directly to trigger this, and the very layer
---rule this registry exists to make enforceable caught it: `documentation.
---core.scan` reaching into `documentation.core.lang.lua` is exactly the
---coupling the rule forbids, regardless of the reason. Moving the require
---in here, instead of suppressing the finding, is the fix — a second
---language backend is one more line in this list, still with nothing
---outside this file naming it.
---@type string[]
local KNOWN_BACKENDS = {
  "documentation.core.lang.lua",
  "documentation.core.lang.js",
  "documentation.core.lang.ts",
  "documentation.core.lang.tsx",
}

local loaded = false

---Require every entry in `KNOWN_BACKENDS`, once. Deferred to first use
---rather than done at this module's own load time: `core/lang/lua.lua`
---itself requires `documentation.core.lang_registry` (to self-register),
---so requiring it back from here unconditionally at load time would be the
---same circular-require shape `core/lang/lua.lua`'s own header already
---works around — deferring until a lookup is actually needed avoids it
---exactly the same way.
local function ensure_loaded()
  if loaded then
    return
  end
  loaded = true
  for _, modname in ipairs(KNOWN_BACKENDS) do
    require(modname)
  end
end

---@type table<string, Documentation.LangBackend>
local backends = {}

---Registration order, so `M.for_file` is deterministic when (hypothetically)
---two backends both claimed a filename — first registered wins, rather than
---an arbitrary `pairs()` order that could pick a different one on every run
---and make `--check` non-deterministic.
---@type string[]
local order = {}

---@param name string Short identifier, e.g. "lua". Registering the same name
---twice replaces the entry without duplicating it in `order`.
---@param backend Documentation.LangBackend
function M.register(name, backend)
  if not backends[name] then
    order[#order + 1] = name
  end
  backends[name] = backend
end

---The backend that claims `filename` (bare, no path), or `nil` if none do.
---@param filename string
---@return Documentation.LangBackend?
function M.for_file(filename)
  ensure_loaded()
  for _, name in ipairs(order) do
    if backends[name].is_source(filename) then
      return backends[name]
    end
  end
  return nil
end

---@param name string
---@return Documentation.LangBackend?
function M.get(name)
  ensure_loaded()
  return backends[name]
end

---Every registered backend, in registration order. What the walk uses to
---answer "does any backend's `module_file` exist in this directory" without
---hardcoding which backends exist.
---@return Documentation.LangBackend[]
function M.all()
  ensure_loaded()
  local out = {}
  for _, name in ipairs(order) do
    out[#out + 1] = backends[name]
  end
  return out
end

---Drop every registration, then immediately re-register every known
---backend. Test-support: a spec registering a fixture backend must not leak
---it into a later spec's lookups, the same reason `browse/trail.lua`'s
---`M.reset()` exists.
---
---**Re-registers explicitly rather than relying on `ensure_loaded`'s lazy
---reload — verified, not assumed, that the lazy path does not work here.**
---A first draft of this function only cleared `loaded` and left
---`ensure_loaded` to redo the rest on the next lookup; `for_file` returned a
---real backend before that `reset()` and `nil` after it, forever, for the
---rest of the process. The cause: `require(modname)` on a module already in
---Lua's own module cache returns the cached table without re-running the
---file, so the `register(...)` call at a backend's own bottom — the thing
---that repopulates `backends`/`order` — never fires a second time. This
---version reads `.name` off each already-cached backend table instead and
---calls `M.register` directly, which needs no re-execution to work.
function M.reset()
  backends, order = {}, {}
  for _, modname in ipairs(KNOWN_BACKENDS) do
    local backend = require(modname)
    M.register(backend.name, backend)
  end
  loaded = true
end

return M
