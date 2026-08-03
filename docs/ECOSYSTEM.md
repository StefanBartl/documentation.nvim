# Ecosystem architecture — where docs, static analysis and runtime each belong

**Status: architectural concept. Nothing here is implemented.** Written in
response to a feature list (API endpoint inventory, a Postman-lite request
runner, docs cross-references with previews, a docs-only view, file/snippet
hover previews) plus the question it came with: *is a separate
`runtime.nvim` / `analysis.nvim` / `runtime-analysis.nvim` worth it, working
standalone but also with documentation.nvim and mdview.nvim, taking the
telemetry module out of lib.nvim?*

This answers **where each thing belongs and why**, not how to build it. An
implementation concept comes after this one is agreed.

## Epistemic note

This repository's convention is that a design doc states what it verified and
what it assumed. [`FRAMEWORK_CONVENTIONS.md`](FRAMEWORK_CONVENTIONS.md) flags
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
  `fs.collect_recursive`, `fs.is_subpath`, `fs.open.url.system_opener`,
  `cross.uv.spawn_capture` — a superset of telemetry's.

**Not verified, and stated as assumption:** every claim below about a *web
framework's* route syntax (Express, Fastify, FastAPI, axum, …). No such tree
has been parsed here. `FRAMEWORK_CONVENTIONS.md` gives itself the same
caveat and it still applies — re-verify against a real parse at the point
any recognizer is actually written.

---

## 1. Two seams already exist. Everything sorts along them.

Neither is new. Both are already documented in this codebase, and every
feature in the list lands on one side or the other of each.

### Seam A — static vs. runtime

`docs/ROADMAP/telemetry-documentation-bridge.md` already names it:
documentation.nvim knows what **exists and is documented**; telemetry knows
what **actually ran**. Its whole argument is that neither can produce the
other's evidence, and that crossing them is where the value is.

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

### 3.1 API endpoint inventory — static, documentation.nvim

This is a **layer-2 convention recognizer** in `FRAMEWORK_CONVENTIONS.md`'s
own vocabulary: a second pass over a parse tree the language backend already
produced, looking for one ecosystem's structural idiom. `core/plugins.lua`
(lazy.nvim specs) is the existing instance of exactly this shape.

It was blocked on a JS/TS backend when that document was written. **It is no
longer blocked** — `core/lang/ecma.lua` ships functions, imports, calls and
symbols for JS/TS/TSX.

**A refinement of `FRAMEWORK_CONVENTIONS.md`, not a contradiction.** That
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

- a **qualified** name in a code span (`documentation.core.scan.scan_full`) →
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

### 3.4 Docs-only view / filter — cheap, once 3.3 exists

Once the corpus is scanned, "show only docs" and "hide docs" are a filter
over a node classification, and the filter plumbing (`anFilter`/`state.q`,
`editor/browse/filter.lua`'s query language) already exists on every panel.
Not worth designing separately — it is a consequence of 3.3, not a feature
beside it.

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

### The precedent is exact

`lib.nvim.docmap` grew inside lib.nvim, proved itself, and became
documentation.nvim. That extraction was, in its own words, **"a rename
rather than a rewrite, which is the whole point of the result"** — cheap
*because the decoupling had already happened as a design discipline*
(`opts.root`/`opts.source` meant nothing knew lib.nvim's layout). Telemetry
is on the same trajectory and is already decoupled to the same degree.

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

## 5. Naming

Not a strong opinion, but the tradeoffs are real:

- **`analysis.nvim`** — too broad. documentation.nvim performs analysis too;
  a reader cannot tell which plugin does what from the names.
- **`runtime.nvim`** — clean and short, but `runtime` collides conceptually
  with `runtimepath`/`:h runtime`, which is heavily loaded vocabulary in
  Neovim. `require("runtime")` reads like core plumbing.
- **`runtime-analysis.nvim`** — unambiguous, and pairs correctly with
  documentation.nvim. Clunky, and long for a `require`.

Worth considering alongside them: something naming the *act* rather than the
domain — the plugin observes a program and pokes at it. Whatever is chosen,
it should read as documentation.nvim's counterpart, since that is exactly
what it is.

**This is a decision to make deliberately and once** — renaming a published
plugin is the one thing here that gets expensive later.

---

## 6. Sequencing

Ordered so each step is independently useful and nothing is a big-bang.
Steps 1–3 need no new plugin at all.

1. **Signature popup.** Data already in the IR. Smallest possible proof that
   the "surface what we already know" direction pays off.
2. **Docs corpus scan + reference index + `doc-references-missing`.** The
   largest genuinely-new static capability, and the one carrying the user's
   stated motive. The docs-only filter falls out of it.
3. **Bounded snippet previews.** Embeddable tier only.
4. **API endpoint inventory.** Call-based recognizer first (flat, an Analysis
   panel); file-based later (Hierarchy view, per
   `FRAMEWORK_CONVENTIONS.md`).
5. **The new plugin, with the in-editor request runner.** First feature,
   no browser, no server, no CORS.
6. **documentation.nvim's endpoint panel gains "send a request"**, soft
   dependency on step 5.
7. **Telemetry moves** into the new plugin, `wrap_lib()` staying behind.
8. **Full-file previews / browser request runner**, both requiring the serve
   tier and, for the runner, token gating.

---

## 7. What not to build

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
- **Do not build React hook lint rules**, per `FRAMEWORK_CONVENTIONS.md`'s
  existing conclusion — `eslint-plugin-react-hooks` already does that half
  well.

---

## 8. Honest limits

- **Four first-class plugins is real, ongoing maintenance**, against a
  personal-plugin ecosystem that is already ~25 repositories. This document
  argues the boundary is correct; it does not argue the total is free.
- **`core/plugins.lua` passed nine hand-written fixtures and then produced
  235 false positives against one real config** (`MULTILANG.md`'s own
  Considerations section). Every recognizer proposed here — endpoints
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
