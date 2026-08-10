# Workflow — getting real use out of documentation.nvim day to day

Every feature here is documented on its own elsewhere (`docs/COMMANDS.md`,
`docs/PIPELINE.md`, `docs/ANNOTATION_TAGS.md`). This is the different
question: once several features exist, *how do they actually combine*
into something worth reaching for regularly, rather than once after
install and never again.

## Start from `:DocMap check`, not from browsing

The fastest real signal this plugin gives is `:DocMap check` (or
`:DocMap` bare, which checks as a side effect of regenerating). It writes
nothing on its own and populates the quickfix list — run it, `:copen`,
and work the list like any other quickfix output. This is the "did I
break anything" loop, and it is fast enough to run before every commit,
not just occasionally: on a mid-sized repo it is a fraction of a second.

`:checkhealth documentation` is the companion check for "is the tool
itself set up right" (deps, treesitter parser, the resolved root for
wherever you ran it from) — run it once per new repo, not per edit.

## Reading the browser: Hierarchy and Analysis answer different questions

`:DocBrowse` (in-editor) and `:DocMap open` (the generated HTML page)
show the same underlying data, but the **Hierarchy** tab and the
**Analysis** tab answer genuinely different questions, and reaching for
the wrong one wastes the trip:

- **Hierarchy** answers "where does this live, and what does it touch" —
  the Modules/Deps/Calls/Types/Inheritance graphs, direction and depth
  controls. Use it when you already know *what* you're looking at and
  need to understand its neighborhood.
- **Analysis** answers "what across the *whole tree* deserves attention
  right now" — nine sortable/filterable panels (Test coverage,
  Documentation, Dependencies, Complexity, Duplicates, Plugins, Hooks,
  Docs, Endpoints). Use it when you don't yet know what you're looking
  for, only that something in this category is probably worth finding.

A concrete combination: **Complexity panel → pick the worst offender →
jump straight to its Hierarchy neighborhood** (click through, or `gd` in
`:DocBrowse`) to see what actually calls it before deciding whether
splitting it is safe.

## The two things worth checking before refactoring anything

1. **`:DocMap churn <range>`** — commits × complexity, worst first. A
   function that changes constantly *and* is complex is a real
   maintenance risk; a function that is merely complex but has not been
   touched in months is a different, lower-urgency problem. Churn without
   complexity data is just "what do I edit a lot", which is a much
   weaker signal on its own.
2. **`:DocMap impact <ref>`** — where the *lines* you are about to change
   (or just changed, comparing against a ref) actually radiate to,
   function-level, not file-level. Run this before a refactor to know
   the real blast radius, not the file list a diff would show.

## If `runtime-analysis.nvim` is installed: read Telemetry before trusting Analysis's own dead-code list

`:DocBrowse`'s **Telemetry** mode (and the Analysis tab's own
`dead-function` finding, which already reads this join automatically) is
the single highest-value combination this plugin offers once a second,
runtime-truth plugin exists. The badge vocabulary is worth internalizing:

| Badge | Means | Action |
|---|---|---|
| `✕` | No static caller, never called | Real deletion candidate |
| `!` | Called, but no static caller found | A callback/dynamic dispatch documentation.nvim's static scan cannot see — **not dead**, do not delete |
| `○` | Has a caller, never called (yet) | Reachable but unexercised — investigate before concluding either way |
| blank | Caller exists, and it was called | Healthy |

**The trap this table exists to prevent:** documentation.nvim's own
`dead-function` finding, read alone, cannot distinguish `✕` from `!` — a
function only ever invoked through `vim.keymap.set`'s function-value
argument, or called from a sibling repo entirely, looks identical to
genuinely dead code from a pure static scan's point of view. That is
exactly why the join auto-suppresses a `dead-function` finding once
telemetry proves the function alive — but the reverse direction (a
function telemetry has *not yet* proven alive) still needs a human
glance before deleting anything, because "not called in this window" is
never the same claim as "dead". See `runtime-analysis.nvim`'s own
`docs/ROADMAP/personal/runtime-analysis/CHECKLIST.md` (personal, not in
this repo) for the fuller interpretation framework, if you have it.

Same shape applies to the **Endpoints** mode's own `○` badge (a
declared route runtime-analysis.nvim's request history has never sent) —
read as "untested", not "broken".

## Trail is a session tool, not a bookmark you'll remember weeks later

`p` pins, `6` lists, `<CR>` restores the *exact view* (mode, direction,
depth), not just the subject. Use it for "I'm three levels deep in Deps
mode chasing a require chain and need to come back here" — the same
session, the same investigation. `S`/`L`/`X` (save/load/delete a named
trail) persist across restarts and are worth using for something
longer-lived: "the five modules involved in this week's refactor", named
so a `L` a few days later actually finds them again. A trail with no
name and no plan for when you'll use it again is just clutter by the
time you next open `:DocBrowse`.

## `f` (filter) vs `/` (fuzzy jump) — narrowing vs finding

Easy to reach for the wrong one under time pressure: `/` fuzzy-jumps
across the *whole tree* to one destination you already have a rough name
for. `f` narrows *the list currently on screen* to a substring match,
staying in the same mode — use it when you're already looking at the
right list (say, Complexity's Analysis panel) and want to rule out
everything except one subsystem's own naming prefix. `-word` excludes
instead of matching, useful for "everything in this panel except the
generated files".

## Cross-repo: `tag_files` before assuming a dependency's internals are invisible

A `requires_external` box in the Deps graph does not have to be a dead
end. If the external repo also runs `:DocMap` and commits its own
`docs/map/`, `opts.tag_files` (module-prefix → that project's own map
directory) resolves it against the *real* artifact instead of leaving it
inert — the same mechanism `runtime-analysis.nvim`/`documentation.nvim`
already use to cross-link each other's own maps. Worth setting up once
per pair of repos you navigate between often, not per session.

For a dependency that isn't `docmap`-shaped at all — the common case,
any ordinary third-party plugin — `opts.external_repos` gets you most of
the same value: hover the box first, regardless of whether a link
resolved, since the tooltip's own call breakdown (`plenary.async.run
(2×)`) is usually the faster answer to "why is this here" than opening
the dependency's source would be. Reach for the link only when the
breakdown alone doesn't settle it.
