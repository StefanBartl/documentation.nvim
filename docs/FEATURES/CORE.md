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
