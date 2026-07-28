# documentation.nvim — open items

What's actually still open, after a full pass through this project's roadmap
history. Everything shipped is recorded in [`FEATURES.md`](FEATURES.md)
instead — commit hashes and design decisions live there, not here. This file
only holds things with no decision yet, or a decision to *not* build something
(a documented rejection is as much a result as a shipped feature, and worth
keeping so the question doesn't get re-litigated from scratch).

Carried over from `lib.nvim`'s `docs/ROADMAP/docmap_roadmap.md`, which in turn
consolidated `docmodule.md`/`docmodule_NEXT.md` (moved in from the nvim-config
repo, 2026-07-28), `module_map.md`, and
`docmap_hierarchy_and_integrations.md`. All of those are fully superseded by
what actually got built; the original, much longer process narrative is in
lib.nvim's git history if it is ever needed.

> **Names in this file predate the extraction.** Where it says `docmap`,
> `:LibMap` or `lib.nvim.docmap`, read `documentation`, `:DocMap` and
> `documentation.*` — the module moved out into its own plugin on 2026-07-28
> (O2 below, now shipped). Entries are left as written rather than
> search-and-replaced, because several of them are *decisions* whose wording
> is the record.

## Shipped since this file was last written

- **O2 — extract into its own plugin.** Done, 2026-07-28. The rejection below
  said "revisit if the size/coupling actually starts hurting"; what tipped it
  was neither, it was simply the decision to stop treating a 12k-line
  generator as one of lib.nvim's small utilities. Cost roughly what the
  rejection predicted it would: a rename, not a rewrite, because
  `opts.root`/`opts.source`/`opts.extra_checks` already meant nothing in it
  knew lib.nvim's layout. Naming resolved to `documentation.nvim` (not on the
  survey list below — the repo name states the domain, and the module path
  `documentation` follows the repo-basename convention every sibling plugin
  uses). See `docs/PIPELINE.md` § "Why this is its own plugin".
- **Trail** (wayfinder item 2). Done. A pin records a *view* — the mode and
  the axes it was taken in — not just a subject, because half-restoring is
  what makes bookmarks feel unreliable. Identity is deliberately narrower
  than the record: `dir`/`depth` travel on the pin but are not part of its
  key, so the same node at two depths is one bookmark rather than two
  near-duplicates. Keyed by repository root, so pins outlive the window;
  `browse/trail.lua` is pure, which is what lets the whole model be driven
  from a headless spec. Persisting across Neovim sessions is item 3, below.
- **Saved Trails** (wayfinder item 3). Done. Both halves, because they are
  the same file: the working trail persists on its own, and `S`/`L`/`X`
  name, reload and forget copies of it. It did *not* land in `trail.lua` as
  predicted above — that would have cost the purity the entry before it
  argues for. `trail_store.lua` subscribes to a new `trail.on_change`
  instead, which is also the more robust arrangement: a mutation added later
  cannot forget to persist. Loading **adds** rather than replaces (a
  bookmark tool that can silently lose bookmarks stops being trusted), and
  the store lives in `stdpath("state")`, never the repository — a trail has
  no more claim on the project than a jumplist has, and committing it would
  give `--check` an opinion about where one person happened to look.
- **`?` key-hint overlay** (wayfinder item 1a). Done. Rendered from the same
  `KEYS` table `bind()` installs from, so it cannot drift from the actual
  bindings; keys the current mode ignores are marked rather than hidden. The
  spec asserts every bound key appears in the panel.
- **`:checkhealth documentation`** (wayfinder item 1b). Done. Dependencies,
  the treesitter Lua parser and the optional tools, plus the section it exists
  for: the resolved configuration a `:DocMap` issued right now would act on.
  `:DocMap` defaults its root to the cwd, so "it mapped the wrong repository"
  is invisible from the command's own output.

## Genuinely open

### mdview.nvim integration — never built

Concept existed (originally `docmap_hierarchy_and_integrations.md` Part 4),
LuaLS enrichment / Hierarchy tab / `install()` (that doc's Parts 1–3) all
shipped in more complete form than sketched there, but the mdview piece
itself was never started — confirmed by grep, no `mdview` reference
anywhere under `lua/lib/nvim/docmap/`.

**Tier A** (buildable without any mdview.nvim change): a new
`render/mdview.lua` producing markdown shaped for what mdview's `ammonia`
sanitizer's *default* builder actually keeps (`<details>`/`<summary>`,
GFM tables, inline code — no custom CSS classes or `style` attributes,
badges conveyed through text/emoji instead), pushed via mdview's existing
`ws_client.send_markdown(path, markdown, opts)` from `install()`'s
`on_change` hook, guarded by `pcall(require, "mdview.core.state")` so
lib.nvim never hard-depends on mdview.

**Tier B** (a real box+connector diagram inside mdview's own browser tab):
not buildable today — mdview's pipeline is markdown-in/sanitized-HTML-out
with no structured-data render mode. Needs a `kind` field on mdview's own
WS protocol and a client branch that skips comrak/ammonia for
`kind = "structured"`. Belongs in a concept doc in mdview.nvim's own repo,
not here — don't design it twice.

**Two things to verify before Tier A starts** (unresolved when this was
last looked at):
1. Ammonia's exact default attribute allowlist — confirmed the sanitizer is
   `ammonia::Builder::default()` and that mdview only adds `data-sourcepos`
   + the checkbox `<input>` beyond that default, but never read ammonia's
   own crate source to confirm which attributes (e.g. `id`) survive.
2. How a browser tab gets pointed at a *specific* room vs. the
   currently-open buffer's path — `send_markdown` accepts any string as a
   room key, but the routing from a URL to that key wasn't traced.

### Analysis-tab candidates — not yet spec'd

Four tools already shipped (test coverage, doc coverage, fan-in/fan-out,
cyclomatic complexity — see `docmap_features.md`). Two more were identified
as the next-most-valuable but deliberately not built yet, because they're
the most expensive of the candidates considered and hadn't earned their
cost until the tab itself was proven useful with cheaper tools first:

- **Code duplicates** (PMD/CPD-style "copy-paste detector") — structural
  similarity of function bodies across ~250 files. The pattern most likely
  to go unnoticed in a utility library specifically.
- **Churn-hotspots** (Adam Tornhill's *Your Code as a Crime Scene*: git
  history × complexity) — modules that are both *frequently changed* and
  *complex*, the actual refactor-risk signal that neither metric alone
  gives.

Revisit once the Analysis tab (now with four tools) is actually being used
day to day — building the expensive tools before that is optimizing for a
usage pattern that isn't confirmed yet.

### Reference tab — Lua syntax and LuaCATS tags

Two panels, proposed together: a Lua keyword/syntax crib sheet, and one for
the LuaCATS/EmmyLua tags this scanner reads. Both link out to the official
documentation.

**One tab with a selector, not two tabs.** The Analysis tab already
established the pattern — a toolbar of tools over one panel area — and tabs
are the scarce resource here, not panels: there are six already, and a
seventh and eighth spent on "explain the notation" would crowd out the ones
that describe the tree. A single **Reference** tab also gives the obvious
home to whatever comes next in the same category (a `:DocMap` subcommand
index, the check catalogue) without another top-level decision each time.

The two panels are not equally cheap, and the difference matters more than
the grouping does:

- **LuaCATS/EmmyLua tags — should be generated, not written.** A plugin
  whose purpose is detecting documentation drift must not ship a
  hand-maintained list of which tags it supports; that list *is* the drift,
  and it would be the second-hardest thing in this repo to defend after a
  second copy of the keymaps. Same reasoning that put the `?` overlay behind
  the `KEYS` table `bind()` installs from.

  Cost is real but bounded: `functions.lua` recognises tags in an
  `if/elseif` chain, so a `TAGS` table has to be introduced first and the
  chain rewritten to dispatch through it — the `KEYS` move again, and the
  larger half of the work. The payoff is bigger than anti-drift, though: with
  the IR already in the page, the panel can mark which tags *this* tree
  actually uses and how often, which turns a crib sheet into an adoption
  report. [`docs/ANNOTATIONS.md`](../ANNOTATIONS.md) is exactly that analysis
  done by hand for one repository — evidence the question gets asked, and
  evidence it is currently answered manually.

- **Lua syntax — genuinely static, and the first thing in the map that is
  not derived from the scanned tree.** That is the objection to answer
  before building it, not a footnote: every existing panel renders something
  found in the repository, and a keyword table renders the same bytes in
  every checkout. It is defensible — the `?` overlay and `:help
  documentation.nvim` are already static reference surfaces, and the
  argument for putting one *here* is proximity, since the reader is already
  in this page looking at annotations they do not recognise — but it is a
  new category and should be entered deliberately.

  **Scope is the trap.** "The most important parts of Lua syntax" is
  unbounded, and a panel that drifts toward being a tutorial competes with
  PiL and the reference manual and loses. The version that earns its place
  is narrow and lookup-shaped: the keyword list, operator precedence and
  associativity, the standard-library index, `:` vs. `.`, varargs, and the
  metamethod table. Things one looks up, not things one learns.

**Linking out is not a violation of the offline rule.** The badge is
hand-drawn and `tag_files` takes local paths only, but that rule constrains
what `scan_full()` *fetches during generation* — a hyperlink the reader
clicks is not a network dependency of `--check`. Worth stating so it is not
re-litigated.

**Reachable from where the notation appears, not only from the tab.** Right-
clicking a rendered `@param`, a `@deprecated` badge or a LuaCATS type string
and getting "what is this?" is the interaction that makes the panel worth
building — a reference nobody navigates to is a reference nobody reads. It
needs almost no new machinery either: the Hierarchy tab's context menu
already classifies what was clicked (`describeTarget(el)`, entries filtered
to what is available and *disabled with a label* rather than hidden when it
is not), and the page's whole state already lives in its URL fragment — the
property `gO` exploits. So the jump is `#tab=reference&entry=@param`, an
existing navigation with a new address, and the deep-link target is a second
argument for one tab with an anchor per entry over two loose tabs.

**But this only reaches the tags, and that is the sharpest split between the
two panels yet.** The page renders annotations — badges, `@param`/`@return`
rows, LuaCATS type text like `table<string, Documentation.Node>` — so every
one of those is a right-clickable anchor. It renders no Lua *source*: an
inline syntax-highlighted source view was considered and turned down (see
the rejection table below, `gd` jumps into the real editor instead), so
there is nowhere in the map a `goto` or a `<close>` is displayed to click
on. The keyword panel would be reachable only by opening the tab and
looking, which is a much weaker case for it than for the tag panel. Do not
build the right-click affordance expecting it to serve both.

The `:DocBrowse` counterpart is `K` — Vim's own "look up whatever is under
the cursor", currently unbound in the browser and the only key a Vim user
would try first. Same target, same fragment, rendered into the detail pane
or a float rather than a browser tab.

**One thing to decide before writing a single link:** which Lua version.
Neovim runs LuaJIT, i.e. 5.1 plus selected 5.2 extensions — so
`lua.org/manual/5.4` is the wrong target in a way that actively misleads
(`goto`, integer division, and the `<close>`/`<const>` attributes all read
as available). Pin to the 5.1 manual, mark the 5.2-isms Neovim does
provide, and link `:help luaref` and `:help lua-guide` alongside, which are
the versions that are actually correct for the runtime.

## Deliberately not building (documented rejections)

Keeping the reasoning here so the question isn't re-asked from a blank
slate — none of these are "forgot," all were considered and turned down
for a stated reason. Revisit only if the stated condition changes.

| Idea | Why not | Revisit if |
|---|---|---|
| **Source-Browser** (Doxygen's `SOURCE_BROWSER=YES`, inline syntax-highlighted source with clickable cross-refs) | `:LibBrowse`'s `gd` already jumps into the real editor at the real line — strictly better than a static HTML view for actual use | Someone needs to browse source without the repo checked out locally |
| **Full-text search** (Doxygen search index over prose/`@example` blocks, vs. today's name/module/summary-only search) | Real value, but the existing search already covers the daily case (find a module/function); the prose volume in this tree hasn't grown enough to make it bite | Prose volume in the tree grows substantially |
| **`@group`/`@ingroup`** (Doxygen's `\defgroup`, cross-cutting groups independent of directory structure) | High cost (new tag, new aggregation, new view) for a need that's never come up in a 250-file utility tree where modules already *are* the sensible grouping | The repo grows to where "all public APIs, cross-module" becomes a real question |
| **`ctags` export** (`:LibMap tags`) | Anyone with LSP already has `gd`/`gr` via `lua-language-server` — practically everyone who installs `lib.nvim` at all. Only helps non-LSP external tooling, which nobody here uses | Someone needs `lib.nvim` symbols from outside LSP-aware tooling |
| **Live-reload of the HTML page** on save | `:LibBrowse live` already covers the "see changes without a manual regen" need, in the editor, without a second running process/browser tab to keep in sync | `:LibBrowse live` stops being sufficient for some reason |
| **Runtime inspection of a loaded module** (`:LibInspect`, backlog item B1) | Explicitly out of docmap's scope, not deferred *within* it — actually executing/requiring code is a different trust model (side effects, time-dependent, can never feed `--check` or a committed artifact) than docmap's pure static scan. A separate future tool, if built at all | Someone actually starts that tool — open design questions noted below |

**B1 open design questions, if `:LibInspect` is ever started:** cycle/depth
limits when walking a live table, whether to call into `__index` functions
or just report them, and whether the result even belongs in a `ui.kit`
window or somewhere else entirely.

## O2 prep — naming survey + related-plugin feature research (2026-07-28)

Not a decision to pursue O2, just work already done so it's not repeated
if/when the question comes up for real.

### Names checked against GitHub

| Name | Status |
|---|---|
| `dooku.nvim` | **Taken** — [Zeioth/dooku.nvim](https://github.com/Zeioth/dooku.nvim), same problem space |
| `docgen.nvim` | **Taken, twice** — [jamestrew/docgen.nvim](https://github.com/jamestrew/docgen.nvim), [dhananjaylatkar/docgen.nvim](https://github.com/dhananjaylatkar/docgen.nvim) |
| `cartographer.nvim` | **Taken, twice** — [Iron-E/nvim-cartographer](https://github.com/Iron-E/nvim-cartographer) (keymap DSL), [hkupty/cartographer.nvim](https://github.com/hkupty/cartographer.nvim) (archived 2021) |
| `wayfinder.nvim` | **Taken** — [error311/wayfinder.nvim](https://github.com/error311/wayfinder.nvim), and close enough in concept to `:LibBrowse` to risk real confusion even if it weren't |
| `doxygen.nvim` | Not confirmed formally trademarked, but avoid anyway — reusing a distinct, well-known project's exact name for something unrelated reads as a claimed affiliation that doesn't exist |
| `docmap.nvim` | Open. Matches the existing code/command names (`docmap`, `:LibMap`, `:LibBrowse`) — safest choice, no re-branding for anyone already using it via lib.nvim |
| `docgraph.nvim` | Open. States what it is (doc + require/call/type/inheritance graphs) with no metaphor |
| `luagraph.nvim` | Open. Leads with the static-analysis/graph angle over the doc-site angle |
| `codeatlas.nvim` | Open. "Atlas" (a book of maps) extends the metaphor to match the Doxygen-parity breadth better than "map" alone |
| `structura.nvim` | Open. Drops the map metaphor entirely — neutral, more "serious tool" reading |

Re-check before actually registering — availability changes.

### Related-plugin feature survey

Two of four repos found while researching names turned out relevant, two
didn't:

**Not relevant** — [hkupty/cartographer.nvim](https://github.com/hkupty/cartographer.nvim)
(archived project/file/regex/TODO finder, author recommends telescope.nvim
instead; nothing about analysis or graphs) and
[Iron-E/nvim-cartographer](https://github.com/Iron-E/nvim-cartographer) (a
keymap-definition DSL, unrelated to documentation entirely — a name
collision only, not a feature one).

**[dooku.nvim](https://github.com/Zeioth/dooku.nvim)** — same problem space,
opposite architecture: a thin wrapper shelling out to *external*
per-language doc generators (Doxygen/Typedoc/JSDoc/Rustdoc/Godoc/LDoc/Yard)
and opening the HTML result. docmap's own-treesitter-analysis, zero-external-
tool-dependency approach is a deliberate, worth-keeping difference, not a
gap. Its generate-on-write option is the "regenerate on save" idea already
rejected above (unintended diffs); `:DookuOpen` is already `:LibMap open`.
Nothing here worth adopting.

**[wayfinder.nvim](https://github.com/error311/wayfinder.nvim)** — closest
relative of `:LibBrowse`, genuine candidates if `:LibBrowse` gets revisited
(none currently scheduled, listed roughly cheapest/most-valuable first):
1. ~~**`?` key-hint overlay** and **`:checkhealth docmap`**~~ — both
   shipped, see "Shipped since this file was last written" above. They were
   correctly ranked cheapest-first: together they cost one afternoon.
2. ~~**Trail**~~ — shipped. `p` pins the entry under the cursor in any
   mode, `6` lists them, `d` unpins. One `p` rather than wayfinder's
   `p`/`a`/`A`: pressing it on something already pinned has exactly one
   sensible meaning, and a second key would only make the first worse.
3. ~~**Saved Trails**~~ — shipped. Read as one feature or two; it was built
   as both, since auto-persisting the working trail and naming copies of it
   are the same serialization of the same table. `S` saves, `L` loads
   additively, `X` forgets.
4. **Local list filter** with negation/quoted phrases, narrowing the
   *current* Deps/Calls list in place — different from `:LibBrowse`'s
   existing `/`, which fuzzy-jumps across everything.

Already covered, no gap: wayfinder's quickfix export (`x`) is already
`:LibBrowse`'s `gq`.
