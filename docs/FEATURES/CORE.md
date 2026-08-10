# Core

Cross-cutting mechanisms used by more than one tab of the generated page,
plus the two most recent ecosystem-convention Analysis panels.

## Compare marks

Mark any function or module with the `+` beside its `ⓘ` (or a node's own
`+`, which has no signature to hang one off), then open the Compare tab to
see every marked object side by side — Matrix layout lights up the rows
where they actually differ, which is the whole reason to reach for this
over two browser windows.

- **Module:** `core/render/html.lua` (`toggleMark`, `syncMarks`, `markTrigger`)
- **Config:** none — always available, no `opts` key gates it.
- **Docs:** [`docs/PIPELINE.md`](../PIPELINE.md) "Compare tab" section.

## Hierarchy hide/dim

Right-click any box in the Hierarchy graph → "Dim this box" (or "Show this
box" once dimmed), plus a "Hidden (N) — show all" toolbar pill to clear
every dimmed box at once. Dims rather than removes a box from the layout —
same `opacity`-only mechanism the pre-existing hover-focus already used,
just persistent and per-box instead of transient.

- **Module:** `core/render/html.lua` (`toggleHidden`, `syncHidden`, `buildMenu`)
- **Config:** none.
- **Docs:** [`docs/PIPELINE.md`](../PIPELINE.md) "Hide/dim" subsection under
  Hierarchy tab.

## Plugins Analysis panel

Every recognized lazy.nvim spec in the tree, as its own Analysis-tab panel
and as `:DocMap plugins` → quickfix. Exists for the shape of tree this map
was blind to before it: a Neovim *config*, where `lua/plugins/*.lua` is
mostly `return { {...}, {...} }` with no function in sight.

- **Module:** `core/plugins.lua` (`M.extract`)
- **Usercmds:** `:DocMap plugins` (see
  [BINDINGS.md](../BINDINGS.md#user-commands))
- **Docs:** [`docs/COMMANDS.md`](../COMMANDS.md) "`:DocMap plugins`" section.

## Tools Analysis panel

This repo's own [`lib.nvim.deps`](https://github.com/StefanBartl/lib.nvim)
manifest (`docs/install.json`/`docs/INSTALL.md`) — declared external CLI
tools, not Lua dependencies — as its own Analysis-tab panel and as
`:DocMap tools` → quickfix. Declared only: never a live "is it installed
here" probe, since a static page has no host to ask.

- **Module:** `core/tools.lua` (`M.resolve`)
- **Usercmds:** `:DocMap tools` (see
  [BINDINGS.md](../BINDINGS.md#user-commands))
- **Docs:** [`docs/COMMANDS.md`](../COMMANDS.md) "`:DocMap tools`" section.

## Features tab

A repo's own `docs/FEATURES/` folder, when it has one, as a ninth top-level
tab — an index, not a Markdown viewer: one card per `## Feature` section,
its summary and whatever `- **Key:** value` metadata bullets the author
wrote. This entry is the recursive case: the file you are reading is itself
what that tab renders, for this repo.

- **Module:** `core/features.lua` (`M.resolve`), `core/render/html.lua`
  (`drawFeatures`)
- **Config:** none — reads `docs/FEATURES/` (or `docs/features/`)
  automatically when present.
- **Docs:** [`docs/FEATURES_FORMAT.md`](../FEATURES_FORMAT.md) (the format
  this file follows), [`docs/PIPELINE.md`](../PIPELINE.md) "Features tab"
  section.

## Promoted feature tabs

A `- **Tab:** true` bullet promotes one feature out of the Features catalog
above and into a real top-level tab of its own, built dynamically at page
load. Everything after the metadata block — headings, fenced code, lists,
paragraphs, inline `` `code` ``/**bold**/*italic*/links — renders through a
small Markdown subset instead of just being linked out to. This entry is
the recursive case again, one level deeper: "Module Calls view" above this
one in the same file *is* promoted, so the tab it names is currently
rendering the bullet you are reading right now.

- **Module:** `core/features.lua` (`parse_body`'s `body_start_idx`),
  `core/render/html.lua` (`buildPromotedTabs`, `drawFeatureTab`,
  `renderFeatureBody`)
- **Config:** none — the `Tab: true` bullet is per-feature, not a global
  option.
- **Docs:** [`docs/FEATURES_FORMAT.md`](../FEATURES_FORMAT.md) "Promoting a
  feature to its own tab" section, [`docs/PIPELINE.md`](../PIPELINE.md)
  "Promoting a feature to its own tab" section.

## External call/plugin visibility

The Deps view's external box answers *why* a dependency is there, not just
that it is — hover any `+ external` box for a breakdown of exactly which
functions were actually called and how often (`plenary.async.run (2×)`),
counted in the same pass that resolves the internal call graph. Declare
`opts.external_repos` to also turn the box into a real GitHub link,
verified against a local checkout when you name one.

- **Module:** `core/calls.lua` (`node.calls_external`), `core/external_repos.lua`
- **Config:** `opts.external_repos` (module-prefix → `"owner/repo"` or a
  table with `branch`/`lua_root`/`local_path`).
- **Docs:** [`docs/PIPELINE.md`](../PIPELINE.md) "External call/plugin
  visibility" section, [`docs/REUSE.md`](../REUSE.md) "GitHub links for
  third-party deps".

## Module Calls view

A sixth Hierarchy view alongside Modules/Types/Inheritance/Deps/Calls: the
same `kind="call"` edges as Calls, collapsed from function-to-function to
module-to-module and weighted by call count, so five call sites between two
modules draw one arrow labelled "5 calls" instead of five overlapping ones —
a require graph already answers "does A depend on B", this answers "how
much". Same `+ external` toggle, direction and depth axes as Deps.

- **Tab:** true
- **Module:** `core/render/html.lua` (`layoutModuleCalls`,
  `addModuleCallExternals`)
- **Config:** none — call-graph resolution runs unconditionally in `scan()`
  (unlike Types/Inheritance, it needs no LuaLS `--full` pass), so this view
  is available on every generated map.
- **Docs:** [`docs/PIPELINE.md`](../PIPELINE.md) "Module Calls: weighted
  alternative to Calls" section.

### Why weight, not just an edge

A require graph already draws an arrow for "A depends on B" — a binary
fact. What it cannot say is whether that dependency is load-bearing or a
single forgotten call from three years ago. Module Calls exists for
exactly that gap: two modules connected by one call and by forty calls
look identical on a Deps diagram, and very different on this one.

### Edge weight, visually

Stroke width is `min(1.5 + log2(weight) * 1.1, 7)` pixels, applied as an
inline style rather than an SVG `stroke-width` attribute — the page's own
`.hedge{stroke-width:1.5}` CSS rule would otherwise win over a presentation
attribute and silently flatten every edge back to the same width.

```
weight  1 -> 1.5px
weight  2 -> 2.6px
weight  5 -> 4.0px
weight 20 -> 6.1px
weight 64+ (capped) -> 7.0px
```

Log-scaled on purpose: a linear mapping would let one outlier pair (a
config module calling `vim.notify` forty times) dwarf every other,
genuinely interesting difference into invisibility.

### Why a view, not its own tab

The roadmap item this shipped for ("Gewichtete Alternativ-Ansicht des
Call-Graphen") asked for a dedicated tab. Built instead as a sixth
Hierarchy view, reusing the zoom/pan/hide-dim/context-menu/SVG-export
machinery every other view already has — decided with the repo owner on
the grounds that this view is exactly as centered-on-a-node, directed and
depth-limited as Deps already is, and a new tab would have meant either
duplicating that machinery or generalizing it for one caller.

## Root-level hide slider

A vertical, Google Maps-styled slider next to the Modules view — `+` at
the top hides one more layer of the real directory tree, `−` at the
bottom shows one back. Every node that used to sit at the hidden depth
becomes its own parallel root, all drawn at once as a forest, not a
re-center on any single one of them (double-click already does that).
Answers a problem specific to deep trees: several directories before
anything interesting starts means every session begins with the same
uninteresting clicks.

- **Module:** `core/render/html.lua` (`layoutModulesRooted`,
  `rootFrontier`, `maxRootDepth`, `layoutModulesFrom`)
- **Config:** none — the slider's own `max` is measured off the real tree
  (`maxRootDepth()`), not a config value.
- **Docs:** [`docs/PIPELINE.md`](../PIPELINE.md) "Hiding root levels
  (Modules view)" section.
