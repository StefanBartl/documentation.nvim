# Reference tab — Lua syntax and LuaCATS tags

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
  report. [`docs/ANNOTATIONS.md`](../../ANNOTATIONS.md) is exactly that analysis
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

**The cheap version, if this never earns the full build:** a curated link
list and nothing else — no panels, no generation, no context menu. That is
worth having on its own, and it is honest about what most of the value
actually is: knowing *where* to look, not having the answer inlined. Targets
worth collecting are the Lua reference manual on `lua.org` (5.1, see the
version note below), LuaLS's own annotation documentation, and Neovim's
`:help luaref` / `:help lua-guide`. Exact URLs need checking before they
ship — a dead link in a reference panel is worse than no panel, and this
repo already has a `dead-readme-link` check because that lesson was learned
once.

Note this fallback does **not** subsume the tag panel's argument. A link to
LuaLS's documentation says what LuaCATS supports; it says nothing about what
*this scanner* reads, which is the smaller and more useful set, and the one
that can drift.

**One thing to decide before writing a single link:** which Lua version.
Neovim runs LuaJIT, i.e. 5.1 plus selected 5.2 extensions — so
`lua.org/manual/5.4` is the wrong target in a way that actively misleads
(`goto`, integer division, and the `<close>`/`<const>` attributes all read
as available). Pin to the 5.1 manual, mark the 5.2-isms Neovim does
provide, and link `:help luaref` and `:help lua-guide` alongside, which are
the versions that are actually correct for the runtime.

---

## Implementation status and plan (checked 2026-08-15)

**Not built.** Verified against source, not assumed: `docs/FEATURES/CORE.md`
catalogues every tab the generated page has (Compare, Hierarchy hide/dim,
Plugins/Tools/Telemetry Analysis panels, Features, promoted feature tabs,
Module Calls, Loaded) and none of them is a Reference tab; `grep -n
reference lua/documentation/core/render/html.lua` finds only unrelated uses
of the word (cross-reference popups, prose-reference affordances, type
references between fields) — no tab, no `TAGS` table, no keyword list, no
right-click "what is this" affordance. `functions.lua` still recognises
tags in the `if/elseif` chain this document names as the precondition for
the tag panel, not yet a dispatch table.

### Effort and benefit, per the two panels this document already splits apart

| | Effort | Benefit | Quick win? |
|---|---|---|---|
| `TAGS` table refactor (precondition for the tag panel) | S–M | Enables two features at once (see below) | No — real work, but see next row |
| LuaCATS/EmmyLua tag panel, once `TAGS` exists | S | High | **Yes, once the precondition lands** |
| Lua syntax crib sheet (keyword/operator/stdlib lookup panel) | S | Medium | Candidate |
| Right-click "what is this" on rendered annotations | S | High | Candidate — needs the tag panel first |
| Curated link-list fallback (no panels, no generation) | XS | Low–Medium | **Yes, standalone** |

**The `TAGS` table refactor is not only this feature's cost — it pays
twice.** [`IDEAS_IMPLEMENTATION_PLAN.md`](IDEAS_IMPLEMENTATION_PLAN.md)
independently rates §2.1 (an annotation-adoption Analysis panel, generated
rather than hand-written like `docs/ANNOTATIONS.md` is today) as the
highest-value panel idea in that backlog, gated on the exact same
refactor. Building the `TAGS` table once and pointing both the tag-reference
panel here and the adoption panel there at it is cheaper than either
document's own estimate assumes in isolation, and building it twice would
be the kind of duplication this plugin's own conventions warn against
elsewhere. **Recommendation: sequence the `TAGS` table refactor as its own
small piece of work, then both panels become independent quick wins.**

**The tag panel earns "quick win" the moment its precondition exists** —
the IR is already in the page, so "which tags does this tree actually use"
is a filter over data already present, not new extraction. The keyword
panel is genuinely static (this document's own honest framing: "the first
thing in the map that is not derived from the scanned tree") and does not
share that argument — it is cheap in isolation but has the weaker
proximity case, since nothing links to it from elsewhere in the page until
the right-click affordance exists, and that affordance is scoped to reach
only the tag panel, not the keyword one (this document's own "But this
only reaches the tags" section already establishes why).

**If only one piece ships, the curated link-list fallback is the one to
build.** No panels, no `TAGS` table, no context menu — a handful of checked
URLs (the Lua 5.1 manual, LuaLS's own docs, `:help luaref`/`:help
lua-guide`), pinned to the correct Lua version this document already
insists on. Honest about what most of the value actually is — knowing
*where* to look — and small enough to not need a phase of its own. This is
the one candidate in this section that does not depend on anything else
here landing first.

**Recommended sequencing, if this is picked up:** curated link-list first
(ships alone, zero dependencies) → `TAGS` table refactor (shared
precondition, do once) → LuaCATS/EmmyLua tag panel (immediate payoff once
the table exists) → right-click affordance (reaches the tag panel only) →
Lua syntax crib sheet last, since it is the one piece whose case is
"proximity, not necessity," and the weakest claim on being built at all
per this document's own "objection to answer before building it."
