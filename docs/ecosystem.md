# Ecosystem architecture — where docs, static analysis and runtime each belong

> **This is the one architecture document for the whole ecosystem, and it
> lives here.** It describes four pieces and only one of them is this
> repository, so the other three link to this file rather than keeping a copy:
> [`lib.nvim`](https://github.com/StefanBartl/lib.nvim),
> [`runtime-analysis.nvim`](https://github.com/StefanBartl/runtime-analysis.nvim)
> and [`mdview.nvim`](https://github.com/StefanBartl/mdview.nvim). Same pattern
> as the queue in
> [`docmap-desktop/docs/PLAN.md`](https://github.com/StefanBartl/docmap-desktop/blob/main/docs/PLAN.md):
> one source, several pointers, because the alternative is four copies in three
> different states.
>
> Cite it from another repository as
> `documentation.nvim/docs/ecosystem.md`, never as a bare `docs/ecosystem.md`
> — that path resolves to nothing anywhere but here, and nothing in CI would
> report it (`dead-readme-link` strips code spans by design and resolves links
> only within one repository).

> **A fifth piece arrived after this was written (2026-08-30).**
> [`docmap-desktop`](https://github.com/StefanBartl/docmap-desktop) is a Tauri
> app that runs this plugin's standalone binary and serves the same `/api/*`
> routes over a real HTTP origin. It changes nothing in the seams below — it
> is a second *host* for the artifact-and-serve tier §1's Seam B already
> describes, which is why it needed no revision here and gets a note instead.

## Table of content

  - [Intro](#intro)
  - [Epistemic note](#epistemic-note)
  - [1. Two seams already exist. Everything sorts along them.](#1-two-seams-already-exist-everything-sorts-along-them)
    - [Seam A — static vs. runtime](#seam-a--static-vs-runtime)
    - [Seam B — artifact vs. serve](#seam-b--artifact-vs-serve)
  - [2. The feature list, sorted](#2-the-feature-list-sorted)
  - [3. Feature by feature](#3-feature-by-feature)
    - [3.1 API endpoint inventory — static, documentation.nvim](#31-api-endpoint-inventory--static-documentationnvim)
    - [3.2 API request runner — runtime, and the reason a new plugin is justified](#32-api-request-runner--runtime-and-the-reason-a-new-plugin-is-justified)
    - [3.3 Docs cross-references — static, documentation.nvim, genuinely new data](#33-docs-cross-references--static-documentationnvim-genuinely-new-data)
    - [3.4 Docs-only view / filter — cheap, once 3.3 exists](#34-docs-only-view--filter--cheap-once-33-exists)
    - [3.5 Hover previews — three different features wearing one name](#35-hover-previews--three-different-features-wearing-one-name)
    - [3.6 Three more in the same spirit](#36-three-more-in-the-same-spirit)
  - [4. The plugin question, answered](#4-the-plugin-question-answered)
    - [What the numbers say](#what-the-numbers-say)
    - [The precedent is exact](#the-precedent-is-exact)
    - [The answer, and why it revises my earlier one](#the-answer-and-why-it-revises-my-earlier-one)
    - [The resulting ecosystem](#the-resulting-ecosystem)
  - [5. Naming — settled](#5-naming--settled)
  - [6. What runtime-analysis.nvim actually is](#6-what-runtime-analysisnvim-actually-is)
    - [One hard constraint decides most of it](#one-hard-constraint-decides-most-of-it)
    - [What a separate binary or app would actually buy](#what-a-separate-binary-or-app-would-actually-buy)
    - [What it would cost](#what-it-would-cost)
    - [Answer](#answer)
  - [7. How the two plugins meet](#7-how-the-two-plugins-meet)
    - [The naive integration is architecturally excluded](#the-naive-integration-is-architecturally-excluded)
    - [The three surfaces that remain, ranked](#the-three-surfaces-that-remain-ranked)
    - [Direction of the dependency](#direction-of-the-dependency)
  - [8. Sequencing](#8-sequencing)
  - [9. What not to build](#9-what-not-to-build)
  - [10. Honest limits](#10-honest-limits)

---

## Intro

> **Status (2026-08-11): steps 1–8 of §8's sequencing have all shipped.**
> Only step 9 (full-file previews / a browser request runner / a Runtime tab
> under `serve`) is still open, and it is gated on the serve tier. This
> document is therefore a **decision record**, not a backlog — the same genre
> as [`FEATURE_LOG.md`](FEATURE_LOG.md): why something was built the way it was.
> Its original header — "architectural concept, agreed. Nothing here is
> implemented" — was true when written and is preserved below for the
> record; per-step "Done" markers in §8 are the current truth.
>
> Earlier path: `docs/ecosystem.md`. Prose references to it in dated entries
> elsewhere mean this file.

**Original status line, as written:** *architectural concept, agreed.
Nothing here is implemented.*
Written in response to a feature list (API endpoint inventory, a
Postman-lite request runner, docs cross-references with previews, a
docs-only view, file/snippet hover previews) plus the questions that came
with it: *is a separate plugin worth it, what form should it take, and could
documentation.nvim gain a tab that appears when it is installed?*

This answers **where each thing belongs and why**, not how to build it. A
per-step implementation concept follows separately, keeping cost analysis and
task breakdown apart the same way the language work does.

**Decisions taken (§4–§8):** the plugin is worth it, named
**`runtime-analysis.nvim`** and already created; it is a **Neovim plugin**,
not a binary or an Electron app; the two plugins meet **in the editor
first**, never by injecting into documentation.nvim's committed artifact;
and the **work order is documentation.nvim first** — sequencing steps 1–4
before the new plugin's step 5.

---

## Epistemic note

This repository's convention is that a design doc states what it verified and
what it assumed. [`framework_conventions.md`](framework_conventions.md) flags
itself as entirely unverified for exactly this reason; this document is
mixed, so here is the split.

**Verified against real source while writing this:**

- `editor/serve.lua` serves **GET only** (`method ~= "GET"` → 405) and
  documents its own security posture as "small surface": bind `127.0.0.1`,
  whitelist every `<sha>`, no path may leave `out_dir`.
- Its header already documents the `file://` **opaque-origin** problem —
  that is *why* the server exists at all.
- Artifact sizes for this repository: `index.html` **752 KB**,
  `module_map.json` **404 KB**, against **728 KB** of `lua/**.lua` source.
- Docs are currently modelled as a **path and a count only** — `node.readme`
  (a path) and `own.files_md` (a counter, `scan.lua`). No `.md` file's
  *content* is read anywhere in this codebase.
- `Documentation.Edge` is a discriminated union on `kind`
  (`type`/`extends`/`require`/`call`) and already carries a `confidence`
  field for `call`.
- `lib.nvim.net.curl` **already exists**: builds a curl argv from
  method/headers/bearer/query/body, `vim.system`-based, async and blocking
  forms, JSON decoding.
- `lib.nvim.telemetry` is **2 915 lines** across 12 files. Its external
  lib.nvim surface is `autocmd`, `cache.disk`, `fs.mkdirp`, `git`, `notify`,
  `usercmd`, and `ui.kit` (pcall-guarded) — plus exactly **one**
  lib.nvim-specific coupling: `wrap_lib()` via `lib.strategies.control`.
- documentation.nvim's own lib.nvim surface is `autocmd`, `fs.mkdirp`,
  `notify`, `usercmd`, `ui.kit`, `map`, `debounce`, `fs.read`,
  `fs.collect_recursive`, `fs.is_subpath`, `cross.open_default`,
  `cross.uv.spawn_capture` — a superset of telemetry's.

**Not verified, and stated as assumption:** every claim below about a *web
framework's* route syntax (Express, Fastify, FastAPI, axum, …). No such tree
has been parsed here. `framework_conventions.md` gives itself the same
caveat and it still applies — re-verify against a real parse at the point
any recognizer is actually written.

---

## 1. Two seams already exist. Everything sorts along them.

Neither is new. Both are already documented in this codebase, and every
feature in the list lands on one side or the other of each.

---

### Seam A — static vs. runtime

The telemetry-documentation bridge already names it:
documentation.nvim knows what **exists and is documented**; telemetry knows
what **actually ran**. Its whole argument is that neither can produce the
other's evidence, and that crossing them is where the value is.

---

### Seam B — artifact vs. serve

`editor/serve.lua`'s header is explicit that this plugin's self-image was
"produces files, has no runtime", and that the server breaks it
**deliberately and minimally**, for a reason that is not a preference: a page
opened as `file://` gets an opaque origin, and `fetch()` refuses the `file:`
scheme outright. So anything the page must *load on demand* needs a server;
anything it can carry with it does not.

The cost side is measurable, not hypothetical. This repository's 728 KB of
source already produces a 752 KB page and a 404 KB JSON artifact. **Embedding
file contents for previews would roughly double the artifact** — and this is
a 58-file repository. lib.nvim, at ~288 files, would be far worse.

---

## 2. The feature list, sorted

| Feature | Seam A | Needs new extraction? | Needs a runtime? | Home |
|---|---|---|---|---|
| API endpoint inventory | static | **yes** (layer-2 recognizer) | no | documentation.nvim |
| API request runner | **runtime** | no | **yes** | new plugin |
| Docs cross-references | static | **yes** (docs corpus is unread today) | no (bounded previews) | documentation.nvim |
| Docs-only view / filter | static | falls out of the above | no | documentation.nvim |
| Signature popup | static | **no — data already in the IR** | no | documentation.nvim |
| Snippet preview (path:line) | static | bounded snippets only | no | documentation.nvim |
| Full-file hover preview | static | no | **yes** (or a big artifact) | documentation.nvim (serve) |

The single row that sits alone in the "runtime" column is the request runner.
That is the whole plugin question in one line, and section 4 returns to it.

---

## 3. Feature by feature

---

### 3.1 API endpoint inventory — static, documentation.nvim

This is a **layer-2 convention recognizer** in `framework_conventions.md`'s
own vocabulary: a second pass over a parse tree the language backend already
produced, looking for one ecosystem's structural idiom. `core/plugins.lua`
(lazy.nvim specs) is the existing instance of exactly this shape.

It was blocked on a JS/TS backend when that document was written. **It is no
longer blocked** — `core/lang/ecma.lua` ships functions, imports, calls and
symbols for JS/TS/TSX.

**A refinement of `framework_conventions.md`, not a contradiction.** That
document concluded "routes belong in Hierarchy, not Analysis," because a
Next.js route's effective layout is the product of every ancestor
directory's `layout.tsx` — nesting *is* the fact worth showing. That
reasoning is sound and specific to **file-based** routing. It does not
transfer to **call-based** routing:

```js
app.get("/users/:id", getUser);      // Express — flat, no ancestry
```

There is no parent-child structure to preserve, so flattening loses nothing.
The honest split:

- **File-based routing** (Next.js App/Pages Router, SvelteKit, Nuxt, Remix)
  → a Hierarchy view, per the existing conclusion.
- **Call-based routing** (Express, Fastify, Flask/FastAPI decorators, axum,
  chi) → an Analysis panel, structurally identical to Plugins or Hooks.

Both feed one new per-node field — `endpoints`, alongside the existing
`plugins` — so a single Endpoints panel can list every route in the tree
regardless of which recognizer found it: method, path, handler function,
line, framework, and whether the handler carries a doc block.

**Why this one is worth building first among the new extractions:** it is the
only feature in the list that produces information the reader cannot get by
reading one file. Everything else surfaces things they could already find;
an endpoint inventory across a whole codebase is genuinely assembled, and it
is the input every other API feature needs.

---

### 3.2 API request runner — runtime, and the reason a new plugin is justified

Three facts decide this one, all verified:

1. **The static page cannot do it.** `file://` opaque origin, `fetch()`
   refuses the scheme — `serve.lua`'s own header documents this as the
   reason it exists.
2. **The current server cannot do it either.** `serve.lua` answers GET only
   and whitelists every input that reaches a subprocess. A route that
   forwards a caller-supplied request to a caller-supplied URL is an
   **SSRF-shaped capability** — and a localhost server is reachable from
   *any* tab in the browser, not only the map's own page. Adding it would
   require origin or token gating that this server has never needed.
   mdview.nvim's relay already mints a per-session token for exactly this
   class of problem, so the precedent for doing it correctly exists.
3. **The execution primitive already exists.** `lib.nvim.net.curl` builds a
   curl argv from method/headers/bearer/query/body and runs it through
   `vim.system`, async or blocking. Nothing needs writing to *send* a
   request; the work is entirely UI, request state, and history.

**The cheap first version is in-editor, not in the browser.** A Neovim split
holding a request buffer and a response buffer has no CORS problem, needs no
socket, no token, no new security posture — and `lib.nvim.net.curl` plus
`lib.nvim.ui.kit` cover most of it. The browser version is strictly the more
expensive one and should follow, not lead.

**Where it lives:** the runner *executes*; documentation.nvim *knows the
endpoints*. Split along that line — execution and request history in the new
plugin, the endpoint list and the panel that offers "send a request to this
one" in documentation.nvim, wired as a **soft dependency**: the panel is
absent when the runtime plugin is not installed. That is the pattern this
ecosystem already uses in three places (`progress`→fidget,
`telemetry`→mdview, `check.lua`→lua-language-server) and it needs no new
mechanism.

---

### 3.3 Docs cross-references — static, documentation.nvim, genuinely new data

**The gap is real and larger than it looks.** Documentation files are, today,
a path (`node.readme`) and a counter (`files_md`). No `.md` content is read
anywhere. So "which docs mention this function" cannot be answered at all
right now — not badly, not partially.

Three pieces:

1. **A docs corpus scan** — walk `*.md` (and, defensibly, `doc/*.txt`
   vimdoc), extract headings, code spans and links. A markdown parser is not
   needed for the useful 90 %: code spans and headings are what carry entity
   names.
2. **A reference index** — which doc mentions which IR entity.
3. **UI** — an icon wherever an entity is listed, opening the references with
   a preview.

**The matching problem is the same one solved twice already in this
ecosystem**, and it gets the same answer. How do you know a `` `scan_full` ``
in prose means `documentation.core.scan#scan_full`? Exactly as `calls.lua`
resolves a callee and as `lib.nvim.telemetry` resolves a wrapped key to a
module path:

- a **qualified** name in a code span (`documentation.core.deps.build`) →
  exact;
- a **bare** name that is unique in the whole tree → heuristic, marked as
  such;
- a bare name that is ambiguous, or an ordinary English word that happens to
  match → **not a match**, and never rendered as one.

`Documentation.Edge` already carries `confidence` for precisely this
distinction, and its `kind` is already a discriminated union — a `doc_ref`
kind fits the existing shape without widening it.

**One check falls out of this nearly free, and it may be the most valuable
thing in this whole document:** a doc that references an entity which **no
longer exists** is drift — the inverse of dead code, in prose. Nothing else
in this toolchain can see it, it is the exact failure mode of well-maintained
docs going stale, and it is this plugin's stated reason for existing applied
one layer out. Call it `doc-references-missing`.

---

### 3.4 Docs-only view / filter — cheap, once 3.3 exists

Once the corpus is scanned, "show only docs" and "hide docs" are a filter
over a node classification, and the filter plumbing (`anFilter`/`state.q`,
`editor/browse/filter.lua`'s query language) already exists on every panel.
Not worth designing separately — it is a consequence of 3.3, not a feature
beside it.

---

### 3.5 Hover previews — three different features wearing one name

They look alike and are not:

| Ask | Data needed | Cost |
|---|---|---|
| Function signature on hover | `fn.signature` — **already in the IR** | trivial; works in the static artifact today |
| Snippet at `path:line` | N lines around a known line | bounded by entity count; embeddable |
| Arbitrary file on hover | whole file contents | doubles the artifact, or needs serve |

**The first is nearly free and should not wait for the others.** Every
function's signature is already serialised into `module_map.json`; a popup
showing it needs no new extraction, no server, and works offline in the
committed artifact.

**The second is the interesting one.** For "hover a `path:line:col` and see
the code there", the whole file is not needed — a bounded window around a
line the map already knows about is. That is proportional to the number of
entities, not to the size of the source tree, which keeps it embeddable and
keeps the static artifact self-contained.

**The third is the one that needs the server**, and the measured numbers
above are the argument: 728 KB of source against an already-752 KB page.
`serve.lua`'s own History precedent — pay 0.3 s per commit the reader
actually opens rather than 25–50 s of precomputation for all of them —
applies unchanged.

So: **two tiers.** Signature and bounded snippets embedded and always
available; full-file preview an enhancement when serving. The page should
degrade to the embedded tier without a server, not lose the feature.

---

### 3.6 Three more in the same spirit

Since the stated motive is *"wenn wir uns schon so viel Arbeit machen, dass
die Docs und Annotationen passen, dann sollten wir sie auch gut einsetzen"* —
these leverage the same investment:

- **Called but undocumented.** Already proposed in
  `telemetry-documentation-bridge.md` as one of two `doccoverage` aggregate
  lines. Worth restating here because it is the sharpest instance of the
  whole idea: it sorts the documentation backlog by *evidence of actual use*
  instead of alphabetically. It needs the telemetry join, not the docs
  corpus.
- **Doc freshness.** Once a doc references entities, compare the doc's last
  git commit against the referenced entities' last commits. A doc older than
  everything it describes is a candidate for review — measured, not guessed.
- **Entry points.** "Where do I start reading this codebase" — exported,
  documented, called from outside their own module, ranked. Every input
  already exists in the IR; nothing renders it.

---

## 4. The plugin question, answered

---

### What the numbers say

Telemetry is **2 915 lines** with **one** genuinely lib.nvim-specific
coupling: `wrap_lib()`, which instruments the `require("lib")` aggregate
through `lib.strategies.control`. Everything else it uses from lib.nvim —
`autocmd`, `cache.disk`, `fs.mkdirp`, `git`, `notify`, `usercmd`, `ui.kit` —
is generic infrastructure that **documentation.nvim already depends on
too**, as a plain runtime dependency.

So a new plugin would consume lib.nvim exactly the way documentation.nvim
already does. There is no new dependency shape to invent, and no vendoring
question: `FEATURES.md`'s own extraction entry settled that — *"lib.nvim
stays a runtime dependency. Vendoring buys a standalone plugin at the price
of a second maintenance site for code that already exists."*

---

### The precedent is exact

`lib.nvim.docmap` grew inside lib.nvim, proved itself, and became
documentation.nvim. That extraction was, in its own words, **"a rename
rather than a rewrite, which is the whole point of the result"** — cheap
*because the decoupling had already happened as a design discipline*
(`opts.root`/`opts.source` meant nothing knew lib.nvim's layout). Telemetry
is on the same trajectory and is already decoupled to the same degree.

---

### The answer, and why it revises my earlier one

Earlier in this session I said: CLI yes, extraction *not yet* — telemetry
was still moving, and extraction buys identity, not capability.

**That was the right answer for telemetry alone. The feature list changes
it**, for one specific reason: the API request runner is a *second* runtime
feature, and it has nowhere good to live. It does not fit documentation.nvim
(a static analyzer whose one deliberate runtime concession is a GET-only,
whitelist-everything server) and it does not fit lib.nvim (a library of
helpers, not a place for a feature with its own UI, state and history).

So: **yes to the plugin — justified by the request runner, not by
telemetry.**

With a sequencing that keeps it honest:

1. **New code goes there from birth.** The request runner has no migration
   cost; "where does this live" is answered once, at zero price.
2. **Telemetry moves later**, once the new plugin has shipped something and
   proven it is a real home. Moving working code has cost and risk that
   writing new code in the right place does not.
3. **`wrap_lib()` does not move.** Instrumenting `require("lib")` is
   lib.nvim's own convenience, tied to `lib.strategies.control`. It stays,
   as a thin caller of the extracted engine — the same relationship
   `core/lang/lua.lua` has to `functions.lua`.

---

### The resulting ecosystem

Four pieces, each with one sentence's worth of job:

- **lib.nvim** — the shared library everything else consumes.
- **documentation.nvim** — static truth: what exists, what is documented,
  how it connects. *All five docs features above live here.*
- **the new plugin** — runtime truth: what actually ran (telemetry), and
  what an endpoint actually returns (request runner).
- **mdview.nvim** — presentation: Markdown to a browser. Already proven as
  telemetry's `report_style = "mdview"`.

The seam between the middle two is Seam A, which was already documented
before any of this was proposed. That is the strongest argument that it is a
real boundary and not one invented to justify a new repository.

---

## 5. Naming — settled

**`runtime-analysis.nvim`.** Decided and created (`E:/repos/
runtime-analysis.nvim`, empty but for an `init` commit, pushed to GitHub).

Recorded for the next reader, since the alternatives were live options:
`analysis.nvim` was rejected as too broad — documentation.nvim performs
analysis too, and a reader could not tell the two apart by name.
`runtime.nvim` was rejected because `runtime` is heavily loaded vocabulary
in Neovim (`runtimepath`, `:h runtime`), so `require("runtime")` reads like
core plumbing. `runtime-analysis.nvim` is longer, and pairs unambiguously
with documentation.nvim — which is the property that matters, because
naming the pair correctly is what makes the boundary legible.

---

## 6. What runtime-analysis.nvim actually is

Raised as an open question — Neovim plugin, web app, Electron app, or a
compiled Go/C++ program? Worth answering properly, because it is the one
decision here that is expensive to reverse.

---

### One hard constraint decides most of it

**Telemetry cannot be anything other than in-process Lua.** It works by
replacing entries in live Lua function tables (`registry.attach` swaps
`container[field]`), which requires being inside the same Lua state as the
code being measured. No external process — Go, C++, Electron, a browser —
can do that. It is not a performance question or a preference; it is what
the technique *is*.

So a Neovim-plugin component exists necessarily. The real question is only
whether something *else* exists beside it.

---

### What a separate binary or app would actually buy

Measured against what already exists, not in the abstract:

| Hoped-for gain | Reality |
|---|---|
| Performance | Telemetry's hot path is **0.014 µs/call**, measured. Report building runs over a few hundred KB of JSON. Nothing here is compute-bound. |
| A process that outlives Neovim | Already solved: counts persist to disk, `telemetry.load()` reads a namespace with no live instance, and mdview's `standalone` mode already outlives `:qa` by design. |
| A rich browser UI | Already solved **twice in-house**: documentation.nvim generates a self-contained interactive HTML page (4 083 lines of Lua emitting HTML+JS, no CDN, no build step), and mdview.nvim ships a Go relay plus a prebuilt web client. |
| A local HTTP server for a browser-side request runner | The one genuine case — and mdview's relay is *already* a Go binary that serves a web client behind a per-session token. Extending that beats writing a second one. |

---

### What it would cost

Not hypothetical either. mdview.nvim already pays this price and the code is
there to read: `adapter/install.lua` is 226 lines of download,
checksum-verify, extract and version-pin logic against GitHub Releases, plus
a per-platform release pipeline (`windows`/`darwin`/`linux` × `amd64`/
`arm64`), plus a capability probe because an older pinned binary rejects
newer flags silently. Electron would be that, plus a ~150 MB runtime, plus a
Node toolchain, to reach a browser this ecosystem can already reach.

---

### Answer

**runtime-analysis.nvim is a Neovim plugin.** Lua, lib.nvim as a runtime
dependency, exactly the shape documentation.nvim already has.

If a browser tier is ever wanted beyond what mdview already renders, the
honest options are (a) generate a self-contained page the way
documentation.nvim already does, or (b) reuse mdview's relay. **Not** a new
runtime. This is a decision that can be revisited cheaply later precisely
*because* the plugin is Lua — nothing about starting here forecloses adding
a binary if a real need for one ever shows up, whereas starting with
Electron forecloses being a normal Neovim plugin.

---

## 7. How the two plugins meet

Also raised: could documentation.nvim gain a tab that appears when
runtime-analysis.nvim is installed? **Yes — but not the obvious way, and the
reason is a constraint this repository already enforces on itself.**

---

### The naive integration is architecturally excluded

documentation.nvim's primary output is a **committed, byte-deterministic
artifact**. The `map` CI job regenerates it in memory and byte-compares
(`scripts/ci.sh map` → `gen_map.lua --check`). Therefore:

> The artifact's content must not depend on what happens to be installed on
> the machine that generated it.

If documentation.nvim embedded runtime data at generation time, a machine
with runtime-analysis.nvim installed would produce a different `index.html`
than CI — which has no such plugin — and the gate would fail. Committing the
runtime data instead does not rescue it: telemetry counts change on every
flush and are *personal usage*, not repository truth, so they belong in a
cache directory, not in git.

**LuaLS is the existing precedent for how optional enrichment is handled
here**, and it confirms the rule rather than contradicting it: `opts.luals`
is an explicit flag (`--full`), the IR distinguishes "did not run" (`nil`)
from "ran, found nothing" (`{}`), and the *committed* artifact is the one
generated **without** it. Optional data is allowed; optional data that
silently changes the committed artifact is not.

---

### The three surfaces that remain, ranked

1. **In-editor, `:DocBrowse` gains a mode. ← start here.**
   No artifact, no determinism problem — the editor-side browser renders
   live data at view time. It is also **already designed**:
   `telemetry-documentation-bridge.md` specifies exactly this as "Mode 7,
   telemetry", down to the observation that `MODES` is a table the key
   bindings, `?` panel and whichkey registration all iterate, so a seventh
   entry costs one string plus one entry builder. Cheapest surface, full
   join, design already written.

2. **Browser, but loaded at view time under `serve`.**
   Follows the History precedent exactly: `serve.lua` already fetches commit
   analysis on demand rather than baking all ~90 commits in, for the same
   reason. A Runtime tab can always be present in the artifact (so the page
   stays byte-identical) and populate itself from an endpoint when served,
   showing an honest empty state under `file://`. Later, and only if the
   in-editor mode proves the join is worth looking at often.

3. **runtime-analysis.nvim renders its own separate page.**
   Zero coupling, but it discards the join — and the join *is* the value, per
   the bridge document's entire argument. Worth it only for views that are
   purely runtime (a request-runner history, say), never for the crossed
   static × runtime views.

---

### Direction of the dependency

**documentation.nvim must not hard-depend on runtime-analysis.nvim.**
`pcall(require, …)`, mode absent when unavailable — the bridge document
already states this rule, and the ecosystem already applies it in three
places (`progress`→fidget, `telemetry`→mdview, `check.lua`→lua-language-
server).

One consequence worth recording now: the bridge document currently names
`pcall(require, "lib.nvim.telemetry")` as the probe. **That module path
changes** when telemetry moves (step 7 of the sequencing below), so the join
should be written against a small named interface from the start — "give me
`{ [key] = calls }` for this namespace, and tell me which keys you can
resolve to module paths" — rather than against telemetry's module layout.
That interface already exists in substance: `telemetry.load()`,
`Data.modules`, and `resolved_modules()` were built for exactly this
consumer during the same week this document was written.

**Update (2026-08-03):** the predicted change happened — step 7 below is
done, and the probe is now `pcall(require, "runtime-analysis.telemetry")`.
`telemetry.load()`/`Data.modules`/`resolved_modules()` moved with it
unchanged, so the interface this note called for is exactly what a future
Mode 8 (step 8 below) would join against — nothing here needed revising,
only the module path this paragraph itself named as an example.

---

## 8. Sequencing

**Agreed work order: documentation.nvim first, runtime-analysis.nvim after.**
That is steps 1–4 below, all of which land in this repository and none of
which need the new plugin to exist. `runtime-analysis.nvim` stays an empty
repository until step 5, which is the correct state for it — an empty repo
costs nothing, whereas a half-built one invites being wired into things
before its shape is settled.

Ordered so each step is independently useful and nothing is a big-bang.

**In documentation.nvim:**

1. ~~**Signature popup.** Data already in the IR. Smallest possible proof
   that the "surface what we already know" direction pays off.~~
   **Done (2026-08-03)** — shipped as the *annotation* popup, which is what
   the data actually supported: the signature was already every list's
   label, so the gap was the params/returns/prose behind it, not the
   signature itself. `fnAnnotationHTML` is now shared between the detail
   pane and the popup, and that refactor was verified output-identical
   across all 56 nodes with functions rather than assumed.
2. ~~**Docs corpus scan + reference index + `doc-references-missing`.** The
   largest genuinely-new static capability, and the one carrying the stated
   motive.~~ **Data layer done (2026-08-03)** — `core/docs.lua`, `ir.docs`,
   and the check. Resolution is qualified-only by default
   (`opts.docs_heuristic` mirrors `opts.calls_heuristic`) after a first real
   run showed the bare-name path matching `write`/`open`/`scan`/`esc`. Four
   false-positive classes were found and excluded by running it against this
   repository rather than against fixtures. **UI done (2026-08-03)** — a marker beside any
   entity the prose mentions, rendered only where references exist, reusing
   the annotation popup's card rather than adding a second floating element.
   **Docs-only overview done (2026-08-03)** — an eighth Analysis panel over
   `ir.docs.files`, exactly as cheap as §3.4 predicted: no new extraction,
   just the existing `anFilter`/`anSort`/`anHead` plumbing every other
   panel already uses. Step 2 is now fully done.
3. ~~**Bounded snippet previews.** Embeddable tier only.~~ **Done
   (2026-08-03)** — `core/snippet.lua`, shared by both language backends,
   caps each function's own body at 40 lines and reports how many were cut.
   Rendered only in the annotation popup, deliberately not folded into
   `fnAnnotationHTML` (the Tree tab's detail pane already lists every
   function of a node in full; adding up to 40 code lines per function
   there would turn a many-function node's pane into mostly code, for a
   question the pane's own click-through to source already answers).
   **Measured, not assumed:** this repository's own artifact grew ~29%
   (`index.html`, 797KB → 1031KB) and ~54% (`module_map.json`, 430KB →
   662KB) from this alone — bounded and proportional to entity count as
   §3.5 predicted, but a real cost worth stating plainly rather than
   calling "cheap" the way step 2's docs-only overview genuinely was. Only
   a function's own declared span is covered; a snippet at an arbitrary
   `path:line:col` (a call site, a doc reference's own line in the `.md`
   file) is not attempted — those lines live in files this pass over
   function definitions was never reading, a separate task, not a small
   extension of this one.
4. ~~**API endpoint inventory.** Call-based recognizer first (flat, an
   Analysis panel); file-based later (Hierarchy view, per
   `framework_conventions.md`).~~ **Call-based done (2026-08-03)** —
   `core/endpoints.lua` recognizes `app.get("/path", handler)`-shaped
   registrations (Express/Fastify/Koa syntax), feeding a new `endpoints`
   field alongside `plugins`, a ninth Analysis panel, and `:DocMap
   endpoints` (mirroring `:DocMap plugins` exactly). `framework` is read
   from the file's own imports, never guessed from the call shape — Express/
   Fastify/Koa all share the identical syntax. **File-based routing
   (Next.js/SvelteKit/Nuxt/Remix) remains not attempted** — it belongs in a
   Hierarchy view per the reasoning already in §3.1, a materially different
   piece of work, not a follow-up to this one.

**Then in runtime-analysis.nvim:**

5. ~~**The plugin's first feature: the in-editor request runner.** No
   browser, no server, no CORS. `lib.nvim.net.curl` for execution,
   `lib.nvim.ui.kit` for the panes.~~ **Done (2026-08-03)** —
   `runtime-analysis.nvim`'s `:RARequest`/`:RASend`, one request per buffer
   in the same shape VS Code's REST Client/IntelliJ's HTTP Client already
   use. Not `lib.nvim.ui.kit`'s panes in the end: that toolkit's
   `viewer`/`surface` components are floats that close on focus loss,
   exactly wrong for an edit-send-glance-edit-again workflow — a plain
   persistent split, hand-written, fit the job this needed. Required
   extending `lib.nvim.net.curl` first: its existing `fetch_json` API
   force-decoded every response as JSON and never exposed the HTTP status
   code or headers at all (curl's own exit code says nothing about the
   HTTP status — it is `0` for a successful request regardless of `200` or
   `404`) — `fetch_raw`/`fetch_raw_blocking` are new there, verified
   against a hermetic `vim.uv` TCP server, no external test dependency.
   See `runtime-analysis.nvim`'s own README and `lib.nvim`'s
   `lua/lib/nvim/net/curl/README.md`.
6. ~~**documentation.nvim's endpoint panel gains "send a request"**, soft
   dependency on step 5.~~ **Done (2026-08-03)** — not the *static* HTML
   Analysis panel (a browser page cannot `pcall(require, ...)` a Neovim
   plugin — nonsensical outside an editor), but a new **Endpoints mode in
   `:DocBrowse`** instead, the in-editor browser this session's own
   research found is "already mode-based" (see step 8's note below, which
   this discovery came from first). `gs`, scoped to that mode, is the soft
   dependency: `pcall(require, "runtime-analysis")`, absent with a clear
   message otherwise, the same pattern already used for `progress`→fidget
   and `check.lua`→lua-language-server. Opens a pre-filled request buffer
   rather than sending immediately — a route's path is relative and may
   have unfilled `:param`s, genuinely nothing static analysis could send
   correctly on its own.
7. ~~**Telemetry moves** into runtime-analysis.nvim, `wrap_lib()` staying in
   lib.nvim as a thin caller.~~ **Done (2026-08-03)** — all 13 files (2915
   lines) moved verbatim into `runtime-analysis.telemetry`, registered as
   `:RATelemetry` (renamed from `:LibTelemetry` for consistency with
   `:RARequest`/`:RASend`). `wrap_lib()` itself was **not** migrated: it was
   deleted from the moved module, and `lib.nvim` instead gained
   `lib.strategies.telemetry_wrap`, a thin caller built entirely on the
   already-public `inst.wrap()` — the only lib.nvim-specific piece was
   materializing `require("lib")`'s metatable-hidden keys via `rawset`
   first (see `lib.strategies.control`), which is now this new module's
   whole job. Real data, not just cosmetics, had to move too: the cache
   directory default (`stdpath("cache")/lib.nvim/cache`), the Markdown
   report root, and the JSON export filename prefix all now resolve under
   `runtime-analysis.nvim` instead — verified with a new test asserting an
   instance's resolved cache dir, since nothing before this exercised that
   default at all. lib.nvim's CI gained a second checkout step (mirroring
   runtime-analysis.nvim's own existing checkout of lib.nvim) so the new
   `telemetry_wrap_spec.lua` exercises the real cross-repo integration
   rather than only its soft-`pcall` no-op branch. See
   `runtime-analysis.nvim`'s `lua/runtime-analysis/telemetry/README.md` for
   the full API, and lib.nvim's `docs/modules.md`/`doc/lib.nvim.txt` for the
   pointer left behind at the old location.
   **Revised (2026-08-03, same day):** `lib.strategies.telemetry_wrap`
   initially took an already-constructed instance as a parameter, splitting
   "who knows about `runtime-analysis.telemetry`'s API" across two files for
   no real benefit with exactly one caller. Reworked into a self-contained
   `setup()`/`teardown()` pair that owns the whole lifecycle — creating the
   instance, the materialize-then-wrap dance, starting it — so a caller
   needs neither `runtime-analysis.telemetry`'s API nor
   `lib.strategies.control`'s. Also gained `runtime-analysis.telemetry.auto()`
   in the same round: the generic "new+wrap+start on a plugin's load event"
   shape, extracted out of what had been hand-rolled entirely in personal
   config, with the plugin-manager hook and per-plugin policy deliberately
   left to the caller (see that module's own README section).
8. ~~**`:DocBrowse` gains a telemetry mode** — the static × runtime join,
   in-editor, per `telemetry-documentation-bridge.md`'s existing design.
   That document calls it "Mode 7", written before step 6 above claimed
   position 7 in the actual `MODES` list for Endpoints instead — it will
   be the 8th entry when it lands, a renumbering worth noting here so a
   future reader is not confused by the mismatch between this document's
   number and the array position telemetry actually gets.~~ **Done
   (2026-08-04)** — landed as the design doc specified, at position 8 as
   predicted. `documentation.core.check.used_keys(ir)` (extracted from
   `check_dead_functions`'s own body, unchanged logic, so the check and the
   mode can never quietly disagree about what "has a static caller" means)
   crossed against `runtime-analysis.telemetry.load(namespace)` in a new
   `documentation.core.telemetry_join` module — soft dependency throughout,
   `nil` treated as "no data" at every call site, never as evidence.
   `opts.telemetry_namespace` (new, `opts.title` by default — every
   telemetry instance in this ecosystem is already namespaced by the
   plugin's own display name) is what both the mode and dead-function
   suppression join against.

   Both aggregate lines shipped too, printed by `:DocMap`'s own CLI
   alongside the existing doc-coverage line, silently absent (not zero) when
   no telemetry data exists for the run: documented-but-never-called (the
   maintenance-cost set) and undocumented-but-called (a documentation
   backlog prioritized by evidence of actual use, the line the design doc's
   own text called "the most immediately useful number in this whole
   document"). `dead-function` itself gained one line of real behavior
   change: a finding is suppressed once telemetry proves the *exact*
   function alive, exactly the design's ⚠️/`!` cell and nowhere else —
   never escalated to a higher severity, matching the design doc's own
   explicit "a prompt to look, never a delete list" instruction for this
   check.

   Verified in `TESTS/browse_telemetry_spec.lua` against a real
   `runtime-analysis.telemetry` instance when one is reachable
   (`RUNTIME_ANALYSIS_DIR`, the same rtp wiring `browse_endpoints_spec.lua`'s
   own `gs` test already established) — a real wrap, real calls, a real
   flush to disk, read back with no live instance the same way a fresh
   `:DocMap check` run would — not only the join's pure-data-in-pure-data-out
   half. See `runtime-analysis.nvim`'s `docs/FINISHED.md` for that
   repository's own side of this entry.

   **Extended (2026-08-10): the write side.** Step 8 as originally shipped
   was read-only — the telemetry mode and dead-function suppression could
   join against *some* namespace, but nothing made this tree itself write
   to one; a caller had to hand-instrument `require("documentation")` with
   runtime-analysis.telemetry to get anything to read back at all. New
   module, `documentation.core.telemetry_self`: self-instruments this
   tree's own aggregate on `documentation.setup()`, on by default, opt-out
   via `opts.telemetry = false` — the same `~= false` shape `opts.which_key`
   already established — and a no-op without runtime-analysis.nvim
   installed, the identical soft-dependency posture every other integration
   point in this document already takes. Built on
   `runtime-analysis.telemetry.auto()` directly (the generic "new+wrap+start
   on load" helper `lib.strategies.telemetry_wrap` was itself built around,
   step 7's own entry above) rather than a bespoke materialize-then-wrap —
   this tree's own module table has no metatable-hidden aggregate the way
   `require("lib")` does, so the generic path was sufficient with nothing
   lib.nvim-specific to work around. Same namespace resolution as the read
   side (`opts.telemetry_namespace` or `opts.title`), so a caller who sets
   nothing gets both sides pointed at the same place automatically.
   Verified in `TESTS/telemetry_self_spec.lua`, same real-checkout-vs-absent
   split as `browse_telemetry_spec.lua`.
9. **Full-file previews / browser request runner / a Runtime tab under
   `serve`** — all three require the serve tier, and the runner additionally
   requires token gating.

Steps 8 and 9 are the ones that pay off the whole two-plugin split; steps
1–4 are worth doing whether or not the split ever happens, which is the
property that makes this order safe to commit to now.

---

## 9. What not to build

- **Do not embed file contents wholesale.** Measured: it roughly doubles an
  already-752 KB artifact, on this repository's small tree.
- **Do not turn `serve.lua` into a general proxy.** If a browser-side runner
  ever happens, it needs origin/token gating first — a localhost server is
  reachable from every tab, not only from the map's page.
- **Do not build the browser request runner before the in-editor one.** It
  is strictly more expensive and strictly less safe, for the same feature.
- **Do not extract telemetry before the new plugin has shipped something
  else.** A one-feature plugin whose one feature is moved working code has
  proven nothing and risks a regression for zero capability gained.
- **Do not guess doc references.** An ordinary word matching a function name
  must be *no match*, not a low-confidence one. The precedent is
  `calls.lua`'s `opts.calls_heuristic` being **off by default** — a confident
  wrong edge is worse than a missing one.
- **Do not build React hook lint rules**, per `framework_conventions.md`'s
  existing conclusion — `eslint-plugin-react-hooks` already does that half
  well.
- **Do not let runtime data into the committed artifact.** Not at generation
  time (breaks the byte-comparison gate) and not by committing it (personal
  usage, high churn, belongs in a cache directory). §7 has the full argument.
- **Do not ship a binary or an Electron runtime for runtime-analysis.nvim.**
  §6 has the cost measured against what mdview.nvim already pays for exactly
  that. Revisit only if a need appears that Lua genuinely cannot serve.

---

## 10. Honest limits

- **Four first-class plugins is real, ongoing maintenance**, against a
  personal-plugin ecosystem that is already ~25 repositories. This document
  argues the boundary is correct; it does not argue the total is free. The
  agreed work order mitigates it — steps 1–4 are worth doing on their own
  merits, so the fourth plugin only starts costing once there is a reason
  for it to exist.
- **`core/plugins.lua` passed nine hand-written fixtures and then produced
  235 false positives against one real config**. Every recognizer proposed here — endpoints
  especially — carries that risk profile. Real trees, not fixtures.
- **Every framework-syntax claim above is unverified.** No Express, FastAPI
  or axum tree has been parsed here. Verify at implementation time, the way
  `ecma.lua`'s node shapes were verified against real parses rather than
  assumed from grammar documentation.
- **The docs corpus scan has no size bound yet.** A repository with a large
  `docs/` tree could make the reference index the biggest thing in the
  artifact. Whether it is embedded, served, or capped is an implementation
  decision this document deliberately leaves open.
- **`file://` remains the primary distribution mode.** Every feature above
  must degrade to something useful without a server, or it is not really
  part of the committed artifact this plugin exists to produce.

---

