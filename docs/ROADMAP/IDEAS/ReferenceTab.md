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

---

## The lookup layer — revision 2026-08-18

### The objection above expired, and this document did not notice

Two sections up, this document turns the keyword panel down on proximity
grounds, and the argument is explicit: *"It renders no Lua source: an inline
syntax-highlighted source view was considered and turned down, so there is
nowhere in the map a `goto` or a `<close>` is displayed to click on."*

**That is no longer true.** `core/snippet.lua` exists, and
`core/render/html.lua` renders `fn.snippet` into a `.fn-snip` block for every
function that has one — bounded to 40 lines, escaped, unhighlighted, but
present. The map ships source now. Both language backends feed it (`snippet.
extract` is shared between `functions.lua` and `core/lang/ecma.lua` precisely
because the bounding rule is a policy, not a per-language fact).

So the weakest claim in this document — that a keyword reference would be
reachable only by opening a tab and looking — no longer holds. Every `goto`,
`<close>`, `pcall`, `await` and `=>` in the tree is already on screen,
already in a container this page controls, and already escaped into DOM this
page builds. What is missing is only the layer that recognises them.

Recorded rather than quietly edited into the sections above, for the same
reason Part 3 of `MULTILANG.md` is recorded rather than folded into Part 1: a
stale estimate that gets silently overwritten leaves no evidence that the
premise moved.

### One layer, four trigger surfaces

The instinct is to call this "keyword tooltips" and build it. The cheaper and
more defensible shape is to notice that the page has **four** places where
the reader meets notation they may not recognise, and that all four want the
same thing: a short definition, in place, with an optional link out.

| Surface | Trigger | Data behind it |
|---|---|---|
| **Source snippets** (`.fn-snip`) | a language keyword — `goto`, `<close>`, `await`, `yield` | a per-language keyword glossary (new) |
| **Source snippets** | a standard-library call — `table.concat`, `Object.entries` | a per-language stdlib glossary (new); `calls_external` already knows which ones this tree actually uses |
| ~~**Rendered annotations**~~ | a `@deprecated`/`@async`/`@nodiscard`/`@internal`/`@since` badge | **built 2026-08-20** on `core/tags.lua`. The badges *are* the tags, so they are the trigger — a reader who does not know what `nodiscard` promises is looking straight at the word. `@param` and type strings are not triggers yet: those are rendered as structured sections rather than as the tag's own name |
| **Drift findings** | a check id — `param-name-mismatch`, `layer-violation` | the check catalogue, which `MULTILANG.md` Part 4's stage 3.6 and `I18N.md`'s I18N-0 are *both* about to introduce anyway |

Four features or one depends entirely on whether the lookup is a registry or
four hardcoded tables. It should be a registry: `lookup(kind, key)` returning
`{ summary, anchor? }`, with the four kinds registered from four places. The
alternative — a tooltip implementation per surface — is the shape this
repository's own conventions warn about elsewhere, and it would be four
independent places to forget a language when a backend is added.

### Where the glossary data lives

On the language backend, as an optional field, reached through
`core/lang_registry.lua` like everything else:

```lua
---@field keywords table<string, Documentation.Glossary.Entry>?
---@field stdlib   table<string, Documentation.Glossary.Entry>?
---@field reference Documentation.Glossary.Reference?
```

Three consequences, each deliberate:

- **A backend without a glossary degrades to nothing, not to a wrong
  glossary.** The fields are optional; an unrecognised token is simply not
  decorated. No fallback to Lua's keywords for a Rust file, which is the one
  failure mode that would be worse than the feature's absence.
- **It goes into the page, not into `module_map.json`.** The glossary is
  tool data, not scanned data — it is the same bytes in every checkout, so
  putting it in the IR would inflate a byte-deterministic artifact with
  content that says nothing about the repository. `html.lua` inlines it
  directly, the same way it already inlines everything else the page needs.
- **The layer rule holds.** `core.render.html` must not require
  `core.lang.*`; it asks the registry, which is exactly the seam that already
  exists for `scan.lua` and `check.lua`.

### The governing principle: density on demand, never on screen

The goal behind all of this is to get as much out of a file as the file
actually contains. The constraint is that no view may become unreadable in
the process. Those two only coexist under one rule, and it is worth stating
once here rather than re-arguing per feature:

**Everything in this section is reachable by an intentional act — hover,
right-click, a key — and nothing in it adds permanent chrome to a view.**

Concretely, what that forbids: a new badge row, a new always-visible column,
a second line under every function, an icon per token. What it permits: any
amount of depth behind a deliberate gesture, because a reader who did not
gesture pays nothing for it.

There is already a precedent in the page, and it is the model to copy rather
than invent around: the Deps and Module Calls views' `+ external` toggle
shows a plain box, and only a hover breaks it down into *which* functions
were called and how often (`plenary.async.run (2×)`). The dense answer exists,
costs nothing until asked for, and the view stays a graph.

Four rules that keep it that way:

- **One card component, one card at a time.** Every lookup below renders into
  the same popup, with the same dismissal, the same maximum height. Four
  bespoke tooltips would re-create the clutter this rule exists to prevent.
- **Bounded, like `snippet.lua` already bounds source.** A card that can grow
  to forty lines of type detail is a panel wearing a tooltip's clothes. Cap
  it, and say how much was omitted — the same policy `snippet.lua` and
  `docs.lua`'s `REFS_PER_ENTITY` already apply.
- **Never on hover-through.** A card that opens while the pointer is merely
  crossing the region is chrome the reader did not ask for. Intent means a
  short dwell, or a click.
- **Absent data says so, in place.** A hover with nothing behind it shows
  "not known", not an empty card and not nothing at all — the same posture
  the Telemetry tab already takes when no Neovim session collected anything.

### The rest of the family — all from data the IR already has

The keyword and stdlib glossaries are new data. Everything below is not: it
is already extracted, already in the artifact, and currently only reachable
by navigating somewhere else. That makes these the cheapest entries in this
entire document — no scanner work at all, only a trigger and a card.

| Hover target | What it shows | Where the data already is |
|---|---|---|
| A call in a snippet that resolves inside the tree | callee's summary, its module, a jump | `ir.edges` call resolution — the Calls view already draws exactly this |
| An external module in a snippet or `require` | which of its functions this file actually calls, and how often | `calls_external` — the `+ external` tooltip already renders this shape elsewhere |
| A type name in a signature or annotation | its `@class` fields and where it is declared | `types_detail`, present whenever the map was generated `--full` |
| A function's own name in the snippet header | its complexity, fan-in/fan-out, whether a test names it | the Analysis tab computes all four over the same IR |
| A `require`/`import` path | resolved in-tree, external, or unresolved — three different answers currently indistinguishable at a glance | `requires`, `requires_external`, and the absence of both |
| A `@deprecated` / `@internal` marker in a snippet | what it means here, and who still calls it anyway | the tag plus `required_by` |
| A line in the snippet | the commit that last touched it | git — **only where a host can run it**, which is `:DocMap serve` and `docmap-desktop`, not a published page. Degrades to "needs a host", the message this page already has for History |

And the language-specific ones, which are the reason the glossary sits on the
backend rather than in one shared table — each is meaningless in every
language but its own:

- **Lua:** `:` vs `.` on a call, varargs, metamethod names, `<close>`/
  `<const>` (and the LuaJIT caveat this document already insists on).
- **JS/TS:** `async`/`await` semantics, `=>` binding of `this`, `?.`/`??`,
  TS's `satisfies`/`as const`, decorators.
- **Python:** decorators, `self`/`cls`, dunder methods, `*args`/`**kwargs`.
- **Rust:** lifetimes (`'a`), `&`/`&mut`, `?`, `impl Trait`, `unsafe`.
- **Go:** receivers, `defer`, channel operators, exported-by-capitalisation.
- **C:** storage classes, `const` placement, macro vs. function.

These are also the clearest argument that this feature belongs *with*
`MULTILANG.md` rather than beside it: a language backend that ships an
extractor and no glossary is a language the reader can see but not ask about.
Make the glossary part of what "supporting a language" means, from the second
backend onward.

### Links, and the staleness objection — answered, not waved away

The concern is real and this repository has already paid for it once: the
`dead-readme-link` check exists because a dead link shipped. A reference
panel full of 404s is worse than no panel, and the sections above already
insist that exact URLs be verified before they ship.

Three rules that make linking survivable:

1. **The explanation never depends on the link.** One sentence of our own
   prose, offline, in the artifact. The link is an enhancement; if every URL
   on the internet broke tomorrow the feature would still answer the question
   it exists to answer. This is the same two-tier shape `docs/ECOSYSTEM.md`
   §3.5 already uses for hover previews — always-available tier first,
   enhancement second.
2. **One base URL per language, anchors derived.** Not one URL per keyword.
   `goto` links to `<lua-5.1-manual>#pdf-goto`, `await` to
   `<mdn-js-reference>/Operators/await`. Then the surface that can rot is a
   handful of base URLs, checkable by one CI gate, instead of several hundred
   independently rotting links. An anchor that moves degrades to landing on
   the right page at the wrong position — a much softer failure than a 404.
3. **Version-pinned, per this document's own existing insistence.** Neovim
   runs LuaJIT: 5.1 plus selected 5.2 extensions, so the 5.4 manual is
   actively misleading about `goto`, integer division and `<close>`. The Lua
   glossary pins 5.1 and marks the 5.2-isms Neovim does provide. For JS/TS
   the equivalent question is which reference — MDN is the stable answer and
   its URL structure has been stable for a decade, which is a fact to check
   at implementation time rather than assert here.

A fourth rule if the base URLs turn out to rot anyway: ship the anchors and
make linking opt-in (`opts.reference_links = false` to suppress). Not built
unless it is needed — recorded so the fallback is not re-derived under
pressure.

### Sequencing

The keyword surface is now the *cheapest* of the four, not the weakest: the
source is already rendered, the container already exists, and unlike the tag
panel it needs no `TAGS` refactor first. That inverts this document's
"recommended sequencing" above, which put the syntax crib sheet last
specifically because of the proximity argument that has since expired.

1. **Lookup registry + keyword glossary for Lua, in-place hover on
   `.fn-snip`.** No new tab, no `TAGS` table, no context menu. Self-contained.
2. **Same for JS/TS**, which is one more table against the existing `ecma.lua`
   registrations and proves the per-language seam.
3. ~~**Stdlib glossary**, same machinery, larger table.~~ **Built
   2026-08-18.** The tokenizer grew dotted-run matching, longest prefix
   first, with the undecorated tail emitted plain — `vim.uv` matches inside
   `vim.uv.fs_stat` and the card does not claim to describe `.fs_stat`.
   Entries were chosen by counting real use, not by transcribing a manual.
   Neovim's API sits in Lua's glossary marked `origin = "Neovim"`, which is
   also what withholds the Lua-manual link from it: a reader pointing at
   `vim.split` must not be sent to lua.org.
4. ~~**`TAGS` table refactor**~~ — **built 2026-08-20** as
   `core/tags.lua`, and it paid all three times as predicted: this document's
   tag panel, `IDEAS_IMPLEMENTATION_PLAN.md` §2.1's adoption panel, and the
   lookup layer's third kind. The catalogue already rides on the page as
   `IR.tags`, so both remaining consumers are now what their own estimates
   claimed they would be once the precondition landed.

   Two things the entry did not anticipate. **The catalogue needs an
   `origin` field**: half these tags are this project's own conventions, and
   a LuaLS link for `@todo` would load, look authoritative and answer
   nothing — the same rule the stdlib glossary already applies to `vim.*`.
   And **the parsing stays in `functions.lua`**: the handlers close over one
   doc block's accumulators, so what the two halves share is the name list,
   asserted in both directions rather than merged.
5. **Check catalogue as the fourth kind** — land it with `MULTILANG.md` 3.6
   and `I18N.md` I18N-0, which are already required to touch the same data in
   one pass.
6. **The Reference tab itself**, if the panels still earn a tab once the
   in-place lookups exist. Genuinely open: the hover may be most of the value,
   and a tab nobody navigates to was this document's own warning.

The curated link-list fallback stays what it always was: the version to ship
if none of the above happens.
