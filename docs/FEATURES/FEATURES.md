# documentation.nvim — shipped features

A ledger of what's been built, why it was built that way, and (where known)
the commit it shipped in. For *how to use* any of this, see
[`docs/PIPELINE.md`](../PIPELINE.md) — this file is the decision record, not a
usage manual, so it stays short per feature: the interesting trade-off, not
the full narrative. Full history (verification steps, exact test counts, etc.)
lives in git log, not here.

Carried over from lib.nvim's `docs/ROADMAP/docmap_features.md`, which was
itself extracted from `docmap_roadmap.md`/`docmap_roadmap_next.md`; the
original, much longer process narrative each entry below compresses is in
lib.nvim's git history.

> **Names in this file predate the extraction** (2026-07-28). Where it says
> `docmap`, `:LibMap` or `lib.nvim.docmap`, read `documentation`, `:DocMap`
> and `documentation.*`.

## IR & data model

- **Edge kinds** (`require`, `call`, `type`, `extends`) — one discriminated
  `ir.edges` array instead of parallel fields, so layout/filter/draw logic
  exists exactly once per concern instead of once per edge type.
- **Require-graph** (`deps.lua`) — extracted per-file (not into a throwaway
  global set like the old `check_orphans` did), with line numbers. Enables
  `require-cycle` (Tarjan SCC), `require-not-declared` and opt-in
  `layer-violation` checks nearly for free.
- **Call-graph** (`calls.lua`) — treesitter-based (LuaLS's own `--doc` misses
  most of this repo's functions). Alias-resolves `local fs = require(...)`
  before matching call sites; deliberately **discards** unresolvable
  receivers rather than guessing. Confidence is tracked (`exact` vs.
  `heuristic`); the heuristic fallback (name matches exactly one function in
  the tree) is **opt-in**, default off — "a wrong call graph is worse than an
  incomplete one."
- **`extends` edges** (inheritance) — parents live on `defines[1].extends`
  (an array, for multiple inheritance), not `entry.extends` as originally
  guessed; verified against real `lua-language-server 3.18.2` output before
  writing code. An `@alias` never carries `extends`, even when it aliases a
  class.
- **Deferred vs. load-time requires distinguished** — a `require()` inside a
  function body (lazy) is a real edge but drawn differently (dotted) from a
  top-level one; the cycle check only complains about load-time cycles.
  Comment-only `require(...)` mentions (doc examples) are excluded.

## Checks (`check.lua`)

All info/warn severity, never error, unless noted:
`require-cycle`, `require-not-declared` (see its own entry below — this file
claimed it for a long time before it existed), `layer-violation` (opt-in),
`dead-function` (a function with zero resolvable callers — scoped carefully:
always flags unreferenced `local function`s and `@internal`-tagged ones,
only flags ordinary exported functions under `opts.dead_code = true`, to
avoid flagging half the public API), `param-name-mismatch` (positional
comparison of the nth `@param` against the nth real parameter — not a set
comparison, which would silently pass two swapped parameters), plus the
pre-existing `missing-summary`/`undocumented-param`/`missing-readme`.

## Hierarchy tab — six views

`Modules` (children edges) / `Types` (collaboration, `kind="type"`) / `Deps`
(`kind="require"`) / `Calls` (`kind="call"`, per-*function* boxes, not
per-module) / `Inheritance` (`kind="extends"`, its own layout — doesn't use
the shared `walk()`, since a module typically declares a base class *and*
its subclasses together, which `walk()`'s per-seed-layer-0 model would
otherwise collapse onto one row; depth here is longest-path-from-a-
parentless-class instead, verified correct on a 3-level diamond fixture) /
**Module Calls** (Session 2026-08-10 — same `kind="call"` edges as Calls,
collapsed module-to-module and weighted by call count: five call sites
between two modules draw one arrow labelled "5 calls", visually thicker via
`stroke-width = min(1.5 + log2(weight)*1.1, 7)`, not five overlapping
lines). The roadmap item that requested this
("Gewichtete Alternativ-Ansicht des Call-Graphen") asked for its own tab;
shipped instead as a sixth Hierarchy view reusing the existing
zoom/pan/hide-dim/context-menu/SVG-export machinery — decided with the user
on the grounds that the view is exactly as centered-on-a-node/directed/
depth-limited as Deps already is, and a new tab would mean either
duplicating that machinery or generalizing it for one caller. `+ external`
(off `node.calls_external`, summed per (node, module) pair since a module
can call several distinct external functions where `requires_external` is
already a deduplicated name list) works the same way it does on Deps.

- **Direction** (`in`/`out`/`both`) and **depth** (1/2/3/∞, `MAX_HNODES=90`
  hard cap) as orthogonal toolbar axes for Deps/Calls, not separate views.
- **Backedges** get their own routing (lateral, not through boxes) and CSS
  class — the layered BFS is tree-shaped, require/call graphs aren't.
- **Keyed reconcile** (FLIP-style) instead of `innerHTML = ""` + rebuild:
  boxes tracked in a `Map<key, HTMLElement>`, enter/update/exit sets, CSS
  `transition` on `left`/`top` for the "boxes visibly migrate" feel. Edges
  are hidden during the move and redrawn after (not path-interpolated —
  cheaper, no framerate risk at 90 boxes).
- **Context menu** (right-click) — `describeTarget(el)` classifies the
  clicked element, entries filtered to what's actually available; disabled
  (not hidden) with an explanatory label when data is missing (e.g. no
  LuaLS run yet), same pattern the Types view already used.
- **Semantic zoom** — mouse-wheel geometric zoom (`transform: scale()` on a
  `#hstage` layer, position math untouched) plus a **separate** semantic
  zoom: crossing an asymmetric threshold with hysteresis
  (`DRILL_IN z≥1.80 → z:=0.90`, `DRILL_OUT z≤0.55 → z:=1.15`, 260ms cooldown)
  re-centers on the module under the cursor. Naive symmetric thresholds
  flicker; the fix was firing only on *crossing* the threshold, not on
  being in a state past it — otherwise any further wheel motion in *either*
  direction re-triggers. Drilling on the already-centered box is a no-op,
  not a reset. Deps/Calls map the same gesture to `depth ±1` instead (a
  require graph has no "one level in/out" the way a tree does).
- **LOD** — below ~0.65 scale, box detail lines hide (name only); pure CSS
  class toggle, no re-render.
- **Root-level hide slider** (Session 2026-08-10, Modules only) — a
  vertical Google Maps-style slider peels the top N layers off the real
  tree, turning every node that used to sit at that depth into its own
  parallel root (`layoutModulesRooted`/`rootFrontier`, both built on a new
  `layoutModulesFrom(seeds)` the old single-seed `layoutModules` now
  delegates to). Mutually exclusive with centering on a specific node —
  `navigate()` clears one axis whenever a patch sets the other.

## Navigator (`:LibBrowse`)

Editor-side counterpart to the HTML page — `layout.mount` (list/detail/
status, 3 slots), same modes as the browser (`1`-`4` = Structure/Deps/Calls/
Types, plus a 5th, History), `j`/`k` move with detail following immediately,
`<CR>` drills in or follows an edge, `-`/`<BS>` out, `<C-o>`/`<C-i>` visit
history, `h`/`l` direction, `+`/`_` depth, `gd` opens source (closes the
view — floats sit over the whole editor, "jump to a file you can't see"
isn't a jump), `gq` current list → quickfix, `/` fuzzy-jumps via
`ui.kit.picker`.

- **Artifact-first, not scan-first.** `module_map.json` read (~10ms) beats a
  live `scan()` (~0.65s, measured) by ~65×; `:LibBrowse live` opts into
  `install({watch=true})` when the 0.65s is acceptable. A live-file mtime
  check flags a stale artifact instead of silently showing wrong data.
- **History mode** (`:LibBrowse history`) — commit list → functions a diff
  touched (with caller counts) → `<CR>` on a function leaves History for
  **Calls (incoming)** rather than building a third bespoke "callers" list —
  same underlying question, already-answered by an existing mode.

## Analysis tab

Tool-selector toolbar (not a diagram) — panels are tables/rankings over the
IR, not graph boxes; closer to the Notes tab than the Hierarchy tab
architecturally. Five tools shipped, each a pure `ir -> result` function
(same shape as a `Check`, result is a table instead of a findings list):

- **Test coverage** (`coverage.lua`) — `fn.tested` via the same
  identifier-counting technique `calls.lua` already uses, run against
  `TESTS/*_spec.lua` instead of the source tree. Replaces the manual
  `@test` tag (0 real uses in the wild) without removing the tag itself.
  Renders only a positive "tested" badge, never an "untested" warning — the
  heuristic has a real, documented blind spot (indirectly-tested functions
  never named in a spec), and a warn-badge on most of ~600 functions would
  be noise, not signal.
- **Documentation coverage** (`doccoverage.lua`) — one definition of
  "documented" shared by `M.resolve` *and* `M.summary` (so they can't drift
  apart), matching the three existing findings exactly rather than
  inventing a second, possibly-different rule. `@return` deliberately
  excluded — unlike parameters, there's no structural fact in the raw
  signature to check an `@return` line against. Optional `coverage.svg`
  badge, hand-drawn rather than fetched from shields.io (a network call
  during `scan_full()` would make `--check` network-dependent).
- **Fan-in/fan-out** (`renderAnalysisDeps`) — pure client-side aggregation
  over already-serialized `n.requires`/`n.required_by`, no new Lua
  extraction. Sorted by fan-in descending (the module with the most
  dependents first — "what breaks most if I touch this").
- **Code duplicates** (`duplicates.lua`) — see its own entry below.
- **Cyclomatic complexity** (McCabe: 1 base + one point per
  `if`/`elseif`/`while`/`for`/`repeat` + one per `and`/`or`) — node types
  verified empirically against a real parsed tree before writing the
  query, not guessed. Computed unconditionally during the main scan (needs
  the treesitter node itself, which only exists during that one pass),
  unlike the other three tools which resolve lazily. Ranks by *function*,
  not module average — a module average would hide the one genuinely
  complex function inside an otherwise healthy module.

## Notes & Index tabs

- **Notes tab** — `@deprecated` (pre-existing data, never collected before)
  plus new `@todo`/`@bug`/`@test` tags. These are **arrays**, not
  `string?` — a function with two open todos has two todos; a scalar would
  silently drop the second. Verified `lua-language-server` neither knows
  nor warns about the new tags before introducing them (a tag that
  triggers an LSP warning on every use would defeat the point). Empty
  sections render an explicit "nothing here" instead of disappearing, so
  "genuinely empty" stays distinguishable from "not collected."
- **Index tab** — alphabetical, by **bare name** (`M.read` sorts under
  **R**), not the raw identifier — the `M.` prefix is this repo's local
  convention, not part of the function's actual name; sorting by raw
  identifier would collapse the majority of entries onto "M". Names with a
  non-alphabetic start (`_evict`) get their own `#` bucket instead of being
  dropped. A second, module/namespace-level A-Z index exists alongside the
  function index (same jump-bar code, reused not duplicated).

## Cross-project linking (`tagfiles.lua`)

`opts.tag_files = { "prefix" = "path/to/other/module_map.json" }` resolves
an otherwise-inert `requires_external` box against another project's own
committed map, turning a dead gray box into a real, clickable link into
that project's page. Deliberately **local paths only, no URLs** — a network
fetch during `scan_full()` would make `--check` network-dependent, the same
reasoning that kept the DOT export decoupled from an actual `dot` binary.

## Commands

`:LibMap` (generate), `:LibMap check`/`full` (drift-check / LuaLS-enriched
run), `:LibMap open` (prefers a running `:LibMap serve` over `file://`),
`:LibMap graph {deps|calls} [module]` (opens the HTML view pre-centered),
`:LibMap why <a> <b>` (shortest require-path between two modules — BFS,
distinguishes load-time from lazy edges in the answer, since that's the
difference between "must go" and "fine as-is"), `:LibMap diff <ref>`
(structural diff between two revisions — modules/functions/deps/cycles/
blast-radius added or changed; tolerates older schema versions rather than
failing on them), `:LibMap impact [ref]` (→ quickfix: what a diff touches,
transitively, live-computed, no artifact needed — default `ref` is `HEAD`,
so a clean tree's blank `:LibMap impact` answers "what does my uncommitted
work affect"), `:LibMap serve [stop]` (local-only HTTP server, see below),
`:LibMap graph --dot` (Graphviz export), `:DocMap churn [range]`
(churn x complexity ranking -> quickfix; see its own entry below).

## Commit history with blast radius (`history.lua`, `:LibMap serve`)

The one feature Doxygen doesn't have: click a commit, see which functions
it touched, who calls those functions, which modules that reaches
transitively.

- **Can't be embedded in the committed artifact** — `--check` byte-compares
  committed vs. freshly-generated output; embedding `git log` data creates
  a commit that invalidates its own artifact the moment it lands (no fixed
  point exists). Ruled out the "just add a History tab like the others"
  approach specifically, not the browser view as a whole.
- **A `file://`-origin page can't `fetch()` a neighbor file either**
  (opaque origin, CORS blocks it in real browsers) — ruled out "cache file
  next to the HTML" as the workaround.
- **Resolved with a real (but strictly local) HTTP server**
  (`serve.lua`, ~150 lines on `vim.uv`, no new dependency) —
  `:LibMap serve` binds `127.0.0.1` only (never `0.0.0.0`), validates
  `<sha>` against `^[0-9a-f]{7,40}$` before it ever reaches `git` (verified
  against real injection attempts with curl: `--upload-pack=…`, `$(id)`,
  `abc;id`, path traversal, oversized/undersized hashes — all rejected with
  400, none reach git), rejects `HEAD` too (a whitelist with exceptions
  isn't one), and tears down on `VimLeavePre`.
- **Costs are lazy** — a commit detail costs ~0.3s (measured), computed on
  click, vs. ~25-50s to precompute all resolvable history up front. This is
  *why* the server approach won over a static snapshot file, not just a
  nice property of it.
- **Three degrade states, not one**: exact attribution; *approximated*
  (older commits before `fn.line_end` existed — approximated as "next
  function's start minus one," verified this never over- or
  under-attributes on real commits including a pure-insertion one that
  correctly reports zero approximation); and *revision older than the map*
  (degrades to "files only," doesn't error on a missing parent artifact).
- **`:LibBrowse history`** is the editor-side equivalent — no server
  needed (the editor never had the `file://` origin restriction); `<CR>`
  on a touched function leaves History for Calls-incoming rather than
  building a redundant third view.

## Reuse & operations

- **`install()` / `uninstall()`** — programmatic entry point returning a
  live handle (`handle.ir()`, `.node(id)`, `.on_change(fn)`); `watch=true`
  attaches a debounced `BufWritePost` autocmd instead of requiring a manual
  `:LibMap` per edit. `command.setup()` (what `:LibMap` itself is) is now a
  thin `install({watch=false})` call, so lib.nvim's own behavior didn't
  change when this was added underneath it. Idempotent teardown by design.
- **`cli.lua`** — the `--check`/`--full` logic extracted out of
  `scripts/gen_map.lua` into `run(opts, argv) -> exit_code`, with no
  `vim.cmd("cq …")` inside it (that stays the caller's job, so the function
  itself stays plain and testable). `scripts/gen_map.lua` itself shrank to
  3 lines that any consuming plugin copies verbatim.
- **Reusable pre-commit hook template** — three variables
  (`SOURCE_DIR`/`OUT_DIR`/`GEN_SCRIPT`) at the top of
  `scripts/hooks/pre-commit`, everything else generic shell. Deliberately
  **checks, doesn't regenerate-and-stage** — a hook that regenerates and
  stages produces diffs nobody intended, and interacts badly with
  `--amend`/rebases. Local (`core.hooksPath`) chosen over a tool like
  `lefthook` specifically *because* this needs to be portable to whatever
  repo copies it — `lefthook` would impose an extra dependency on every
  *consumer* of `lib.nvim`, not just this repo.
- **DOT/Graphviz export** — same edge-walking core as the Mermaid renderer;
  gives ranking/clustering/print-quality output Mermaid and the in-browser
  layered-BFS both lack.
- **`gO`** — jump from `:LibBrowse` straight into the HTML page at the same
  mode/center/direction/depth/function, since the browser page's entire
  state already lives in its URL fragment; effectively `format()` +
  `:LibMap open`.

## Tag adoption

`@internal` propagated to the function level (previously module-level
only) — applied to the 15 exported functions in the one directory
(`lua/lib/lua/time/diff/internal/`) that's actually a real, non-anonymous
`internal/` convention match; incidentally surfaced two already-dead
functions there, left in place (cleanup wasn't this task's job, the
`dead-function` finding now correctly names them). `@todo`/`@bug`/
`@deprecated` adoption: genuinely nothing to convert — every "deprecated"/
"legacy" mention in the tree turned out to reference a Neovim API
deprecation being worked around, not a `lib.nvim` function actually
replaced by another. `@see`: one real pair added
(`fs.scan_cached.scan` ↔ `fs.scan_roots.scan`, session cache vs.
disk-persistent cache of the same walk) where the module headers already
described each other as counterparts but never linked at the function
level.

## Extraction into a standalone plugin (2026-07-28)

`lib.nvim.docmap` -> `documentation.nvim`. A rename rather than a rewrite,
which is the whole point of the result: `opts.root`/`opts.source`/
`opts.extra_checks` existed so that nothing here knew lib.nvim's layout, and
the only file that did know was `config.lua`.

Three things genuinely changed, all consequences of no longer being a
library's own submodule:

- **`config.lua`** went from one repository's options (plus its
  repo-specific `type-not-exported` check) to a generic default builder.
  `source` is derived from the root — `lua/<name>` when `lua/` holds exactly
  one candidate directory, `lua` otherwise — so `:DocMap` works in a checkout
  nobody configured. Deliberately shallow: one probe, no walking. A wrong
  guess that looks confident is worse than an obvious default overridden once.
- **Root resolution inverted.** `command.setup()` walked up from its own
  source file, which was correct while the mapped tree was always the one it
  lived in. Installed under a plugin manager that resolves to the plugin's own
  checkout, so the default is `vim.fn.getcwd()`. This is also why
  `:checkhealth documentation` prints the resolved config — the failure mode
  it introduced is invisible from `:DocMap`'s own output.
- **`setup()` on `init.lua`** as the plugin entry point.
  `require("documentation")` alone still registers no command.

lib.nvim stays a **runtime dependency**. Vendoring buys a standalone plugin at
the price of a second maintenance site for code that already exists, and every
sibling plugin already depends on it. The headless runners cannot assume a
plugin manager, so they resolve it from `$LIB_NVIM_DIR`, `.deps/lib.nvim` or a
sibling checkout.

Three spec assertions turned out to be about lib.nvim's *tree* rather than
about the code, and failed the moment the suite ran anywhere else — the
commit-list row count (`> 1`, true for a ~95-commit history), the
`gI`/detail-pane agreement check (first three rows of one fixed module), and
`lib.nvim.fs` as the namespace fixture. Fixed as portability bugs, not
renamed.

## `?` key-hint overlay and `:checkhealth documentation` (2026-07-28)

The two items the roadmap's wayfinder survey ranked cheapest-and-most-valuable.

**`?`** renders from the same `KEYS` table `bind()` installs from. That is the
whole design: a hand-maintained second list of keys is exactly the drift this
plugin exists to detect, and shipping one inside it would be hard to defend.
The spec asserts the claim rather than a comment doing it — every key bound on
the list buffer must appear in the panel. Writing that test immediately turned
up that `nvim_buf_get_keymap` + `keytrans` round-trips `<CR>` as `<lt>CR>` and
`<C-o>` as `<C-O>`, so the comparison normalises both.

Keys the current mode ignores are **marked, not hidden** — "why did `+` do
nothing" is the question the overlay is opened to answer, and a key that has
vanished reads as one that was never there. They stay *bound* in every mode
too: the handlers already gate themselves, and an unbound key falls through to
Vim's own meaning, where `+` moves the cursor down a line.

**`:checkhealth documentation`** covers the dependencies and the treesitter Lua
parser (not optional the way `lua-language-server` is — without it the map
renders a tree of modules with no functions, which looks like a scanner bug),
then the section it exists for: the resolved configuration. Staleness there is
an mtime comparison and says so; `:DocMap check` is the authoritative answer
and costs a full scan, which is not what a health check should spend.

## Trail and Saved Trails (2026-07-28)

Wayfinder survey items 2 and 3. `p` pins the entry under the cursor in any
mode, `6` lists them, `d` unpins, and the count rides along in every other
mode's status line — a trail invisible from where you pin is a feature with no
feedback. One `p` rather than wayfinder's `p`/`a`/`A`: pressing it on something
already pinned has exactly one sensible meaning.

Deliberately **not** `<C-o>`/`<C-i>`. The history stack answers "where was I a
moment ago" — automatic, time-ordered, truncated by the next move. A trail
answers "where do I want to get back to" — deliberate, and only an explicit
unpin removes an entry. Reading a dependency graph produces dozens of history
stops and about four places worth returning to.

- **A pin is a view, not a subject** — mode and axes (`dir`/`depth`/`sha`)
  travel with it and `<CR>` restores all of them. Half-restoring is what makes
  bookmarks feel unreliable.
- **Identity is narrower than the record.** `dir`/`depth` are on the pin but
  not in its key, so the same node at two depths toggles one bookmark instead
  of growing a near-duplicate nobody meant to create.
- **Keyed by repository root**, not by browser instance.

Persistence (item 3) did **not** land in `trail.lua` as the roadmap predicted,
because that would have cost the purity that lets the whole model be driven
from a headless spec. `trail_store.lua` subscribes to a new `trail.on_change`
instead — the indirection is also the more robust arrangement, since a mutation
added later cannot forget to persist. It reaches disk only through `M.path()`,
a function rather than a constant, which is what lets the spec point it at a
temp file instead of the user's real state directory.

- **`stdpath("state")`, never the repository.** A trail is navigation state
  with no more claim on the project than a jumplist has; committing it would
  put one reader's path into every checkout and give `--check` an opinion
  about it.
- **`L` adds, never replaces.** Replacing would silently destroy the trail
  built this session, and the alternative is a confirmation dialog nobody
  wants on a navigation key. Additive also composes — two saved trails load
  one after the other. `X` forgets a *saved* trail and never touches the pins
  on screen.
- **Hydration is once per root**, at `browse.open()`. Re-reading on every open
  would discard whatever was pinned since: the newest pins, the worst half to
  lose. A malformed file costs that root its pins and never raises — this
  lives where a full disk or an older version of the plugin can leave
  anything behind.

Two bugs the specs caught rather than the code asserting: `-` in the trail
silently moved the node axis under an unchanged screen (now a guarded no-op),
and `flush()` guarded on its in-memory mirror being loaded as well as on there
being dirty roots — so a pin made before anything had hydrated was reported as
written and dropped.

## Local list filter (2026-07-28)

Wayfinder survey item 4. `f` narrows the list on screen in place, with ANDed
terms, `-negation` and `"quoted phrases"`.

The decision that shapes it is what it is **not**. `/` is a fuzzy jump across
every module and function — "take me to the thing I can name". `f` answers
"show me less of what I am already looking at", and that wants plain
case-insensitive substrings: fuzzy matching is forgiving, and forgiveness is
wrong here, because the whole point of typing `-spec` is that nothing
containing "spec" survives it. No `OR` either — the reason to narrow a list is
to make it shorter, and every `OR` makes it longer.

- **Applied after the mode has built its list**, in `render`, never inside a
  mode. Every mode gets it for free and none of them has to know it exists —
  which is also why it ended up bound in all six rather than in Deps/Calls as
  the roadmap scoped it. Restricting it would have been extra code to do less.
- **Matches the row's label**, what is on screen, and nothing else. Filtering
  on data the row does not display would make rows vanish for reasons the
  reader cannot see, which is the failure this feature exists to avoid rather
  than to cause.
- **The status line always carries an active filter and its hidden count**,
  in all three of its shapes. This is the only view state that *removes rows*,
  so without it a narrowed list and a genuinely short one are the same
  picture. An empty result renders an explicit row, never a blank column —
  the same rule the HTML page's empty Notes sections follow.
- **It belongs to the list it was typed against.** Changing the subject
  (mode, node, function) drops it; changing an axis (direction, depth) keeps
  it. That asymmetry is the feature — re-seeing the same narrowing from the
  other direction is the reason to narrow — while carrying a query into a
  different module's list would present a short list as a complete one. The
  decision is made on what actually changed rather than on the patch, since
  `enter` can hand `go` an `id` equal to the current one.
- **It travels with positions in the visit history but is not a history
  stop.** Adding it to `SNAP_KEYS` removed special cases rather than adding
  them: `<C-o>` back onto a narrowed list finds it narrowed the same way, and
  stepping off drops it without anything having to remember to. Making the
  key itself a stop would mean `<C-o>` sometimes undoes a move and sometimes
  undoes typing.

One key rather than two: `f` opens prefilled with the query in effect, so
editing and clearing are one gesture. A separate clear key would only exist
because this one refused to show what it had — the reasoning that gave `p` a
single toggle.

`filter.lua` is pure, so the whole query language is driven headlessly,
including the lenient cases that only exist because it is typed live: an
unterminated quote runs to the end of the input, and a lone `-` is dropped
rather than negating a term not yet typed. The one UI-level assertion is that
`f` *opens* something — which is what keeps the `S`/`L`/`X` "opens nothing"
assertions honest, since those pass equally well on a key that was never bound.

## `require-not-declared` (2026-07-28)

Listed in this file as shipped since before the extraction, and never
implemented — confirmed by grep against `lib.nvim` at `eaab532^`, where it
appears in `docmap_features.md` and nowhere in the code. `check.lua` had
twelve checks; README and PIPELINE listed exactly those twelve. Only the
ledger claimed a thirteenth.

Built rather than struck out, because the gap it names is real: an
unresolvable `require()` lands in `requires_external`, which is also where a
genuine third-party dependency lands. Right for `plenary.async`, silently
wrong for `documentation.brwose.trail` — a typo, a rename, or a module deleted
while a caller kept asking for it. All three break at runtime and none of them
look different in the map.

- **Separated on the first path segment.** A require whose leading segment is
  one the tree declares as its own is a claim about this tree, and this tree
  is what the scan can be authoritative about. Whole segment, never a raw
  string prefix — `documentation` must not match `documentationx.util`.
- **`warn`, not `error`.** Same family as `require-cycle` and
  `dead-see-target`: a reference pointing at nothing. Error is reserved for
  the two checks about the tree's own contract (`missing-module-tag`,
  `module-path-mismatch`), and this one rests on a heuristic about namespaces.
- **The escape hatch already existed.** A project split across repositories
  under one namespace is the remaining false positive, and `opts.tag_files`
  is precisely the declaration that a prefix lives in another project's map.
  Matched with `tagfiles.lua`'s own rule rather than a second one.
- **Line numbers from `requires_raw`**, which is internal to the scan and
  never serialized. Checks run against the in-memory IR straight after the
  walk, so it is there — and a message without a line is useless, since one
  file can require the same missing module twice.

Zero findings on this repository, which is the correct answer and also why
the spec asserts both directions in one fixture: a file requiring both a
missing in-namespace module *and* a real external one. Asserting only the
positive would pass on a check that flagged every external require there is.

## Code duplicates (2026-07-28)

The first of the roadmap's two "expensive" Analysis-tab candidates, and the
only one of them that was ever buildable as a panel — see the churn entry.

It exists because this is the one shape of drift the rest of the plugin is
structurally blind to. Two modules that each grew their own `read(path)` fail
no check, fail no test, and produce nothing in any graph: the require graph is
silent precisely because neither one requires the other.

- **Compared on structure, never text.** `fn.shape` is a hash of the
  treesitter node types over a function's whole subtree, computed in
  `functions.lua` during the scan for the same reason `complexity` is —
  only there does the parse tree exist. Ignoring identifier and literal names
  is the whole point: a copy-paste gets renamed on the way in, so a detector
  finding only byte-identical bodies would find the one case nobody ships.
  Type-2 clones, what PMD's CPD reports by default.
- **Anonymous nodes included.** An operator is an anonymous child, so
  skipping them — the obvious reading of "node types" — would make `a + b`
  and `a - b` one shape.
- **Two independent hashes, not one.** A collision here does not degrade the
  answer, it fabricates one: "these two functions are identical" is a claim.
  Multiply-and-add rather than FNV's xor, so the arithmetic stays inside a
  double's exact-integer range without a bitwise library.
- **A size floor of 40 nodes**, a constant rather than an option. Below it a
  shared shape means nothing — every tree has a dozen one-line accessors that
  match each other — and measured here, no floor reports five groups where 40
  reports the two worth reading. A knob nobody knows how to set is worse than
  a documented default. `considered` ships alongside `groups` so "nothing
  found" stays distinguishable from "nothing was large enough to look at".
- **A panel, never a check.** Verified against this repo's own tree, which
  reported exactly two groups: `read(path)`, implemented identically in three
  modules — a real duplicate the plugin previously had no way to see — and
  `scan.lua`'s `is_dir`/`is_file`, which share a shape and share nothing
  else. That second one is the argument: `--check` must not fail on this.

**The first finding was acted on.** The `read(path)` group is gone: all three
copies — `browse/trail_store.lua`, `cli.lua`, `health.lua` — now call
`lib.nvim.fs.read`, which `browse/source.lua` and `tagfiles.lua` already used.
Its contract already matched what the local copies returned (`nil` for a
missing file, the raw bytes otherwise, binary mode on purpose), so no call site
had to be bent to a different one; the extra `err` it returns second is
discarded at all three, each a single-value context. The panel now reports one
group, the `is_dir`/`is_file` pair it is supposed to keep reporting — which is
the tool working in both directions: it found a duplicate worth removing and
still declines to call the remaining pair a defect.

The other limit is stated rather than worked around: a single edited line
breaks the match, so this finds copies and not near-copies. Sliding a window
over a token stream to find the longest common run is a genuinely more
expensive algorithm, and exact-shape matching is what earns its cost first. A
panel that stays empty on a tree that obviously has duplication is the
argument for the window — not an assumption made up front.

`ir.duplicates` is serialised despite being derived, unlike the fan-in/fan-out
panel which aggregates data already in the JSON: this grouping needs
`fn.shape`, and a page reading the artifact has no parse tree to redo it with.
Measured cost — `module_map.json` grew from 256 KB to 273 KB.

## Churn hotspots — `:DocMap churn` (2026-07-28)

The roadmap's second expensive Analysis-tab candidate, and the one that
turned out not to be an Analysis-tab candidate at all.

**It cannot be a panel.** It needs `git log`, and git data cannot enter the
committed artifact: `--check` byte-compares committed output against
freshly-generated output, so a map carrying history invalidates itself on the
commit that embeds it. There is no fixed point. That is precisely the wall the
History tab hit and the reason `serve.lua` exists. The roadmap listing it
beside code duplication as the same kind of work was simply wrong — one is a
pure `ir -> result` function like every other Analysis tool, the other cannot
be computed without a repository.

So it ships where `:DocMap impact` already lives: live-computed into the
quickfix list, nothing written, no artifact involved. The alternative was a
third `serve.lua` route, which buys a browser panel at the price of requiring
a running server for a question best asked from the editor anyway.

- **The product, because neither factor alone is actionable.** A module edited
  fifty times that is five lines of constants is a config file; a
  three-hundred-point parser untouched in two years is finished. The
  intersection is complicated code that keeps having to change — expensive
  now and expensive again next week.
- **Summed complexity per module, not averaged.** An average asks "how bad is
  the typical function here", which is the wrong question: a module carrying
  one 200-point monster and nine trivial helpers has a real problem an average
  divides away. `hottest` rides along because the sum names a module and never
  a place to start reading.
- **Merges excluded**, since a merge lists everything either side changed —
  counting one edit twice and rewarding long-lived branches. **`out_dir`
  excluded**, since in a repository that commits its own map it is regenerated
  by nearly every commit and would outrank everything real.
- **Unmatched paths counted, not dropped.** READMEs, CI config and deleted
  files change too; a number with no idea how much it ignored is worse than no
  number.
- **Modules with no documented functions are dropped, not scored zero.** A
  risk ranking ending in a run of zeroes reads as if the tail were low-risk,
  when it is really unmeasured.

The limitation is documented rather than engineered around, and the spec is
what surfaced it: `commits × complexity` is a scalarization, so a large enough
value on one axis outranks a moderate value on both. The first fixture written
for this asserted that churned-but-trivial ranks below complex-but-finished,
and it does not — that depends entirely on the numbers. Tornhill's own
presentation is a scatter plot whose answer is the top-right quadrant, which
has no such failure mode but is also not a ranking, and a quickfix list is a
ranking. Kept because both columns are on every row: when the order looks
wrong, the two numbers beside it say why immediately. Normalising the axes
would fix the ordering and cost exactly that.

Verified against this repository, which is a weak test of the signal and a
fine test of the plumbing — nine commits since extraction, ranking
`documentation.editor.browse` first at 5 commits × complexity 223.

## `core/` and `editor/` — an enforced split (2026-07-28)

`documentation.scan` → `documentation.core.scan`,
`documentation.browse` → `documentation.editor.browse`, and so on for every
module. A breaking rename, taken while the plugin is unpublished because that
is the cheapest this ever gets.

**Not tidiness — enforceability.** The pipeline was already 35% editor-free by
accident of the purity rule, and nothing whatsoever stopped it re-merging:
`scan.lua` could have required `browse/` and no check would have said a word.

The plugin already shipped the mechanism (`opts.layers`, `layer-violation`),
but it could not express this boundary against a flat tree. The editor half
was five unrelated module paths, and a rule from `documentation` down to the
browser would have flagged `browse/init.lua` requiring `browse/view.lua`. Two
prefixes make it one line, now declared in `scripts/gen_map.lua`:

```lua
layers = { { from = "documentation.core", to = "documentation.editor" } }
```

so `--check`, and therefore CI, fails when the core reaches into the editor.
The tool checks its own split.

- **It found a real violation on the first run.** `tagfiles.lua` — core —
  required `command.lua` for `find_node`, a lookup that touches nothing but
  the IR. Now `core/find.lua`; `command.find_node` stays as an alias, since
  it is part of that module's published surface.
- **One-directional on purpose.** The editor reaching into the core is the
  point of the core existing. Only the other direction costs anything.
- **`init.lua` sits outside the rule** and reaches both halves. That is what
  a facade is for, and giving it a special case would have meant a rule with
  an exception, which is not a rule.
- **Notification prefixes now name the command, not the module.** The
  mechanical rename turned `[documentation.browse]` into
  `[documentation.editor.browse]`, which is a user-visible string tracking an
  implementation detail. `[DocBrowse]` is what the reader typed.

Two spec assertions turned out to be about the *tree* rather than the code and
failed the moment it moved — the same class of bug the extraction commit had
to fix three times. `<CR> descends into the row under the cursor` asserted
"row 3", which had happened to be a module and became a function; it now finds
the last node-shaped row. And `gd` hardcoded `documentation/deps.lua`; it now
derives the path from the module name it centred on. Both were fixed as
portability bugs in the spec, not by restoring the old layout.

Cost, for the record: 45 files rewritten, 19 `dead-readme-link` findings from
the module READMEs pointing at moved files — every one of them raised by this
plugin's own check against its own tree, which is the argument for the check.

## Generated page — four interaction gaps closed (2026-07-29)

All four requests of 2026-07-28 built. Two produced decisions worth keeping.

**1. Sortable Analysis panels.** Every column header in Test coverage,
Documentation, Dependencies and Complexity sorts; clicking the active column
flips direction, clicking a new one starts at that column's natural direction
(descending for a number, ascending for a name). The sort is in the URL
fragment, so a sorted panel is linkable and survives Back.

The decision the entry asked for — shared sort state or per-subtab — resolved
to **shared**, and that fell out of the implementation rather than being
chosen up front: the columns differ per panel, so `anSort` looks the key up in
the panel's own column spec and silently falls back to that panel's default
order when it does not match. A `asort=fanIn` carried into the Complexity
panel therefore degrades to the normal view instead of breaking it, which is
what makes one shared axis safe.

Each panel's **default** order survives untouched, and that mattered more than
it looks: "worst coverage first, then most functions affected, then id" is an
editorial judgement about where to look, and collapsing it to "sorted by pct
descending" would have quietly changed what the panel recommends.

**2. Middle-mouse panning.** Hold the middle button anywhere in the graph
and drag in both axes. Left-drag deliberately still selects text — the boxes
carry module names people copy. Three things had to be suppressed: the
browser's own autoscroll (`preventDefault` on `mousedown` button 1),
`auxclick` (which would open a link in a new tab if the drag ended over one),
and text selection while dragging. The listeners are on `window`, not the
element, so a drag that leaves the graph keeps working and a release outside
it still ends the drag.

**3. The search box works per tab.** Analysis gained a real filter,
including the Duplicates panel — which filters by *group*, not by member: a
duplicate group with its matching members removed is no longer a duplicate
group, so a group survives if any member matches and is then shown whole.

The general shape resolved as the entry predicted: one contract per tab, not
one matcher over the page. What is shared is the placeholder, which now names
what the current tab will match, and the box is **disabled** on the three tabs
that do not filter — a box that invites typing and then ignores it is what
made this read as broken in the first place.

**4. The header counts are links.** modules → the Hierarchy Modules view,
files → the Tree tab, namespaces → the Index tab's Modules view, errors and
warnings → the findings disclosure at the foot of the page, opened and
scrolled to the first row of that severity, which then flashes. A count of
zero renders disabled rather than as a live link.

Two things in the original entry were **wrong**, corrected here so the next
reader does not inherit them:

- *"Errors and warnings have no home on the page at all."* They do — a
  collapsed `<details>` at the page foot, present on every tab. It was never
  linked to, which is a different and much cheaper problem than the new panel
  the entry proposed. No panel was built.
- *"Namespaces need a view."* They did not. The Index tab's Modules view
  already lists "every module and namespace filed under the last segment of
  the module path". A sixth tab would have been a third rendering of a set
  that already had two.

**And one real bug, found by testing this.** The Duplicates panel had *never
worked*. `render/html.lua` builds its own embedded payload
(`meta`/`root`/`nodes`/`edges`/`tag_links`) rather than reusing `to_json`, and
`duplicates` was never added to it — so the panel read `IR.duplicates`, found
nothing, and showed "This map was generated before duplicate detection
existed. Regenerate it to see this panel." on *every* map, including one
generated a second earlier. The advice was impossible to follow: regenerating
produced the same payload again. Confirmed against the committed artifact at
`HEAD`, so it shipped that way. Fixed by adding `duplicates` to the payload,
with the empty shape rather than `nil` when absent so the panel can still tell
"ran, found nothing" from "this artifact predates the feature".

The lesson worth keeping: the two serialisations were allowed to drift because
only one of them is byte-compared by `--check`. Any field added to `to_json`
from now on needs a deliberate answer about whether the page needs it too.

## `:DocMap plugins` and the Plugins Analysis panel — lazy.nvim spec inventory (2026-08-03)

The map's first feature aimed specifically at a Neovim *config* rather than
a Neovim *plugin*. Motivated by checking, concretely, whether this plugin is
useful applied to a real ~450-file `nvim` user config — the answer was
"structurally yes, but blind to the files someone most wants an overview
of": `lua/plugins/*.lua` is mostly `return { { "author/repo", event = "…" },
… }`, no function or symbol in sight, so every existing panel and check saw
an empty leaf. `core/plugins.lua` extracts these during the same scan pass
as `functions`/`symbols`, off the parse tree that already exists; `n.plugins`
is a new `Documentation.Node` field, serialized like `functions`/`symbols`.
`:DocMap plugins` (quickfix, sorted by repo) and a sixth Analysis-tab panel
both read it — the panel via client-side aggregation over the serialized
per-node data, the same split fan-in/fan-out uses, since (unlike
`duplicates`) there is no cross-file grouping that needs to happen in Lua.

**Scoped to lazy.nvim's spec shape specifically, named as such.**
packer.nvim (`use {...}` calls) and vim-plug (`Plug '...'` commands) are a
different shape and would need their own extractor, not a bent version of
this one — a real follow-up, not attempted here.

**Not followed:** `local M = {...}; return M`. Tracing an identifier back
to its assignment is exactly the kind of guess this scanner declines to
make elsewhere (`deps.lua` on `require(expr .. var)`). A file using the
indirect form contributes no plugins, the same as it contributes no
functions to `functions.lua` today.

**Verified against a real config, and it found two precision bugs no
synthetic fixture would have** — the reason to test a feature like this
against real data before calling it done, not just against cases invented
to match the design:

- **A single spec returned directly is not an array whose fields are each
  their own entry.** `return { {...}, {...} }` (many plugins) and `return {
  "repo", event = "…" }` (one plugin — a real, common style: config split
  one file per plugin, confirmed as this exact config's own convention in
  places) parse to the same node type. Read naively, `event`'s *value*
  looked like just another positional array element, and a first pass
  genuinely produced a spec whose `repo` was the string `"VeryLazy"`. Fixed
  on the one real distinguishing signal: an array of specs never has a
  *named* field at the outer level; a single spec's own trigger/metadata
  keys always do.
- **A bare-string array is not unique to plugin specs.** A plain list of
  command names (`return { "NeotestRunNearest", … }`, found genuinely
  documenting `:command` names via a doc-comment convention in the same
  config) is the identical shape. Fixed by requiring a bare positional
  string to contain `/` with no embedded whitespace — GitHub shorthand is
  the one thing lazy.nvim's own contract requires of that position, so this
  is the format, not a style guess. Reduced one real config's
  false-positive count from 235 spec-shaped matches to 52 genuine ones,
  verified by hand against the file and line each came from.

Also flags a repo declared in more than one file — a real footgun in a
config split across files, where the last one lazy.nvim imports silently
wins and no other check or panel here could ever have surfaced it.

Verification method worth naming: the read-only path
(`doc.scan_full(cfg)` → `render.html(ir, findings, cfg)` → write the string
to a scratch file, never `write_artifacts`) never touched the config
directory being analyzed — no `docs/map/` appeared there, confirmed by
`git status` on that repository before and after. The rendered HTML was
served from a local static server and driven in a real browser
(`document.querySelector(...).click()`, reading `console` for errors),
since nothing in CI lints the JavaScript embedded in `render/html.lua` —
that verification only happens by actually loading the page.

## `core/lang_registry.lua` — the language-backend seam (2026-08-03)

`docs/ROADMAP/IDEAS/MULTILANG.md`'s Phase 0, item one and two: a real, working
extension point for a second language, built without touching a single
existing function's behavior. Verified, not assumed — every field on every
pre-existing node in this repository's own map came back byte-identical
after the change; the only diffs were two new nodes (for the two new files)
and the require-graph/stats edges those two files legitimately add.

**The seam is narrower than it looks.** `scan.lua`'s walk hardcoded three
Lua facts: `"%.lua$"` (is this my file), `"init.lua"` (does this directory
own a module), and a direct call into `functions.lua` (how do I read one).
All three now go through `core/lang_registry.lua`'s `for_file`/`module_file`
contract instead. Everything else — `functions.lua` itself, `scan.lua`'s own
`parse_header`, the `@types/` collection, `export_shape` — is untouched and
still Lua-specific, deliberately: those are real language-support work with
no abstraction to build yet, not oversights.

`core/lang/lua.lua` is the thin registration, not a second implementation:
`is_source`/`module_file` are new, one line each, and `parse_header`/
`scan_file` are one-line delegations to the code that already existed.
Both delegations are deferred `require()`s inside their own function
bodies, the same established pattern `functions.lua`/`symbols.lua` already
use for their own back-reference to `scan.lua`'s `split_summary` — verified
this is not circular the same way that precedent already is, by tracing
exactly when each require actually fires.

**The new layer rule caught a real design mistake while this was being
built, the same way the `core`/`editor` rule caught `tagfiles.lua` reaching
into `command.lua`.** The first draft had `scan.lua` require
`core/lang/lua.lua` directly, to trigger its self-registration —
`documentation.core` reaching into `documentation.core.lang.lua`, exactly
the coupling `{ from = "documentation.core", to =
"documentation.core.lang" }` exists to forbid. `--check` flagged it
immediately. Fixed by giving the registry itself a small, explicit list of
backend modules to require lazily (`KNOWN_BACKENDS`) — the one place
allowed to name a specific backend — rather than suppressing the finding.
Verified the rule the other direction too: it stays silent on the
legitimate registration path, and a deliberate throwaway violation (a
one-off file requiring `core/lang/lua.lua` directly) was caught and the
file deleted before commit.

**A second, subtler bug, found only by testing `reset()` for real rather
than trusting the docstring:** the first version of `reset()` cleared
`backends`/`order` and also cleared a `loaded` flag, on the theory that the
registry's lazy `ensure_loaded()` would repopulate the real "lua" backend
on the next lookup. It does not — `require()` on a module already in Lua's
own cache returns the same table without re-running the file, so the
`register(...)` call at a backend's own bottom line never fires a second
time. Verified empirically with a two-line throwaway script before writing
the fix: `for_file("x.lua")` returned a real table before `reset()` and
`nil` after it, forever, for the rest of the process. Fixed by giving each
backend a `name` field on its own table and having `reset()` re-register
every known backend explicitly, from its already-cached module, rather
than depending on re-execution that Lua's semantics do not provide.
`TESTS/lang_registry_spec.lua` asserts the fixed behavior directly, in its
own file rather than a block in `docmap_spec.lua` — that file already sits
at Lua's 200-local-per-function ceiling, and this suite touches the
process-wide singleton every other spec's real scanning depends on.

Three of `MULTILANG.md`'s remaining Phase 0 items — owning-scope,
one-file-many-modules, and the schema-versioning check — are explicitly
**not** done and not needed yet: modern JS/TS is function-based enough
(React function components and hooks, not classes) and file-is-a-module
enough (the same shape Lua already has) that Phase 1 does not require
them. Recorded as deferred-with-reason in `MULTILANG.md` itself, not
silently skipped.

## `core/lang/ecma.lua` — JavaScript, TypeScript and TSX as real backends (2026-08-03)

`docs/ROADMAP/IDEAS/MULTILANG.md`'s Phase 1: the first real (non-Lua) language
plugged into the seam `core/lang_registry.lua` built. One shared
implementation (`ecma.lua`) behind three one-line registrations (`js.lua`,
`ts.lua`, `tsx.lua`), the same relationship `core/lang/lua.lua` has to
`functions.lua` — because the three grammars agree on every shape this
module actually reads, verified against real parses rather than assumed
from documentation.

**Built and verified against real grammars, not guessed at.** Since
touching this repository's own Neovim environment was explicitly ruled
out for this work, the `tree-sitter` CLI built `javascript`/`typescript`/
`tsx` shared libraries from cloned grammar sources into a scratch temp
directory, used only to probe real node shapes (`tree-sitter parse`/
`query`) and, after the extraction was written, to run the full
`ecma.lua` fixture against real parses of all four function forms, JSDoc,
`async`, hook detection, and both import styles — twice: once to catch
two real bugs (below), once clean. Nothing from that scratch directory is
part of the repository or the committed test; `TESTS/lang_js_spec.lua`
looks for a parser the normal way (`vim.treesitter.language.add`, no
explicit path) and skips with a stated reason when none is on the
runtimepath, which is the honest state of this repository's own CI today.

**Scope, stated narrowly rather than guessed at:** `function name() {}`,
`const/let name = (...) => {}`, `const/let name = function() {}`, and any
of those under `export`/`export default` (verified: both wrap the same
`declaration` field, no distinguishing node). Not covered: class methods,
object-literal methods, `module.exports = {...}`, generators, IIFEs — a
file using only those contributes no functions, the same honest gap
`functions.lua` leaves for a Lua construct it cannot read a def out of.
Imports: ESM (default/named/namespace) and CommonJS `require()` assigned
to `const`/`let`; a computed `require()` target or dynamic `import()` is
not resolved, matching `deps.lua`'s own stated position on computed
targets. `complexity`/`shape` are real, computed against this grammar's
own verified node names (`ternary_expression`, `switch_case`; no
`elseif_statement`/`repeat_statement` — `else if` is a nested
`if_statement`). React hooks are recognized by the same `^use[A-Z]` naming
convention `eslint-plugin-react-hooks` itself relies on (`is_hook`),
carried on `Documentation.FunctionInfo` alongside a real field rather than
inferred at the panel layer — `docs/FRAMEWORK_CONVENTIONS.md`'s own
conclusion that a *map* of hooks, not rules-of-hooks linting ESLint
already owns, is the underserved half.

**One check needed to learn a second convention exists.**
`check_summaries`' `missing-module-tag` fired on `node.module` being falsy
— correct for Lua, which needs `---@module` to recover a name its file
path alone cannot give, but wrong for JS/TS, whose module identity *is*
its file path with nothing to declare. Caught by reasoning through the
check's code before writing the JS backend, not by a failing test after
the fact. Fixed with a new `Documentation.LangBackend.module_tag` field
(default `true`) and a `wants_module_tag(node)` helper that asks the
registry, never a specific backend — the same discipline `check.lua`
already keeps elsewhere. Verified byte-identical behavior on this
repository's own all-Lua tree (same findings) before and after.

**A second, more consequential bug: the new layer rule itself over-fired
once a second language actually had internal files to require each
other.** `js.lua`/`ts.lua`/`tsx.lua` each require `ecma.lua` — all three
live under `documentation.core.lang`, so that require never leaves
`core.lang`'s own scope. But `check_layers`' prefix match only checked
that `from` was under `rule.from` and `to` was under `rule.to`; since
`documentation.core.lang.js` is trivially also "under" `documentation.core`
by plain prefix, the rule fired on `ecma.lua` being required from inside
its own package, misreading an edge that never crossed the
core-into-`core.lang` boundary as though it had. Caught by actually
regenerating this repository's own map after adding the three backends,
not assumed clean because Stage 1's version of the rule had been correct
for the one case it was tested against. Fixed by requiring `from` to sit
*outside* `rule.to`'s scope as well as inside `rule.from`'s — the general
fix, not a special case for `core.lang`, so any future rule with a nested
`to` under `from` gets the same correct behavior. Verified both
directions after the fix: the three legitimate intra-`core.lang` requires
went silent, and a deliberate throwaway direct require
(`scan.lua` → `core/lang/lua.lua`) was still caught, then removed before
commit.

Left genuinely open, not silently answered: calls/symbols extraction,
class-method owning-scope, `.jsx` support (left for `js.lua` to extend,
per that file's own header), `module.exports = {...}` recognition, and
this repository's own CI not yet installing a JS/TS parser to run
`lang_js_spec.lua`'s assertions rather than its skip path. Tracked in
`docs/ROADMAP/IDEAS/MULTILANG.md`'s Phase 1 checklist.

## A seventh Analysis panel — Hooks (2026-08-03)

The most contained, immediately practical follow-up to the JS/TS backend:
surface `is_hook` (already computed, unread by anything) as its own
Analysis panel, the same shape `renderAnalysisPlugins` already gave
`n.plugins` — data that already sits on the serialized IR, no new Lua
extraction, no git, nothing to wait on. Closes the loop on
`docs/FRAMEWORK_CONVENTIONS.md`'s own conclusion that a *map* of hooks,
not rules-of-hooks linting, is the underserved half of React support —
and on this session's original ask for a concrete, demoable example
built on the new backend.

`Documentation.FunctionInfo.is_hook` is now a declared field on the type
(`boolean?`, Lua never sets it) rather than the "harmless passenger, not
real yet" state `ecma.lua`'s own comment left it in — nothing to change
in the JSON encoder itself, since `core/json.lua`'s `M.encode` walks
whatever table it is given rather than a fixed field whitelist; the field
already survived serialization, it was only ever unread.

**A real, pre-existing bug found while wiring the panel in, not
introduced by it.** `parseState`'s `atool` URL-parameter whitelist
(`html.lua`, the hash-routing state parser) only accepted `doc`/`deps`/
`complexity` — `duplicates` and `plugins` were added as panels after that
whitelist was last touched and never added to it. The practical effect:
a shared link, a page reload, or the Back button landing on
`#tab=analysis&atool=duplicates` silently fell back to the Test-coverage
panel instead, with no error — the URL round-trip was quietly broken for
two of the six panels that existed before this change. Found by having
to touch that exact line to add `hooks` to it and asking what else was
missing, not by a report. Fixed by listing all three (`duplicates`,
`plugins`, `hooks`) rather than only adding the new one. `drawAnalysis`'s
own separate whitelist (used for the toolbar's active-button state) was
already current for `duplicates`/`plugins` — only `parseState`'s had
drifted — and both now agree.

**Verified in an actual browser, not by reading the JS.** This
repository's html.lua panels have no automated test today (there is no
JS test harness in this repo, and the existing six panels are equally
untested that way) — so a hand-built `module_map.json` fixture with two
`is_hook` functions was served locally and driven directly: the panel
lists both rows with the right columns; clicking the `Line` header
sorts ascending then descending; typing into the filter box narrows to
one row and reports "1 of 2 shown"; clicking a row navigates to the Tree
tab with the right node id; reloading with `#atool=duplicates`,
`#atool=plugins` and `#atool=hooks` in the URL now lands on the right
panel instead of silently resetting. The empty state (no hook found) was
verified separately against this repository's own real, all-Lua
generated map, which naturally has no `is_hook` function.

Left open, the same items `MULTILANG.md` already tracked before this
panel existed: no `.jsx` support, no class-method hooks, no CommonJS
`module.exports` recognition — the panel shows whatever `ecma.lua`'s
existing scope already finds, nothing more.

## CI now installs real JS/TS/TSX parsers (2026-08-03)

Closes the last item Stage 2's own ledger entry left open: this
repository's GitHub Actions `tests` job only ever exercised
`TESTS/lang_js_spec.lua`'s stated skip path, never its real assertions —
the same grammars this session built by hand into a scratch directory to
verify `ecma.lua` during development were never available to CI itself.

`.github/workflows/ci.yml`'s `tests` job now builds all three grammars
from source with the `tree-sitter` CLI (both `tree-sitter-javascript` and
`tree-sitter-typescript` ship pre-generated `parser.c`, so only
`tree-sitter build` — compiling, not generating — is needed) into
`.deps/ts-parsers`, then exports `DOCUMENTATION_TS_PARSERS_DIR` via
`$GITHUB_ENV` for the `scripts/ci.sh tests` step that follows it.
`TESTS/run.lua` reads that variable itself and appends it to the rtp —
optional, unlike the existing `LIB_NVIM_DIR` handling right above it in
the same file, since `lang_js_spec.lua` already has a real, tested skip
path for the ordinary case of a local run with no such variable set; a
missing/absent directory is silently a no-op, not an error, the same way
an absent `lib.nvim` is a hard failure and an absent JS parser is not.

Verified by actually cloning both grammar repos and running
`tree-sitter build` locally before writing the workflow step, then
running the full suite twice — once with the built parsers on the rtp via
the new environment variable (all real assertions ran), once without
(the pre-existing skip path, unchanged) — rather than trusting the YAML
would work the first time it ran in CI.

## Every CI run on this repository had been failing (2026-08-03)

Found while checking whether the previous change's new CI step actually
ran, via `gh run list` — not by design. Every push to `main` in this
repository's history, going back to the very first commit, had a failing
`CI` check: `luacheck`, `tests`, and `map` every time; only `stylua`
(which runs through a dedicated GitHub Action, not `scripts/ci.sh`) had
ever gone green. Nothing about this was specific to today's changes —
`gh run list --limit 15` showed the same three-job failure on commits
from days before this session started.

**Root cause: a single Lua footgun, duplicated in three files.**
`have_lib_nvim()` (`scripts/ci.lua`), `add_lib_nvim()` (`TESTS/run.lua`),
and `ensure()` (`scripts/gen_map.lua`) all built their candidate-directory
list the same way:

```lua
local candidates = { vim.env.LIB_NVIM_DIR, root .. "/.deps/lib.nvim", ... }
for _, d in ipairs(candidates) do ...
```

`ipairs` stops at the first `nil` it finds. `vim.env.LIB_NVIM_DIR` is
`nil` on every run that does not set it — which is every CI job, since
none of them set that variable; they rely entirely on the `.deps/lib.nvim`
checkout instead. A table literal with `nil` in slot 1 has a hole there,
so `ipairs` returned zero iterations, and the `.deps/lib.nvim` candidate —
the one CI's own `actions/checkout@v4` step had already populated
correctly — was never even inspected. `have_lib_nvim()` always returned
`false`, `have_lib_nvim`'s caller always failed with "lib.nvim not
found", and the tests/map gates never ran a single real check on GitHub
Actions since the ci.sh/ci.lua split that introduced this pattern.

Confirmed by reproducing the exact layout locally rather than reading the
code and guessing: cloned this repository and `lib.nvim` into a scratch
directory laid out exactly like the two `actions/checkout@v4` steps in
`.github/workflows/ci.yml` do, then ran `scripts/ci.sh tests`/`map` with
`LIB_NVIM_DIR` explicitly unset — reproduced the identical failure
message from the real CI logs. A two-line probe script confirmed the
mechanism directly: `for _, v in ipairs({nil, "x", "y"}) do end` iterates
zero times.

Fixed in all three files identically: build the candidates list with
explicit `candidates[#candidates + 1] = ...` assignments, appending the
environment variable only when it is actually set, so no run ever
produces a table with a hole in it. Verified against the same
reproduction: `tests` and `map` both now find `.deps/lib.nvim` and pass
with `LIB_NVIM_DIR` unset.

**A second, independent bug found while fixing the first, in the same
investigation:** the `luacheck` CI job's own log showed a different
failure — `nvim is not on PATH` — before ever reaching the actual
luacheck run. `scripts/ci.sh` is a thin wrapper that launches
`scripts/ci.lua` via `nvim --headless -l ...` (documented in that file's
own header as the reason the split exists at all: Neovim as a
cross-platform script host). That launcher requirement is real and
applies to every gate the wrapper runs through, including `luacheck` —
`ci.lua`'s own `GATES.luacheck()` uses `vim.system`/`vim.fn.executable`,
Neovim-only APIs — but the `luacheck` job in `ci.yml` only ever installed
Lua 5.4 and luarocks, never Neovim itself, so `scripts/ci.sh luacheck`
failed before `ci.lua` was ever reached. Fixed by adding the same
`rhysd/action-setup-vim@v1` step the `tests`/`map` jobs already have.

Verified end to end, not just per file: reproduced the full checkout
layout (`documentation.nvim` + `lib.nvim` checked out exactly as
`ci.yml` does it, `LIB_NVIM_DIR` unset) and ran all four gates —
`stylua`, `luacheck`, `tests`, `map` — in that one reproduction,
confirming all four now pass together before pushing.

## Calls extraction for JS/TS/TSX (2026-08-03)

The next item on `MULTILANG.md`'s Phase 1 checklist: `ecma.lua`'s
`scan_file` returned `{}` for `calls_raw` since Stage 2 landed. Two new
functions mirror `calls.lua`'s own Lua-side split exactly:
`extract_calls` (per-file syntax: every call site, its raw callee text,
which top-level function encloses it) and `identifier_counts` (how often
each bare name appears, for `local_refs` — a function passed as a value
has no call site naming it). Both are one query each
(`(call_expression function: (_) @callee)` and `(identifier)`),
structurally identical to `calls.lua`'s own `(function_call name: (_)
@callee)`/`(identifier)` pair, verified against a real parse before
writing them: a bare call's `function` field is an `identifier`
(`helper`); a method-shaped call's is a `member_expression` whose text
reconstructs as `obj.method`.

**The genuinely interesting result: `calls.lua`'s own resolver
(`M.build`) needed zero JS-specific changes.** It was already
language-agnostic — it reads `node.calls_raw`/`node.requires_raw`/
`node.functions` as plain data, never a treesitter node, so it has no Lua
syntax baked into the *resolution* step, only the earlier *extraction*
step did. Feeding it real `ecma.lua`-scanned `calls_raw` through a
minimal one-node IR resolved a same-file bare call (`helper()`) into a
real `kind="call"` edge at `confidence="exact"`, on the first try, with
the exact same code path a same-file Lua call already takes. A
member-expression call (`obj.method()`) is captured as raw data too, but
correctly resolves to nothing — `obj` is neither a require alias nor a
same-file `M.`-prefixed function (a shape JS itself has no equivalent
of, since JS functions are declared bare), so it silently matches no
branch in the resolver, the same honest degradation an unknown Lua
receiver already gets.

**Explicitly not attempted: cross-file call resolution.** Lua's call
resolution works because `local fs = require("lib.nvim.fs")` binds a
*module* to a name, and `fs.read(...)` is then an alias-plus-member
lookup. JS's named imports (`import { helper } from "./bar"`) bind the
*function itself* directly into scope — the call site is bare
(`helper()`), with no alias or prefix for `calls.lua`'s existing
resolution branches to key on at all. Making this work needs
`ecma.lua`'s `extract_requires` to record which names an import bound
(not just the module string), and a new resolution rule in `calls.lua`
for "this bare name came from a specific tracked import" — a real,
separate task, not a small extension of today's work, and recorded as
its own open item rather than folded into "calls extraction" as if it
were the same size.

Verified end to end, not per function in isolation: a committed test
(`TESTS/lang_js_spec.lua`) scans a small fixture with both call shapes,
checks `calls_raw`/`local_refs` directly, then feeds the result through
`calls.lua`'s real, unmodified `M.build` and asserts the actual edge that
comes out — the same real grammar (built from source into a scratch
directory, this environment untouched) used for every other verification
this phase, exercised twice: with the parser present (real assertions)
and absent (the existing skip path, unchanged).

`docs/ROADMAP/IDEAS/MULTILANG.md`'s "calls/symbols extraction" checklist item
is now two items: calls is done (with cross-file resolution split out
as its own explicitly open task), symbols remains untouched.

## Symbols extraction for JS/TS/TSX (2026-08-03)

The other half of the split checklist item the calls-extraction session
left open: `ecma.lua`'s `scan_file` returned `{}` for symbols — module-scope
`const`/`let`/`var` bindings that are not functions and not `require()`
calls, the part of a module's surface that answers "what is in here"
rather than "what can I call." `extract_symbols` mirrors
`documentation.core.symbols`'s own Lua-side scope and classification
exactly (table/constant/binding), verified against a real parse before
writing it — the same discipline as every extractor in this file.

Two shapes are excluded, because another stage already owns them, the
identical reasoning `documentation.core.symbols` gives for excluding
`local fs = require(...)` and `M.foo = function() ... end` on the Lua
side: a declarator whose value is an `arrow_function`/`function_expression`
(`as_function` already claims it), and a `require("…")` call
(`extract_requires` already claims it). Verified this does not
double-count a same-statement mix — `const helper = () => {}, CONFIG =
{...};` correctly yields one function (`helper`) and one symbol
(`CONFIG`), since `classify_symbol` excludes `helper`'s declarator on its
own regardless of position, with no `if not fn` guard needed in `walk()`.

**Classification, verified node-by-node against a real parse:**
`object`/`array` literals are `"table"`, counted by named-child count
rather than filtering to one node type the way Lua's own `count_fields`
narrows to `field` — JS object literals have more member shapes than Lua
table constructors do (`{ a, b, c: 3, ...rest }` parses as one
`shorthand_property_identifier` each for `a`/`b`, one `pair` for `c: 3`,
one `spread_element` for the rest — all real members, all counted).
`number`/`string`/`true`/`false` are `"constant"` — JS has no single
boolean node type, `true` and `false` are distinct node types, both
confirmed against a real parse rather than assumed to work like a
generic "boolean" the way `count_fields`'s Lua original might suggest.
`null`/`undefined` (shapes with no Lua equivalent at all) fall through to
`"binding"`, deliberately not special-cased — the same treatment any
other literal Lua's own `classify` does not explicitly list already
gets there. TypeScript's type annotations (`const CONFIG: Record<string,
number> = {...}`) do not interfere: the `name`/`value` fields resolve
identically with or without one, confirmed against a real TS parse
alongside `interface`/`type`/`enum` declarations, which simply do not
match `lexical_declaration`/`variable_declaration` and so need no
exclusion of their own.

**No equivalent of Lua's export-table filter.** `documentation.core.
symbols` drops `local M = {}` specifically because `return M` at the end
of the chunk makes it *the module itself*, already represented by the
node — measured at 188 of 600 Lua symbols before that filter existed.
JS/TS has no equivalent: there is no single chunk-level return that names
"the module" the way a Lua `require()`d file's last statement does (see
`ecma.lua`'s own header on module identity never being set for JS/TS).
So every qualifying binding is reported, including one a project might
consider its de facto public surface — an honest difference from Lua's
behavior, not an oversight, since inventing a JS-specific "this export IS
the module" convention to filter on would be a guess this file declines
to make elsewhere either.

Verified end to end, the same pattern the calls-extraction session used:
a real fixture (JSDoc-commented `object`, a `number`, a `string`, an
export-wrapped `object`, a function, an arrow-function-as-symbol
negative case, a `require()` binding, and a computed expression) scanned
through the real, scratch-built parser before a single assertion was
written, confirming the exact five symbols expected and nothing else —
*then* committed to `TESTS/lang_js_spec.lua` as a real assertion block,
not just an ad hoc check thrown away after confirming the shape worked.

`docs/ROADMAP/IDEAS/MULTILANG.md`'s Phase 1 checklist now has two remaining
real gaps from this pass: cross-file call resolution (named imports
binding a bare name directly into scope) and class-method owning-scope
(shared with Phase 0, not unique to JS/TS).

## The annotation popup (2026-08-03)

Step 1 of [`docs/ROADMAP/FEATURES/ECOSYSTEM.md`](ECOSYSTEM.md)'s sequencing, and chosen to
be first for a specific reason: **it needed no new extraction at all.** Every
list in this map — Index, Notes, Complexity, Duplicates, Hooks — showed a
function as its signature and nothing else, while the params, returns,
deprecation and prose had already been parsed, already been serialised into
`module_map.json`, and were already rendered by the Tree tab's detail pane.
They were one navigation away. This closes that distance without the artifact
growing by a single byte of data.

Hovering (or focusing, or clicking) the `ⓘ` beside any listed function opens
a card with the full annotation: signature with its badges, deprecation
banner, summary, params with types and descriptions, returns, `@overload`
alternatives, see-also links, and `@example`. Its footer links to the owning
module at the defining line.

**`fnAnnotationHTML` is shared, not copied.** The detail pane's rendering was
extracted into one function that both it and the popup call. Two copies of
"how a function's annotations look" is precisely the drift this plugin
exists to detect, and shipping one inside it would have been hard to defend
— the same argument the `?` key-hint overlay already makes for rendering
from the same `KEYS` table it binds from. What deliberately stayed behind
with the detail pane: the `<div class="fn">` wrapper and the Calls-view
links, both of which need `callOut`/`callIn` and a stable per-function
anchor that a floating card does not have.

**The refactor was proven output-identical, not assumed to be.** The
committed artifact was saved before the change, both versions were loaded
side by side in a browser, and the detail pane's rendered HTML was compared
for all 56 nodes that have functions. 54 were byte-identical. The two that
differed did so in exactly one place each — the lines-of-lua stat, `4 083 →
4 246` for `html.lua` and the same `+163` in the root total — which is the
direct, explainable consequence of this change adding 163 lines to that
file, and nothing else moved. Same byte-accountable standard
`core/lang_registry.lua`'s own entry set.

Behaviour was verified in a real browser rather than inferred from the
source: the popup opens on hover and closes on leave after a grace period
that lets the pointer travel into the card; click pins it so a long
`@example` can actually be read; Escape, click-outside, blur, resize and
scroll all close it, mirroring the context menu's existing lifecycle rather
than inventing a second set of rules for a second floating thing on the same
page; the card flips above its trigger near the bottom edge instead of
running off-screen (checked against the last row on the page); the trigger
is keyboard-focusable and Enter opens the same card; and the footer link
navigates to the module and closes the popup. Trigger counts came out at 323
in Index, 323 in Complexity and 4 in Duplicates — and **0 in Hooks, which is
correct**: this is a Lua repository with no React hooks.

**One code path could not be exercised by this repository at all.** The
Notes tab lists `@todo`/`@bug`/`@test`/`@deprecated` functions, and nothing
here carries any of those four — the tab renders four "nothing carries this"
messages. Rather than ship that branch untested on the grounds that it looks
identical to the Index one, a copy of the artifact was patched to give one
real function a `@todo`, loaded, and checked: the trigger appears, takes
keyboard focus, and resolves to the right annotation.

## The documentation corpus — `core/docs.lua` (2026-08-03)

Step 2 of [`docs/ROADMAP/FEATURES/ECOSYSTEM.md`](ECOSYSTEM.md), and the largest genuinely
new *extraction* since the JS/TS backend. Everything else in this plugin
reads source — annotations sitting next to the code they describe. This reads
the other half: the `.md` files that describe the same tree from outside.
Until now a documentation file was known to the map as a path
(`node.readme`) and a counter (`stats.files_md`); **nothing had ever opened
one.**

Three pieces. A **corpus scan** (every `.md` outside `out_dir`, hidden
directories and `node_modules` — `out_dir` is excluded because the generated
`overview.md` names every module in the tree and would make everything
"documented" by the artifact trying to measure it). A **reference index**,
`ir.docs.refs`, keyed `nodeId` for modules and `nodeId#fnName` for functions
— the same key shape `calls.lua` and the page already use. And
**`doc-references-missing`**, a check for prose describing something that is
no longer there: dead code's mirror image, and the only drift in this
catalogue that lives entirely outside the source tree, where a rename does
not move the two halves in one diff.

**The first real run is the whole story of this entry.** It produced **25
findings, 24 of them false**, and resolved **194 references** whose
most-cited entity was a local function named `git` collecting documents that
discuss the version-control tool. `MULTILANG.md`'s Considerations section
predicted exactly this shape — `core/plugins.lua` passed nine fixtures and
then produced 235 false positives against one real config — and the fix was
the same: run it against something real *before* believing it. Four
exclusions came out of that run, each one now a named case in
`TESTS/docs_spec.lua`:

- **`documentation.nvim` is a repository, not a member access.** Ten of the
  25 findings were "module `documentation` has no member `nvim`". Any
  `*.nvim` mention is now excluded, reading the same ecosystem convention
  `ecma.lua` already reads for `use*` hooks.
- **`documentation.*` is a glob**, not a claim that `*` is a member. The
  remainder must now look like an identifier.
- **`documentation.editor` is a real namespace** with no `init.lua` and
  therefore no `@module` tag to be indexed by. Every dotted *prefix* of a
  known module is now registered — derived from the module names themselves,
  so no second path-to-module convention exists here to disagree with
  `check.expected_module`.
- **A ledger entry documenting a rename is correct, not stale.**
  `FEATURES.md` itself writes `` `documentation.scan` → `documentation.core.
  scan` ``; the old name is *supposed* to be gone. A mention whose line
  points an arrow at another span **that resolves** is now read as a rename
  note. Narrow on purpose: an arrow pointing at something equally missing is
  not evidence of a rename, and is still reported.

**Resolution is qualified-only by default**, and that decision has a
measurement behind it too. `opts.docs_heuristic` (off, mirroring
`opts.calls_heuristic` exactly) gates bare-name matching, because the bare
names actually doing the matching here were `write`, `open`, `scan`, `add`
and `esc` — every one a *file-local* helper and every one an ordinary
English word. A subtler version of the same leak survived the first fix: a
file-local `local function git` is indexed under the bare name `git`, so it
matched *exactly*, not heuristically. Undotted mentions are now answered
from the deduplicated bare index and never from the exact one, whatever
index would have had them.

After all of it: **25 findings → 1, and 194 references → 46, every one
qualified and every one real.** Smaller and trustworthy beats larger and
noisy, which is the same trade `calls_heuristic` already makes.

The one surviving finding was genuine, and it was in a document written
earlier the same day: `docs/ECOSYSTEM.md` illustrated qualified references
with a `scan_full` qualified onto `documentation.core.scan`, when
`scan_full` lives in `documentation` itself. The check found a real error in
the design document proposing the check. Fixed in the same commit.

**And then it found this paragraph**, because the sentence above originally
quoted the broken reference verbatim to explain it. A document *quoting* a
dead reference is indistinguishable, to a scanner reading code spans, from
one *making* it — there is no marker in Markdown for "this identifier is the
subject, not a link". Recorded in `core/docs.lua`'s header as a real limit
rather than worked around with a magic comment: the honest fix is to write
about a dead name without putting it in backticks, which is what the
sentence above now does.

`check_see_targets` now shares `docs.build_index` rather than building its
own boolean copy of the same name set — two answers to "what names does this
tree export" would drift, and noticing that is this plugin's whole job.

Two bugs were caught by `TESTS/docs_spec.lua` while writing it, both real:
the ambiguity leak above, and a double-backtick pattern using `[^`]+` for
content whose entire purpose is to *contain* backticks.

## Doc references in the map, and a determinism bug (2026-08-03)

The UI half of step 2: a marker beside anything the prose mentions, opening
the references with their surrounding line. Rendered **only where references
exist** — an always-present icon that is usually empty trains the reader to
ignore it, while one that appears exactly when a document mentions this thing
is a signal before it is even clicked. It reuses the annotation popup's card
and lifecycle rather than introducing a second floating element: two
independently positioned popups that can both be open would have to negotiate
overlap, focus and Escape between them, and no reading task wants both at
once.

**Two bugs, both found by opening the page rather than by reading the code.**

The first was already documented in this file, one line above where it
happened again. `duplicates` carries a comment explaining that it had been
missing from the page payload, which made its panel permanently unreachable.
That payload is built independently of `documentation.to_json`, so adding a
field to the IR *and* to the JSON artifact still leaves the page without it —
which is exactly what happened here: the browser showed an artifact whose
`docs` key did not exist. Now stated plainly in the code rather than left for
a third feature to rediscover.

The second was worse, and would have been invisible without the `map` gate.
The index registered namespace prefixes by iterating `pairs()` over a table,
so `documentation.core` resolved to whichever module under it the hash order
yielded first — **a different one on every run**. In a byte-compared artifact
that is not cosmetic: regenerating produced a different file each time, so
`--check` could never pass and the map was permanently "stale" with no edit
that could fix it. Iterating `ir.order` fixes the determinism; climbing the
`parent` chain in lockstep with stripping name segments also makes the answer
*correct*, resolving a prefix to the real namespace node instead of to an
arbitrary child of it. Three consecutive generations now hash identically,
and the spec asserts both halves.

Writing that regression test exposed a third, quieter problem: the fixture IR
had no `parent` links, so it had been exercising a fallback path rather than
the real one. A fixture that cannot fail the way production fails is not a
test of production.

## The Docs Analysis panel — closing out ECOSYSTEM.md step 2 (2026-08-03)

The one item step 2 left open: `docs/ECOSYSTEM.md` §3.4 predicted "docs-only
overview/filter" would be cheap once the corpus scan existed — no new
extraction, just the existing sort/filter plumbing over data `core/docs.lua`
already collects. That prediction held exactly: an eighth Analysis panel
(`renderAnalysisDocs`), listing every `.md` file the corpus scanned
(`ir.docs.files`) — path, title, resolved-reference count — reusing
`anFilter`/`anSort`/`anHead` unchanged, the same three helpers every panel
since Plugins has used.

**Rows carry no `data-node` and are not `.anrow`-classed, on purpose.** A
`.md` file is not a `Documentation.Node` — there is nowhere in the Tree tab
for a click on one to land. Giving these rows the same hover/click
affordance every other panel's genuinely clickable rows have would be a
false promise; where a reference actually resolves to a function or module
is the marker beside that entity (the doc-reference popup from the previous
entry), not this overview. `doc-references-missing` (`ir.docs.missing`) is
deliberately not repeated here either — it is already a `check.lua` finding
in the Notes tab, and belongs to "what is wrong" rather than "what
documentation exists."

Verified in an actual browser against this repository's own regenerated map
(27 real `.md` files, 51 resolved references): the panel lists every file
with the right title/ref count, sorting the References column flips
ascending/descending correctly, the filter box narrows to a single matching
file, a row click does nothing (confirmed no `anrow` class, no hash change),
and `#atool=docs` survives a reload — the same `parseState` whitelist this
session already had to fix once for `duplicates`/`plugins`; `docs` was added
to it in the same edit rather than left to go stale again.

This closes `docs/ECOSYSTEM.md`'s step 2 completely. Next up per its own
sequencing: step 3 (bounded snippet previews) and step 4 (the API endpoint
inventory).

## Bounded snippet previews — ECOSYSTEM.md step 3 (2026-08-03)

`docs/ECOSYSTEM.md` §3.5 split hover previews into three tiers by cost:
signature (already free, shipped as the annotation popup), a bounded snippet
around a known line (this entry), and a full file (needs `serve`, explicitly
out of scope). This is the second tier: every function's own body, capped,
embedded in the artifact, working offline.

**Shared, not duplicated, across both language backends.** `core/snippet.lua`
is a new, small module: given a source string and a 0-based row span, return
the text capped at `MAX_LINES` (40) plus how many lines were cut. Both
`functions.lua` (Lua) and `core/lang/ecma.lua` (JS/TS/TSX) already have `src`
and a row range in scope at the exact point they build a
`Documentation.FunctionInfo` — neither needed a new file read or a new parse,
only a call to the shared helper. The bounding rule is policy, not a
per-language fact, so a second implementation would have been the kind of
drift `MULTILANG.md` already flags as a real risk once a second language
exists to duplicate against.

**No payload-wiring trap this time — verified why, not assumed.** The
previous two features in this sequence (`ir.duplicates`, `ir.docs`) each
needed an explicit new key in `html.lua`'s payload builder, because both are
*top-level* IR fields the payload assembles by hand. `snippet`/
`snippet_omitted` are ordinary fields on `Documentation.FunctionInfo`, and
`nodes` in that same payload is already `ir.nodes[id]` copied whole — so a
new field on a function flows through automatically, the same way `is_hook`
did in Stage 2. Confirmed by generating this repository's own map and
finding real snippet text already present, rather than assumed from the
architecture alone.

**Deliberately not folded into `fnAnnotationHTML`.** That function is shared
between the Tree tab's detail pane (which already lists every function of a
node in full) and the annotation popup (one function, inspected without
navigating). A node with a few dozen functions, each carrying up to 40 lines
of source in the detail pane, would turn "browse this module" into "read
most of its source" — a question the pane's own click-through to source
already answers one navigation away. `snippetHTML(fn)` is a separate small
function, called only from the popup's own composition in `sigOpen`.

**Measured, not assumed, and reported honestly.** This repository's own
regenerated artifact grew from 797KB to 1031KB (`index.html`, +29%) and from
430KB to 662KB (`module_map.json`, +54%). Bounded and proportional to the
number of functions, as §3.5 predicted — but a real cost, not the "no new
extraction, basically free" character step 2's docs-only overview genuinely
had. `docs/ECOSYSTEM.md`'s own step 3 entry now states this plainly rather
than calling the feature cheaper than it measured.

Explicitly not attempted: a snippet at an arbitrary `path:line:col` — a call
site, or a doc reference's own line inside the `.md` file that mentions it.
Those lines live in files this pass (which only ever visits a function's
*own* file, at its *own* declared span) was never reading. A real, separate
extension, not a small one, and left for later rather than guessed at.

Verified in an actual browser against this repository's own regenerated map:
a short function's popup shows its real body; a function longer than the cap
(`history.lua`'s `M.analyze`, among others) shows the truncated text plus a
"+N more lines" badge with the exact real count; the existing popup lifecycle
(hover-open, click-to-pin, Escape-to-close) is unaffected. A committed
regression test (`TESTS/snippet_spec.lua`) checks `core/snippet.lua` directly
— an exact span, exactly-at-the-cap (the boundary itself, not "one over"),
over-the-cap, and an invalid/inverted span — plus an end-to-end check that
`functions.lua` actually calls it during a real scan.

## API endpoint inventory — call-based routing, ECOSYSTEM.md step 4 (2026-08-03)

`docs/ECOSYSTEM.md` §3.1's own conclusion: call-based routing (Express/
Fastify/Koa) is flat and belongs in an Analysis panel, structurally
identical to Plugins or Hooks; file-based routing (Next.js/SvelteKit/Nuxt/
Remix) has real parent-directory structure worth preserving and belongs in
a Hierarchy view instead — a materially different piece of work, not
attempted here. This entry is the first half only.

**`core/endpoints.lua` is new**, a layer-2 convention recognizer in
`FRAMEWORK_CONVENTIONS.md`'s own vocabulary — the same shape
`core/plugins.lua` already is for lazy.nvim specs, just for JS/TS's routing
convention instead. Recognizes `IDENTIFIER.METHOD("/path", ...handler)`
where METHOD is a lowercase HTTP verb or `all`, verified against a real
parse: `call_expression`'s `function` field is a `member_expression`
(`object`/`property` fields give the receiver and method name), and the
first argument is a `string` node. `app.use(...)` is excluded by construction
— `use` is simply not in the recognized method set, since it mounts
middleware rather than registering one route. With more than two arguments
(middleware chained before a final handler), the *last* argument is taken
as the handler.

**`framework` is read, never guessed.** Express, Fastify and Koa (via
`koa-router`) all accept the identical call shape, so nothing about the
call itself says which one it is — `detect_framework` instead checks this
file's own already-extracted `requires` for a known routing package name,
labelling every route in the file accordingly, or leaving `framework` `nil`
when the shape matched but no known package was imported. **The accepted
risk, stated rather than hidden:** nothing checks what the receiver
identifier is bound to — a cache or router-like object whose own
`.get(path, handler)`-shaped method happens to match would false-positive.
Not verified against a real Express application; `docs/ECOSYSTEM.md`'s own
stated limit ("every framework-syntax claim above is unverified") applies
here too.

**Widened a shared contract carefully, not casually.** `endpoints` is a new,
seventh value in every language backend's `scan_file` return — alongside
`plugins`, not folded into it, since `docs/ECOSYSTEM.md` explicitly treats
them as two separate per-node fields. Touched `Documentation.LangBackend`'s
type, both backends (`functions.lua` returns `{}` unconditionally — no Lua
equivalent convention — `core/lang/ecma.lua` calls the new recognizer), and
`scan.lua`'s two call sites (module node and leaf node construction).

**Two pre-existing call sites broke from the widened tuple, both found by
actually running the test suite, not by reading the diff.** `TESTS/
docmap_spec.lua`'s `select(4, functions.scan_file(...))` used to capture
three trailing values (symbols/plugins/lines); with a new value inserted
before `lines`, it silently captured `endpoints` into what the test expected
to be the line count, and `eq(loc, 13, ...)` failed with a table where an
integer was expected. `TESTS/lang_js_spec.lua`'s original fixture had the
same shape one position earlier. Both fixed by adding one more captured (or
skipped) slot; the failures themselves are the reason this widening was
verified against the full suite rather than only the new recognizer's own
fixture.

Ninth Analysis panel (`renderAnalysisEndpoints`), same shape as Plugins:
Method/Path/Handler/Framework/Declared-in columns, sorted by path by
default (an inventory, not a ranked health metric), `anFilter`/`anSort`
reused unchanged. A named handler gets the same `sigTrigger`/`docTrigger`
icons every other panel's functions do — clicking one opens the real
annotation popup for that function, not a copy. `:DocMap endpoints` mirrors
`:DocMap plugins` almost verbatim: every route into the quickfix list,
sorted by path, with a summary line reporting how many are documented.

Verified in an actual browser, with real Express-shaped source through the
real (scratch-built) JS grammar end to end: `app.get("/users/:id",
getUser)` (a documented handler, framework read from `require("express")`),
`app.post("/users", createUser)` (undocumented), and `app.delete(...,
function(req,res){...})` (inline, no handler name) all recognized correctly
— then the Analysis panel checked separately with a hand-built fixture:
correct columns, sort, filter, row click-through to Tree, the handler
trigger opening the real popup, and the empty state on this repository's
own map (which has no JS/Express code at all).

Left genuinely open: file-based routing (the other half of ECOSYSTEM.md's
own step 4, a Hierarchy view, not an Analysis panel — different enough
work to be its own future entry), and — same caveat every recognizer in
this document carries — no real-world Express/Fastify/Koa application has
been run through this yet, only hand-written fixtures.

## "Send a request" — an Endpoints mode in `:DocBrowse`, ECOSYSTEM.md step 6 (2026-08-03)

`docs/ECOSYSTEM.md`'s own step 6, worded as "documentation.nvim's endpoint
panel gains 'send a request'" — but *panel* meant the static HTML page's
Analysis tab (step 4's own delivery), and a browser page cannot
`pcall(require, "runtime-analysis")` a Neovim plugin. That is not a small
gap, it is the whole reason `docs/ECOSYSTEM.md` §7 already argues the
static × runtime join belongs **in the editor**, not baked into a
committed, byte-compared artifact. So step 6 is a new **Endpoints mode in
`:DocBrowse`** instead — the first new mode added since that browser's own
architecture was documented, and the first real exercise of
`telemetry-documentation-bridge.md`'s claim (in `lib.nvim`) that a seventh
mode costs "one string, one entry builder, one branch."

**Confirmed exactly that cheap, not assumed.** `MODES` in `browse/init.lua`
gained one string (`"endpoints"`); `view.lua` gained one builder
(`endpoints_entries`, reading `n.endpoints` — the same field the static
panel and `:DocMap endpoints` already read, a third consumer of data
`core/endpoints.lua` already extracts, no new extraction here) and one
branch each in the existing `M.entries`/`M.detail`/`M.status` dispatchers.
Unlike every other mode except Trail, Endpoints spans the whole tree rather
than centering on one node — `trail_entries` was the only existing
precedent for that shape, and this mode follows it rather than inventing a
second one.

**`gs` is the soft dependency `docs/ECOSYSTEM.md` §7 calls for explicitly**,
the same pattern already used twice in this ecosystem (`progress`→fidget,
`check.lua`→lua-language-server): `pcall(require, "runtime-analysis")`
inside the keymap's own handler, checked at call time rather than cached
at file-load time, since whether that plugin is installed is not a fact
about when documentation.nvim started. Absent, it notifies and stops —
present, it hands the selected route's method and path to
`runtime-analysis.nvim`'s own `M.open_request(lines)`, a new, small,
explicitly public function added there for exactly this join (see that
plugin's own README) rather than reaching into its internal file layout.

**Deliberately not an immediate send.** A route's `path` (`/users/:id`) is
relative and may contain unfilled `:param`s — genuinely nothing this
plugin's static analysis could send correctly on its own, so `gs` opens a
pre-filled request buffer and leaves the base URL and any real parameter
values for the reader to complete before running runtime-analysis.nvim's
own `:RASend` themselves.

Verified with the real dependency in both states, not only the common
one: `TESTS/run.lua` gained a `RUNTIME_ANALYSIS_DIR` environment variable,
the same shape `DOCUMENTATION_TS_PARSERS_DIR` already has for the JS/TS
parser tests — unset (this repository's own normal state), `gs`'s soft
dependency degrades to a notification, verified directly; set to a real
checkout of `runtime-analysis.nvim`, the same test exercises the real
integration end to end and confirms a real request buffer opens with the
right pre-filled content. A real test bug was found and fixed along the
way: an early draft asserted the buffer *number* must change after `gs`,
which failed — `:enew` reuses the current buffer outright when it is
still the pristine, unmodified `[No Name]` buffer, real Vim behavior the
test's own assumption had not accounted for; fixed by asserting on the
resulting buffer's content instead, which is the actual requirement.

`docs/ECOSYSTEM.md`'s own step 8 (a future telemetry mode) called itself
"Mode 7" before this session's own step 6 claimed position 7 in `MODES`
for Endpoints instead — noted there so a future reader is not confused
when telemetry lands as the 8th entry, not the 7th.

## `:DocMap tools` and the Tools Analysis panel — `lib.nvim.deps` manifest inventory (2026-08-10)

A repo-level counterpart to `:DocMap plugins`, for a different declaration
entirely: not lazy.nvim's `dependencies = {...}`, but
[`lib.nvim.deps`](https://github.com/StefanBartl/lib.nvim)'s own
`docs/install.json`/`docs/INSTALL.md` — the manifest a plugin ships for its
*optional external CLI tools* (pandoc, poppler-utils, curl, …). Blocked on
the data existing at all until `runtime-analysis.nvim` shipped its own
`feat(deps): show declared tools on first setup()`, proving the manifest
format was real and worth reading, not speculative.

`core/tools.lua` reads exactly this repo's own two known paths
(`<root>/docs/install.json`, falling back to `<root>/docs/INSTALL.md`) via
`lib.nvim.deps.spec.load` — deliberately **not** `spec.find`/`spec.plugins`,
which search `runtimepath` and lazy.nvim's plugin registry for *other*
plugins' manifests. That is the wrong shape here: `documentation.nvim` maps
one repo per invocation (see `docs/COMMANDS.md` § "Which repository do they
act on?"), never enumerates installed siblings, and `core/tools.lua` keeps
that same scoping rather than reintroducing multi-repo discovery through
the back door.

**Declaration only, never presence.** Whether a declared tool is actually on
`$PATH` differs by machine, and `ir.tools` is serialised into the committed
artifact — baking a live `vim.fn.executable` result into it would make
`--check`'s byte-compare depend on who last regenerated the map, exactly the
reason `ir.timing` already stays out of the artifact (see `init.lua`). What
`docs/install.json` actually declares (`bin`/`required`/`why`/`pkg`) is
deterministic and is exactly what `core/tools.lua` returns. "Is it installed
here" stays lib.nvim's own live `:Lib deps show <plugin>` command's job, on
purpose, not duplicated into a static page that might be read on GitHub
Pages days later on a different machine entirely.

`lib.nvim.deps.spec` is treated as an optional submodule even though
lib.nvim itself is a hard dependency of this whole plugin — same posture
`bindings/progress.lua` already takes toward `lib.nvim.progress`: a pinned
or older lib.nvim checkout might not ship the `deps` submodule yet, and this
one feature should degrade to "not available" rather than error the whole
scan. `pcall(require, "lib.nvim.deps.spec")` at module load, once, not
per-call.

A malformed manifest entry (missing `bin`, empty `why`, no `pkg` map) does
not just silently vanish from the list the way an unrecognized lazy.nvim
spec shape would — `tools-spec-invalid` (warn) surfaces it as a drift
finding, reusing `lib.nvim.deps.spec`'s own validation (`errors`, never
nil) rather than re-validating a second time in this tree.

Verified against this repository's own tree, which ships neither
`docs/install.json` nor `docs/INSTALL.md`: `ir.tools` is `nil`, the panel
says so plainly instead of rendering an empty table, and `:DocMap tools`
notifies rather than opening an empty quickfix list — the same "a missing
thing is a real answer, not a broken one" posture `docs`/`quicks` already
take when a tree has nothing for them to find.

## Hierarchy: hide/dim individual boxes (2026-08-10)

A right-click "Dim this box" / "Show this box" on any Hierarchy box, plus a
"Hidden (N) — show all" toolbar pill to clear all of them at once — pure
client-side JS in `core/render/html.lua`, no Lua-side change to the IR or
the pipeline at all, since the whole feature is about how already-rendered
boxes are painted, never about what data feeds them.

**Dims, never removes from the layout.** The alternative — actually
excluding a hidden node from `layoutModules`/friends — was considered and
rejected: a Modules-view box has children whose position is computed
relative to it, so removing it mid-tree means either reparenting its
children or leaving a gap, real complexity the stated goal ("make a large
tree less noisy") does not need. Instead a dimmed box keeps its computed
position in `hboxes`/`positions` and gets `opacity: .08` +
`pointer-events: none` — the exact mechanism hover-focus already used
(`#hgraph.focusing .hnode{opacity:.22}`), just made persistent and per-box
instead of transient and neighbour-based. The genuinely structural version
of this idea — re-rooting the whole diagram, hiding an entire level — is a
separate, larger roadmap item ("Hierarchie: Root-Level aus-/einblenden mit
Zoom-Slider") left open on purpose; conflating the two would have turned a
Mittel-effort readability fix into the Hoch-effort re-layout feature.

**State design copied deliberately from Compare marks**, not invented fresh:
`state.hidden`, an array of the same keys `hboxes`/`boxSpec` already use (a
node id, a class name, or an `fnKey`), with its own `localStorage` key
(`docmap:hidden:<pathname>`) and its own hash serialization — but, unlike
`marks`, scoped *inside* `serializeState`'s Hierarchy branch rather than
global, since a dimmed box has no meaning outside that one tab (matching
`dir`/`depth`/`ext`/`fn`, not `marks`). On load, a hash that names a
`hidden` set wins outright over whatever `localStorage` had — the same "an
explicit link is a statement about what to look at, not a suggestion to
union with what this browser had lying around" rule `marks` already
enforces, verified directly (a link naming one box wins over a different
box previously dimmed and stored).

`describeTarget()` gained one field, `hkey` — set only in the branch that
resolves an actual Hierarchy `.hnode` element, so `buildMenu()` can gate the
new entry on "was this menu opened on a graph box" without a second target
type. Right-clicking the same node's tree row or a reference to it in a
detail pane offers no hide/dim entry, correctly: neither has a box on
screen to dim.

No Lua-side test coverage, matching every other piece of Hierarchy
interactivity (`reconcile`, zoom, hover-dim, the context menu itself) —
`html.lua`'s embedded JS has none, by established precedent, not an
oversight here. Verified instead by driving the generated
`docs/map/index.html` in a real browser: dispatched a real `contextmenu`
event on a box, confirmed "Dim this box" appears and toggles the box's
class/the toolbar pill/the URL hash/`localStorage`, confirmed the label
flips to "Show this box" on a second right-click, confirmed the toolbar
pill's "show all" clears everything, and confirmed the hash-wins-over-
localStorage precedence with two different boxes across three separate
fresh page loads.

## `docs/FEATURES/` convention + the Features tab (2026-08-10)

The largest roadmap item this session: a canonical, mechanically-readable
`docs/FEATURES/` folder format, plus a ninth top-level tab that renders it —
`core/features.lua` (parser), `ir.features` (IR field), `drawFeatures()`
(the tab itself), and [`docs/FEATURES_FORMAT.md`](../FEATURES_FORMAT.md)
(the field guide). See `docs/PIPELINE.md`'s own "Features tab" section for
the full design writeup; this entry is the decision record.

**Design was not invented from a blank page.** Before writing anything, a
survey of the user's own ~30 plugins found `docs/BINDINGS.md` universally
consistent (this plugin's own generator) but "FEATURES" genuinely three
different, independently-invented shapes — `lib.nvim` (essay write-ups),
`markdown.nvim` (compact per-feature metadata blocks), `color_my_ascii.nvim`
(full user manuals). The chosen format is deliberately closest to
`markdown.nvim`'s, the one shape that is both ordinary prose and reliably
parseable line-by-line, confirmed by user choice between the three surveyed
options rather than picked unilaterally.

**No fixed metadata vocabulary** (`Module`/`Keymaps`/`Config`, or anything
an author writes) — `markdown.nvim`'s own real `docs/FEATURES/headings.md`
already mixes known keys with one-off ones like `Scope-aware` in the same
file, and a whitelist would have rejected working documentation that
predates this parser. Validated against that real file directly while
building the parser, not only against invented fixtures: the first version
of `parse_body` treated any non-bullet line as ending a metadata run,
which silently dropped every bullet after the first one whose value wrapped
onto an indented continuation line — a real, common shape in that file
(`- **Module:** ...` regularly continues on the next line with a
2-space-indented function list), not a synthetic edge case. Fixed by
folding an indented continuation line into the bullet it continues, and
only ending the run on a blank line or a flush-left non-bullet line.

**Dogfooded**: this repo's own [`docs/FEATURES/`](../FEATURES) (a
deliberately small, real sample — Compare marks, Hierarchy hide/dim, and
the Plugins/Tools Analysis panels — not full coverage, `docs/PIPELINE.md`
stays the complete reference), verified rendering in a real browser against
the generated `docs/map/index.html`: all four cards, their summaries, their
metadata, and the `Module:`-bullet-to-Tree-tab link resolution (which
endswith-matches a bullet's first backtick-quoted token against every
node's own `source`/`path` — the same leniency `tag_links` resolution
already extends elsewhere).

**A real, separate bug found and fixed along the way, affecting `tools` as
much as `features`**: `core/render/html.lua`'s `M.render` builds the
generated page's embedded IR payload as its own `json.encode({...})` table,
independently of `documentation.to_json` (`module_map.json`'s writer) — a
fact a comment thread in that exact function already documented, left by
two *earlier* omissions of the same shape (`duplicates`, `docs`). Both
`ir.tools` (added earlier this session, see the `:DocMap tools` entry
above) and `ir.features` were present on the scanned IR and in
`module_map.json`, but **absent from the generated page's own embedded
JSON** — meaning the Tools Analysis panel had rendered "no manifest found"
unconditionally, for every repo, regardless of whether one actually
existed, since the moment it shipped. Caught here by checking
`module_map.json`'s actual keys against a real repo rather than trusting
that `scan_full` setting the field was the whole story — the same category
of mistake the comment thread already named, now stated a third time in
`M.render` itself so a fourth field does not repeat it.

## External call/plugin visibility — `node.calls_external` + `opts.external_repos` (2026-08-10)

Two problems the roadmap named together, because they turned out to share
one join and one table: *why* is a dependency here (which of its functions
does the tree actually call), and *where* is its source, since it's outside
the scan by definition.

**The "why" half cost no second traversal.** `core/deps.lua` already threw
the alias away the moment it decided a required module was external —
`deps.build` kept only the module string, for `requires_external`.
`core/calls.lua` extends the exact same alias-building pass with the
negative case (`external_aliases`, built alongside the existing internal
`aliases` from the same `node.requires_raw` loop) and joins it against the
same `calls_raw` callee text that already resolves `fs.read(x)`-shaped
internal calls — `node.calls_external`, counted, not just detected. Both the
alias-bound shape (`local async = require("plenary.async"); async.run(x)`)
and the inline shape (`require("plenary.job").new(x)`) resolve, mirroring
the two internal-call shapes `calls.lua` already recognized.

**The "where" half needed new user configuration, and there was no way
around that.** Researched before writing anything: no mapping from a bare
namespace (`"plenary"`) to a GitHub `owner/repo` exists anywhere this plugin
can already see. `core/plugins.lua`'s lazy.nvim spec extraction looked like
a candidate — it does parse real `"owner/repo"` strings — but only fires
when scanning a Neovim *config* repo that declares the dependency, never the
dependency's own plugin repo, which is the actual shape this feature is for
("plenary is a dependency of *this plugin*"). `opts.external_repos` is a new
sibling to `opts.tag_files`, resolving into the identical `ir.tag_links`
table (never overwriting an entry `tag_files` already set) so the existing
`boxSpec`/click-handling code needed zero new UI to consume it.

**A guessed link, corrected mid-build by real data.** The first version
guessed `<lua_root>/<module path>.lua` unconditionally — right for this
repo's own layout, wrong for `lib.nvim`'s: verified against a real checkout
while building this, `lib.nvim` uses the `<module>/init.lua` directory shape
almost everywhere (`autocmd/init.lua`, `fs/read/init.lua`, `deps/spec/init.lua`,
...), and a flat-only guess got every single one of them wrong. Fixed with
an optional `local_path`: when given, both shapes are checked against the
real checkout on disk (`uv.fs_stat`, not a network call — `scan_full()`/
`--check` stay exactly as offline as `tag_files`'s own local-path resolution
already is), verified correct against three real `lib.nvim` modules
end-to-end afterward. Flagged explicitly in both the module header and
`docs/PIPELINE.md`: `local_path` must not vary between where a repo is
regenerated and where its `--check` runs (CI, typically), or the resolved
path shape becomes an irreproducible part of the committed artifact —
exactly the failure mode `tag_files`'s own "local paths only" design
already avoids, so documentation.nvim's own `scripts/gen_map.lua`
deliberately does not configure `external_repos` for itself.

Rendered in the Deps view's existing external box, not a new panel: the
box's second line gains a total (`external ↗ · 27 calls`), its tooltip a
per-function breakdown sorted by count. Verified end-to-end against this
repo's own real `require("lib.nvim...")`/`require("pdfport")`/
`require("runtime-analysis...")` calls — 21 real call sites across the tree,
correctly counted and correctly linked (`lib.nvim.notify` → 27 calls,
`.warn` 14×/`.info` 10×/`.error` 2×/`.create` 1×, linking to
`lib.nvim/blob/main/lua/lib/nvim/notify/init.lua`, confirmed against the
real file on disk) — via a one-off `generate()` call, never wired into the
committed `scripts/gen_map.lua` for the reproducibility reason above.
`TESTS/calls_external_spec.lua` and `TESTS/external_repos_spec.lua` cover
both halves with fixtures, including the wrong-guess-corrected-by-
`local_path` case directly.

## Module Calls — a sixth Hierarchy view, weighted (2026-08-10)

The largest remaining "Hoch" roadmap item: a weighted, module-to-module
alternative to the existing per-function Calls view. Same `kind="call"`
edges, collapsed by shared-reference edge objects (`moduleCallOut[from]`
and `moduleCallIn[to]` for a pair point at the *same* object, so
incrementing `.weight` once when a new call edge is processed updates
whichever adjacency list a walk finds it from), self-edges (two functions
in one file calling each other) dropped since a module graph has nothing
to say about a module calling itself. `layoutModuleCalls`/
`addModuleCallExternals` in `core/render/html.lua`, modelled directly on
the existing `layoutDeps`/`addExternals` — the same `+ external` toggle,
direction and depth axes, sourced from `node.calls_external` (built the
session before this one) rather than `requires_external`, summed per
(node, module) pair since a module can call several distinct functions in
the same external module where `requires_external` is already a
deduplicated module list.

**Shipped as a view, not the tab the roadmap item's own text asked for.**
"Gewichtete Alternativ-Ansicht des Call-Graphen, eigener Tab" said
"verdient einen eigenen Tab statt eine Erweiterung des bestehenden
Hierarchy-Tabs" — deserves its own tab, not an extension of the existing
Hierarchy tab. Raised with the user before implementing (design decisions
1–4 below all confirmed via `AskUserQuestion`) and built as a sixth
Hierarchy view instead, on the grounds that the view is exactly as
centered-on-a-node/directed/depth-limited as Deps already is, and a new
tab would have meant either duplicating the existing zoom/pan/hide-dim/
context-menu/SVG-export machinery for one caller or generalizing it — the
roadmap item's own literal wording is deliberately not what shipped, with
the user's explicit approval. Confirmed via two rounds of questions:
(1) module-to-module aggregated edges, weight = underlying call count, not
function-to-function; (2) external modules included as nodes in the same
graph; (3) a view inside Hierarchy, not a new tab; (4) the same In/Out/Both
toggle and depth control the other directed views already have.

**Weight, drawn.** `stroke-width = min(1.5 + log2(weight) * 1.1, 7)`,
applied via `path.style.strokeWidth` — an inline style, not a
`stroke-width` presentation attribute, because the page's own
`.hedge{stroke-width:1.5}` CSS class rule would silently win over the
latter and flatten every edge back to the same width. Log-scaled so one
outlier pair does not compress every other, genuinely interesting weight
difference into visual noise.

**A real corruption caught in passing, not by any test.** A literal NUL
byte had landed inside a string concatenation (`e.from + "\x00" + e.to`
instead of `"\x20"`) during editing — found via `grep`'s own "binary file
matches" warning on a `.lua` file that should never trigger one, not by
any test or lint (Lua permits embedded NUL bytes inside a string literal,
so `loadfile` alone would not have caught it; the two module-pair keys it
produced would still have been syntactically valid, just silently
wrong — a phantom pair that could never match a real edge). Fixed with a
byte-level Python pass, re-verified with `loadfile` and the full CI suite
afterward.

Verified against this repo's own real call graph (511 call edges, one node
with three distinct external modules called) in a live browser session:
edge weights/labels/stroke-widths correct, external-box aggregation
correct, `dir=both&depth=3` widened the graph correctly, URL-hash
round-tripped through a manual `hashchange` dispatch, no console errors,
Deps/Calls views unaffected by the shared edge-processing loop's
extension. No new `TESTS/*_spec.lua` file — consistent with the
established precedent that `html.lua`'s embedded client-side JS has no
direct Lua test coverage anywhere in this project; `docs/PIPELINE.md`'s own
"Module Calls: weighted alternative to Calls" section is the design
writeup this entry compresses.

## Promoting a feature to its own tab — `Tab: true` (2026-08-10)

A `docs/FEATURES/` author can now mark one feature especially
important with `- **Tab:** true` and get it a real top-level tab instead
of a card in the Features catalog — dynamically registered at page load
(`buildPromotedTabs`), not baked into the nine tabs' static markup.
`core/features.lua`'s `parse_body` gained a third return value,
`body_start_idx` (where the metadata run ended), so a promoted feature's
entire post-metadata section — headings, fenced code, lists, paragraphs —
can be captured as `entry.body` and rendered through a small new
client-side Markdown subset (`renderFeatureBody`/`inlineMd`): the same
"cheap reliable reading beats a general one" discipline the parser itself
already follows, deliberately not CommonMark (no tables, blockquotes,
images, nested/ordered lists, raw HTML).

**Gated on real usage first, then built anyway.** The roadmap item's own
text said this was "erst sinnvoll zu bewerten, wenn `docs/FEATURES/` in
echten Repos genutzt wird und sich zeigt, ob der Bedarf real ist" — only
worth evaluating once real repos show the need. At the time this shipped,
only this repo's own dogfooded `docs/FEATURES/` used the convention at
all. Put to the user explicitly before starting (`AskUserQuestion`); the
answer was to build it now rather than wait.

**A real bug in this entry's own drafting, corrected before it shipped.**
The first cut of this design added a caveat — "requires at least one
metadata bullet, or the body is silently folded into a flattened summary"
— that does not describe anything reachable: `- **Tab:** true` is *itself*
a bullet, so a promoted feature always has at least one, and the
zero-bullet fallback the caveat warned about is `core/features.lua`'s
behavior for an *unpromoted* feature with no bullets at all, never a
promoted one. Caught by writing a throwaway fixture and reading the
parser's real output before finalizing the docs (three shapes: a
Tab-only bullet with nothing else, Tab plus a body, Tab plus another
bullet with no trailing body) — `body` is `nil` exactly when nothing
follows the metadata block, a real state and not a limitation. The three
fixtures became `TESTS/features_spec.lua`'s own coverage once confirmed
correct, and the type doc comment and code comment that repeated the
same wrong claim were fixed alongside the prose.

**A sharp edge in this file's own architecture, hit and fixed while
writing the link-rendering regex.** The whole embedded client-side script
lives inside one Lua `[[...]]` long string, which ends at the first
literal `]]` it finds. `[^\]]` (the ordinary way to write "not a closing
bracket" in a regex) contains exactly that byte pair and silently
truncated the script mid-file — caught immediately by the Lua syntax
check, not shipped. Fixed with `[^\x5d]`, a hex escape for the same
character with no adjacent brackets in the source text.

Dropped from the Features catalog entirely once promoted (`drawFeatures`
filters `entry.tab` out of both the card list and its counts). A stale
promoted-tab link (the feature renamed, un-promoted, or its theme file
deleted since the link was made) falls back to the Features catalog rather
than leaving the page blank — checked in `applyState` against the live
`collectPromotedFeatures()` list before anything else runs.

Dogfooded on this repo's own "Module Calls view" entry in
`docs/FEATURES/CORE.md` (the entry directly above this one in git blame,
promoted the same session it shipped) and verified end-to-end in a live
browser: the tab button appears in the right position with the right
label, its content renders headings/paragraphs/a fenced block/inline code
correctly, the card list drops to 11 and its own file's count reflects the
exclusion, a direct `#tab=feature-module-calls-view` link opens correctly
on a fresh load, and an invalid `feature-` slug redirects to the Features
catalog with exactly one `.view` panel active. `TESTS/features_spec.lua`
covers the parser; the client-side renderer has the same "no direct Lua
test coverage" precedent noted in the Module Calls entry above.

## Root-level hide slider — a forest view for the Modules tab (2026-08-10)

The last remaining concrete "Hoch" item: "Hierarchie: Root-Level
aus-/einblenden mit Zoom-Slider" — a vertical, Google Maps-styled slider
(`+` top, `−` bottom) that hides the top N layers of a deep directory
tree, so the layer that used to sit at that depth becomes the new apparent
root. Aimed at the gap double-click-to-recenter (pre-existing) does not
close: a tree several directories deep before anything interesting starts
means every session begins with the same uninteresting clicks.

**A forest, confirmed before building.** The roadmap text supported two
readings — re-center on one specific node (which double-click already
does) or show every node at the chosen depth simultaneously as parallel
roots. Put to the user directly rather than guessed: "Level-2-**Ordner**",
plural, named the forest reading, and it was confirmed as the one to
build. Technically cheap once decided: `walk()`'s Deps/Calls/ModuleCalls
sibling already took an array of seeds, and even `layoutTypes` already
seeded from several class names at once — only `layoutModules` had ever
been called with exactly one. Refactored into a shared
`layoutModulesFrom(seeds)`; `layoutModules(id)` is now `layoutModulesFrom([id])`,
and the new `layoutModulesRooted(n)` feeds it `rootFrontier(n)` — every
node at exactly `n` steps below `IR.root` via `children`, found with a
plain BFS.

**Mutually exclusive with node-centering, enforced in one place.**
`center` (recenter on a specific node) and `hideroot` (peel off N layers,
forest mode) are two different answers to "what does the Modules view
show" and cannot both apply — `navigate()` now clears whichever one a
patch does not set, whenever the other is set. Centralizing it there
avoided auditing the dozen-plus call sites that set `center`
(double-click, context menu, mouse-wheel drilling, Enter in the search
box) individually; all of them get the reset for free. The one path that
does *not* go through `navigate()` — the search box's live-typing
preview, which calls `drawHierarchy` directly to avoid clobbering history
on every keystroke (a real, previously-fixed bug; see that code's own
comment) — needed the exception spelled out by hand, via a new third
`forceCenter` argument on `drawHierarchy` itself, since bypassing
`navigate()` also bypassed the auto-clear. Caught by reasoning through
every call site during design, not found later by testing: verified
afterward by artificially re-entering forest mode and confirming a typed
search match interrupted it correctly, rather than being ignored.

**The slider's `max` is a real measurement, not a guess** —
`maxRootDepth()`, one cached BFS over the tree's actual `children` depth
— so dragging past the point of nothing-left-to-show is structurally
impossible through the UI. A hand-edited URL hash can still name an
out-of-range `hideroot`; `layoutModulesRooted` clamps it against the same
`maxRootDepth()` at layout time regardless, matching `depth`'s own
"anything unparseable degrades to a sane value" posture.

**`writing-mode: vertical-lr`**, not a `transform: rotate()` hack, turns
the native `<input type=range>` vertical — standard behavior renders min
at the bottom and max at the top with no extra flipping, which is exactly
"+" (hide more, higher value) above "−" (hide less, lower value) matching
the Google Maps analogy the roadmap item itself named.

Verified against this repo's own real tree (`IR.root`'s single child
folding into a genuine 4-way fork one level down: `bindings`/`config`/
`core`/`editor`) in a live browser session: `hideroot=1` shows exactly the
expected single subtree, `hideroot=2` shows exactly the expected 4
parallel roots with zero boxes carrying the "center" highlight class, the
breadcrumb reads correctly at each level, the slider's own `max`/value/
disabled-state track real state, Up decrements instead of walking to a
parent, Root resets both axes, double-click on a forest-root box exits
forest mode and centers on it, a direct `#hideroot=2` link opens correctly
on a fresh load, the live-search override interrupts forest mode
mid-keystroke and Enter commits it permanently, and Deps/Calls/other views
are unaffected (slider hidden, `layoutModules`'s own single-seed behavior
unchanged). No console errors at any step. No new `TESTS/*_spec.lua` file
— same "html.lua's embedded client-side JS has no direct Lua test
coverage" precedent every other Hierarchy-view feature this session has
already noted.

## Call hierarchy in native LSP UI — `opts.callhierarchy` (2026-08-10)

The largest of the two remaining research-gated roadmap items:
"LuaLS' fehlendes in/outgoing calls-Feature mitbedienen", whose own text
said the first step had to be pure research — does a sensible extension
point for this even exist, in LuaLS or in the LSP itself.

**LuaLS: confirmed, not assumed, to have none.** A full GitHub code search
across `LuaLS/lua-language-server` for `callHierarchy`/`incomingCalls`/
`outgoingCalls`/`prepareCallHierarchy` returned zero hits, and the
repo's own open feature request for exactly this
(LuaLS/lua-language-server#2832) has sat unstaffed since August 2024 —
two years old at the time this was checked, no branch, no PR, no
milestone.

**Neovim itself: confirmed, via its own source, to have a real one.**
`vim.lsp.ClientConfig.cmd` may be a Lua function returning a
`vim.lsp.rpc.Client`-shaped table instead of a shell command — a
documented, in-process (no external process spawned) way to attach a
second, narrow LSP client. `vim.lsp.buf.incoming_calls()`/
`outgoing_calls()`/`hover()` all query every attached client and merge
results (`lsp.get_clients()` + `lsp.buf_request_all()`, read directly out
of Neovim's own `lsp/buf.lua`), which is what lets this client sit
*beside* LuaLS rather than needing to replace any part of it — LuaLS
keeps completion, diagnostics, its own hover; this one is asked only the
one question it advertised answering.

**A real, sharp edge found by building a throwaway probe first, not
assumed from documentation** — no worked example of the in-process
(no external process) shape of `cmd` turned up in any search: the client
table's own methods (`request`/`notify`/`is_closing`/`terminate`) are
called *without* an implicit `self`. A `request = function(self, method,
...)` signature received `params` in `method`, silently shifted by one
argument, no error — found by writing exactly that bug first, then a
minimal headless probe confirming the dot-call convention and a real
`vim.lsp.buf_request_all` round-trip end to end, before writing the real
module. Documented in `editor/callhierarchy.lua`'s own header so the next
person who touches this file does not rediscover it the same way.

**Costs no new scan.** `Documentation.Handle.callers`/`callees` already
existed (built for the HTML map's own Calls view); position resolution
uses `Documentation.FunctionInfo.line`/`line_end` — the function's real
declared span — so a cursor anywhere in a function's body resolves
correctly, not only its declaration line. Heuristic-confidence edges
(`opts.calls_heuristic`) are shown, not dropped, flagged with
`" (heuristic match)"` appended to the item's own `detail` — LSP's
`CallHierarchyItem`/`*Call` shapes have no field for "this one's a
guess" the way the HTML map's `weak`-classed dashed edges do.

**Opt-in, off by default** (`opts.callhierarchy`, `install()`-only), same
posture as `watch`/`pdf` — confirmed with the user before building rather
than assumed, on the reasoning that an existing `install()` caller should
not be surprised by a new background LSP client attaching without asking
for it. Scoped by `registry.ensure_callhierarchy`, the same
`is_subpath`-against-`source` mechanism `ensure_watch` already uses, one
sibling function beside it — a file outside the scanned tree never gets
this client.

Also confirmed with the user before building: hover-injection ("N
callers / M callees" surfaced in the ordinary hover popup, alongside
whatever LuaLS's own hover already shows) shipped in the same pass as
call hierarchy itself, not deferred as separate follow-up work — the
roadmap item's own text named it as one of two example integration
surfaces (the other being CodeLens, not built).

Verified twice: `TESTS/callhierarchy_spec.lua` end to end against a real
fixture — `vim.cmd.edit()` firing the real `BufReadPost` autocmd,
`vim.wait()` for the client to actually attach, real
`vim.lsp.buf_request_all()` calls through Neovim's own dispatch, not a
private call into the module — covering `prepareCallHierarchy`,
`incomingCalls`, `outgoingCalls`, `hover`, and the negative scope check
(a file outside `source` never attaches). Then a second time against
this repo's own real codebase, not only the fixture: `M.ensure_watch` in
`registry.lua` came back with two real incoming callers (`M.install`, and
`browse/source.lua`'s own `M.acquire` — a call site not manually checked
beforehand), correctly named, correctly keyed, correctly line-numbered.

## Findings as native diagnostics — `opts.diagnostics` (2026-08-10)

The last remaining Hoch item from the "generell" cluster this session
worked through: "Eigene Findings als `vim.diagnostic` statt nur
Quickfix" — `Documentation.Finding[]`, until now reachable only through
the `:DocMap check` quickfix list, also published as native
`vim.diagnostic` entries on every open buffer that has one.

**Simpler than the call-hierarchy item shipped just before it, on
purpose.** No LSP client needed at all — `vim.diagnostic.set(ns, bufnr,
diagnostics)` works directly on any already-open, loaded buffer.
`bindings/diagnostics.lua`'s `publish(root, handle)` groups
`handle.findings()` by `node`, resolves each to a real open buffer via
`vim.fn.bufnr()` (never opens or loads one itself), and sets diagnostics
once per touched buffer — no request/response cycle, no in-process fake
server, none of `opts.callhierarchy`'s own architecture.

**File-level granularity confirmed as the right v1 scope, not assumed.**
Checked before writing anything: `Documentation.Finding` carries no
`line` field, only `node` (a whole file) — and the existing quickfix
publisher (`bindings/usrcmds/generate.lua`'s `M.check`) has the exact
same limitation, setting `filename` but never `lnum` either. Put to the
user directly: extend `Documentation.Finding` with an optional `line`
now (real per-line precision for the ~5-6 checks that already compute
one internally, at the cost of also touching `core/check.lua`), or ship
the simpler, `bindings/`-only version first. Chosen: file-level first: no
`core/` change, matches what quickfix already does, and per-line
precision stays a real, separately-scoped future step rather than
scope-creeping into this pass.

**`info`-severity findings are shown, not filtered, on the user's own
call** — mapped to `vim.diagnostic.severity.HINT`, a fourth,
deliberately unobtrusive tier the quickfix list's own `M.check` has no
equivalent for and explicitly excludes them from
(`if f.severity ~= "info"`). Confirmed rather than assumed to just
mirror quickfix's own filter: using a capability quickfix never had
beats reproducing its narrower one for no real reason.

**Clearing a fixed finding needed to be earned, not assumed for
free** — `vim.diagnostic.set()` replaces the whole set for a
buffer/namespace pair, but a buffer whose last finding just got fixed
drops out of the current pass's `by_node` grouping entirely, so nothing
would tell it to clear on its own without extra bookkeeping. `publish`
tracks every buffer it has ever diagnosed, per root, and explicitly
zeroes any that fell out of the current findings. Verified precisely,
not just by count: `TESTS/diagnostics_spec.lua` fixes two of four real
findings in a fixture (`missing-summary`, `dead-function`) and rescans,
then asserts the *other* two specific findings
(`missing-readme`, `unreferenced-module`) survive rather than merely
checking the count dropped — a bug that cleared everything and reset it
wrong would also shrink the count, which is exactly what a looser
assertion would have missed.

Wired via `registry.ensure_diagnostics`, a sibling of `ensure_watch`/
`ensure_callhierarchy` using the identical `is_subpath`-against-`source`
scoping, plus one `handle.on_change` subscription for live refresh on a
watch-triggered or manual rescan. One real ordering difference from its
two siblings, worth stating plainly: this needs `entry.handle` to exist
*synchronously* at call time (`on_change` is subscribed once, not read
lazily from inside a later autocmd callback the way
`ensure_callhierarchy`'s is), so `install()` calls it only after
`entry.handle` is fully built — after, not alongside, `watch`/
`callhierarchy` above it.

Verified a second time against this repo's own real codebase, not only
the fixture: opening `editor/health.lua` (flagged `unreferenced-module`
by the real scan — required by no other file in this tree) produced
exactly one real `HINT`-severity diagnostic, correct check name, correct
message, on line 1.

## Compiler Explorer links, experimental — `opts.godbolt` (2026-08-10)

The "Fragwürdig — eher nicht umsetzen" item, reopened on the user's own
feedback: "Compiler Explorer ist für kompilierte Sprachen gedacht... für
Lua fehlt der eigentliche Nutzen fast komplett" was the wrong call, and
the user was right to push back rather than let it sit rejected.

**Checked before agreeing, not taken on the user's word alone** — the
project's own established practice all session: `/api/languages` on
Compiler Explorer's real API lists `lua` as a genuine language id,
`/api/compilers/lua` lists five real Lua interpreter versions (5.1.5
through 5.5.0), and the `lua` compiler class's own source
(`lib/compilers/lua.ts`) runs `luac -l -l -p <file>` — a real, verbose
bytecode listing with source-line association, exactly the kind of
"compiled output" the original assessment said Lua had none of.
Confirmed a second way, not just by reading source: built a real
clientstate link from this repo's own `registry.lua#norm_root` function,
opened it in a real browser, and got back a real disassembly
(`VARARGPREP`/`CLOSURE`/`RETURN` opcodes, locals/upvalues tables) from a
real server-side compile — the original dismissal was simply wrong, and
would have stayed wrong without checking a primary source instead of
trusting a training-time assumption about what Compiler Explorer
supports.

**The other half of the user's feedback — loading the whole project —
does not hold up the same way, and the gap is disclosed rather than
faked.** `luac` compiles exactly one file per invocation; Compiler
Explorer's multi-file/project support is CMake/build-system-specific
(C/C++, Java templates), and nothing Lua-specific for it turned up
anywhere checked. Shipped instead: a module's own link concatenates its
own functions' snippets in declaration order, a real, useful
approximation of the file's interesting content, not a byte-perfect
reconstruction — comments, `require`s, module-scope symbols outside a
function are not part of it. This gap is the concrete, stated reason the
feature ships marked **experimental**, confirmed with the user before
building rather than silently under-delivering on "whole project" and
calling it done.

**Structurally different from the three features shipped just before
it, confirmed with the user first.** `callhierarchy`/`diagnostics`/`watch`
are all `install()`-only, live-editor features. This one bakes into the
generated static page itself (`meta.godbolt`, the exact render-time-only
mechanism `out_depth` already uses) — `generate()`/`scan_full()`-time, so
it works for anyone who opens the committed `docs/map/index.html` cold,
matching what the roadmap item's own original text actually described (a
page feature with icons, not an editor affordance).

**No new IR field.** The link is built entirely client-side, lazily on
click, from `fn.snippet` — already serialized for the existing
hover-preview feature (bounded snippets, ECOSYSTEM.md step 3) and already
bounded the same way. A truncated snippet produces a correctly-labelled
but incomplete compile on Compiler Explorer's side, the same honesty the
in-page preview already carries via its own `snippet_omitted` count, not
a new limitation this feature introduces.

**Compiler Explorer's own documented `clientstate` URL scheme**
(`godbolt.org/clientstate/<base64 JSON>`) needs no API call to build —
UTF-8-safe base64 (the standard `encodeURIComponent`/`unescape`/`btoa`
detour, since `btoa` alone is Latin1-only) client-side, then open the
result. Fully deterministic from the same source, so this puts nothing
non-reproducible into a committed artifact — checked against `--check`'s
own byte-for-byte comparison before building, not after.

## `.plugin-gated` badge/accent styling (2026-08-10)

A small `🔌` badge (`::after` on the button) plus a `var(--ext)` text tint
— the same colour the Hierarchy graphs already use for "connects outside
this map", reused here for "depends on something outside this plugin" —
for a tab-bar/panel button whose usefulness depends on something optional
being present. Applied first to the existing Analysis → Tools button
(`data-atool="tools"`, populated from `docs/install.json` when the
scanned repo declares one), with a `title` tooltip spelling out exactly
what it's conditional on.

Deliberately a CSS class (`.plugin-gated`), not a one-off style on the
Tools button specifically: raised alongside a concept for a future
Telemetry Analysis panel (`docs/ROADMAP/ROADMAP.md`'s "Genuinely open"
section) that will need the identical treatment once built, gated on a
soft dependency (`runtime-analysis.nvim`) rather than a manifest file —
same visual signal, two different kinds of "optional" underneath it.
Confirmed with the user which visual treatment (badge + tint, vs. badge
alone, vs. tint alone) before building.

## Analysis → Telemetry panel, server-backed (2026-08-10)

A new `.plugin-gated` Analysis atool (`data-atool="telemetry"`, sibling to
Tools) surfacing `runtime-analysis.telemetry`'s call counts for this
project's own functions, joined against the IR by `core/telemetry_join.lua`
— the same join `:DocBrowse telemetry` already used, now reachable from the
generated static page too.

**Not `generate()`-time baking, unlike Tools — this was the original design
and it was wrong.** An earlier draft of this feature's concept note assumed
it would bake the current aggregate into `module_map.json` the same way
`opts.tools` bakes `docs/install.json`. That assumption did not survive
contact with `--check`: call counts change between runs, and any two
regenerations of the same source would produce a different artifact for a
reason that has nothing to do with the tree changing — exactly the
determinism `core/tools.lua`'s own header already argues host-presence
checks must stay out of the artifact for, one step further (there the
*shape* is deterministic and only presence is not; here the counts
themselves are the volatile part).

Built instead as a new `GET /api/telemetry` route on
`documentation.editor.serve` (`:DocMap serve`), reading
`telemetry_join.load()`/`.rows()` fresh on every request — always the
latest aggregate, never stale, exactly `serve.lua`'s own History route's
reasoning (a `file://` page cannot `fetch()` anything at all, so "load on
click" already meant a server for History, and now for this too). Opened
from `file://` the panel explains itself rather than silently doing
nothing, the same treatment History already gives that case. Every "nothing
to show" case (no namespace configured, no map generated yet, no telemetry
data recorded) answers `200` with `{available:false, reason:...}` and a
specific message — never an HTTP error, since absence of telemetry data is
a normal outcome here exactly as `telemetry_join.lua` already insists
everywhere else.

**A real, previously-unnoticed bug in `core/telemetry_join.lua` was found and
fixed while building this — not a synthetic issue, a real one.** Verifying
against real data (`runtime-analysis.telemetry`'s own self-instrumentation
of this tree, curled through a real headless server) initially returned
zero rows despite confirmed real data on disk. Root cause: `Documentation.
IR.nodes` is keyed by `node.id`, which `core/scan.lua` sets to a *file
path*; `wrap_loaded()`/`telemetry.auto()` (this tree's own
`core/telemetry_self.lua` uses the latter) resolve `Data.modules` values to
the *dotted* `@module` form instead. `M.rows`'s `ir.nodes[module_id]` was
looking a file-path-keyed table up by a dotted string that was never one of
its keys — every row silently failed to match, unconditionally, in every
project using `auto()`/`wrap_loaded()`. This is not a rare edge case: it is
the *common* case, and it meant `:DocBrowse telemetry` (ECOSYSTEM.md step
8, shipped earlier) had been showing "no telemetry data" for every function
regardless of real usage since the day it shipped, and
`telemetry_join.doc_usage_summary` had always reported 0/0. Fixed by adding
a `node.module` → node index and trying both the direct-id and dotted
conventions (`ir.nodes[module_id] or by_module[module_id]`) — a caller's
own explicit `wrap(tbl, label, {module_id=...})` can legitimately choose
either form, and `TESTS/browse_telemetry_spec.lua`'s existing fixture
exercises the direct-id one, so both had to keep working, not just the one
this feature happened to need. No test needed rewriting; the existing
fixture's assumptions were compatible with the fix once the two-path lookup
was in place.

Regression-checked against `TESTS/browse_telemetry_spec.lua` (unchanged,
still green) and against real, non-trivial data: 151 real functions with
telemetry data resolved correctly post-fix, verified via a real running
`:DocMap serve` instance and the Claude Browser MCP tools (panel render,
sort order, row-click navigation to the real node), not a synthetic
fixture.

## Telemetry snapshot picker + A/B diff view (2026-08-10)

Once `runtime-analysis.nvim` shipped named snapshots (its own §4.5), the
Telemetry panel gained a picker — "Snapshot:" (Latest + every saved
snapshot, newest first) — and, once at least one snapshot exists, a second
"Compare vs:" select that switches the panel into a diff table: Function /
A / B / Δ (B − A), sorted by `|Δ|` descending, a red/green cue on the delta
column. `GET /api/telemetry` gained an optional `?snapshot=<name>` query
parameter (percent-decoded server-side, `+`-as-space handled in the
standard order); a new `GET /api/telemetry/snapshots` route lists what the
picker populates from. Both new routes follow the same "everything is a
normal 200 with `available: false` and a reason, never an HTTP error"
posture the original panel already established — a snapshot name that
doesn't resolve (typed by hand, or evicted since the link was shared) is
"not found," not a broken page.

**The original concept note for this (written the same day the Telemetry
panel first shipped) planned to reuse the generic Compare tab's marking
mechanism — the `+` next to `ⓘ` that lets a reader put two functions or
modules side by side. That plan did not survive actually reading what
Compare compares.** `CMP_ROWS` is a fixed set of *static* IR attributes
(signature, params, complexity, tested, documented, …) read off whichever
real node or function a mark's key resolves to (`fnByKey`/`byId`) — there
is no third axis for "as of which point in time," because every one of
those attributes is a property of the current tree, not something that
changes between two snapshots of the same function. A telemetry snapshot
comparison needed a different axis entirely (the same function, two
different moments), which Compare's data model has no room for and was
never built to have. Built instead as its own dedicated view inside the
Telemetry panel — the right shape for what the feature actually is, not a
strained reuse of a mechanism that compares a different kind of thing.
Caught and corrected before writing any of the comparison code, not after
shipping the wrong shape and reworking it.

Union of both sides' functions for the diff, not an intersection: a
function only one snapshot has a row for is exactly as real an answer as
one both do (it did not exist yet, or was simply never called, at the
other point in time) — dropping it would hide exactly the kind of change
snapshots exist to surface.

State (`state.tsnap`/`state.tsnapb`) threaded through the URL the same way
`atool`/`asort` already are, so a specific comparison is a shareable link —
verified by opening `#tab=analysis&atool=telemetry&tsnapb=<name>` fresh and
confirming it opens directly into that exact diff, not just by toggling the
selects and trusting the state machine.

**A real Lua-syntax bug, caught before it shipped rather than after:** the
entire client script is one Lua `[[ ... ]]` long-bracket string (`local JS
= [[ … ]]`), and an early draft of the picker's option-list builder used
`[value, label]` tuple arrays — `[["", "Latest"]]`, closing one array
literal immediately after another produces two adjacent `]` characters,
which is exactly the sequence that closes that Lua string early. Caught
immediately via a real `nvim -l` load (not just the file's own syntax
highlighting, which had nothing to say about it) rather than discovered
after `:DocMap serve` was already committed. Fixed by using `{v, l}`
objects instead of tuples, which contain no bracket pair that could ever
collide with the enclosing string's own delimiter — a mechanical
constraint the fix's own comment states plainly, so the next tuple-shaped
convenience added to this file does not reintroduce it.

Verified against real, non-trivial data end to end: a real named snapshot
saved via `telemetry.snapshot()` against this tree's own live cache
directory (not a throwaway fixture), `GET /api/telemetry/snapshots` and
`GET /api/telemetry?snapshot=…` both hit directly with `curl`, then the
actual picker driven through the Claude Browser MCP tools — option lists,
the compare-mode diff table, the not-found message for a name that does
not resolve, and the URL round-trip on a fresh navigation. The test
snapshot was deleted from the real cache directory afterward rather than
left behind as debris in a live environment.

## `opts.snippet_max_lines` (2026-08-10)

Found during a doc-currency audit prompted directly by the user: `core/
snippet.lua`'s `MAX_LINES` (bounds `fn.snippet`, the hover-preview payload
and — since `opts.godbolt` shipped — the Compiler Explorer link's own
source) was a real, user-relevant feature implemented as a hardcoded
module constant with no `opts` field, confirmed worth fixing alongside a
matching gap in `runtime-analysis.nvim` (its own `SNAPSHOT_RETENTION`). A
second candidate found the same pass, `core/duplicates.lua`'s `MIN_SIZE`,
was confirmed to stay as is — its own code comment already argues callers
should not need to override it, and the user agreed that reasoning holds.

Resolved once per `scan()`/`scan_full()` call, in `core/scan.lua`, into
`core/snippet.lua`'s `M.MAX_LINES` — not threaded as a parameter through
the shared `scan_file(path)` interface all five language backends
(`lua`/`js`/`ts`/`tsx`/`ecma`) implement, which would have meant touching
that contract for one policy value only the outer scan loop needs current
before it starts. Explicitly reset on every `M.scan` call (`opts.
snippet_max_lines or snippet.DEFAULT_MAX_LINES`, a new field split out
from the old `MAX_LINES` specifically so a real, permanent default still
exists to reset to) rather than left as a one-way mutation — a scan with
no override must never inherit a previous scan's, since `:DocBrowse`
bouncing between repos (or several `:DocMap` calls in one session) can
scan more than one repo's `opts` in the same process.

## `opts.mdview` — live preview via mdview.nvim, Tier A (2026-08-10)

Closed out the roadmap's "mdview.nvim integration — never built" entry,
which had sat with a concept (`docmap_hierarchy_and_integrations.md` Part
4) but zero implementation — confirmed at the time by grep, no `mdview`
reference anywhere under the tree. That entry itself already split the
work into a buildable Tier A (a Markdown render shaped for what mdview's
ammonia sanitizer keeps, pushed via `ws_client.send_markdown` from
`install()`'s `on_change`) and a Tier B (a real diagram inside mdview's own
tab) it explicitly said was "not buildable today" and "belongs in a
concept doc in mdview.nvim's own repo, not here — don't design it twice".
Shipped: Tier A, exactly as scoped. Tier B is not attempted here, for the
same reason the original entry gave — nothing changed about mdview's own
WS protocol to make it buildable, and it stays that repo's decision, not
this one's.

**The roadmap entry's own two "verify before starting" items were resolved
from primary source before writing a line of `render/mdview.lua`, not
assumed correct because the concept doc sounded confident:**

1. **Ammonia's default attribute allowlist** — read directly out of the
   vendored crate source on disk (`~/.cargo/registry/src/index.crates.io-*/
   ammonia-4.1.3/src/lib.rs`), not from documentation or a training-time
   assumption. Two findings mattered for what `render/mdview.lua` could
   safely emit: `generic_attributes` is only `{"lang", "title"}` — `id` and
   `style` never survive sanitization, on any tag — and `<details>`/
   `<summary>` need nothing extra from mdview's own `sanitizer()` because
   both are already in ammonia's *default* tag set (verified by reading
   `Builder::default()`'s own `tags = hashset![...]` literal). mdview's
   `native/wasm-render/src/lib.rs#sanitizer()` turned out to add only
   `<input>` (task-list checkboxes) and a `class` attribute scoped to
   `<code>` alone beyond that default — smaller than the roadmap entry's
   own wording ("additionally permits… span… div") suggested, since `span`
   and `div` were already default-allowed and the code comment's list was
   listing what it re-asserts, not what is new.
2. **Room routing** — traced through mdview's own `init.lua#M.open()` and
   `adapter/ws_client.lua` rather than guessed: the room key a browser tab
   watches is `normalize.path()` of the previewed file's absolute path,
   the exact same normalization `ws_client.send_markdown(path, markdown,
   opts)` already applies internally before building its `/update?key=…`
   URL. No separate "point a tab at a room" mechanism needed inventing —
   pushing to `<root>/<out_dir>/overview.md`'s absolute path (the same
   path `generate()` already writes `overview.md` to) is the entire
   address, so "open that file, run `:MDViewStart`" is the whole setup.

**No Mermaid, disclosed rather than silently broken.** mdview's client has
no Mermaid dependency at all (checked: nothing under `src/client/`
references it) — a fenced ` ```mermaid ` block would survive ammonia
(`pre`/`code` are default-allowed) but render as inert text, not a
diagram. Rather than ship `render/markdown.lua`'s two Mermaid sections
unchanged and let them look broken in mdview specifically,
`render/mdview.lua` drops them and adds one line pointing at the
interactive `index.html` map instead.

**Soft dependency, matching `opts.pdf`'s existing pdfport.nvim posture
exactly**, down to the same `pcall(require, …)` presence probe pattern —
not installed → silent no-op; installed but no session attached (checked
via `mdview.core.state.is_attached()`/`get_server()`, the identical guard
`mdview.open()` itself uses) → skipped per push rather than queuing a
doomed request. Deliberately *not* `ws_client.wait_ready()`'s `/health`
poll for that check: `wait_ready` blocks up to 10s, retrying every 200ms,
which would tax every single `on_change` for a user who turned
`opts.mdview` on but never ran `:MDViewStart` — the in-process state check
costs nothing by comparison.

**Only reacts to `on_change`, same posture as `watch`/`callhierarchy`/
`diagnostics`.** Documented plainly rather than left implicit: `opts.
mdview` without `opts.watch` still works, but the preview then only
updates on a manual `handle.rescan()`/`:DocMap`, not on every save.

Test coverage in `TESTS/mdview_spec.lua`, stubbing
`package.loaded["mdview.core.state"]`/`["mdview.adapter.ws_client"]` —
the same soft-dependency test posture `pdf_artifact_spec.lua` already
established for pdfport.nvim, chosen over depending on a real mdview.nvim
checkout (which would need a running relay server and a curl subprocess to
exercise for real, well past what a unit test should require).

## Loaded panel — cold viewing via persisted snapshots (2026-08-10)

Closes runtime-analysis.nvim's own docs/ROADMAP.md §5.4 ("persist
loaded-vs-declared for cold viewing"), raised the same day §4.5 (named
telemetry snapshots) shipped and explicitly left open pending it — "the
snapshot mechanism there first will make the marginal cost of asking
`loaded.lua` for the same thing obvious one way or the other" (that
entry's own words). It did: once §4.5 existed as a real, working pattern,
building the parallel for loaded-vs-declared was a much smaller lift than
the original "is this even worth having" framing suggested.

**Real user pushback resolved the open question, not further analysis.**
§5.4's own text called this "a real open question whether a persisted
loaded-vs-declared snapshot is worth having at all". The user's own
feedback disagreed directly: reports can already be saved and reopened —
why should surfacing them in documentation.nvim, as persisted state data,
listed and clicked through one at a time, be a hard problem? It wasn't.
Once framed as "the exact same mechanism §4.5 already proved, applied to
a different kind of runtime fact", the remaining work was mechanical, not
a fresh design question.

**One identifier, not two — a real design decision, confirmed by tracing
how telemetry's own two identifiers actually differ, not assumed they
would.** `core/telemetry_self.lua` wraps `main = "documentation"` (a
require prefix) under `namespace = "documentation.nvim"` (`opts.title`) —
two different strings, for this repo itself, because a telemetry namespace
can wrap arbitrary code under any prefix. A loaded snapshot has nothing to
name except the prefix it was taken under, so `runtime-analysis.loaded`'s
new snapshot API takes only `prefix` — no separate namespace argument a
caller would have to keep in sync with it by hand — and
`loaded_diff.M.prefix(opts)` on this side derives the identical value
independently from `opts.source`/`opts.lua_root` (the same
`check.expected_module` transform already applied to every file in the
tree), rather than adding an `opts` field for it. Neither side ever tells
the other which prefix was used; both compute the same one.

**Shipped across both repos**, mirroring §4.5's own shape closely:

- `runtime-analysis.loaded` gained `M.snapshot`/`M.list_snapshots`/
  `M.load_snapshot` — same `lib.nvim.cache.disk` storage primitive
  `telemetry/store.lua` uses, a parallel `"loaded/"` cache-key prefix so
  the two never collide, same `SNAPSHOT_RETENTION = 20` default and
  eviction policy, same "always explicit, nothing snapshots on its own"
  posture. `:RA loaded snapshot <prefix> [name]` / `:RA loaded snapshots
  <prefix>` are the only call sites.
- `core/loaded_diff.lua`'s live `M.rows(ir)` and the new
  `M.rows_from_snapshot(ir, snapshot)` now share one `diff(ir,
  present_for)` implementation — refactored rather than duplicated, so
  the live and cold paths can never quietly drift into different
  discrepancy logic.
- `editor/serve.lua` gained `GET /api/loaded?snapshot=<name>` and
  `GET /api/loaded/snapshots`, mirroring `route_telemetry`/
  `route_telemetry_snapshots` closely but structurally simpler: **no
  "latest" fallback**, and no A/B compare. A loaded diff is a property of
  *some* live session's `package.loaded`; a server route answering a
  browser tab in a different process has no live one of its own to read,
  the identical honest limit `loaded_diff.lua`'s own header already
  states for the live browse mode — so unlike Telemetry, there is nothing
  to default to, and the panel prompts for a snapshot rather than
  guessing. A/B compare was left out on scope grounds, not an oversight:
  the user's own framing was "list them, click through one report after
  another", not "diff two captures" — Telemetry's compare view answers a
  real but different question this feature was never asked for.
- A new **Loaded** Analysis panel (`core/render/html.lua`), reusing
  Telemetry's own `.telpicker` CSS and `telOptionsHTML` builder rather
  than duplicating them.

**Verified against real data before calling it done, not assumed from the
code.** A real headless session took a real snapshot
(`runtime-analysis.loaded.snapshot`), started `documentation.editor.serve`,
and curled both new routes: `/api/loaded/snapshots` listed the real
snapshot; `/api/loaded?snapshot=<name>` returned a real, correct diff
against this repo's own IR — including a synthetic `loaded_only` field
planted specifically to confirm that direction, not only `declared_only`
(the direction a mostly-cold headless session produces by default, which
would have hidden a bug in the other direction). A request for a snapshot
name that was never saved correctly answered `"snapshot not found"`
rather than an error.

Test coverage: `docs/TESTS/loaded_spec.lua` (runtime-analysis.nvim side,
snapshot/list/load/retention/eviction) and `TESTS/browse_loaded_spec.lua`
(documentation.nvim side, `M.prefix` and `M.rows_from_snapshot` — the
latter needs no real runtime-analysis.nvim checkout at all, unlike the
existing `M.rows` block in the same file, since it never touches a live
`package.loaded`). The server routes themselves are not unit-tested,
the same posture `docmap_spec.lua`'s own comment states for
`/api/telemetry`: "the route table and socket handling are verified by
running the thing and talking to it, which a spec cannot do without an
event loop" — covered by the real curl verification above instead.

## `undocumented-param` credits `@overload`-only signatures (2026-08-11)

Closed the last item that had been sitting in `docs/ROADMAP.md`'s
"Genuinely open" section since `@overload` was first parsed and rendered
(2026-07-31). `check_undocumented_params` (`core/check.lua`) compared a
function's raw signature parameter count against its `@param` line count
only — a function documented entirely through `@overload` instead of
`@param` (its real parameter list living inside the `fun(...)` literals)
had zero `@param` lines by construction, so the check unconditionally read
that as "undocumented", regardless of how thoroughly the overloads
actually documented it.

**Scoped to the exact false-positive case, not "any function with
overloads".** The fix only skips the finding when **both** hold: zero
`@param` lines at all, and at least one `@overload`'s own parsed `params`
covers the declared parameter count. A function with *some* `@param`
lines — still fewer than the signature declares — is still a real
finding, overloads present or not; crediting that case too would have
hidden a genuine gap the check exists to catch. Verified with a test
matrix, not just the happy path: overload covers it (silent), overload
present but too short (still fires), partial `@param` lines plus a
covering overload (still fires), no overload at all (unchanged, still
fires).

**Costed correctly by the roadmap entry itself before this was picked
up** — asked directly whether this was a per-plugin convention needing
rollout everywhere, or a fix in documentation.nvim's own scanner: the
latter. `check_undocumented_params` is centralized code every scanned
tree runs through, so the fix takes effect for every plugin the moment it
ships here — there was never a "roll this out to other repos" step to
plan for, and no new data or per-repo configuration was needed, only the
already-parsed `Documentation.OverloadInfo.params` from the 2026-07-31
work.

- **Module:** `core/check.lua` (`check_undocumented_params`)
- **Tests:** `TESTS/check_overload_credit_spec.lua` — its own file, not a
  block in `docmap_spec.lua`, which already sits near Lua's
  200-local-per-function ceiling (the same reason
  `browse_loaded_spec.lua`/`browse_telemetry_spec.lua`/
  `browse_endpoints_spec.lua`/`check_type_vs_class_spec.lua` are all their
  own files too).
