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
  right now" — eleven sortable/filterable panels (Test coverage,
  Documentation, Dependencies, Complexity, Duplicates, Plugins, Hooks,
  Docs, Endpoints, Tools, Telemetry). Use it when you don't yet know what
  you're looking for, only that something in this category is probably
  worth finding.

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

## Snapshot before a refactor, not just after

The Analysis tab's **Telemetry** panel (`:DocMap serve` running) reads the
*live* aggregate by default — good for "what does usage look like right
now", useless for "did this refactor actually change how these functions
get called". `runtime-analysis.nvim`'s named snapshots close that gap, and
the habit worth building is **snapshotting before you start, not only
comparing after**:

```
:RATelemetry snapshot my-plugin pre-refactor
```

Do the refactor, let real usage accumulate for a while, then either open
the Telemetry panel and pick `pre-refactor` in the "Snapshot:" select and
`Latest` in "Compare vs:", or skip the browser entirely and run
`:RATelemetry snapshot-compare my-plugin pre-refactor post-refactor` —
the resulting Δ (panel) or `changed`/`new_functions`/`cold_functions`
listing (command) is the actual answer to "did this change what gets
called and how often", not a guess from reading the diff. A snapshot
taken *after* the fact can only ever be compared against another
snapshot taken after, which answers "did usage change since I remembered
to start tracking it" — a weaker, later question than the one a `pre-`
snapshot answers for free.

`snapshot-compare` classifies by the A→B *delta*, not raw totals — worth
knowing before reading its output: `Data.functions[key].calls` is a
lifetime counter that only ever grows, so it cannot tell you "silent
since `pre-refactor`" the way it sounds like it might; `cold_functions`
there means "had history before this snapshot, zero *new* calls since",
which is the question that actually has an answer between two
chronologically ordered snapshots.

Retention is LRU (`telemetry.SNAPSHOT_RETENTION`, default 20, `opts.
snapshot_retention` per namespace) — a snapshot worth keeping past that
window needs a name that will still make sense a dozen snapshots later
(`pre-refactor`, not `test`), since eviction has no idea which ones you
actually meant to keep.

Snapshots are also device-tagged (`telemetry.snapshot(ns, name, {device=...})`,
default `vim.uv.os_gethostname()`) — worth naming the device explicitly
when the "before" and "after" runs happen on different machines, since
`pre-refactor`/`post-refactor` alone does not say which one ran where.

## `opts.callhierarchy` + `opts.diagnostics`: never leave the editor for the common questions

Both are `install()`-only and off by default, and together they cover the
two questions a reader reaches for `:DocBrowse` for most often, without
actually opening it: "what calls this" (`opts.callhierarchy` — native
`vim.lsp.buf.incoming_calls()`/`outgoing_calls()`, plus a caller/callee
count injected into hover) and "is this file clean" (`opts.diagnostics` —
`:DocMap check`'s own findings as native `vim.diagnostic` entries, so
`[d`/`]d` and a diagnostics float work exactly like they do for LSP
warnings). Turning both on costs nothing until a buffer under `source/` is
opened — no scan runs, no LSP client attaches, until then. Worth enabling
by default in a personal config once the combination has earned its
keep; the two are unrelated to each other (one is call graphs, one is
findings), so either is useful alone too.

The setup for the call-hierarchy half is one option and two keymaps —
Neovim ships no default binding for incoming/outgoing calls, so nothing
happens until you add one. That, plus how to tell an unattached client
from a function that genuinely has no callers (the two look identical:
an empty quickfix list), is in
[docs/CALL_HIERARCHY.md](CALL_HIERARCHY.md).

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

## Generating for many repos at once: `opts.generate_all`, not a loop

`:DocMap`/`:DocMap full` act on one repository per invocation, resolved
from the current buffer — right for "I'm working on this tree right
now," wrong for "regenerate the map for every plugin I maintain" (a
plain loop over `:DocMap full` in each would run every scan on this
Neovim's own main thread, one after another, blocking it for the whole
batch). `opts.generate_all = { projects = {{root, title}, ...} }` on
`setup()` registers `:DocMap all`/`:DocMapAll` for exactly that case: one
real headless Neovim subprocess per project, chained so exactly one is
ever running, never blocking this session. One project failing does not
abort the rest — the closing notification names every one that did.

Not registered unless configured — `opts.generate_all.projects` is data
only a consuming config can supply (this plugin never reads anyone's
plugin list itself), so an unconfigured `setup()` gains neither command.
`opts.generate_all.autoload = true` additionally checks, once at
`setup()` time, which configured projects have no map yet and generates
only those — worth turning on once a project list is already configured
here, since listing a plugin there is already the signal its map is
wanted; leave it off if writing into other repos' `docs/map` without
being asked is the wrong default for how you use this.

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
