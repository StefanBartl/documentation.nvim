# documentation.nvim — idea backlog

Brainstormed features, grouped by theme. **Nothing here is scheduled**, and
nothing here has been costed the way [`ROADMAP.md`](ROADMAP.md)'s entries
have — this is the layer *before* that: ideas worth writing down so they are
not re-derived, with enough reasoning attached to judge them later.

Three sibling files, three jobs, and keeping them apart is the point:

| File | Holds |
|---|---|
| [`FEATURES.md`](FEATURES.md) | What shipped, and the trade-off behind it. The decision record. |
| [`ROADMAP.md`](ROADMAP.md) | What is genuinely open, and what was **considered and rejected** (with the condition that reopens it). |
| **this file** | What has not been decided about at all yet. |

Anything here that graduates to "we are actually going to look at this"
moves to `ROADMAP.md` with a real cost estimate; anything that ships moves
to `FEATURES.md`. Items already tracked in `ROADMAP.md` — the
`@overload`/`undocumented-param` fix, other languages, running without
Neovim, the mdview bridge, the Reference tab — are **not repeated here**,
only cross-referenced.

**The filter every idea below is judged against:** this plugin's value is
*detecting where documentation and code stop agreeing*. Features that make
the map prettier are worth less than features that make a disagreement
visible, and several attractive ideas are ranked low below on exactly that
ground.

---

## 1. New drift checks

The 14 existing checks are the plugin's core. These are the gaps in that
catalogue — ordered by how much of a real, silent problem each one catches.

### 1.1 Code blocks in Markdown, checked against the real API

`doc-references-missing` reads *inline code spans* in prose. It does not
read **fenced code blocks** — which is where a README's usage examples
live, and where a rename does the most damage: a `README.md` whose example
calls a function that no longer exists is worse than prose mentioning it,
because a reader will copy it.

The extraction is already 80% there (`core/docs.lua` scans every `.md`
file, `code_spans()` already exists). The new work is parsing a Lua fence
with treesitter — a parser this plugin already loads — and resolving the
calls in it against the same index.

**The obvious objection, which has an answer:** an example block is often
deliberately partial or pseudo-code. So the check has to be conservative in
exactly the way `docs_heuristic` already is — qualified calls only
(`documentation.core.scan.something`), never bare names — and it should
report at `info` severity, the same class `dead-function` sits in for the
same reason.

### 1.2 `@example` blocks that do not parse

Same idea, one step easier: `@example` content is already extracted and
already rendered in the annotation popup. Running it through the Lua parser
and reporting a syntax error is nearly free, and an `@example` that does not
parse is unambiguously wrong — no judgement call, no false-positive class.

Cheapest real check in this document. Probably the one to build first.

### 1.3 API-surface change detection

`:DocMap diff` already reports what a revision changed about the tree's
shape. The missing framing is **severity**: removing a public function,
changing its parameter count, or narrowing a type is a *breaking* change,
and today it reads the same as adding one.

Everything needed is present — every commit carries its own artifact, and
`diff` already retrieves and compares them. What is new is a classification
pass over that comparison, and a `--check`-able mode: "this branch removes
a published function" is a thing CI should be able to fail on.

**Where it gets hard, honestly:** "public" is a judgement in Lua. `M.foo` on
a returned table is public; a local is not; a function on a table that is
itself returned from a factory is ambiguous. `dead_code`'s existing
"published functions" notion is the closest thing to a definition this plugin
already has, and this check would depend on it being right.

### 1.4 Tests that name a function which no longer exists

`tests_dir` already feeds `fn.tested`, so the mapping between tests and
functions exists in one direction. The reverse — a spec file referencing a
function that has been renamed away — is the same class of drift
`doc-references-missing` catches for prose, in the place it is most likely
to rot unnoticed (a spec that still passes because it tests a shim).

### 1.5 Orphaned `@class` / `@alias`

A type declared, documented, and referenced by nothing. Structurally
identical to `unreferenced-module` (which already exists) one level down.
Cheap once LuaLS enrichment has run, and genuinely useful in a tree that has
accumulated types across a refactor.

### 1.6 `@since` / version-tag drift

If a function carries `@since 2.1` and the repository's own tags say 2.1
never existed, that is checkable. Speculative — this tree does not use
`@since` — but worth noting that the check is nearly free *if* the
convention is ever adopted, which is an argument for adopting it.

### 1.7 Cross-repository checks over `tag_files`

`tag_files` already links maps across projects. Today that is navigation
only. The same links could be *checked*: this repo's `@see
otherplugin.module.fn` pointing at something that repo's artifact says no
longer exists. Real value in a multi-repo ecosystem (exactly the one this
plugin lives in), and no new extraction — both artifacts already exist.

---

## 2. New Analysis panels

Nine exist. The bar for a tenth is that it answers a question the other
nine cannot, from data already in the IR — anything needing `git log`
cannot be a panel at all (see `:DocMap churn`'s own entry in
`FEATURES.md` for why: a committed artifact carrying history invalidates
itself).

### 2.1 Annotation adoption — generated, not hand-written

[`docs/ANNOTATIONS.md`](../ANNOTATIONS.md) is this analysis done **by
hand**, for one repository, once. A plugin whose entire purpose is
detecting drift shipping a hand-maintained inventory of its own tag usage
is difficult to defend — that document *is* drift, structurally.

`ROADMAP.md`'s Reference-tab entry already identified the precondition (a
`TAGS` table in `functions.lua`, replacing the current `if/elseif` chain).
This is the same work with a smaller, more defensible payoff: the panel
reports which tags *this tree* uses and how often, which is an adoption
report rather than a crib sheet, and it cannot go stale.

**Rank this highest of the panel ideas** for exactly that reason.

### 2.2 Public API surface

Every published function, in one list, with its documentation state and
whether anything outside its own module calls it. Today that information is
spread across Index (names), Documentation coverage (state) and Deps
(edges) — three places, none of which answers "what does this plugin
actually expose".

Directly useful for the thing this ecosystem keeps doing: extracting a
module into its own plugin. `lib.nvim.docmap` → documentation.nvim and
`lib.nvim.telemetry` → runtime-analysis.nvim were both preceded by exactly
this question, answered by hand both times.

### 2.3 Ownership / bus factor

Per module: how many distinct authors, when it was last touched, what share
the top author wrote. `git log`-dependent, therefore **a command, not a
panel** — `:DocMap ownership`, structurally identical to `:DocMap churn`
which already solved this constraint.

Genuinely useful on a team. On a single-author repository it reports "1"
everywhere, which is worth saying out loud before building it here.

### 2.4 Coupling and cohesion

Fan-in/fan-out already ships. The next metric up — how much a module's own
functions call *each other* versus reaching outward — is the one that
identifies a module that should be split. Real analysis value; also the
kind of metric that is easy to compute and hard to act on, so it earns its
place only if the number turns out to point somewhere specific.

### 2.5 Unused requires

A `require` whose result is never referenced. Adjacent to
`require-not-declared` (which exists) but the opposite direction, and
cheap: the IR already has both the require edges and the symbol references.

---

## 3. The generated page

### 3.1 Compare two artifacts, in the page

`:DocMap diff` renders to a message; `:DocMap impact` to the quickfix list.
Neither shows the *shape* change visually, and the page is where shape is
legible. Loading two `module_map.json` files and diffing the graph — nodes
added/removed highlighted, edges gained/lost — is the visualization the
existing textual diff cannot be.

Needs no new extraction (every commit already carries its artifact), and
`:DocMap serve` already solves the "fetch another commit's artifact"
problem for the History tab.

### 3.2 Copy-link for the current view

The whole page state already lives in the URL fragment — that is what
`:DocMap graph` and `gO` exploit. There is no button that hands the reader
that URL. One-line feature, disproportionate usefulness for "look at this
specific thing" in a PR comment.

### 3.3 Print / PDF stylesheet

A `@media print` block so the Tree tab and the Analysis panels print
legibly. Low glamour, occasionally exactly what someone needs for a review,
and it costs a stylesheet rather than a feature.

### 3.4 Keyboard navigation across the page

Tab order and shortcuts exist in places (the annotation popup is
keyboard-reachable; the Analysis panels largely are not). Worth a pass on
its own terms, and a prerequisite for anyone using this via a screen
reader.

---

## 4. The editor browser (`:DocBrowse`)

### 4.1 Telemetry mode (ECOSYSTEM step 8)

Already designed in full, in
[`lib.nvim/docs/ROADMAP/telemetry-documentation-bridge.md`](https://github.com/StefanBartl/lib.nvim/blob/main/docs/ROADMAP/telemetry-documentation-bridge.md),
and now buildable: `runtime-analysis.telemetry` exposes `load()` (read a
namespace with no live instance) and `Data.modules` (resolve a wrapped key
to a real module path), which were built for exactly this consumer.

The join's payoff is the `dead-function` cross-check — static "no caller
found" against runtime "actually called, 4 000 times" — where each side's
blind spot is covered by the other's evidence. **The one item in this file
with a finished design and both halves of its contract already shipped.**

Note the numbering: it lands as `MODES[8]`, not 7 — Endpoints took position
7 in the actual list. `ECOSYSTEM.md` already records this to spare a future
reader the confusion.

### 4.2 Picker integration

`pickers.nvim` (this ecosystem's own) or telescope/fzf-lua/snacks as an
alternative entry point: fuzzy-find a module or function across the whole
IR and jump straight to it, without navigating the tree. `:DocBrowse`'s
`/` is a search *within* the current list; this is the "I know the name, get
me there" interaction, which is a different one.

Cheap — the IR is already a flat, ordered list with locations attached.

### 4.3 `K` — look up the notation under the cursor

Vim's own "what is this" key, currently unbound in the browser and the
first thing a Vim user would try. `ROADMAP.md`'s Reference-tab entry
already names this as that feature's editor-side counterpart; noted here so
the two do not get built as separate things.

### 4.4 Breadcrumb in the statusline

Where you are in the tree, in the window's own statusline rather than only
in the browser's header. Small; mostly matters once the tree is deep enough
to lose track in.

---

## 5. Framework and language conventions

The language backends (`core/lang/*`) answer "what is a function here". The
convention layer above them (`core/plugins.lua`, `core/endpoints.lua`)
answers "what does this ecosystem's structure *mean*". That second layer is
where the remaining value is, and
[`FRAMEWORK_CONVENTIONS.md`](../FRAMEWORK_CONVENTIONS.md) is its design
document.

### 5.1 File-based routing — the other half of step 4

`ECOSYSTEM.md` step 4 shipped call-based routing (Express/Fastify/Koa) as
an Analysis panel and explicitly left file-based routing
(Next.js/SvelteKit/Nuxt/Remix) out, with a reason worth keeping: the
directory nesting *is* the information, so it belongs in a **Hierarchy
view**, not a flat panel. Different work, not a follow-up.

### 5.2 OpenAPI generation from the endpoint inventory

`core/endpoints.lua` already extracts method + path + handler + framework.
An OpenAPI skeleton is mostly a serialisation of that, and it is the one
output that other tooling (clients, mock servers, documentation sites)
consumes directly.

**Be honest about what it cannot produce**: request/response *schemas*,
which is most of what makes an OpenAPI document valuable, and which no
static scan of an untyped handler can infer. A skeleton with paths and
methods and empty schemas may be worth less than it sounds. Costed at "one
serialiser" and valued at "unclear" — that gap is the reason it is here
rather than in `ROADMAP.md`.

### 5.3 Component conventions — Vue / Svelte SFCs

Single-file components are a real structural convention (template + script
+ style in one file, with a component's *name* deriving from its path) that
the current node model has no shape for. Substantial work, entirely
speculative, and gated behind whether this plugin is ever pointed at a
frontend repository in earnest.

### 5.4 ORM models and migrations

Prisma/Drizzle/Sequelize schemas as a recognized convention — a data model
is structure, and it is invisible to every panel today. Same gate as §5.3.

---

## 6. Integrations and output

### 6.1 SARIF output for CI

The one item in this section with a clear, immediate payoff. SARIF is the
format GitHub code scanning ingests — emitting the existing findings in it
would put every drift check inline on the pull request that caused it,
which is where a `missing-summary` finding actually gets fixed.

The findings already have file, line, severity and message. This is a
serialiser and a CI step, not analysis.

### 6.2 A GitHub Action

Package the existing `--check` gate so another repository can adopt it in
three lines. [`REUSE.md`](../REUSE.md) already documents the "copy two files
and edit five lines" path; an action is the version that does not require
copying anything.

### 6.3 Publishing the map to GitHub Pages

The page is already self-contained, offline-capable HTML with no build
step — which makes it a static site by construction. A workflow that
publishes it on push is nearly free, and it turns "the map is in the repo"
into "the map has a URL".

### 6.4 Mermaid export

`:DocMap dot` produces Graphviz. Mermaid's advantage is different and
specific: **GitHub renders it inline**, so a Mermaid dependency graph can
live in a README or a PR comment and be *looked at* rather than downloaded.
Same edges, third serialiser, and the cheapest of the three.

### 6.5 Workspace symbols from the IR

The IR knows every symbol and its location — the same thing an LSP
workspace-symbol request answers. Whether this is worth building depends
entirely on whether it beats `lua-language-server`, which most people
already have. **Probably not**; noted so the question is not re-asked.

---

## 7. Scale and performance

Not currently a problem, which is the honest reason none of this is
scheduled. Written down because the first repository large enough to make it
one will make all of it urgent at once.

- **Incremental scan.** `install({ watch = true })` re-scans the whole tree
  on every write (~0.65s here). Re-scanning only the changed file and
  patching the IR is the obvious win, and the hard part is not the parse —
  it is that edges are global (a changed `require` affects another node's
  `required_by`).
- **Parse caching across sessions.** Keyed by content hash; `lib.nvim.cache.disk`
  already exists.
- **Parallel parsing.** Neovim's Lua is single-threaded for this; would need
  `vim.uv` worker processes, which is a large change for a currently-absent
  problem.
- **A measured ceiling.** Nobody has run this against a 5 000-file tree.
  Knowing where it falls over is worth more than optimizing before knowing.

---

## 8. Artifact and schema

- **Version the JSON schema explicitly.** `module_map.json` has grown
  fields steadily (`duplicates`, `docs`, `endpoints`, `snippet`), and
  `:DocMap diff` already has to detect and degrade against older artifacts.
  A declared schema version would make that detection explicit rather than
  inferred from which keys are present.
- **A documented payload contract between `to_json` and the page.** Twice
  now (`duplicates`, then `docs`) a new IR field reached the JSON artifact
  but not the page's own embedded payload, silently disabling a panel. Both
  incidents are in `FEATURES.md`. A single builder, or a test asserting the
  two key sets match, would end that class of bug rather than documenting
  it a third time.
