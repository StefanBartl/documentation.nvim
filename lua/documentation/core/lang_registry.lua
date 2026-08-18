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
--- See `docs/ROADMAP/IDEAS/MULTILANG.md` for the task list this seam is Phase 0
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

---What this build can read, and at what fidelity — the answer a host asks
---for before trusting this binary with anything.
---
---**Why `grammar_loaded` is a probe rather than a stored flag.** A grammar
---is resolved from `$DOCMAP_TS_DIR`/`$DOCMAP_TS_<LANG>` at the moment it is
---first needed (see `standalone/treesitter.lua`), and in Neovim from the
---runtimepath — neither is knowable at registration time, and both can be
---true on one machine and false on the next with the identical binary. So
---this asks, per call, through the same `vim.treesitter.language.add`
---the scan itself would end up going through.
---
---`false` and `nil` are different answers and stay different: `false` means
---"this backend wants a grammar and could not get one" — degraded fidelity,
---a complete module tree with no function-level data — while `nil` means
---"this backend needs no parser", which is not a degradation at all. A host
---that collapsed them would report a healthy backend as broken.
---
---Deliberately not cached. It is called once per host handshake, and a
---cached "missing" would survive the user pointing at the grammars
---directory, which is precisely the moment the answer is supposed to
---change.
---@return { name: string, grammar: string?, grammar_loaded: boolean? }[]
function M.report()
  ensure_loaded()
  local out = {}
  for _, name in ipairs(order) do
    local backend = backends[name]
    -- Named for what it holds rather than the shorter `loaded`, which is
    -- this module's own file-level "are the backends required yet" flag --
    -- two unrelated meanings one letter apart in one file.
    local has_grammar = nil
    if backend.grammar then
      -- `vim.treesitter.language.add` is the one probe both hosts answer:
      -- Neovim's own, and `standalone/treesitter.lua`'s shim, which
      -- implements it as a `pcall` around its loader for exactly this kind
      -- of question. `pcall`ed anyway — under `vim_shim.lua`'s inert stub
      -- there is no `language` table at all, and a build without the
      -- tree-sitter rock must report "no grammar", not raise.
      local ok, added = pcall(function()
        return vim.treesitter.language.add(backend.grammar)
      end)
      -- Neovim returns `true`/`nil+err`; the shim returns a plain boolean.
      -- `== true` normalises both without treating a truthy non-boolean as
      -- a yes.
      has_grammar = ok and added == true
    end
    out[#out + 1] = { name = name, grammar = backend.grammar, grammar_loaded = has_grammar }
  end
  return out
end

---Every backend's keyword glossary, keyed by file extension.
---
---Keyed by extension rather than by backend name because of what the
---consumer has in hand: the renderer is looking at a snippet belonging to a
---node whose `source` is a path, and the IR does not yet carry a `language`
---field (see `docs/ROADMAP/IDEAS/MULTILANG.md` Part 4, stage 3.1). An
---extension is what the page can actually key on today, and when that field
---arrives this can gain a second index without the page changing shape.
---
---Backends sharing one glossary table share one entry value -- `js`, `ts`
---and `tsx` all point at the same table, not three copies -- which the
---renderer relies on to emit it once and reference it three times rather
---than tripling that part of the payload.
---
---A backend with no `extensions` or no `glossary` contributes nothing. That
---is the honest degradation: no decoration at all, rather than another
---language's keywords explaining a word that means something else here.
---@return table<string, Documentation.Glossary>
function M.glossaries()
  ensure_loaded()
  local out = {}
  for _, name in ipairs(order) do
    local backend = backends[name]
    if backend.glossary and backend.extensions then
      for _, ext in ipairs(backend.extensions) do
        out[ext] = backend.glossary
      end
    end
  end
  return out
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
