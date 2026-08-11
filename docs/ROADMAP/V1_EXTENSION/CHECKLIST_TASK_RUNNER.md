# A checklist/task syntax with a runner and dashboard — costed, not decided

Raised 2026-08-11: a syntax for a user to write a checklist of tasks,
runnable through documentation.nvim or runtime-analysis.nvim (whichever
fits), reported as a dashboard tab/subtab — with the user's own nvim-config
`docs/ROADMAP/RULES` work named as a real source of checklist data points.
Analysis, not a proposal, the same posture
[`DESKTOP_WEBAPP.md`](DESKTOP_WEBAPP.md) in this same directory takes.

## The real data this was grounded against

`docs/ROADMAP/RULES/` (the nvim-config repo) is a genuinely large, already-done
example of exactly this shape: 33 per-plugin reports plus 9 thematic
syntheses, each guideline cited to a real `file:line` in a real plugin.
`themes/keybindings-count.md`, read for this analysis rather than assumed:
"does `<leader>xy` support `2<leader>xy`/`3<leader>xy`/...", answered per
keymap, with both positive examples (`dap.nvim`'s step keymaps chaining
through DAP listeners rather than naively looping) and the reasoning
behind each verdict.

**This example immediately narrows the idea, and the narrowing matters
more than it looks.** "Does this keymap support count where it should" is
not something a static scanner can safely decide — it needs to know
whether count-semantics make sense for *this* action, which is a judgment
call, not a pattern match. It was answered once, by a person, reading the
code. That is the honest shape of a large fraction of real checklist
items: **recorded facts, not re-derivable rules** — closer to a
maintained assertion log than a lint check.

## What "runnable" can honestly mean — two different scopes

### (a) Auto-checkable items only

A checklist item bound to something documentation.nvim/runtime-analysis.nvim
can already verify without a human: "every public module has a README"
(this repo's own `missing-readme` check, already exists), "every
`<leader>`-prefixed keymap has a `desc`", "every `:RA`-shaped usrcmd has a
`docs/COMMANDS.md` entry". This fits documentation.nvim's own stated
filter exactly — [`IDEAS.md`](IDEAS.md)'s own words: *"this
plugin's value is detecting where documentation and code stop
agreeing"* — because every item in this scope reduces to a drift check,
just phrased as a checklist line instead of a fixed catalogue entry.

**What it costs:** essentially nothing new mechanically — the check
catalogue (`core/check.lua`, 16 checks today) already has the pattern
(walk the IR, report a finding). The new part is a **user-authored**
predicate instead of a built-in one, which is a real design question (see
below), not a re-implementation of anything that exists.

**What it cannot do:** answer anything like the count-support example
above, or most of what `RULES/` actually contains — security/performance
deviations from a naive approach, whether an algorithm choice was
deliberate. Those need a reader, not a scanner.

### (b) A curated ledger, with staleness detection

Take scope (a)'s honest limit seriously instead of working around it: let
a checklist item be a **hand-verified fact**, pinned to a `file:line` (or
a module id), with a **timestamp/commit-hash** of when it was last
checked. Nothing here is re-derived automatically — but the pinned
location *can* be watched: if the cited file has changed since the
checklist item was last verified (a real, cheap check — `git log` on one
path, or a content hash), the dashboard flags it "changed since last
verified" rather than silently continuing to show a verdict that may no
longer be true.

This is a materially different, and more honest, feature than (a): not
"run and get pass/fail", but "surface what needs re-reading". It matches
what `RULES/` actually is far better than (a) does, and it composes with
(a) rather than replacing it — an item can start as a hand-verified fact
and graduate to an automated check later, if and when someone writes the
predicate for it.

**Recommendation, if this is ever built: start with (b), not (a).** (a)
alone re-derives a narrower version of the existing check catalogue with
extra syntax; (b) is the part of the idea that is actually new, and it is
what the `RULES/` example itself demonstrates the value of.

## Where it lives

Most of a first version's plausible content is **static** — file
presence, keymap/usrcmd shape, doc cross-references — the same kind of
fact `core/check.lua` already reads off the IR. That argues for
documentation.nvim as the home for the checklist *definition* and (a)-style
auto-checks, with runtime-analysis.nvim joined in later the same way
telemetry/loaded already are — an item like "was this feature actually
exercised this session" is runtime evidence by nature and has no static
answer, the identical split [`ECOSYSTEM.md`](../FEATURES/ECOSYSTEM.md) already draws between the
two plugins for every other feature.

Concretely, this would most likely land as a **tenth Analysis panel**
(nine exist today, see [`IDEAS.md` §2](IDEAS.md#2-new-analysis-panels))
or a promoted feature tab (the `Tab: true` mechanism `docs/FEATURES/CORE.md`
already documents, built for exactly "a feature that outgrows a panel").
Not a new top-level tab from scratch — the toolbar-of-panels pattern
already exists and a checklist dashboard is structurally another panel in
it, not a different kind of page.

## A sketch, not a spec

```markdown
<!-- e.g. docs/CHECKLIST.md, a new corpus core/docs.lua-shaped file could read -->

## Keybindings

- [x] `<leader>xy` supports count where it should
      <!-- @ref lua/plugins/dap.nvim/bindings/keymaps.lua:32 -->
      <!-- @verified 2026-08-08 -->
- [ ] Picker inputs support autocompletion
      <!-- @ref lua/plugins/foo.nvim/bindings/usrcmds.lua:14 -->
```

`- [x]`/`- [ ]` is already the syntax every roadmap file in this whole
ecosystem uses — including the source message that raised this idea.
`@ref`/`@verified` as HTML-comment metadata (invisible in a rendered
preview, parseable by a scanner) mirrors how `@module`/`@field` LuaCATS
tags already ride inside ordinary comments elsewhere in this tree. Fully
sketched, **not designed**: the exact tag vocabulary, whether `@ref`
resolves against the scanning repo's own IR or an arbitrary path, and how
"changed since verified" gets computed (working-tree mtime vs. a real
`git log` walk, the same choice `core/churn.lua` already had to make) are
all open.

## Real open questions, not resolved here

- **Does a "task" mean boolean pass/fail only, or does some real use case
  need a threshold** (e.g. "at least 80% of public keymaps have a
  `desc`")? Nothing named so far needs more than boolean; worth deciding
  before building rather than after, since it changes the schema.
- **Persistence and history.** A "changed since verified" flag on its own
  answers "should someone look again", not "how has this checklist's own
  pass rate moved over time" — the second question would want the same
  named-snapshot shape `runtime-analysis.telemetry`/`runtime-analysis.loaded`
  already have (§4.5/§5.4, both shipped this session), applied to a third
  kind of data. Not scoped here; flagged as the natural next question if
  (b) ships and someone wants trend data.
- **Where does verification actually happen** — does checking an item off
  happen by hand-editing the Markdown (cheap, matches how every roadmap
  file in this ecosystem is already edited), or does it want a real
  command/UI affordance (`:DocMap checklist verify <item>`)? The `RULES/`
  precedent was produced by hand-editing Markdown throughout; no stated
  need for anything more exists yet.
- **Multi-repo scope.** `RULES/` spans 33 repos; documentation.nvim scans
  one repo at a time. A checklist naming facts across many repos (as
  `RULES/themes/*.md` does) does not fit a single project's own generated
  map at all — it would need the "many repos, one config" shape
  [`IDEAS.md` §6.6/§6.7](IDEAS.md#66-a-generic-cli-entry-no-per-repo-copy)
  already scopes (also unbuilt), or it stays a per-repo feature and the
  cross-repo view stays what `RULES/` already is: hand-maintained
  Markdown, which is not obviously wrong for something this infrequent.

## Revisit if

Someone actually wants to track a real checklist this way rather than as
plain Markdown (which is free, already works, and is what `RULES/` already
demonstrates is sufficient for a one-time systematic pass). The strongest
case for building anything here is **repeated** re-verification of the
same facts over time — a one-time audit like `RULES/` does not obviously
need a runner at all.
