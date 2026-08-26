# Features tab — one sub-tab per theme file

Proposed 2026-08-26. The Features tab renders every theme file's entries in
one long scroll, one `<h3>` group per file. The proposal is to make each theme
file a **sub-tab** instead, so a repo can single out the features worth
singling out and leave the rest in an overview.

## The shape it would take

The reader's order is already fixed as of the same session — `core.md` first,
`FEATURES.md` second, then the rest by name (see
[`../../FEATURES_FORMAT.md`](../../FEATURES_FORMAT.md), "Naming and order").
That ordering was the half that was cheap, and it is done; this document is
about the half that is not.

With sub-tabs, those three positions stop being a scroll order and start
meaning something:

| Position | File | Reads as |
|---|---|---|
| first | `core.md` | The handful of features the plugin exists for — what a reader wants before anything else |
| second | `FEATURES.md` | Everything not singled out: the overview |
| after | `UI.md`, `SEARCH.md`, … | One theme each, opened when the reader wants that theme |

A repo with a single `docs/FEATURES.md` gets one sub-tab, which should render
as no sub-tab bar at all rather than a bar with one button.

## Cost

**Smaller than it looks, because the data is already shaped for it.**
`features.resolve` returns `files[]`, each with its own `theme`, `intro` and
`entries[]`, and `drawFeatures` in
[`core/render/html.lua`](../../../lua/documentation/core/render/html.lua)
already walks that list emitting one titled group per file with a count badge.

What is actually missing:

- A sub-tab strip built from `feats.files` — the same `themeTitle()` and count
  already used for the `<h3>`.
- Show/hide per group instead of rendering all of them, plus a default
  selection (the first file, i.e. `core.md` where present).
- The `totalFeatures` line at the top has to say something sensible when only
  one theme is visible.
- The single-file case: suppress the strip.

That is one function, and no change to the parser or the IR. Call it an
afternoon, not a project.

## The one decision to make first

**How does this interact with `- **Tab:** true`?** That mechanism already
exists and does something adjacent: it promotes a *single feature* out of the
catalogue into its own **top-level** tab, with a rich Markdown body. Sub-tabs
would promote a *theme file* into its own sub-tab.

Two ways to highlight, at two different levels, is not automatically wrong —
they answer different questions ("this one feature deserves a page" vs. "these
features belong together"). But it is worth stating which is which in
`FEATURES_FORMAT.md` before building the second one, or a repo author faces a
choice with no guidance and the two mechanisms drift into being alternatives
for the same job.

The likely answer: `Tab: true` stays what it is — a feature big enough to need
a page of its own — and sub-tabs are simply how the catalogue is navigated,
with no per-repo decision attached. If that holds, nothing about `Tab: true`
changes and the two never compete.

## Why it is not built yet

Ordering shipped because it was ten lines and improved the current scroll
immediately. The sub-tab strip is a UI change to a tab that several other
tabs' conventions apply to, and it should be built alongside a look at
whether the Analysis tab's toolbar pattern (see
[`ReferenceTab.md`](ReferenceTab.md), "One tab with a selector, not two tabs")
is the right precedent to follow — that tab already solved "several panels,
one tab" once.
