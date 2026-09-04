# Core

Cross-cutting mechanisms used by more than one tab of the generated page,
plus the two most recent ecosystem-convention Analysis panels.

## Revision completion on `:DocMap diff` / `:DocMap churn`

Both take a revision — `diff [ref]` a single one, `churn [rev-range]` a
range — and both now complete against the repository's own named revisions:
local branches, remote branches (prefixed, `origin/main`, which is how git
accepts them), and tags, newest commit first. For `churn`, typing `A..` and
pressing `<Tab>` completes the right-hand side and returns the whole `A..B`
token, since Vim replaces the entire lead rather than appending to it.

Before this, both slots fell through to the action-name list, offering
`bindings`/`plugins`/… where a revision belongs — worse than no completion,
because every candidate was wrong.

Refs are cached for a few seconds, not for the session: branches come and go
while an editor is open, so a session-long cache would be stale in the
ordinary case, while the short TTL still keeps a held `<Tab>` from spawning
one `git for-each-ref` per keystroke.

- **Module:** `bindings/usrcmds/init.lua` (`revisions`, the `complete`
  callback), [`lib.nvim.git.refs`](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/git/README.md)
- **Config:** none — always available.
- **Docs:** [`docs/BINDINGS.md`](../BINDINGS.md) "User commands".

## Compare marks

Mark any function or module with the `+` beside its `ⓘ` (or a node's own
`+`, which has no signature to hang one off), then open the Compare tab to
see every marked object side by side — Matrix layout lights up the rows
where they actually differ, which is the whole reason to reach for this
over two browser windows.

- **Module:** `core/render/html.lua` (`toggleMark`, `syncMarks`, `markTrigger`)
- **Config:** none — always available, no `opts` key gates it.
- **Docs:** [`docs/pipeline.md`](../pipeline.md) "Compare tab" section.

## Hierarchy hide/dim

Right-click any box in the Hierarchy graph → "Dim this box" (or "Show this
box" once dimmed), plus a "Hidden (N) — show all" toolbar pill to clear
every dimmed box at once. Dims rather than removes a box from the layout —
same `opacity`-only mechanism the pre-existing hover-focus already used,
just persistent and per-box instead of transient.

- **Module:** `core/render/html.lua` (`toggleHidden`, `syncHidden`, `buildMenu`)
- **Config:** none.
- **Docs:** [`docs/pipeline.md`](../pipeline.md) "Hide/dim" subsection under
  Hierarchy tab.

## Plugins Analysis panel

Every recognized lazy.nvim spec in the tree, as its own Analysis-tab panel
and as `:DocMap plugins` → quickfix. Exists for the shape of tree this map
was blind to before it: a Neovim *config*, where `lua/plugins/*.lua` is
mostly `return { {...}, {...} }` with no function in sight.

- **Module:** `core/plugins.lua` (`M.extract`)
- **Usercmds:** `:DocMap plugins` (see
  [BINDINGS.md](../BINDINGS.md#user-commands))
- **Docs:** [`docs/commands.md`](../commands.md) "`:DocMap plugins`" section.

## Tools Analysis panel

This repo's own [`lib.nvim.deps`](https://github.com/StefanBartl/lib.nvim)
manifest (`docs/install.json`/`docs/INSTALL.md`) — declared external CLI
tools, not Lua dependencies — as its own Analysis-tab panel and as
`:DocMap tools` → quickfix. Declared only: never a live "is it installed
here" probe, since a static page has no host to ask.

- **Module:** `core/tools.lua` (`M.resolve`)
- **Usercmds:** `:DocMap tools` (see
  [BINDINGS.md](../BINDINGS.md#user-commands))
- **Docs:** [`docs/commands.md`](../commands.md) "`:DocMap tools`" section.

## Telemetry Analysis panel

`runtime-analysis.telemetry`'s call counts for this project's own
functions, joined against the tree and shown as a sortable table — plus,
once `runtime-analysis.nvim` has any named snapshots saved
(`:RATelemetry snapshot`), a picker to view an older capture and a
"Compare vs:" select for a Function/A/B/Δ diff table between any two.
Unlike every other Analysis panel, not computed from the embedded IR: call
counts change between runs, so `:DocMap serve` fetches this one live on
every open (`GET /api/telemetry[?snapshot=name]`) instead of baking it
into the committed artifact, the same reasoning the History tab's own
on-demand `git` reads already established.

- **Module:** `core/telemetry_join.lua`, `editor/serve.lua`
  (`route_telemetry`, `route_telemetry_snapshots`), `core/render/html.lua`
  (`drawAnalysisTelemetry`, `telPickerHTML`)
- **Config:** none to turn the panel on — it degrades to an explanatory
  message when `runtime-analysis.nvim` is not installed or nothing has
  been recorded yet, the same posture Tools takes toward a missing
  manifest. Needs `:DocMap serve` running (or `:DocMap open` while it
  runs); opened from `file://` it explains why rather than doing nothing.
- **Docs:** [`docs/pipeline.md`](../pipeline.md) "Telemetry" and
  "Telemetry snapshot picker" sections.

## Plugin-gated badge

A small `🔌` badge plus an accent tint marks any tab-bar button whose
usefulness depends on something optional being present — Tools (a
`docs/install.json` manifest) and Telemetry (`runtime-analysis.nvim`)
today, applied via one shared `.plugin-gated` CSS class rather than a
one-off style per button, so the next panel in this shape needs no new
styling work, only the class.

- **Module:** `core/render/html.lua` (`.plugin-gated` CSS, applied to the
  `data-atool="tools"`/`data-atool="telemetry"` buttons)
- **Config:** none — a styling convention, not a feature to switch on.

## Features tab

A repo's own `docs/FEATURES/` folder, when it has one, as a ninth top-level
tab — an index, not a Markdown viewer: one card per `## Feature` section,
its summary and whatever `- **Key:** value` metadata bullets the author
wrote. This entry is the recursive case: the file you are reading is itself
what that tab renders, for this repo.

- **Module:** `core/features.lua` (`M.resolve`), `core/render/html.lua`
  (`drawFeatures`)
- **Config:** none — reads `docs/FEATURES/` (or `docs/features/`)
  automatically when present.
- **Docs:** [`docs/features_format.md`](../features_format.md) (the format
  this file follows), [`docs/pipeline.md`](../pipeline.md) "Features tab"
  section.

## Promoted feature tabs

A `- **Tab:** true` bullet promotes one feature out of the Features catalog
above and into a real top-level tab of its own, built dynamically at page
load. Everything after the metadata block — headings, fenced code, lists,
paragraphs, inline `` `code` ``/**bold**/*italic*/links — renders through a
small Markdown subset instead of just being linked out to. This entry is
the recursive case again, one level deeper: "Module Calls view" above this
one in the same file *is* promoted, so the tab it names is currently
rendering the bullet you are reading right now.

- **Module:** `core/features.lua` (`parse_body`'s `body_start_idx`),
  `core/render/html.lua` (`buildPromotedTabs`, `drawFeatureTab`,
  `renderFeatureBody`)
- **Config:** none — the `Tab: true` bullet is per-feature, not a global
  option.
- **Docs:** [`docs/features_format.md`](../features_format.md) "Promoting a
  feature to its own tab" section, [`docs/pipeline.md`](../pipeline.md)
  "Promoting a feature to its own tab" section.

## External call/plugin visibility

The Deps view's external box answers *why* a dependency is there, not just
that it is — hover any `+ external` box for a breakdown of exactly which
functions were actually called and how often (`plenary.async.run (2×)`),
counted in the same pass that resolves the internal call graph. Declare
`opts.external_repos` to also turn the box into a real GitHub link,
verified against a local checkout when you name one.

- **Module:** `core/calls.lua` (`node.calls_external`), `core/external_repos.lua`
- **Config:** `opts.external_repos` (module-prefix → `"owner/repo"` or a
  table with `branch`/`lua_root`/`local_path`).
- **Docs:** [`docs/pipeline.md`](../pipeline.md) "External call/plugin
  visibility" section, [`docs/reuse.md`](../reuse.md) "GitHub links for
  third-party deps".

## Module Calls view

A sixth Hierarchy view alongside Modules/Types/Inheritance/Deps/Calls: the
same `kind="call"` edges as Calls, collapsed from function-to-function to
module-to-module and weighted by call count, so five call sites between two
modules draw one arrow labelled "5 calls" instead of five overlapping ones —
a require graph already answers "does A depend on B", this answers "how
much". Same `+ external` toggle, direction and depth axes as Deps.

- **Tab:** true
- **Module:** `core/render/html.lua` (`layoutModuleCalls`,
  `addModuleCallExternals`)
- **Config:** none — call-graph resolution runs unconditionally in `scan()`
  (unlike Types/Inheritance, it needs no LuaLS `--full` pass), so this view
  is available on every generated map.
- **Docs:** [`docs/pipeline.md`](../pipeline.md) "Module Calls: weighted
  alternative to Calls" section.

### Why weight, not just an edge

A require graph already draws an arrow for "A depends on B" — a binary
fact. What it cannot say is whether that dependency is load-bearing or a
single forgotten call from three years ago. Module Calls exists for
exactly that gap: two modules connected by one call and by forty calls
look identical on a Deps diagram, and very different on this one.

### Edge weight, visually

Stroke width is `min(1.5 + log2(weight) * 1.1, 7)` pixels, applied as an
inline style rather than an SVG `stroke-width` attribute — the page's own
`.hedge{stroke-width:1.5}` CSS rule would otherwise win over a presentation
attribute and silently flatten every edge back to the same width.

```
weight  1 -> 1.5px
weight  2 -> 2.6px
weight  5 -> 4.0px
weight 20 -> 6.1px
weight 64+ (capped) -> 7.0px
```

Log-scaled on purpose: a linear mapping would let one outlier pair (a
config module calling `vim.notify` forty times) dwarf every other,
genuinely interesting difference into invisibility.

### Why a view, not its own tab

The roadmap item this shipped for ("Gewichtete Alternativ-Ansicht des
Call-Graphen") asked for a dedicated tab. Built instead as a sixth
Hierarchy view, reusing the zoom/pan/hide-dim/context-menu/SVG-export
machinery every other view already has — decided with the repo owner on
the grounds that this view is exactly as centered-on-a-node, directed and
depth-limited as Deps already is, and a new tab would have meant either
duplicating that machinery or generalizing it for one caller.

## Root-level hide slider

A vertical, Google Maps-styled slider next to the Modules view — `+` at
the top hides one more layer of the real directory tree, `−` at the
bottom shows one back. Every node that used to sit at the hidden depth
becomes its own parallel root, all drawn at once as a forest, not a
re-center on any single one of them (double-click already does that).
Answers a problem specific to deep trees: several directories before
anything interesting starts means every session begins with the same
uninteresting clicks.

- **Module:** `core/render/html.lua` (`layoutModulesRooted`,
  `rootFrontier`, `maxRootDepth`, `layoutModulesFrom`)
- **Config:** none — the slider's own `max` is measured off the real tree
  (`maxRootDepth()`), not a config value.
- **Docs:** [`docs/pipeline.md`](../pipeline.md) "Hiding root levels
  (Modules view)" section.

## Call hierarchy in native LSP UI

`opts.callhierarchy` attaches a second, narrow LSP client to Lua buffers
under `source`, alongside whatever real language server is already
there — LuaLS, typically. Answers `textDocument/prepareCallHierarchy`,
`callHierarchy/incomingCalls`/`outgoingCalls`, and injects a
caller/callee count into `textDocument/hover`, all backed by
`Documentation.Handle.callers`/`callees` with no new scan. Built because
LuaLS has no call-hierarchy support of its own — checked against its
source (zero hits for `callHierarchy`) and its own long-open, unstaffed
feature request, not assumed. Neovim's own native `vim.lsp.buf.
incoming_calls()`/`outgoing_calls()`/`hover()` already query and merge
every attached client, so this sits beside LuaLS rather than replacing
any part of it.

- **Module:** `editor/callhierarchy.lua`, `editor/registry.lua`
  (`ensure_callhierarchy`)
- **Config:** `opts.callhierarchy` (`install()` only, boolean, default
  `false`).
- **Docs:** [`docs/pipeline.md`](../pipeline.md) "Call hierarchy in
  native LSP UI" section.

## Findings as native diagnostics

`opts.diagnostics` publishes `Documentation.Finding[]` — until now
reachable only through the `:DocMap check` quickfix list — as native
`vim.diagnostic` entries on every open buffer that has one. No LSP
client needed, unlike call hierarchy above: `vim.diagnostic.set()` works
directly on an already-open buffer. File-level granularity, matching the
quickfix list's own existing precedent (`Documentation.Finding` carries
no line number); `info`-severity findings map to
`vim.diagnostic.severity.HINT` and are shown, where the quickfix list
drops them.

- **Module:** `bindings/diagnostics.lua`, `editor/registry.lua`
  (`ensure_diagnostics`)
- **Config:** `opts.diagnostics` (`install()` only, boolean, default
  `false`).
- **Docs:** [`docs/pipeline.md`](../pipeline.md) "Findings as native
  diagnostics" section.

## Compiler Explorer links (experimental)

A "⚙ Compiler Explorer ↗" link next to every module and function in the
generated page — opens `godbolt.org` in a new tab, pre-loaded with that
entity's real source and Lua selected, showing a genuine `luac -l -l -p`
bytecode disassembly. Not a workaround: verified against Compiler
Explorer's own API and compiler source that `lua` is a real, first-class
language there. Marked experimental because a module's own link
concatenates its functions' snippets rather than the file's exact
content — Compiler Explorer's Lua compiler takes one file per compile,
with no project/multi-file mode the way CMake/C++ has.

- **Module:** `core/render/html.lua` (`godboltUrl`, `godboltTrigger`)
- **Config:** `opts.godbolt` (`generate()`/`scan_full()`, not
  `install()`-only — bakes into the generated page — boolean, default
  `false`).
- **Docs:** [`docs/pipeline.md`](../pipeline.md) "Compiler Explorer
  links, experimental" section.

## Live preview via mdview.nvim

`opts.mdview` pushes a live, Mermaid-free Markdown rendering of the
in-memory IR into an already-running
[mdview.nvim](https://github.com/StefanBartl/mdview.nvim) session on every
`on_change`, so a browser tab previewing this root's `overview.md` stays in
sync with the tree as it changes rather than only with whatever
`generate()` last wrote to disk. Soft dependency (`pcall`-guarded, same
posture as `opts.pdf`'s pdfport.nvim) — a silent no-op when mdview.nvim is
not installed, or installed but no session is currently attached.

- **Module:** `core/render/mdview.lua`, `editor/registry.lua`
  (`ensure_mdview`)
- **Config:** `opts.mdview` (`install()` only, boolean, default `false`).
- **Docs:** [`docs/pipeline.md`](../pipeline.md) "Live preview via
  mdview.nvim" section.

## Loaded panel — cold viewing of a loaded-vs-declared snapshot

`:DocBrowse loaded`.s live diff (on the runtime-analysis.nvim side) only ever
answers "what does *this* editor
session's `package.loaded` disagree with" — a browser tab, running in a
different process, has no live `package.loaded` of its own to read. The
Analysis → **Loaded** panel is the cold counterpart: it reads a *named,
persisted* snapshot (`:RA loaded snapshot <prefix> [name]`,
runtime-analysis.nvim's own §5.4) instead of a live session, the same
Telemetry-snapshot shape (§4.5) applied to a different kind of runtime
fact. No "latest" fallback — unlike Telemetry there is no live aggregate
to default to, so the panel prompts for a snapshot rather than guessing.

- **Module:** `core/loaded_diff.lua` (`M.prefix`, `M.rows_from_snapshot`),
  `editor/serve.lua` (`route_loaded`, `route_loaded_snapshots`)
- **Docs:** [`docs/pipeline.md`](../pipeline.md) "Loaded panel" section.

## Bindings extraction — keymaps, user commands, autocmds

The other three quarters of what a Neovim *config* actually is. `core/
plugins.lua` above covers plugin specs; this covers the rest, on the same
terms: a `lua/bindings/mappings/*.lua` full of `map("n", "<C-a>", …)` has
no functions and no symbols, so it says nothing on a map — even though
"what do I have bound, and where" is one of the questions a config is most
often opened to answer.

Available as `:DocMap bindings` → quickfix, sorted by left-hand side so
**collisions land adjacent**: the same `<leader>x` bound in two files is a
real, hard-to-find config bug (whichever module loads last silently wins),
flagged the same way `:DocMap plugins` flags a repo declared twice.
Buffer-local bindings are excluded from collision counting — shadowing a
global mapping in an ftplugin is the intended idiom, not a clash.

**Wrappers are declared, not guessed.** The `vim.*` APIs are recognized
with no configuration. A config's own helper is not, until named in
`opts.bindings.wrappers` — because a bare `map(...)` is also the most
natural name for a list-mapping helper, and guessing wrong means silently
reporting `vim.tbl_map` as a keymap. That opt-in is not timidity but the
measurement: in the config this was built against, keymaps were 233×
`map(...)` versus 4× `vim.keymap.set`, so wrapper support is the primary
case rather than a refinement of one. Three real aliasing shapes were found
in a single config — `map`, `usercmd.create`, and a bare `local
nvim_create_autocmd = api.nvim_create_autocmd` — none of which any amount
of built-in knowledge would have caught.

Deliberately out of scope: `vim.opt` options (assignments, not calls, and a
flat list of names is weaker than `:set` already gives interactively) and
keymap right-hand sides (as often a multi-line function as a string; `desc`
is the better answer and `line` points at the real thing).

Available both as `:DocMap bindings` (quickfix) and as the Analysis tab's
**Bindings** panel, which sorts, filters and flags collisions the same way —
the panel is JS-side aggregation over the already-serialised IR, no second
extraction (the same split `renderAnalysisPlugins` documents).

`bindings` is serialized into `module_map.json` **unconditionally**, unlike
the `#x > 0` fields around it: a cold consumer has to be able to tell "this
artifact predates bindings extraction" from "this tree registers none", and
an always-present key is the only thing that distinguishes them. That
difference is load-bearing for anything joining against the artifact
without a live session.

- **Module:** `core/bindings.lua` (`M.extract`, `M.recognized`),
  `core/render/html.lua` (`renderAnalysisBindings`), `init.lua` (`to_json`)
- **Config:** `opts.bindings.wrappers` — `callee -> argument layout`
  (`keymap`/`keymap_buf`/`usercmd`/`usercmd_buf`/`autocmd`). Only a wrapper
  preserving the wrapped API's argument order is declarable; one that
  reorders is out of scope rather than mis-parsed.
- **Usercmds:** `:DocMap bindings` (see
  [BINDINGS.md](../BINDINGS.md#user-commands))
- **Tests:** `TESTS/bindings_spec.lua`
- **Docs:** [`docs/commands.md`](../commands.md) "`:DocMap bindings`" section.

## Owning scope — a class with its methods under it

A function records what owns it: `Documentation.FunctionInfo.owner` (the
class, `impl` block, trait, receiver type or inline module it is declared in)
and `owner_kind` (which of those it is). Fourteen of the twenty backend files
set it; the rest have no such construct to read, and the three that do and
still do not are named as gaps in [`languages.md`](../languages.md).

The visible effect is in the detail pane. A Python file with three classes of
four methods used to be twelve sibling entries beside a class name that owned
nothing; it now reads `Functions (12, 3 scopes)` with each class heading its
own four. A Rust file separates `impl Widget`, `trait Doer` and
`mod inner { … }` — three groups whose names are written identically and
which are three different things.

**Why a field and not a prefix match on the name.** `Class.helper` written at
module scope and `helper` written inside `class Class` produce the identical
`name`; Lua's own `M.foo` is dotted because `M` is the module table; Ruby
writes `Class#method` and `Class.method`, PHP and Rust `::`. Grouping by
punctuation gets all three wrong, and `TESTS/scopes_spec.lua` asserts exactly
those cases.

**Derived, never serialised.** `module_map.json` carries the two fields and
nothing built from them: the grouping is `core/scopes.lua` for Lua-side
consumers and the same grouping in JavaScript on the page. A scope is not a
node — no summary, no coverage, no edges, no id.

- **Module:** `core/scopes.lua` (`M.group`, `M.split`, `M.all`, `M.summary`),
  the fourteen `core/lang/*.lua` backends that set the fields,
  `core/render/html.lua` (`groupByOwner`)
- **Config:** none — always available, and silent for a language with no
  owning construct.
- **Artifact:** `Documentation.FunctionInfo.owner`/`owner_kind`, schema 6
- **Tests:** `TESTS/scopes_spec.lua`, plus owner assertions in
  `TESTS/lang_python_spec.lua` and `TESTS/lang_rust_spec.lua`
- **Docs:** [`docs/languages.md`](../languages.md) "Owning scope" section.
