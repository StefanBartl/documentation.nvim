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
  "documentation.core.lang.zig",
  "documentation.core.lang.java",
  "documentation.core.lang.c",
  "documentation.core.lang.cpp",
  "documentation.core.lang.asm",
  "documentation.core.lang.python",
  "documentation.core.lang.csharp",
  "documentation.core.lang.go",
  "documentation.core.lang.rust",
  "documentation.core.lang.php",
  "documentation.core.lang.ruby",
  "documentation.core.lang.kotlin",
  "documentation.core.lang.swift",
  "documentation.core.lang.dart",
  "documentation.core.lang.scala",
  "documentation.core.lang.haskell",
  "documentation.core.lang.elixir",
  "documentation.core.lang.erlang",
  "documentation.core.lang.ocaml",
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

---Which backends this scan is allowed to use, or `nil` for all of them.
---
---**A filter rather than an unregistration**, and the difference matters:
---`M.report()` deliberately ignores it. That call is the capability
---handshake — *what can this build read* — and the answer must not change
---because one project asked for a subset. A host that saw a backend vanish
---from the handshake would conclude the binary cannot read that language.
---
---**Scan-scoped, with the same reset discipline as
---`core/snippet.lua`'s `MAX_LINES` and `core/bindings.lua`'s `WRAPPERS`**,
---for the same reason and against the same failure: `:DocBrowse` bouncing
---between two repositories in one Neovim session would otherwise carry the
---first one's language filter into the second, silently producing a map
---missing every file of a language nobody excluded. `M.scan` sets this from
---`opts.languages` before the walk and back to `nil` when there is none.
---
---Threading it through instead was considered and declined: `for_file` is
---called from the walk, from `check.lua` and from `config.detect_source`,
---and a parameter would have to reach all three plus every future caller
---to be correct — where a scan-scoped field is correct by default and
---wrong only if somebody forgets the reset, which is one place to look.
---@type table<string, true>?
M.ENABLED = nil

---@param name string
---@return boolean
local function enabled(name)
  return M.ENABLED == nil or M.ENABLED[name] == true
end

---Set the scan-scoped filter from a list of backend names.
---
---`nil` or an empty list both mean **all backends**, which is the reading
---that cannot lose somebody's data: an empty selection almost always means
---"the caller has nothing to say", and taking it as "read nothing" would
---produce an empty map that looks like a broken repository. A caller that
---genuinely wants one language names it.
---
---Unknown names are kept rather than rejected. `M.unknown` reports them so
---a caller can say so; dropping them here would make `{"golang"}` behave
---like `{}` and read everything, which is the opposite of what was asked.
---@param names string[]?
function M.set_enabled(names)
  if not names or #names == 0 then
    M.ENABLED = nil
    return
  end
  local set = {}
  for _, name in ipairs(names) do
    set[name] = true
  end
  M.ENABLED = set
end

---Names in `names` that no backend answers to.
---
---Separate from `set_enabled` so the caller decides what to do about them.
---A typo in a per-project setting is worth a sentence, not a silent scan
---that finds nothing and blames the repository.
---@param names string[]?
---@return string[] unknown Sorted.
function M.unknown(names)
  ensure_loaded()
  local out = {}
  for _, name in ipairs(names or {}) do
    if not backends[name] then
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end

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
    if enabled(name) and backends[name].is_source(filename) then
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
---`calls` is what makes an empty panel explainable: nineteen of the
---twenty-three backends produce no call sites, so the Calls views render
---empty for a Go or Rust project and look exactly like a project with no
---calls in it. A host that can read this field can say which it is. See
---`Documentation.LangBackend.emits_calls`.
---@return { name: string, grammar: string?, grammar_loaded: boolean?, calls: boolean }[]
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
    out[#out + 1] = {
      name = name,
      grammar = backend.grammar,
      grammar_loaded = has_grammar,
      -- Normalised to a real boolean rather than passed through as
      -- `true`/`nil`: this crosses a JSON boundary to a host, and `nil`
      -- would simply be an absent key there — which reads as "this engine
      -- is too old to say", a third state that does not exist here. The
      -- grammar answer above is genuinely three-valued and stays that way;
      -- this one is not.
      calls = backend.emits_calls == true,
    }
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
    -- Filtered too: a glossary for a language this scan did not read is
    -- payload nobody can reach, in an artifact already measured in hundreds
    -- of kilobytes.
    if enabled(name) and backend.glossary and backend.extensions then
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
---
---Respects `M.ENABLED`, and it has to: this is what decides whether a
---directory holding `index.ts` is a *module* or a bare namespace. A filter
---that reached `for_file` and not here would drop a language's files while
---still letting its `module_file` shape the tree around them — a map of
---modules with nothing in them, which is worse than either answer.
---@param unfiltered boolean? Ignore `M.ENABLED`. For callers asking what
---this *build* has rather than what this *scan* is using — `M.reset`'s own
---re-registration, and specs over the contract every backend must keep.
---@return Documentation.LangBackend[]
function M.all(unfiltered)
  ensure_loaded()
  local out = {}
  for _, name in ipairs(order) do
    if unfiltered or enabled(name) then
      out[#out + 1] = backends[name]
    end
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
