# Framework conventions — the layer above language support

What `core/plugins.lua` actually is, generalized: not "Lua support," which
already existed, but a **recognizer for one ecosystem's structural
convention within an already-supported language** — lazy.nvim's shape of
`return { { "author/repo", event = "…" }, … }`. Nothing about it needed a
new parser; it needed a second pass over the same parse tree, looking for a
pattern specific to *how one tool in the Lua ecosystem is used*, not to Lua
itself.

That pattern generalizes, and the web ecosystem — Next.js, React, and
siblings — is the obvious next place it applies, exactly as asked. This
documents what is actually there, what of it is worth building, and answers
the UI question (filter-tab vs. label-tab) with a third option grounded in
what this codebase already has.

**Dependency, stated up front:** none of this is buildable today. It needs a
JS/TS scanner backend, which [`MULTILANG.md`](ROADMAP/MULTILANG.md) costs out and
does not schedule. This document is layer 2, sequenced strictly after that
layer 1 — a roadmap note for *if*, not a proposal to start now.

> **Update (2026-08-03): that dependency is satisfied.** `core/lang/ecma.lua`
> ships functions, imports, calls and symbols for JS/TS/TSX, so layer 2 is no
> longer blocked. [`ECOSYSTEM.md`](ECOSYSTEM.md) takes the routing question
> further — in particular it refines this document's "routes belong in
> Hierarchy" conclusion, which holds for *file-based* routing but not for
> *call-based* routing (`app.get("/x", h)`), where there is no ancestry to
> preserve and an Analysis panel is the honest shape.

**Epistemic note, unlike the rest of this repository's convention:** every
other design doc here states a claim about syntax only after verifying it
against a real parse (`tree-sitter query` against real files, for the plugin
extraction; a real `lua-language-server 3.18.2` run, for the LuaCATS
`extends` field). Nothing below has that treatment — there is no JS/TS
backend in this repo to verify against. What follows is stated from stable,
long-published framework documentation, not from a parse. Flagged rather
than presented with the same confidence as the rest of this repo's design
docs, on purpose.

---

## The two-layer architecture, restated

1. **Language backend** — parses the syntax, produces functions/symbols/
   imports. `MULTILANG.md`'s entire subject. Nothing ecosystem-specific.
2. **Convention recognizer** — a second pass over the same parse tree,
   looking for one ecosystem's structural idiom. `core/plugins.lua` is the
   first one of these that exists, for Lua + lazy.nvim. Layer 2 cannot exist
   without layer 1, but is otherwise independent of it: recognizing Next.js
   routes needs a JS/TS backend to exist, not to be *complete* — the same
   way `plugins.lua` needs `functions.lua`'s treesitter setup, not
   `luals.lua`'s optional LuaLS enrichment.

Every recognizer below is layer 2. None of them are a reason to build layer
1; `MULTILANG.md` already made that case (JS/TS first, on doc-convention
fit) independent of any of this.

---

## What is actually there, for the web ecosystem

### File-based routing — the strongest candidate, and not Next.js-specific

Next.js's **App Router** (`app/`) is almost pure filesystem convention, the
same shape this plugin already assumes for Lua (`init.lua` marks a
directory as a module — App Router just has more reserved filenames):

| File | Meaning |
|---|---|
| `page.tsx` | The route's own UI — a directory without one is not a route. |
| `layout.tsx` | Wraps this segment and everything under it. **Nests**: the effective UI for any route is the product of every ancestor's layout, in order. |
| `loading.tsx` / `error.tsx` / `not-found.tsx` | Automatic boundaries — React Suspense/error-boundary wiring the framework installs without the developer writing JSX for it. |
| `route.ts` | An API endpoint, not a page — exports named `GET`/`POST`/etc., a genuinely different shape from a page component. |
| `template.tsx` | Like `layout.tsx` but remounts on navigation — easy to confuse with `layout.tsx`, a real "did they mean to use the other one" question. |
| `[id]` / `[...slug]` / `[[...slug]]` | Dynamic / catch-all / optional-catch-all segments. |
| `(group)` | Route group — organizes files, contributes nothing to the URL. |
| `@slot` | Parallel route — a directory rendered *alongside* its sibling, not nested under it. |

The **Pages Router** (`pages/`) is the older convention, structurally
different rather than a subset: `pages/api/*` is where API routes live (no
`route.ts` split), `_app.tsx`/`_document.tsx` are special top-level files
with no App Router equivalent, and there is no colocated-layout nesting —
layout is composed by hand in `_app.tsx`. **Mixing both routers for
overlapping paths is a real, documented Next.js footgun** (the two systems
resolve routes independently and can silently shadow each other) — exactly
the class of thing this plugin's checks exist to catch, and exactly the
kind of drift no generic tool would ever surface, because it is specific to
one framework's routing internals.

**This is not a Next.js-only pattern.** The same file-is-a-route idiom,
different filename tables:

- **SvelteKit** — `+page.svelte`, `+layout.svelte`, `+server.js`, `+error.svelte`. If anything more aggressively convention-driven than Next.js: the `+` prefix makes every special file self-announcing.
- **Nuxt** (Vue) — `pages/`, near-identical to Next's Pages Router; Nuxt 3's `app.vue` + `layouts/` mirrors the layout-composition idea.
- **Remix** — routes by filename too, with its own nested-route convention (`.` in a filename encodes nesting without a directory).
- **SolidStart** — modeled directly on Next's App Router.

So the honest design is **one recognizer, parametrized by a
framework-filename table** (Next App Router's table, Next Pages Router's
table, SvelteKit's table, …), the same way `core/plugins.lua`'s header
already commits to being lazy.nvim-shaped and named as such rather than
pretending generality — each framework gets its own table, not a single
heuristic guessing at all of them.

### React hooks — real, but a crowded space

The `use*` naming convention (`useState`, `useEffect`, a custom
`useDebounce`) is structural and detectable by name alone — the same
signal React's own **Rules of Hooks** lint rule
(`eslint-plugin-react-hooks`) already uses. That is the catch: hook-call
analysis (conditional calls, calls inside loops, missing dependency-array
entries) is an already-mature, already-ubiquitous check every React project
already runs. Building it here would mostly duplicate `eslint-plugin-
react-hooks`, not fill a gap the way `plugins.lua` filled a gap nothing
else covered for lazy.nvim specs.

What is *not* already covered anywhere: a **map of custom hooks** — which
ones exist, what they depend on (their own `useX` calls inside), which
components use which. That is closer to the "what plugins do I have"
question `plugins.lua` answers than to a lint rule, and it is genuinely
underserved.

---

## The UI question, reframed

The question as asked was filter-tab vs. label-tab. Neither is quite the
right unit, because **both already exist** in this codebase, doing exactly
those two jobs, for everything the map already knows about:

- **Filtering** — `anFilter`/`state.q`, a free-text substring search already
  present on every Analysis panel (and `editor/browse/filter.lua`'s richer
  `-negate`/`"phrase"` query language in the editor-side browser). Adding
  hooks or routes does not need a *new* filter mechanism — it needs their
  fields folded into the existing `haystack` string each row already
  builds, the same one line of wiring `plugins.lua`'s panel used.
- **Labels** — node-kind icons (`▸` module, `·` namespace, `ƒ` function)
  and badges (`spec.lazy`, `fn.internal`) are how this map already marks
  "what kind of thing is this row" wherever a list of mixed kinds is shown.

So the real decision was never filter-vs-label. It is **which of the two
existing extension points** — a new **Hierarchy graph view**, or a new
**Analysis-tab panel** — a given framework concept belongs to. That
question has a clean, structural answer for both candidates above:

- **Routes belong in Hierarchy, not Analysis.** A route's effective layout
  chain is *the product of every ancestor directory's `layout.tsx`* — the
  parent-child nesting is the entire point, the same reason Modules is a
  tree and not a table. Flattening it into an Analysis-panel row per route
  would discard the one fact worth showing. A sixth Hierarchy view (**Routes**,
  alongside Modules/Types/Deps/Calls/Inheritance) is the honest shape —
  reusing the shared layered-BFS layout, walking the layout chain instead
  of `children`.
- **Hooks belong in Analysis, not Hierarchy.** A hook-usage map is a flat
  ranking — which custom hooks exist, how many components call each one —
  structurally identical to the Complexity or Plugins panel: no meaningful
  parent-child relationship between call sites to preserve. A seventh
  Analysis tool, not a graph.

Icons/badges and free-text filtering apply to both regardless of which
extension point they land in, inherited for free from the existing
`anHead`/`anFilter`/`anSort` plumbing and the Hierarchy tab's own node-icon
convention — neither needs inventing.

---

## Recommendation

**Not now, and sequenced behind `MULTILANG.md`'s JS/TS step**, which is
itself not scheduled. If that step ever happens: build the **file-based
router recognizer first**, generalized across frameworks by a
filename-table parameter rather than hardcoded to Next.js, landing as a new
**Routes** Hierarchy view — it is the one candidate here that is both
genuinely underserved by existing tooling and structurally suited to a
graph this map already knows how to draw. Hooks mapping is a real but
lower-priority follow-on, competing for attention with a tool
(`eslint-plugin-react-hooks`) that already does the higher-value half of
that job well.
