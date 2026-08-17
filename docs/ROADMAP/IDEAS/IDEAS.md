# documentation.nvim — idea backlog

## Table of content

  - [Intro](#intro)
  - [1. New drift checks](#1-new-drift-checks)
    - [1.1 Code blocks in Markdown, checked against the real API](#11-code-blocks-in-markdown-checked-against-the-real-api)
    - [1.2 `@example` blocks that do not parse](#12-example-blocks-that-do-not-parse)
    - [1.3 API-surface change detection](#13-api-surface-change-detection)
    - [1.4 Tests that name a function which no longer exists](#14-tests-that-name-a-function-which-no-longer-exists)
    - [1.5 Orphaned `@class` / `@alias`](#15-orphaned-class-alias)
    - [1.6 `@since` / version-tag drift](#16-since-version-tag-drift)
    - [1.7 Cross-repository checks over `tag_files`](#17-cross-repository-checks-over-tag_files)
  - [2. New Analysis panels](#2-new-analysis-panels)
    - [2.1 Annotation adoption — generated, not hand-written](#21-annotation-adoption-generated-not-hand-written)
    - [2.2 Public API surface](#22-public-api-surface)
    - [2.3 Ownership / bus factor](#23-ownership-bus-factor)
    - [2.4 Coupling and cohesion](#24-coupling-and-cohesion)
    - [2.5 Unused requires](#25-unused-requires)
  - [3. The generated page](#3-the-generated-page)
    - [3.1 Compare two artifacts, in the page](#31-compare-two-artifacts-in-the-page)
    - [3.2 Copy-link for the current view](#32-copy-link-for-the-current-view)
    - [3.3 Print / PDF stylesheet](#33-print-pdf-stylesheet)
    - [3.4 Keyboard navigation across the page — done](#34-keyboard-navigation-across-the-page--done-removed-2026-08-15)
  - [4. The editor browser (`:DocBrowse`)](#4-the-editor-browser-docbrowse)
    - [4.1 Telemetry mode (ECOSYSTEM step 8) — done](#41-telemetry-mode-ecosystem-step-8--done-removed-2026-08-15)
    - [4.2 Picker integration](#42-picker-integration)
    - [4.3 `K` — look up the notation under the cursor](#43-k-look-up-the-notation-under-the-cursor)
    - [4.4 Breadcrumb in the statusline](#44-breadcrumb-in-the-statusline)
  - [5. Framework and language conventions](#5-framework-and-language-conventions)
    - [5.1 File-based routing — the other half of step 4](#51-file-based-routing-the-other-half-of-step-4)
    - [5.2 OpenAPI generation from the endpoint inventory](#52-openapi-generation-from-the-endpoint-inventory)
    - [5.3 Component conventions — Vue / Svelte SFCs](#53-component-conventions-vue-svelte-sfcs)
    - [5.4 ORM models and migrations](#54-orm-models-and-migrations)
  - [6. Integrations and output](#6-integrations-and-output)
    - [6.1 SARIF output for CI](#61-sarif-output-for-ci)
    - [6.2 A GitHub Action](#62-a-github-action)
    - [6.3 Publishing the map to GitHub Pages](#63-publishing-the-map-to-github-pages)
    - [6.4 Mermaid export](#64-mermaid-export)
    - [6.5 Workspace symbols from the IR](#65-workspace-symbols-from-the-ir)
    - [6.6 A generic CLI entry, no per-repo copy](#66-a-generic-cli-entry-no-per-repo-copy)
    - [6.7 A REUSE.md recipe for "many repos, one config"](#67-a-reusemd-recipe-for-many-repos-one-config)
  - [7. Scale and performance](#7-scale-and-performance)
  - [8. Product shape](#8-product-shape)
    - [8.1 A polished desktop/web-app version](#81-a-polished-desktopweb-app-version)
    - [8.2 A checklist/task syntax with a runner and dashboard — done](#82-a-checklisttask-syntax-with-a-runner-and-dashboard--done-shipped-2026-08-11)
    - [8.3 Modern protocols, WASM, and agent integration](#83-modern-protocols-wasm-and-agent-integration)
  - [9. Artifact and schema](#9-artifact-and-schema)

---

## Intro

Brainstormed features, grouped by theme. **Nothing here is scheduled**, and
nothing here has been costed the way [`ROADMAP.md`](../ROADMAP.md)'s entries
have — this is the layer *before* that: ideas worth writing down so they are
not re-derived, with enough reasoning attached to judge them later.

Three sibling files, three jobs, and keeping them apart is the point:

| File | Holds |
|---|---|
| [`FEATURES.md`](../../FEATURES/FEATURES.md) | What shipped, and the trade-off behind it. The decision record. |
| [`ROADMAP.md`](../ROADMAP.md) | What is genuinely open, and what was **considered and rejected** (with the condition that reopens it). |
| **this file** | What has not been decided about at all yet. |

Anything here that graduates to "we are actually going to look at this"
moves to `ROADMAP.md` with a real cost estimate; anything that ships moves
to `FEATURES.md`. Items already tracked in `ROADMAP.md` — other languages,
running without Neovim, the Reference tab — are **not repeated here**, only
cross-referenced. (The `@overload`/`undocumented-param` fix and the mdview
bridge, both once tracked there too, have since shipped — see `FEATURES.md`.)

**The filter every idea below is judged against:** this plugin's value is
*detecting where documentation and code stop agreeing*. Features that make
the map prettier are worth less than features that make a disagreement
visible, and several attractive ideas are ranked low below on exactly that
ground.

---

## 1. New drift checks

The 14 existing checks are the plugin's core. These are the gaps in that
catalogue — ordered by how much of a real, silent problem each one catches.

---

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

---

### 1.2 `@example` blocks that do not parse

Same idea, one step easier: `@example` content is already extracted and
already rendered in the annotation popup. Running it through the Lua parser
and reporting a syntax error is nearly free, and an `@example` that does not
parse is unambiguously wrong — no judgement call, no false-positive class.

Cheapest real check in this document. Probably the one to build first.

---

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

---

### 1.4 Tests that name a function which no longer exists

`tests_dir` already feeds `fn.tested`, so the mapping between tests and
functions exists in one direction. The reverse — a spec file referencing a
function that has been renamed away — is the same class of drift
`doc-references-missing` catches for prose, in the place it is most likely
to rot unnoticed (a spec that still passes because it tests a shim).

---

### 1.5 Orphaned `@class` / `@alias`

A type declared, documented, and referenced by nothing. Structurally
identical to `unreferenced-module` (which already exists) one level down.
Cheap once LuaLS enrichment has run, and genuinely useful in a tree that has
accumulated types across a refactor.

---

### 1.6 `@since` / version-tag drift

If a function carries `@since 2.1` and the repository's own tags say 2.1
never existed, that is checkable. Speculative — this tree does not use
`@since` — but worth noting that the check is nearly free *if* the
convention is ever adopted, which is an argument for adopting it.

---

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

---

### 2.1 Annotation adoption — generated, not hand-written

[`docs/ANNOTATIONS.md`](../../ANNOTATIONS.md) is this analysis done **by
hand**, for one repository, once. A plugin whose entire purpose is
detecting drift shipping a hand-maintained inventory of its own tag usage
is difficult to defend — that document *is* drift, structurally.

`ROADMAP.md`'s Reference-tab entry already identified the precondition (a
`TAGS` table in `functions.lua`, replacing the current `if/elseif` chain).
This is the same work with a smaller, more defensible payoff: the panel
reports which tags *this tree* uses and how often, which is an adoption
report rather than a crib sheet, and it cannot go stale.

**Rank this highest of the panel ideas** for exactly that reason.

---

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

---

### 2.3 Ownership / bus factor

Per module: how many distinct authors, when it was last touched, what share
the top author wrote. `git log`-dependent, therefore **a command, not a
panel** — `:DocMap ownership`, structurally identical to `:DocMap churn`
which already solved this constraint.

Genuinely useful on a team. On a single-author repository it reports "1"
everywhere, which is worth saying out loud before building it here.

---

### 2.4 Coupling and cohesion

Fan-in/fan-out already ships. The next metric up — how much a module's own
functions call *each other* versus reaching outward — is the one that
identifies a module that should be split. Real analysis value; also the
kind of metric that is easy to compute and hard to act on, so it earns its
place only if the number turns out to point somewhere specific.

---

### 2.5 Unused requires

A `require` whose result is never referenced. Adjacent to
`require-not-declared` (which exists) but the opposite direction, and
cheap: the IR already has both the require edges and the symbol references.

---

## 3. The generated page

---

### 3.1 Compare two artifacts, in the page

`:DocMap diff` renders to a message; `:DocMap impact` to the quickfix list.
Neither shows the *shape* change visually, and the page is where shape is
legible. Loading two `module_map.json` files and diffing the graph — nodes
added/removed highlighted, edges gained/lost — is the visualization the
existing textual diff cannot be.

Needs no new extraction (every commit already carries its artifact), and
`:DocMap serve` already solves the "fetch another commit's artifact"
problem for the History tab.

---

### 3.2 Copy-link for the current view

The whole page state already lives in the URL fragment — that is what
`:DocMap graph` and `gO` exploit. There is no button that hands the reader
that URL. One-line feature, disproportionate usefulness for "look at this
specific thing" in a PR comment.

---

### 3.3 Print / PDF stylesheet

A `@media print` block so the Tree tab and the Analysis panels print
legibly. Low glamour, occasionally exactly what someone needs for a review,
and it costs a stylesheet rather than a feature.

---

### 3.4 Keyboard navigation across the page — **done, removed 2026-08-15**

Shipped as [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) Phase 4,
Slices 5 and 6: keyboard parity (`tabindex="0" role="button"`, a delegated
Enter/Space handler) for the Index tab's links and `.feat-name`/
`.feat-tab-name`, and roving tabindex for the three long lists (Tree,
History, Analysis) plus their sort headers. Verified against real tab-stop
counts and DOM state, not asserted — see that document for the detail
Slices 5/6 record, including a measurement mistake caught and corrected
along the way.

---

## 4. The editor browser (`:DocBrowse`)

---

### 4.1 Telemetry mode (ECOSYSTEM step 8) — **done, removed 2026-08-15**

Shipped: `:DocBrowse telemetry` is the static × runtime join this section
described — `runtime-analysis.telemetry`'s `load()`/`Data.modules` join
against `dead-function`'s "no caller found," documented in
[`../FEATURES/ECOSYSTEM.md`](../../FEATURES/ECOSYSTEM.md) §8 and
[`../FEATURES/FEATURES.md`](../../FEATURES/FEATURES.md).

---

### 4.2 Picker integration

`pickers.nvim` (this ecosystem's own) or telescope/fzf-lua/snacks as an
alternative entry point: fuzzy-find a module or function across the whole
IR and jump straight to it, without navigating the tree. `:DocBrowse`'s
`/` is a search *within* the current list; this is the "I know the name, get
me there" interaction, which is a different one.

Cheap — the IR is already a flat, ordered list with locations attached.

---

### 4.3 `K` — look up the notation under the cursor

Vim's own "what is this" key, currently unbound in the browser and the
first thing a Vim user would try. `ROADMAP.md`'s Reference-tab entry
already names this as that feature's editor-side counterpart; noted here so
the two do not get built as separate things.

---

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
[`FRAMEWORK_CONVENTIONS.md`](../../FRAMEWORK_CONVENTIONS.md) is its design
document.

---

### 5.1 File-based routing — the other half of step 4

`ECOSYSTEM.md` step 4 shipped call-based routing (Express/Fastify/Koa) as
an Analysis panel and explicitly left file-based routing
(Next.js/SvelteKit/Nuxt/Remix) out, with a reason worth keeping: the
directory nesting *is* the information, so it belongs in a **Hierarchy
view**, not a flat panel. Different work, not a follow-up.

---

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

---

### 5.3 Component conventions — Vue / Svelte SFCs

Single-file components are a real structural convention (template + script
+ style in one file, with a component's *name* deriving from its path) that
the current node model has no shape for. Substantial work, entirely
speculative, and gated behind whether this plugin is ever pointed at a
frontend repository in earnest.

---

### 5.4 ORM models and migrations

Prisma/Drizzle/Sequelize schemas as a recognized convention — a data model
is structure, and it is invisible to every panel today. Same gate as §5.3.

---

## 6. Integrations and output

---

### 6.1 SARIF output for CI

The one item in this section with a clear, immediate payoff. SARIF is the
format GitHub code scanning ingests — emitting the existing findings in it
would put every drift check inline on the pull request that caused it,
which is where a `missing-summary` finding actually gets fixed.

The findings already have file, line, severity and message. This is a
serialiser and a CI step, not analysis.

---

### 6.2 A GitHub Action

Package the existing `--check` gate so another repository can adopt it in
three lines. [`REUSE.md`](../../REUSE.md) already documents the "copy two files
and edit five lines" path; an action is the version that does not require
copying anything.

---

### 6.3 Publishing the map to GitHub Pages

The page is already self-contained, offline-capable HTML with no build
step — which makes it a static site by construction. A workflow that
publishes it on push is nearly free, and it turns "the map is in the repo"
into "the map has a URL".

---

### 6.4 Mermaid export

`:DocMap dot` produces Graphviz. Mermaid's advantage is different and
specific: **GitHub renders it inline**, so a Mermaid dependency graph can
live in a README or a PR comment and be *looked at* rather than downloaded.
Same edges, third serialiser, and the cheapest of the three.

---

### 6.5 Workspace symbols from the IR

The IR knows every symbol and its location — the same thing an LSP
workspace-symbol request answers. Whether this is worth building depends
entirely on whether it beats `lua-language-server`, which most people
already have. **Probably not**; noted so the question is not re-asked.

---

### 6.6 A generic CLI entry, no per-repo copy

[REUSE.md](../../REUSE.md)'s CI path is "copy `scripts/gen_map.lua`, edit five
lines". That is the right shape for a repository that maps *itself* on every
CI run — the options are fixed, so hardcoding them in a committed file is
honest. It is the wrong shape for mapping an arbitrary repository once, from
wherever you happen to be, which is what came up sketching CLI support for a
config that keeps several dozen personal plugins as sibling checkouts: nobody
wants a `gen_map.lua` copy sitting in each one just to run `--check` by hand
occasionally.

`core/cli.lua`'s `M.run(opts, argv)` already does not care where `opts` came
from — the sketch below only replaces "how the options table gets built",
same dependency-probing `gen_map.lua` already has, flags instead of a literal
table:

```lua
-- scripts/cli.lua — sketched, not wired into ci.lua or REUSE.md.
--   nvim --headless -l scripts/cli.lua -- --root /path/to/repo [flags]
local args = _G.arg or {}
local flags = {}
for _, a in ipairs(args) do
  local key, val = a:match("^%-%-([%w_]+)=(.*)$")
  if key then
    flags[key] = val
  elseif a:match("^%-%-[%w_]+$") then
    flags[a:sub(3)] = true
  end
end

if not flags.root or flags.root == true then
  io.stderr:write("cli.lua: --root <path> is required.\n")
  os.exit(1)
end

local root = tostring(flags.root):gsub("\\", "/"):gsub("/+$", "")
vim.opt.runtimepath:prepend(root)
-- ... same ensure()-shaped dependency probing gen_map.lua already has ...

local opts = require("documentation.config").build(root, {
  source = flags.source,   -- nil is fine: auto-detected
  title = flags.title,
  repo_url = flags.repo_url,
  branch = flags.branch,
  out_dir = flags.out_dir,
  tests_dir = flags.tests_dir,
})

local code = require("documentation.core.cli").run(opts, args)
vim.cmd("cq " .. code)
```

Open questions before this is worth building for real: whether flag parsing
belongs in this plugin at all versus staying a "here is the fifteen-line
pattern, adapt it" REUSE.md recipe (the file already has two of those); and
whether an *optional* `.docmap.lua` config file in the target repo — read
when present, flags overriding it — is worth the extra surface over "just
pass flags every time" for a repo visited more than once. Neither has an
answer yet, which is the whole reason this is here and not in `scripts/`.

---

### 6.7 A REUSE.md recipe for "many repos, one config"

The companion to 6.6: a config that clones several dozen personal plugins as
siblings under one directory (this plugin's own author's setup is the
motivating case) wants "map every checkout that exists locally" as one
command, not one invocation per repo typed by hand.

The shape only exists because such a config already has to answer "which
repos, and where are they on disk" for its own plugin manager — a generic
version of this belongs in *that* config's own tooling, not in
documentation.nvim, which correctly knows nothing about any particular
config's plugin-list format. What documentation.nvim *can* own is a REUSE.md
recipe showing the pattern, so the next person solving this problem starts
from a sketch instead of from nothing:

```lua
-- Sketched against one real config's shape (a `{ repo, name }` list reader
-- plus a `local_dev(name) -> path|nil` resolver over a REPOS_DIR env var) --
-- the specific readers are config-local, the loop over them is not.
for _, entry in ipairs(personal_plugin_list()) do
  local dir = local_checkout_path(entry.name)   -- nil: not cloned, skip
  if dir then
    local opts = require("documentation.config").build(dir, { title = entry.name })
    local argv = checking and { "--check", "--lenient" } or {}
    local code = require("documentation.core.cli").run(opts, argv)
    io.stdout:write(("[%s] exit %d\n"):format(entry.name, code))
  end
end
```

Same open question as 6.6 about where flag/config parsing should live, plus
one specific to this shape: `core.cli.run` writes straight to stdout/stderr
per repo with no repo-name prefix on its own output (only the wrapper's own
`io.stdout:write` line here adds one) — fine for one repo, a little hard to
scan across thirty. Worth a `label` option on `run()` if this ever gets
built for real, rather than every caller re-solving it.

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

## 8. Product shape

Two bigger-picture ideas, each substantial enough to warrant a full
analysis document rather than a paragraph here — the same
[`PORTABILITY.md`](PORTABILITY.md)/[`MULTILANG.md`](MULTILANG.md) pattern
this backlog already uses for anything too large for one entry.

---

### 8.1 A polished desktop/web-app version

[`DESKTOP_WEBAPP.md`](DESKTOP_WEBAPP.md) — costs out "desktop app" and "web
app" separately (they share a UI, not a trust model or a distribution
story). **Updated 2026-08-15: the desktop half shipped**, as its own
repository, [`docmap-desktop`](https://github.com/StefanBartl/docmap-desktop) —
shell, project switcher, generation, packaging, all done. The web half is
unchanged and remains the least developed of the two: a hosted, multi-tenant
service has no trust model sketched anywhere in this ecosystem, and
`editor/serve.lua`'s own `127.0.0.1`-only posture is a deliberate answer for
the single-user case, not an oversight to lift.

---

### 8.2 A checklist/task syntax with a runner and dashboard — **done, shipped 2026-08-11**

This shipped as `documentation.nvim`'s checklist ledger — see
[`docs/CHECKLIST_FORMAT.md`](../../CHECKLIST_FORMAT.md) for the format,
[`docs/MCP.md`](../../MCP.md) for `docmap_checklist`, and
[`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md)'s Phase 2 for the build
history. The original costing document (`CHECKLIST_TASK_RUNNER.md`) is
absorbed into those three and has been removed, the same way
`PROTOCOLS_AND_AGENTS.md` was — grounded against a real example (the
nvim-config repo's own `docs/ROADMAP/RULES/` systematic audit), it
concluded most of what such an audit contains is a **hand-verified fact
pinned to a file:line**, not something a scanner can re-derive, and that the
curated ledger with staleness detection (scope **(b)**) was the part worth
building, not a re-implementation of the check catalogue with new syntax
(scope **(a)**, correctly not built). One thread from that document is
still open and not yet built: trend data on the ledger's own pass rate over
time, the same named-snapshot shape `runtime-analysis.telemetry`/`loaded`
already have, applied to a third kind of data — see
[`IDEAS_IMPLEMENTATION_PLAN.md`](IDEAS_IMPLEMENTATION_PLAN.md).

---

### 8.3 Modern protocols, WASM, and agent integration

`PROTOCOLS_AND_AGENTS.md` — four ideas raised together ("cutting-edge tech /
new future-protocols"), costed apart
because they differ by an order of magnitude in effort. Short version:
an **MCP server** is the strongest and by far the cheapest (a thin
adapter over `Documentation.Handle`/`core/cli.lua`, which already exist;
stdio transport sidesteps every trust question) and it is the enabler for
**agent-driven checklists**, which need no native rewrite. **WASM** is
well-precedented in-house (mdview) but inherits two treesitter problems
and answers a question nobody has asked. **WebSocket/WebTransport** is a
no on current requirements — every existing `serve` endpoint is
request/response-shaped, and the protocol should follow a push-shaped
feature rather than lead it.

---

## 9. Artifact and schema

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

---

