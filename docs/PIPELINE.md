# Pipeline

How `documentation.nvim` works, stage by stage, and why each stage decided
what it did. The user-facing tour is [README.md](../README.md); this is the
document to read before changing anything.

Generates a **module map** from an annotated Lua tree: scan → LuaLS enrichment
(opt-in) → check → render. Doxygen-shaped, but scoped to the part that is
actually useful for a Lua utility library — hierarchy, module purpose, links,
type relationships, and drift detection.

The generated map for this repo lives in [`docs/map/`](map/):
[`index.html`](map/index.html) (interactive — Tree, Hierarchy,
Notes, Index, History and Analysis tabs) and [`overview.md`](map/overview.md) (renders
on GitHub).

> **On the numbers quoted throughout.** This grew inside `lib.nvim` as
> `lib.nvim.docmap`, and every measurement below — "226/226 `@module`
> coverage", "997 functions", "~250 files", "highest fan-in is
> `lib.nvim.notify` (30)" — was taken against *that* tree, which is also why
> `lib.nvim.*` is the running example. They are kept as written rather than
> re-measured against this repository's own 25 files: they are the evidence
> the design decisions were actually made on, and a smaller tree would not
> reproduce them. Where a decision's *reason* is a measurement, the
> measurement matters more than which repository it came from.

## Usage

```vim
:DocMap                    " regenerate the artifacts
:DocMap check              " verify without writing; findings go to the quickfix list
:DocMap full               " regenerate WITH LuaLS enrichment (class/alias detail, type + inheritance edges)
:DocMap open               " open the generated HTML in the system browser
:DocMap graph deps         " open the HTML on the dependency graph
:DocMap graph calls lib.nvim.fs   " …or on one module's call graph
:DocMap why lib.nvim.ui.kit lib.nvim.fs   " shortest require path between two
:DocMap dot deps           " the require graph as Graphviz DOT, in a buffer
:DocMap diff HEAD~5        " what this branch changed about the tree's shape
:DocMap impact             " …and where the changed lines radiate to -> quickfix
:DocMap impact HEAD~5      " …measured against an older revision instead of HEAD
:DocMap serve              " start the local map server (enables the History tab)
:DocMap serve stop         " …and shut it down again
:DocMap dot calls lib.nvim.fs   " …scoped to one module's neighbourhood

:DocBrowse                 " navigate the same map inside the editor
:DocBrowse live            " …re-scanning on every write
:DocBrowse lib.nvim.fs     " …opened on one module
:DocBrowse history         " …opened on the commit list
```

`:DocBrowse` is the editor-side counterpart to the generated page — a
drill-down navigator over the same edges rather than a diagram, because a
terminal cannot draw one better than the browser already does. What it can do
instead is jump to the source (`gd`), fill the quickfix list (`gq`) and stay
live. See [browse/README.md](../lua/documentation/editor/browse/README.md).

`why` answers the question the Deps view can only be walked by hand to
answer. The chain goes to the **quickfix list**, not to a message, because
every hop *is* a location: the edge carries the line its `require` is written
on, so each entry jumps straight to the line that creates that link. The
summary says up front whether the path is load-time throughout or goes through
a lazy require somewhere — usually the difference between "has to go" and "is
fine".

`diff` is where the committed artifact stops being a picture and becomes a
*comparison point*: it is already in every commit, so `git show
<ref>:docs/map/module_map.json` is the whole retrieval and any two revisions
compare without generating anything. What comes out — modules and functions
added or removed, dependencies gained or lost, load-time cycles introduced,
blast radii that moved — is a review summary nobody writes by hand.

Two decisions worth knowing. Functions are split by whether the declared name
is qualified (`M.compare`, the module's surface) or bare (`node_set`, a
file-local helper); listing both equally buried the six entries that mattered
under eleven that did not, so the helpers are counted rather than listed. And
comparing against an **older schema** suppresses the dependency, cycle and
impact sections with the reason stated: schema 1 predates the require graph
entirely, so reporting every dependency in the tree as "added" would be
technically true and completely useless.

## Where a diff radiates to (`history.lua`)

`diff` answers what a revision changed about the *shape* of the tree.
[`history.lua`](../lua/documentation/core/history.lua) answers the other question a reviewer has:
these concrete lines changed — **who calls the code that changed**. Pure in
the same sense `diff.lua` is (text and IRs in, a structure out; no git, no
filesystem), so the same retrieval trick applies — every commit carries its
own artifact, so `git show <ref>:docs/map/module_map.json` needs no
generation step.

`git diff --unified=0` is what makes it tractable: with no context lines
every hunk header's ranges *are* the changed lines. The two sides index
different files — `-` numbers lines in the parent, `+` in the revision — so
they resolve against two IRs and merge, rather than misattributing every
removal in a file that shifted.

A function counts as touched when a changed line falls within
`[line, line_end]` — its body, deliberately not its doc comment: a
doc-comment edit is real but does not radiate to callers, and the drift
checks above already cover that half. `fn.line_end` was added for exactly
this and is the only new IR field the feature needed; the span was already
computed at scan time for `calls.lua`.

Two answers come out, one precise and one coarse: `calling_modules` (the
nodes holding an actual call site into a touched function) and
`impacted_modules` (the transitive `required_by` closure via
`deps.impact` — the same walk `:DocBrowse gI` uses, so the two agree by
construction).

**Degradation is explicit, because it had to be.** `line_end` only exists
in artifacts generated after it was added, so older revisions carry only
`line`. Falling back to `line` alone means "a change counts only if it lands
exactly on the `function` keyword" — measured against `1ce752e`, whose hunks
sit at lines 235-239 and 249-254 of `S.dedent`'s body, that found **zero** of
the two functions the commit demonstrably changed. So a missing `line_end` is
approximated as the next function's start minus one, which over-attributes
the gap between functions rather than under-attributing the bodies, and sets
`Impact.approximate` so a caller can say so instead of implying precision it
does not have. With that fallback the same commit correctly reports
`S.dedent` and `M.is_array`.

Three cases yield a changed file with no function attribution, all
legitimate rather than errors, collected in `unattributed` rather than
dropped: the path is not a scanned node, the IR predates function scanning,
or the lines sit outside every function (module-level code — which is why a
commit editing only the `local JS = [[…]]` block in `render/html.lua`
correctly attributes nothing).

Nothing here excludes the generated artifacts, and it should not — that is a
pathspec decision for whoever invokes git. It matters though: measured on
one commit, the full diff is 4.8 MB of which all but ~16 KB is the
regenerated `docs/map/`, so callers pass `:(exclude)<out_dir>` or they
analyse mostly generated noise.

### `:DocMap impact [ref]`

The command half: git and a quickfix list around the pure analysis above.
Semantics match `diff` — everything between `ref` and the **working tree**,
`HEAD` by default. So a bare `:DocMap impact` answers "what does my
uncommitted work affect", the pre-commit question, and on a clean tree
`impact HEAD~1` is exactly "what did the last commit affect". One rule
rather than two, and it puts the *live* IR on the `+` side, which matters:
the live IR always carries `line_end`, so the new side is always attributed
exactly and only the historical side can degrade.

The list interleaves each touched function (at its declaration) with its call
sites (at the call, indented) — the call sites being the actionable half,
"these places run the code you changed", and real locations, which is why
this is a quickfix list rather than a message. Files nothing could be
attributed to come last: they explain why the count is lower than the diff
looks, but they are not findings. When any span had to be approximated the
summary says so out loud instead of implying precision.

Building those entries lives in `history.quickfix_items`, not in
`command.lua`, for the same reason `diff.render` lives in `diff.lua`: it
keeps the command a thin git-and-UI shell and leaves the shape of the answer
testable without a repository.

The parent artifact is fetched but not required — without it the `-` side
simply contributes nothing, which is the honest result for a revision that
predates the map, so a failure there is a notice rather than an abort.

## The History tab and `:DocMap serve`

The same analysis, per commit, in the browser. It is the only tab not
computed from the embedded IR, and it *cannot* be: the numbers come from git
and from the artifact committed at each revision, neither of which is in the
page.

**Why that forces a server.** A page opened as `file://` gets an opaque
origin in Chrome and Firefox; `fetch()` refuses the `file:` scheme for CORS
requests outright, and Firefox isolates file origins additionally
(`privacy.file_unique_origin`, FF68+). `:DocMap open` opens exactly that way.
So "load it when the reader clicks" cannot mean "read a neighbouring file" —
it has to mean an origin, and that means [`serve.lua`](../lua/documentation/editor/serve.lua). This is a
deliberate break with docmap's previous "produces files, has no runtime"
self-image, taken because the alternative is not a worse version of the
feature but no feature.

What it buys is laziness. One commit costs ~0.3s (two `git show` reads of the
committed artifact plus the pure analysis, measured); precomputing this
repo's ~95 commits would cost 25-50s **and** be stale on the next commit. On
demand it is 0.3s for the commits actually opened, and never stale, because
git is asked at request time.

```
GET /                      the map itself
GET /api/commits?n=100     the commit list
GET /api/commit/<sha>      touched functions + callers + impacted modules + diff
```

**Security posture**, enforced rather than documented and hoped for:

- binds `127.0.0.1` on an OS-assigned port, never `0.0.0.0`;
- every `<sha>` is checked against `^[0-9a-f]{7,40}$` **before** it reaches
  git — a whitelist, not an escape, because the value becomes a subprocess
  argument and `--upload-pack=…` is a perfectly valid-looking path segment.
  `HEAD` is refused too: a whitelist that starts making exceptions stops
  being one;
- static serving takes a bare filename, so no request can walk out of
  `out_dir`;
- `VimLeavePre` tears the socket down, so quitting cannot leave one
  listening.

Requests are parsed in the libuv read callback but **handled** on the main
loop via `vim.schedule`: `vim.system():wait()` is `vim.wait` underneath and
cannot run in a fast-event context.

**Opened from `file://` the tab explains itself** rather than silently doing
nothing — the committed map is the common case, since that is what is in the
repo, and a dead tab there would read as a bug. Same treatment the
class-based Hierarchy views give a map generated without LuaLS. It also does
not *attempt* the fetch in that case, so the console stays clean.

Two states the UI distinguishes rather than merging, because they are
different answers: a revision that **predates the map** (nothing could be
attributed, only files are known) and one whose map **predates `line_end`**
(spans approximated, attribution over-reaches into the gaps between
functions). Module chips link into the Tree like any other cross-reference,
but only when the node still exists in the *current* map — a commit can name
something since renamed, and a link that navigates nowhere is worse than
plain text saying so.

**The editor gets the same thing without a server.** `:DocBrowse history` is
the fifth `:DocBrowse` mode and calls git directly, so none of the origin
problem above applies to it — the server exists to get the browser past a
restriction the editor never had. Both read the same
[`history.lua`](../lua/documentation/core/history.lua) analysis and show the same two caveats, so their
answers agree by construction rather than by review. See
[browse/README.md](../lua/documentation/editor/browse/README.md).

`dot` is the third renderer for the same edges, and it exists because the
other two cannot do what Graphviz does: the HTML page lays boxes out in BFS
layers and cannot route an edge around anything, and Mermaid is rendered by the
code host, which is worth a lot and costs all control over the result. It is
deliberately **not** wired to a `dot` binary — that would add an external
dependency and a "dot not found" failure mode to a feature whose whole output
is text. The buffer is something to yank, `:w`, or pipe through
`:%!dot -Tsvg`.

Its `scope` is a bounded neighbourhood, not unbounded reachability. That
sounds like the right answer and is not: measured over this tree, unbounded
scope kept 750 of 872 lines, because in a connected dependency graph almost
everything reaches almost everything. A scope that excludes nothing is not a
scope.

`graph` completes both the kind and, after it, the names the map knows — it is
the same page as `open`, opened at a state instead of at the root, since the
whole navigable state of the HTML lives in its URL fragment. Two things that
had to be right for that to work at all: the target is handed over as a
`file://` **URL**, because a fragment appended to a bare filesystem path just
becomes part of the filename and every opener then fails silently; and a name
resolves against a declared `@module`, a raw node id, *or* the module path a
**namespace**'s location implies — `lua/lib/nvim/fs` has no `init.lua` and so
declares no module, yet `lib.nvim.fs` is exactly what someone types, and
namespaces are the aggregation points a dependency graph is most useful at.

```bash
nvim --headless -l scripts/gen_map.lua               # regenerate
nvim --headless -l scripts/gen_map.lua --check       # verify: stale or drift -> exit 1
nvim --headless -l scripts/gen_map.lua --check --lenient  # fail on staleness only
nvim --headless -l scripts/gen_map.lua --full        # + LuaLS enrichment
```

The `:DocMap` command is opt-in — call `require("documentation.bindings.usrcmds").setup()`
to register it. Requiring `documentation` alone never creates a command.

## Live objects: `install()` / `uninstall()`

`generate()` and `:DocMap` are one-shot: scan, write files, done. `install()`
is the other half — a live `Documentation.Handle` another plugin's source code
reaches for directly, instead of parsing `module_map.json` off disk:

```lua
local handle = require("documentation").install({
  root = vim.fn.getcwd(),
  source = "lua/myplugin",
  watch = true,      -- rescan on BufWritePost under source/**.lua, debounced
})

handle.ir()                          -- current Documentation.IR, in memory
handle.node("lua/myplugin/init.lua") -- single node lookup

-- Graph queries, against whatever the handle currently holds — including
-- after a watch-triggered rescan, which is the reason they live on the handle
-- rather than as free functions over an IR someone captured earlier.
handle.requires("lua/myplugin/fs")   -- require edges out
handle.required_by("lua/myplugin/fs")
handle.callees("lua/myplugin/fs#M.read")   -- "<node id>#<declared name>",
handle.callers("lua/myplugin/fs#M.read")   -- the same ids the HTML map uses

local unsub = handle.on_change(function(ir, findings)
  -- runs after the initial scan and after every rescan (manual or watched)
end)

handle.uninstall()  -- or: require("documentation").uninstall(handle)
```

`uninstall()` is idempotent — tearing down twice, or a handle that was never
installed, is a no-op, not an error, matching this repo's own
`usercmd.create`'s tolerance for repeated setup under hot-reload configs.

`registry.ensure_watch(root)` starts watching a root that is already
installed, without replacing its handle. That distinction is the point:
`install()` treats a collision as replace, which drops every `on_change`
subscriber — so upgrading by re-installing would silently unsubscribe
everyone. The case that needed it: `command.setup()` installs with the plain
config, which sets no `watch`, so a `:DocMap` earlier in the session left
exactly the handle `:DocBrowse live` then reused, and "live" meant a view that
never re-scanned.

The watch itself is covered end to end in
[`TESTS/docmap_spec.lua`](../TESTS/docmap_spec.lua) — a
real `:write` through a real buffer, with `vim.wait` pumping the event loop
until the debounced rescan lands. Both directions are asserted: a write under
`source` rescans, and a write outside it does **not**. The second matters more
than it looks. Scoping this with an autocmd glob pattern is the obvious
approach and silently never fires on Windows, because Vim matches the raw
OS-native buffer path against a forward-slash pattern; the explicit
`is_subpath` check replaced it, and the test guards the opposite failure of
over-matching (verified by removing the check and watching the assertion
fail).

`:DocMap`/`docmap.command.setup()` is itself built on `install()`: it reuses
(or creates) a handle for `opts.root` rather than scanning separately, so a
plugin that calls `install()` first and later also calls `command.setup()`
gets the *same* IR both ways, and `on_change` subscribers see every `:DocMap`
run too. `opts.command_name` (default `"DocMap"`) exists so two independent
`setup()` calls — this repo's own map and a consuming plugin's — don't
register the same command name (`usercmd.create` defaults to `force = true`,
so that collision would silently overwrite one of them, not error).

## LuaLS enrichment (`opts.luals`)

Off by default — a full-repo `lua-language-server --doc` run costs several
real seconds (measured: ~4.5s over this repo's ~250 files). Merges parsed
`@class`/`@alias` definitions onto the node that owns the file, plus two kinds
of directed edge (`node.types_detail`, `ir.edges`) — see
[`luals.lua`](../lua/documentation/core/luals.lua):

- **type-reference edges** (`kind="type"`) extracted from field types — "this
  class's field points at that class", what the Hierarchy tab's dashed edges
  and the Types view draw from;
- **inheritance edges** (`kind="extends"`) from `---@class Child : Parent`,
  what the Inheritance view draws from. A class's parents also stay readable
  on `types_detail[].extends` as written, *including* parents that resolve to
  nothing in the scanned tree — those produce no edge, the same rule
  `requires_external` follows for requires that point outside the map.

Without it, the Hierarchy tab still works off plain parent/child structure,
just with no dashed edges and no Inheritance view — which is why the committed
artifact under `docs/map/` is generated **without** `--full`: CI's `--check`
compares it byte for byte and would then need `lua-language-server` installed
to reproduce it. Both class-based views say so explicitly when opened against
such an artifact instead of rendering blank.

```lua
require("documentation").generate({ ..., luals = true })
-- or: :DocMap full / nvim --headless -l scripts/gen_map.lua --full
```

If `lua-language-server` isn't on `PATH`, or the run fails, this degrades to
an `info`-severity `luals-unavailable` finding rather than failing the scan —
everything else in the IR is still valid.

## Using it for another plugin

Nothing outside [`config/`](../lua/documentation/config/init.lua) knows any one repository's layout. Another
plugin points docmap at its own tree:

```lua
require("documentation").generate({
  root = "/path/to/my-plugin",
  source = "lua/myplugin",
  lua_root = "lua",
  title = "myplugin.nvim",
  out_dir = "docs/map",
  repo_url = "https://github.com/me/my-plugin",
})
```

The only requirement on the tree is that files carry `---@module`. Everything
else — module prefix, directory layout, types directory name — is an option.

## Pipeline

| Stage | Module | Produces |
|---|---|---|
| Scan | [`scan.lua`](../lua/documentation/core/scan.lua) | `Documentation.IR` — hierarchy, summaries, links |
| Scan | [`functions.lua`](../lua/documentation/core/functions.lua) | `node.functions` — per-function docs via `vim.treesitter`, unconditional (no LuaLS needed) |
| Scan | [`symbols.lua`](../lua/documentation/core/symbols.lua) | `node.symbols` — module-scope tables, constants and bindings |
| Graph | [`deps.lua`](../lua/documentation/core/deps.lua) | `kind="require"` edges + `node.requires`/`required_by` |
| Graph | [`calls.lua`](../lua/documentation/core/calls.lua) | `kind="call"` edges — which function calls which |
| LuaLS (opt-in) | [`luals.lua`](../lua/documentation/core/luals.lua) | class/alias detail + `kind="type"` and `kind="extends"` edges merged into the IR |
| Check | [`check.lua`](../lua/documentation/core/check.lua) | `Documentation.Finding[]` — documentation drift |
| Render | [`render/`](../lua/documentation/core/render/) | HTML (Tree + Hierarchy + Notes + Index + History + Analysis tabs), Markdown, Mermaid, DOT |
| Encode | [`json.lua`](../lua/documentation/core/json.lua) | deterministic JSON |
| Diff | [`diff.lua`](../lua/documentation/core/diff.lua) | `Documentation.Diff` — what one revision changed about the shape |
| History | [`history.lua`](../lua/documentation/core/history.lua) | `Documentation.History.Impact` — which functions a diff's changed lines touch, and who calls them |
| Live | [`registry.lua`](../lua/documentation/editor/registry.lua) | `install()`/`uninstall()` — an in-memory `Handle` instead of files |
| CLI | [`cli.lua`](../lua/documentation/core/cli.lua) | `--check`/`--full` entry point, reused verbatim by `scripts/gen_map.lua` and any consuming plugin's equivalent |
| Tag files | [`tagfiles.lua`](../lua/documentation/core/tagfiles.lua) | `ir.tag_links` — `requires_external` modules resolved against another project's own committed artifact (`opts.tag_files`) |
| Coverage | [`coverage.lua`](../lua/documentation/core/coverage.lua) | `fn.tested` — auto-derived, no manual `@test` tagging required |
| Doc coverage | [`doccoverage.lua`](../lua/documentation/core/doccoverage.lua), [`render/badge.lua`](../lua/documentation/core/render/badge.lua) | documented/total function count, optional `coverage.svg` badge (`opts.badge`) |

`deps` and `calls` run inside `scan()` itself, unlike the LuaLS merge: they
need no external tool and cost only in-memory resolution over data the walk
already read, so every caller of `scan()` — checks, renderers, a live handle —
sees the same fully-formed IR rather than some seeing a half-built one.

### One edge array, four kinds

`ir.edges` carries a `kind` discriminator (`"type"`, `"extends"`, `"require"`,
`"call"`) rather than living in four parallel arrays, so layout, filtering and
drawing exist once each instead of once per relationship. Each producer sorts
its own block and appends it; there is deliberately **no** shared comparator
over the merged array, because the optional fields are disjoint per kind and
one sort would have to special-case all of them (an early version did, and
compared `from_class` against `nil` the first time a require edge appeared —
and `"extends"` would have been the next casualty, since it is the one kind
with no `via`).

`scan_full()` in [`init.lua`](../lua/documentation/init.lua) is `scan` + optional `luals` + `check`
in one call — the step `generate()` and `install()`'s rescan both build on, so
the enrichment wiring exists exactly once. The IR itself is the contract
between scan/LuaLS and render/check: renderers never touch the filesystem,
and the scanner never knows what will be drawn.

### What the scanner does *not* do

It does not parse Lua. It reads each file's leading comment block — everything
before the first non-comment line — and stops. That is reliable here because
`---@module` coverage in this tree is 226/226, and it costs ~200 lines instead
of a Lua front end.

The consequence: the scanner alone knows *that* a module exists and what it
says about itself, not what its functions are — that's [`functions.lua`](../lua/documentation/core/functions.lua)'s job.

## Function-level scanning (`node.functions`)

Unlike the header scanner, this one *does* need to find code, not just a
leading comment block — but it still isn't `lua-language-server --doc`.
Verified against real `doc.json` output: `--doc` only surfaces symbols
reachable through a `@class`/`@alias` type graph, so an ordinary
`function M.foo(...)` in a module with no aggregate class declaration for its
exports simply never appears. Retrofitting every module with a redundant
aggregate class (duplicating what `---@param`/`---@return` already say above
each function) would have been a drift risk, not a shortcut.

So [`functions.lua`](../lua/documentation/core/functions.lua) uses `vim.treesitter` instead — already a
lib.nvim dependency (`lib.nvim.treesitter`), no new one added. A query finds
the three function shapes this repo actually uses (`function M.foo(...)`,
`local function foo(...)`, `M.foo = function(...)`), matched via
`iter_matches` rather than `iter_captures` (the two shapes put `@fname`
before or after `@fdef` in source order depending on which matched — only
match-grouped iteration handles both correctly). Only functions declared
directly in a file's top-level scope are scanned; a `local function` nested
inside another function's body is an implementation detail, not part of the
module's documented surface, and is walked past.

Each function's doc-comment block (the contiguous `---` lines immediately
above it, tracked by row-contiguity, not indentation guessing) is parsed for:

- the already-common tags: `@param`, `@return`, `@generic`
- previously-unused-in-this-repo LuaLS tags now given real value:
  `@deprecated` (rendered as a banner), `@see` (rendered as a link, validated
  by the `dead-see-target` check below), `@async`, `@nodiscard`, `@overload`
- two tags outside the LuaCATS spec: `@example` (a fenced code block,
  multi-line) and `@since` (deliberately not `@version`, which LuaLS defines
  as a required-Lua-runtime declaration — a different question from "since
  when has this existed in this project")
- `@internal`, which marks a function as implementation rather than published
  surface

`@internal` earns its place by sharpening every question of the form "is this
used". `undocumented-param` skips it, because an internal function's
documentation bar is the author's own and nagging is how a heuristic check
earns a spot on someone's ignore list; the structural diff counts it as a
helper rather than listing it as an API change; and the map badges it. Without
the tag those all have to guess from the *shape* of the declared name —
`M.compare` looks public, `node_set` looks private — which is a decent guess
and only a guess.

See [`docs/ANNOTATIONS.md`](ANNOTATIONS.md) for the full survey of which
tags this repo already uses heavily, which real ones it doesn't (and why
they'd be worth adopting), and where the two custom tags fit in.

Two new generic checks build on this: `dead-see-target` (warn — an `@see`
target that resolves to nothing, same idea as `dead-readme-link`) and
`undocumented-param` (info — a text-based heuristic comparing the raw
signature's parameter count to the number of `@param` lines; deliberately
`info`-only since the heuristic can be wrong on complex signatures).

## What a module *is*, not just what it exports

Two things the detail pane could not answer before, both filled during the
same scan and the same parse:

**Module-scope tables, constants and bindings** ([`symbols.lua`](../lua/documentation/core/symbols.lua)).
`functions.lua` answers "what can I call"; this answers the rest of "what is in
here" — the lookup tables a module dispatches through, the constants that
encode its thresholds, the singletons it holds at load time. Reading a module's
source those are usually the first thing you look for, and no generated
documentation showed them.

Top level only, anchored on `(chunk …)` in the query rather than by walking
ancestors: a `local seen = {}` inside a function body is an implementation
detail, exactly as a nested `local function` is. Two shapes are deliberately
*not* reported, because another stage already owns them and reporting them
twice would be two places to keep in sync:

| Not reported | Owned by |
|---|---|
| `local fs = require("…")` | `deps.lua` — it is a dependency, and the alias is what makes call resolution work |
| `M.foo = function(…)` | `functions.lua` — it is a function |

A third exclusion is the module's own export table. It is not state a reader
wants listed — it *is* the module, already represented by the node and by
`node.export` — and it appears in essentially every file: measured over
lib.nvim, 188 of 600 entries, 159 of them literally named `M`. It is
identified by the chunk's `return`, covering both `return M` and
`return setmetatable(M, {…})`, rather than by "empty table", which would have
been wrong in the other direction: `local cache = {}` is real module state
that happens to start empty.

**Subtree stats** (`node.stats`). Modules, namespaces, `.lua`/`.md`/other
files, lines of Lua, functions, symbols and types, aggregated over the node
*and everything below it* — the question a directory answers is "how big is
this part of the tree". The roll-up walks `ir.order` backwards, which is a
valid post-order because `scan` appends a node before descending into it, so
every child sits after its parent.

Line counting happens in `functions.scan_file`, the one place the whole file is
already in memory; only `@types/` members — which carry no functions and so
never go through it — get their own cheap read. `stats.types` is the exception
that `scan` cannot fill, since the class/alias count only exists once LuaLS
enrichment ran, so `luals.merge` fills and rolls it up the same way.

## Call-graph scanning (`kind="call"` edges)

[`calls.lua`](../lua/documentation/core/calls.lua) reuses the tree [`functions.lua`](../lua/documentation/core/functions.lua)
already parsed — extraction and resolution are split, because resolution is
not a per-file question. `fs.read()` only means something once you know this
file bound `fs` to `lib.nvim.fs` and that some node declares that module,
which is why require-alias collection in [`deps.lua`](../lua/documentation/core/deps.lua) is a
prerequisite rather than a coincidence.

Four shapes resolve **exactly**, each a syntactic fact rather than a guess:

| Written | Resolved because |
|---|---|
| `fs.read(x)` | `fs` is bound by `local fs = require("lib.nvim.fs")` |
| `require("lib.nvim.fs").read(x)` | the module path is in the call itself |
| `M.helper(x)` | `M` is a prefix this file's own functions are declared on |
| `helper(x)` | a bare name matching a file-local `local function` |

The inline-require form is checked before the alias form, because its callee
text starts with the identifier `require`, which the alias branch would
otherwise try to look up as a local binding. It is worth its own branch rather
than being written off as rare: it is how this tree calls a lazily-required
dependency without a top-level binding, and supporting it added 25 real edges.

Everything else is dropped: `obj:method()` on an unknown receiver,
`vim.fs.dirname()` (outside the tree), `M[name]()` (not a name at all).
`opts.calls_heuristic` adds one guessed shape back — an unresolved bare name
matching exactly one function in the whole tree — marked
`confidence = "heuristic"` and drawn dashed. Off by default: a call graph that
confidently draws a wrong edge is worse than one that draws fewer.

Genuinely invisible to this is dynamic dispatch. `lib.nvim.require`'s lazy and
metatable strategies produce calls that appear nowhere in the source, and a
callback handed to `vim.schedule` or stored in a table is a call whose target
is a value, not a name. Doxygen has the same blind spot in C++ for the same
reason — which is why **no call-derived check is ever `error` severity**, and
why the Calls view's empty state says so rather than implying the function
calls nothing.

On reusing `lib.nvim.logger`'s pattern: it was considered and rejected as
direct code reuse — `logger.record` is built for runtime events (timestamps,
levels, redaction, ring-buffer flush-on-crash), while this scans static
source once. What *is* transferable is the shape of the idea: structured,
tagged records plus a dedicated inspection command (`:LibLogger show` as a
model for a possible future `:DocMap functions <module>`). Not built here —
the HTML detail pane's Functions section covers the immediate need — but
worth keeping in mind if a CLI-side query ever becomes worth adding.

## Structure of the map

| Node kind | What it is |
|---|---|
| `module` | A directory containing `init.lua` |
| `namespace` | A directory without `init.lua`, grouping others |
| `file` | A non-`init.lua` Lua file |

Helper files stay visible as leaves rather than being folded into their
parent — `find_upward_dir/matcher.lua` is real, documented, and worth finding.
A `@types/` directory is an **attribute** of its module, not a sibling node:
types belong to the thing they type, and promoting them doubles the tree for
no navigational gain.

## Hierarchy tab

A second view in the generated HTML, alongside the Tree/detail pane: `<div>`
node boxes laid out in layers by depth from a centered node, with an SVG
overlay drawing solid parent/child connectors and (once `opts.luals` ran)
dashed type-reference connectors. Center on any module or namespace via its
detail-pane "Hierarchy ↳" link, or double-click a box to re-center on a
smaller subtree — capped at 90 nodes per view (`MAX_HNODES` in
[`render/html.lua`](../lua/documentation/core/render/html.lua)), since a box-and-connector diagram of
the whole ~250-node tree at once is not something either box-and-connector
diagrams or the people reading them handle well.

Box positions are computed analytically from the IR (layer index × row
position), not measured off the DOM — deliberately, so the diagram renders
correctly whether or not the pane is currently visible, with no
measure-after-show step to get right. The view auto-scrolls to center the
node it was centered on, since a shallow layer (the root has one box) sharing
a horizontal axis with a much wider deeper layer means the centered node can
sit thousands of pixels from the left edge on a large map.

### The five views

Toggled from the Hierarchy toolbar. Three of them are undirected structure, two
are directed graphs with a direction control of their own:

| View | Boxes are | Edges are | Doxygen equivalent |
|---|---|---|---|
| **Modules** | IR nodes | `children`, plus type edges dashed on top | Directory / class hierarchy |
| **Types** | `@class`/`@alias` definitions | `kind="type"` | Collaboration diagram |
| **Inheritance** | `@class` definitions that have a parent or a subclass | `kind="extends"` | Class hierarchy / inheritance diagram |
| **Deps** | IR nodes | `kind="require"` | Include dependency graph |
| **Calls** | individual **functions** | `kind="call"` | Caller / callee graph |

**Inheritance** is the one view that does *not* layer by distance from the
centered object, and cannot: a module normally declares a base class and its
subclasses side by side, so all of them seed the walk at once and a
distance-from-seed layout collapses the whole hierarchy onto one row (observed
on `Lib.Cache.Opts` sitting beside its own `LoadOpts`/`SaveOpts`). Depth comes
from the relation instead — longest path from a class with no parent, so a
class always renders strictly below *every* parent, including in a diamond
where one path is shorter than the other. Both directions are always shown;
unlike Deps and Calls there is no reason to want one side alone, so it costs no
state axis. Classes with no inheritance at all are left out rather than drawn as
isolated boxes in a view that exists to show relationships.

Direction (`← In` / `⇄ Both` / `Out →`) is an axis of the state, not two more
views: "callers of X" and "callees of X" are the same diagram walked the other
way, and splitting them would have doubled the view list with buttons saying
nearly the same thing. `Both` runs the two walks *independently* from the same
seeds — once a walk has gone up into callers, continuing downwards through
those callers' other callees would fill the diagram with functions unrelated
to the center. Doxygen makes the same choice.

Depth defaults to 2. A require graph's neighbourhood grows far faster than a
tree's, and `MAX_HNODES` alone would fill every diagram to the cap.

**`+ external`** (Deps only) also draws the requires that resolve to nothing in
the scanned tree — other plugins, or anything outside `source`. They live in
the IR as plain module strings on `node.requires_external`, never as invented
nodes: the map only claims to describe what it scanned, and a box with no
source, no summary and no functions behind it would break that. One box per
module however many nodes reach for it, since "these four all pull in plenary"
is the thing worth seeing. The boxes are inert by default — no navigation, no
context menu, because there is nothing to navigate to — unless `opts.tag_files`
resolves one; see "Cross-project links" below.

A prerequisite fell out of building it: `require("lib.lua." .. key)`, which is
how this tree's aggregators dispatch, puts a string literal exactly where the
extraction pattern looks and yields the dangling prefix `lib.lua.`. That
resolved to nothing and so cost nothing while unresolved requires were
discarded — and would have become four confident boxes for modules that do not
exist the moment they became visible. A module path has no empty segment, which
is what a leading, trailing or doubled dot means, so those are now rejected at
extraction. Verified: the resolved edge set is unchanged by the fix.

**Backedges.** The tree views never had them; a require or call graph is
cyclic, so a target keeps its first-seen BFS depth and later edges into it
point sideways or up. Drawn with the ordinary S-curve those run straight
through every box in between, so an edge whose target is not strictly below
its source is routed out of the box's side and back in — and every directed
view gets arrowheads, without which a same-layer edge says nothing about which
way it points.

### Functions are addressable

A function's id is `"<node id>#<declared name>"` — derived from data already in
the IR, so nothing extra is generated or serialized, and stable across
regenerations as long as the name is. That id is what the URL can point at,
what the Calls view centers on, and what the context menu acts on. Before it, a
function existed only as a block of text inside one node's detail pane.

They also appear in the Tree tab, behind a per-node collapsed `ƒ N functions`
group rather than mixed into `children`: `children` is IR structure and
functions are not part of it, and this tree renders eagerly — folding ~1500
function rows into the always-expanded default would bury the module structure
the tree exists to show.

### Right-click

Every clickable object — a tree row, a function row, a graph box, a type or
function entry in the detail pane — resolves through one `describeTarget()`
into `{kind, nodeId, fnKey, className, label}`, and the menu is built from
that. One resolver instead of four menus is what keeps "right-click anything,
get the same verbs" true as views are added.

Entries that lead nowhere are **disabled with their count shown**, not hidden:
an enabled item that opens an empty diagram teaches people to distrust the
menu. `preventDefault` fires only when the target actually resolves, so
selecting a paragraph of prose and reaching for the browser's own Copy still
works.

### Hide/dim

"Dim this box" / "Show this box" in the context menu — reachable only from an
actual Hierarchy box (`describeTarget`'s `hkey` field, set in that one
branch), never from a tree row or a detail-pane reference, since neither has
a box on screen to dim. A "Hidden (N) — show all" pill next to the toolbar's
zoom controls (hidden itself when nothing is dimmed) clears all of them in
one click, mirroring `#markbar`'s own role for Compare marks.

**Dims, never removes.** A dimmed box keeps its computed position and stays
in `hboxes`/`positions` — `opacity: .08` plus `pointer-events: none`, the
same mechanism hover-focus already uses (`#hgraph.focusing .hnode{opacity:
.22}`), just persistent and per-box instead of transient and neighbour-based.
Actually removing a node from the layout was considered and rejected: a
Modules-view box has children whose position depends on it being there, and
removing it mid-tree would mean either reparenting them or leaving a gap —
real work with real edge cases (what happens to a hidden namespace's own
children?) that the "make a large tree less noisy" goal does not need.
Structural removal is a **separate, larger** idea, tracked on its own as the
roadmap's "Hierarchie: Root-Level aus-/einblenden mit Zoom-Slider" item —
re-rooting the whole diagram, not toggling one box.

State (`state.hidden`, an array of the same keys `hboxes`/`boxSpec` already
use — a node id, a class name, or an `fnKey`) is a second, independent
instance of the same pattern Compare marks established: hash-serialized
*inside* the Hierarchy branch of `serializeState` (unlike `marks`, which is
global — a dimmed box only exists in this tab, so a Tree-tab link carrying
`hidden=` would name a control that link's view does not have), mirrored into
its own `localStorage` key (`docmap:hidden:<pathname>`), and on load a hash
that names a `hidden` set wins outright over whatever was stored — the same
"an explicit link is a statement, not a suggestion to union with" rule
`marks` already follows.

### Movement

Boxes are held in a keyed map and **reused across redraws**, so a box present
before and after a re-center is the same element at a new `left`/`top` and the
CSS transition animates it there. The previous `hgraph.innerHTML = ""` threw
that identity away every time, which is why every navigation was a hard cut
even when the two layouts shared most of their boxes.

Positions are still computed analytically from the IR, never measured off the
DOM — that is what lets the diagram be correct while the pane is `display:none`
— and animating did not change it: the movement is interpolation *between* two
deterministic layouts, not a simulation. No force-directed layout, no physics.

Edges are the exception: `d` is not an animatable CSS property, and a per-frame
path interpolator for up to 90 edges buys very little over simply not drawing
lines that would point at boxes still in motion. They are hidden while the
boxes move and faded in once they arrive.

Hovering a box dims everything that is not a direct neighbour — pure class
toggling, no relayout, and on a dense require graph the difference between a
readable diagram and a spider's web. Every transition is disabled under
`prefers-reduced-motion: reduce`.

### Zoom

Two mechanisms that are kept apart in the code, because conflating them makes
both half-work:

- **Geometric** — the same diagram, larger. A CSS transform on `#hstage`. No
  relayout, no redraw, and deliberately **not** in the URL: it is comfort, not
  state.
- **Semantic** — past a threshold, a *different excerpt*: one level down into
  the module under the cursor, or one level up. That is the
  `navigate({center})` a double-click already does.

The geometric zoom is the feel between two levels; the semantic one is the
jump. Only the jump touches history — the same rule the search preview had to
learn, for the same reason.

Positions stay analytic. The transform sits on a layer *above* the computed
pixel coordinates, so `positions`, `reconcile()` and the SVG paths never learn
that a zoom exists. `#hgraph` is sized to the *scaled* extent, because a
transform leaves layout size alone and the scroll area would otherwise not
grow on zoom-in, putting half the diagram out of reach.

| Gesture | Effect |
|---|---|
| wheel | scale, anchored on the cursor |
| shift+wheel | pan horizontally |
| `+` / `-` / `0` | zoom in / out / reset |

**Thresholds fire on *crossing*, not on being past.** That distinction is the
whole design, and getting it wrong was a real bug: a zoom that came to rest
above `DRILL_IN` drilled *in* on the next notch even when that notch was a
zoom-*out*. Crossing semantics also mean a refused jump can leave the zoom
above the line without re-firing on every further notch — which is what makes
"zoom further in to read a leaf box" work.

Asymmetric thresholds plus a cooldown, or it flaps: committing at 1.80 and
resetting to exactly 1.80 would re-trigger on the smallest wobble, so a
successful jump lands at 0.90 (in) or 1.15 (out), well inside the band, and a
jump blocked by the cooldown pulls the zoom back just inside the threshold so
the next notch can cross again rather than having to be wound all the way
back.

A jump that cannot happen — a leaf with no children, the root on the way out,
an external box, or the box that is *already* the center — pulses the box
instead of silently doing nothing, which reads as a bug.

In **Deps and Calls** the threshold binds to `depth ± 1` instead. "One level
deeper" is not defined in a require graph, which is not a containment
hierarchy; depth is the axis that means "show more" there, and it already
exists as state and as a control.

Below ~0.65 scale the secondary line in each box is unreadable grey noise, so
`#hstage.lod-min` hides it — pure CSS, no redraw, and the second sense in
which this zoom is semantic.

### SVG export

`↓ SVG` writes the current diagram as a standalone file. The boxes are redrawn
as plain `<rect>`/`<text>` rather than wrapped in `<foreignObject>`, which
Inkscape and most converters do not render, and colours are read back off the
live DOM so the export matches the theme it was taken from.

### Cross-project links (`opts.tag_files`)

Doxygen's `TAGFILES` equivalent: since `docmap.cli`/the pre-commit hook
template made docmap trivially reusable (see "Reusing docmap in another
plugin" below), a tree of several small plugins all depending on `lib.nvim`
and each generating its own map is the normal case, not a hypothetical one.
Every one of those maps drew `lib.nvim.fs`, `lib.nvim.ui.kit`, etc. as a
nameless, inert grey box in the Deps view's `+ external` toggle — a require
that resolves to nothing *in that scan*, even though it resolves perfectly
well inside `lib.nvim`'s own committed map.

```lua
require("documentation").generate({
  ...,
  tag_files = { ["lib.nvim"] = "/path/to/lib.nvim/docs/map" },
})
```

Every `requires_external` module matching the prefix (`lib.nvim.fs`, not
`lib.nvimx` — the same whole-segment matching `Documentation.LayerRule` uses) is
looked up in that directory's `module_map.json`. What resolves gets a solid,
accent-coloured box instead of the usual dashed muted one, and clicking it
opens the other project's `index.html` at that node, in a new tab. What
doesn't match any prefix, or doesn't resolve to a real node once the other
artifact is loaded, is left exactly as before — silently inert, never an
error.

Local paths only, deliberately: the tag file is read synchronously during
`scan_full()`, the same way `opts.root` itself is — a network fetch here
would turn a deterministic `--check` into one that depends on network
availability and timing, the same reasoning that keeps `dot` unwired to a
`dot` binary. Point it at a sibling checkout's `docs/map/` directory, the
same one `--check` already compares its own artifacts against.

### Auto-derived test coverage (`fn.tested`)

`@test` already existed as a manual tag (see
[`docs/ANNOTATIONS.md`](ANNOTATIONS.md)) and has exactly zero real hits
in this tree — a doc-comment that duplicates what the actual spec file
already says is a second source of truth, and second sources of truth
drift. [`coverage.lua`](../lua/documentation/core/coverage.lua) measures instead: every function's
bare name is checked against every identifier mentioned anywhere under
`opts.tests_dir` (default `TESTS`), the same technique
[`calls.lua`](../lua/documentation/core/calls.lua)'s `identifier_counts` uses for "used as a value",
pointed at the test tree instead of the source tree.

Coarse in the safe direction: `M.read` and an unrelated local `read` both
count, so `fn.tested` can be `true` on a name collision it did not earn —
the same trade `local_refs` already makes. The real blind spot runs the
other way: a function exercised only *indirectly* (called by another
function a spec does name) never lights up, so `tested = false` means "not
found by name in a spec", not "definitely untested". That asymmetry is why
the renderer only ever shows a `tested` badge (Index tab, function detail
pane) for the `true` case — a badge on most of the tree's ~600 functions
would be noise dressed up as a warning, not information.

`docmap.coverage.summary(ir)` returns `tested, total`; `:DocMap`/
`nvim --headless -l scripts/gen_map.lua` print it as one line after
regenerating (`390/997 functions found by name in TESTS (39%)`, this
repo's own current number). The natural home for this as a browsable, not
just a printed, number is the planned "Analysis" tab — see the roadmap.

### Documentation coverage (`opts.badge`, R4)

[`doccoverage.lua`](../lua/documentation/core/doccoverage.lua) turns three scattered per-function
findings — `missing-summary`, `undocumented-param`, `param-name-mismatch` —
into one number: a function counts as documented when it has a non-empty
summary *and* its parameters are fully and correctly named, reusing exactly
the same logic those findings already run rather than a second
implementation that could quietly disagree. `@return` is deliberately not
part of the definition — a function's raw signature carries no count of what
it returns the way it does for parameters, so there is no structural fact to
check against, only "did the author write a line", which the findings above
already cover badly enough without a coverage number pretending to be more
precise than that. `@internal` functions are excluded, same as all three
findings this builds on.

```lua
local documented, total = require("documentation.core.doccoverage").summary(ir)
```

`opts.badge = true` additionally writes `coverage.svg` — a hand-rolled,
shields.io-shaped badge (see [`render/badge.lua`](../lua/documentation/core/render/badge.lua)), not one
fetched from shields.io itself: a network call during `scan_full()` would
make `--check` depend on availability and timing the same way a `dot`-binary
call would, which is exactly why `render/dot.lua` is a text export instead.
Off by default — most consumers of `generate()` do not want an extra
committed file they never asked for; `:DocMap`/`gen_map.lua` print the same
number as a plain line regardless
(`666/997 published functions fully documented (67%)`, this repo's own
current number, without `opts.badge` set).

### Modules vs Types

Two "aufbereitungen" (renderings) of the same annotation data, toggled via
buttons in the Hierarchy toolbar:

- **Modules** — the directory/module hierarchy above: boxes are IR nodes,
  solid edges are `children`, dashed edges are `ir.edges` filtered to the
  laid-out subtree.
- **Types** — a materially different graph, not a relabeling: boxes are
  individual `@class`/`@alias` definitions from `node.types_detail`, and
  edges are walked directly from `ir.edges`' `from_class`/`to_class` (which
  can cross node boundaries freely — a field can reference a class owned by
  any module in the map, and that's the point of this view). Requires
  `opts.luals` to have run; shows a message pointing at `:DocMap full`
  otherwise, or if the centered node has no types of its own.

### Search re-centers, not just filters

The same `#q` input that filters Tree rows re-centers the Hierarchy view on
the best-matching module while typing, when the Hierarchy tab is active.
Matching prefers an exact name/module match, then a name/module prefix, then
a substring anywhere (including the summary).

Typing updates the diagram live but does **not** touch browser history — see
[Back/Forward](#backforward-navigation) for why that matters here
specifically, not just as a nicety. Press Enter to commit the current match
as a real, navigable stop.

### Clickable findings

Each row in the "Drift findings" table that names a real IR node (most of
them — a couple of repo-specific checks report against synthetic paths that
were never scanned nodes, and those rows just stay inert) is clickable:
selects that node in the Tree tab.

### Back/forward navigation

Every discrete action (selecting a tree node, switching tabs, centering the
Hierarchy view, toggling Modules/Types) pushes a real `history` entry, so the
browser's own Back/Forward buttons step through the app's actual states —
not just react to a directly-edited URL hash, which is all the original
single-node `#<id>` scheme supported.

The state serialized into the hash is `{tab, id, center, view, dir, depth, fn}`
— every axis goes through `navigate()`, including the direction and depth
controls; a control that set one behind its back would produce a diagram the
Back button cannot return from. Only the axes the current view actually uses
are serialized, so a Tree-tab link is not three pieces of noise long. See
`serializeState`/`parseState`/`applyState`/`navigate` in
[`render/html.lua`](../lua/documentation/core/render/html.lua). One non-obvious rule worth knowing if
you touch this: **live-preview updates (the Hierarchy search box while
typing) must never call `history.replaceState`.** An earlier version did,
and it silently broke Back — `replaceState` overwrites whatever entry is
currently on top of the stack, which right after switching to the Hierarchy
tab is the tab-switch entry itself. The first keystroke clobbered it, so
committing the search with Enter ended up pushing a *duplicate* of the
already-overwritten entry instead of a distinct new stop, and Back from the
committed search landed on an indistinguishable copy of itself instead of
the pre-search tab state. Live preview now calls `drawHierarchy()` directly,
bypassing history entirely; only Enter (or any other discrete action) calls
`navigate()`.

## Notes tab

Doxygen's Deprecated / Todo / Bug / Test lists, as a third tab. Four
aggregates over data the scan already has: `@deprecated` (a single string, the
migration hint) plus the three repeatable note tags `@todo`/`@bug`/`@test`
(one list entry per occurrence — see
[`docs/ANNOTATIONS.md`](ANNOTATIONS.md)). Entries sort by module, then by
line, and clicking one jumps to that module in the Tree tab.

One tab rather than Doxygen's four pages: in a given tree three of these tags
are usually unused, and four tabs that are empty most of the time are four
tabs of noise. Empty sections say so explicitly instead of disappearing, so
"nothing here is deprecated" stays distinguishable from "this build did not
collect it" — the same reason the class-based Hierarchy views explain
themselves rather than rendering blank.

Deliberately **not** modelled as `check` findings. None of these is drift or
an error, and routing them through findings would fold an author's own to-do
list into the exit code CI fails on.

## Index tab

Doxygen's "File Members": every documented function in the tree, A–Z, with a
letter jump bar — 997 of them for lib.nvim. Clicking one opens its module in
the Tree tab; `@internal`, `@deprecated` and (R2) `tested` entries are tagged
inline.

Sorted on the **bare** name, so `M.read` files under **R**. The `M.` is this
repo's local-table convention rather than part of what the function is called,
and filing most functions under a single "M" would be an index in name only.
`calls.lua` needed the same reduction for call resolution; its `bare()` is the
model. A name that starts with something non-alphabetic (`_evict`) collects
under `#` rather than being dropped.

It earns a tab next to the Tree's filter and the picker's fuzzy match because
neither of those gives you the flat alphabet — which is the one way to find a
function whose module you do not already know.

### Functions / Modules toggle (R3)

The same flat-alphabet idea, one level up — a **Functions / Modules** toggle
(`state.iview`, mirroring the Hierarchy tab's view buttons) switches between
the function index above and a second one over every `module`/`namespace`
node, deliberately excluding `file` nodes: a file is reached through its
module in the Tree tab already, and this index exists for "I know the name,
not where it lives", which a leaf file rarely is. Doxygen keeps a separate
File Index and Class Index for the same reason — two different "I know the
name" questions, not one.

Sorted the same way as the function index — bare last segment of the module
path (`lib.nvim.fs` files under **F**) — for the same reason: `calls.lua`'s
`bare()` reduction is the model both indexes share. Each entry shows its kind
(`module`/`namespace`) and function count, and clicking one opens it in the
Tree tab, same as the function index.

Both halves of the toggle render lazily and cache their HTML in module scope
(`indexFnHTML`/`indexModHTML`) rather than recomputing on every switch — the
IR is static for the page's lifetime, so there is nothing to invalidate.
`iview=modules` is the only URL state this tab carries (omitted when it is
the default), the same "only the axes a view actually uses" rule
`serializeState` already applies to Hierarchy's `dir`/`depth`/`ext`.

## Analysis tab

A tool palette, not a diagram — a fifth tab (`atool` state axis, same
`iview=`-shaped URL rule as the Index tab) whose toolbar switches between
panels the way Hierarchy's view buttons switch between graphs, applied to
aggregate numbers instead of boxes. Six tools today:

- **Test coverage** — `fn.tested` (R2, [`coverage.lua`](../lua/documentation/core/coverage.lua))
- **Documentation** — `fn.documented` (R4, [`doccoverage.lua`](../lua/documentation/core/doccoverage.lua))
- **Dependencies** — `n.requires`/`n.required_by` (R6, fan-in/fan-out)
- **Complexity** — `fn.complexity` (cyclomatic/McCabe, [`functions.lua`](../lua/documentation/core/functions.lua))
- **Duplicates** — `ir.duplicates` (structural copy-paste detection, [`duplicates.lua`](../lua/documentation/core/duplicates.lua))
- **Plugins** — `n.plugins` (lazy.nvim spec inventory, [`plugins.lua`](../lua/documentation/core/plugins.lua))
- **Tools** — `ir.tools` (this repo's own `lib.nvim.deps` manifest, [`tools.lua`](../lua/documentation/core/tools.lua))

The first two are per-module breakdowns over data `scan_full()` already
stamped into the IR: a table, one row per module/namespace/file that owns
at least one function, hit/total/percentage/bar. Sorted **worst-first** —
lowest percentage at the top, ties broken by functions-affected (a 0%
module with 20 functions needs attention before one with 1) — because a
panel meant to answer "where should I look" should not bury that answer
alphabetically the way the Index tab correctly does for "I know the name."
Clicking a row opens that module in the Tree tab, same as every other
cross-reference in the page.

Deliberately reads `fn.tested`/`fn.documented` rather than recomputing
either in JS: `doccoverage.is_documented`'s parameter-name comparison in
particular has real logic (the colon-method `self` exception) that must
never exist in two places that could quietly drift apart. The Documentation
panel excludes `@internal` functions from its totals — matching
`doccoverage.summary`'s own definition exactly, so the panel's percentage
can never disagree with the number `:DocMap`/the CLI prints for the same
tree; the Test-coverage panel does not, since `coverage.resolve` stamps
`fn.tested` on every function regardless of `@internal`.

**Dependencies** (R6) is shaped differently on purpose: it counts edges over
the node itself, not a boolean over its functions, so it reads straight off
`n.requires.length`/`n.required_by.length` — both already sorted,
deduplicated indexes into `ir.edges`'s require edges — rather than reusing
the function-counting panel's `pick` callback bent into a shape it wasn't
built for. Sorted by **fan-in descending**: the module the most other
modules depend on is the one whose blast radius matters most if it changes,
the same "most consequential first" rule the coverage panels' pct sort
already follows. Fan-out is the tiebreak, not an equal-weight second key —
a module nothing depends on but that itself pulls in a lot is a different
smell (a "God module" candidate), worth seeing but not at the cost of
burying real fan-in leaders. Verified against this repo's own tree: highest
fan-in is `lib.nvim.notify` (30), exactly the kind of foundational module
this ranking exists to surface.

**Complexity** ranks *functions*, not modules — the one panel that is a
per-function list rather than a per-module breakdown, because "longest/most
tangled function" is a property of one function, and averaging it into a
per-module score would bury the one function that actually needs attention
under a healthy module's mean. Reads `fn.complexity` — cyclomatic
complexity (McCabe): one point per `if`/`elseif`/`while`/`for`/`repeat`/
`and`/`or`, plus a base of 1, computed by
[`functions.lua`](../lua/documentation/core/functions.lua)'s `cyclomatic_complexity` over each
function's own subtree (including nested anonymous closures — a callback's
branches are still branches the function's reader has to follow, and
docmap never scans the closure as its own unit). Unlike `tested`/
`documented`, this is computed unconditionally during the same scan pass
that already has the treesitter node in hand — there is no later
IR-only "resolve" step that could derive it afterwards. Verified against
this repo's own tree: the highest-ranked function is `docmap.command`'s
`M.setup` (complexity 104) — the `:DocMap` subcommand dispatcher, exactly
the shape of function this ranking exists to surface.

**Duplicates** is the copy-paste detector, and it exists because this is the
one shape of drift the rest of the plugin is structurally blind to. Two
modules that each grew their own `read(path)` fail no check, fail no test,
and produce nothing in any graph — the require graph is silent precisely
because neither one requires the other.

The comparison is on `fn.shape`, a hash of the treesitter node *types* over
a function's whole subtree, never their text, computed in
[`functions.lua`](../lua/documentation/core/functions.lua) during the scan for the
same reason `complexity` is: only there does the parse tree exist. Ignoring
identifier and literal names is the entire point — a copy-paste gets renamed
on the way in, so a detector that only found byte-identical bodies would find
the one case nobody ships. This is the "type-2 clone" of the copy-paste
literature, and what PMD's CPD reports by default.

Two limits, both stated rather than worked around:

- **A single edited line breaks the match.** This finds copies, not
  near-copies. Real clone detectors slide a window over a token stream to
  find the longest common run — a genuinely more expensive algorithm, and
  exact-shape matching is what earns its cost first. If this panel is
  consistently empty on a tree that obviously has duplication, *that* is the
  argument for the window.
- **Sharing a shape is not by itself a defect.** Verified on this repo's own
  tree, which reports exactly two groups: `read(path)` implemented
  identically in three modules — a real duplicate, and one the plugin had no
  way to see before — and `scan.lua`'s `is_dir`/`is_file`, which share a
  shape and share nothing else. That second one is why this is a panel and
  never a check: `--check` must not fail on it.

A **size floor** (40 syntax nodes) keeps it readable. Below it a shared shape
means nothing — every tree has a dozen one-line accessors that match each
other — and measured here, no floor reports five groups where 40 reports the
two that are worth reading. It is a constant rather than an option, because a
knob nobody knows how to set is worse than a documented default. The result
carries `considered` alongside `groups`, so "nothing found" stays
distinguishable from "nothing was large enough to look at".

`ir.duplicates` is serialised into the artifact even though it is derived,
which the fan-in/fan-out panel is not: that one aggregates data already in
the JSON, while this grouping needs `fn.shape`, and a page reading the
artifact has no parse tree to redo it with. Cost is measured: the two new
per-function fields plus the result grew this repo's `module_map.json` from
256 KB to 273 KB.

The remaining roadmap candidate, **churn hotspots**, is not a panel here and
cannot become one. It needs `git log`, and git data cannot go into the
committed artifact for exactly the reason the History tab is not a tab:
`--check` byte-compares committed output against freshly-generated output, so
embedding history produces a commit that invalidates its own artifact the
moment it lands. There is no fixed point. The roadmap listed the two
candidates side by side as if they were the same kind of work; only one of
them was ever buildable here. It ships as **`:DocMap churn`** instead —
live-computed into the quickfix list, nothing written, the shape `:DocMap
impact` already had. See [`churn.lua`](../lua/documentation/core/churn.lua) for the
scoring and for the one property worth knowing: `commits × complexity` is a
scalarization, so a large enough value on one axis outranks a moderate value
on both. Tornhill's own presentation is a scatter plot whose answer is the
top-right quadrant and which has no such failure mode — but that is not a
ranking, and a quickfix list is. Both columns ship on every row, so when the
order looks wrong the numbers beside it say why.

**Plugins** exists for a tree this map was blind to before it: a Neovim
*config* (as opposed to a Neovim *plugin*), where `lua/plugins/*.lua` is
mostly `return { { "author/repo", event = "…" }, … }` — no functions, no
symbols, nothing any other panel has anything to say about. Extracted in
[`plugins.lua`](../lua/documentation/core/plugins.lua), during the same scan
pass as `functions`/`symbols`, off the parse tree that already exists.
Scoped to **lazy.nvim's spec shape** specifically and named as such —
packer.nvim and vim-plug specs look different and would need their own
extractor, not a bent version of this one.

Verified against a real, ~450-file Neovim config rather than only synthetic
fixtures, which found two precision bugs neither invented test case would
have:

- **A single spec returned directly is not an array whose fields are each
  their own entry.** `return { {...}, {...} }` (many plugins) and `return {
  "repo", event = "…" }` (one plugin — a real, common style: config split
  one file per plugin) parse to the same node type. Read naively, `event`'s
  *value* looks like just another positional array element, and a first
  pass genuinely produced a spec whose `repo` was the string `"VeryLazy"`.
  Fixed on the one real distinguishing signal: an array of specs never has
  a *named* field at the outer level; a single spec's own trigger/metadata
  keys always do.
- **A bare-string array is not unique to plugin specs.** A plain list of
  command names (`return { "NeotestRunNearest", … }`, found genuinely
  documenting `:command` names in the same config) is the identical shape.
  Fixed by requiring a bare positional string to contain `/` with no
  embedded whitespace — GitHub shorthand is the one thing lazy.nvim's own
  contract requires of that position, so this is the format, not a style
  guess. Reduced one real config's false-positive count from 235 spec-shaped
  matches to 52 genuine ones.

Also flags a repo declared in more than one file — a real footgun in a
config split across files, where the last one lazy.nvim imports silently
wins and nothing else in this map could ever have surfaced it.

**Tools** is shaped like Plugins (a repo-level inventory, not a per-function
score) but reads a different declaration entirely:
[`lib.nvim.deps`](https://github.com/StefanBartl/lib.nvim)'s
`docs/install.json`/`docs/INSTALL.md`, the manifest a plugin ships for its
*optional external CLI tools* (`pandoc`, `poppler-utils`, …), not for its
Lua dependencies. `core/tools.lua` reads exactly this repo's own two known
paths — never `lib.nvim.deps.spec`'s `find`/`plugins`, which search
`runtimepath` for *other* plugins' manifests, the wrong shape for a tool
scoped to one repo at a time (see `core/tools.lua`'s header, same posture
`config/init.lua` already takes toward "which repo am I looking at").

Declared only, same discipline `duplicates`/`plugins` already follow for
different reasons: whether a tool is actually on `$PATH` differs by machine,
and baking that into `ir.tools` would make `--check`'s byte-compare depend
on who last regenerated the map — the same reasoning that keeps `ir.timing`
out of the artifact. What `docs/install.json` declares (`bin`/`required`/
`why`/`pkg`) is deterministic and is exactly what `ir.tools` holds; "is it
installed here" stays lib.nvim's own live `:Lib deps show` command's job, on
purpose, not duplicated into a static page.

A malformed entry doesn't just vanish from the panel — `tools-spec-invalid`
(§ Drift checks) surfaces it as a finding, so a typo'd manifest fails loud
instead of a tool quietly never showing up.

## Drift checks

The rendered map is the visible half; the checks are the half that catches
bugs. Generic checks (any annotated Lua tree):

| Check | Severity | Catches |
|---|---|---|
| `missing-module-tag` | error | A source file with no `---@module`. |
| `module-path-mismatch` | error | Declared `@module` ≠ where the file lives — copy-pasted or stale headers. |
| `missing-summary` | warn | `@module` present but no description line. |
| `dead-readme-link` | warn | A relative link in a README pointing at nothing. |
| `missing-readme` | info | Module without a README — should be a decision, not an accident. |
| `unreferenced-module` | info | Required by no other file in the tree. |
| `dead-see-target` | warn | A function's `@see` target resolves to no known module or function. |
| `type-vs-class` | warn | A module's own table is annotated `---@type Foo` and later has real fields assigned to it — LuaLS reports `missing-fields`/"fields cannot be injected" for this exact shape; `---@class M : Foo` is the annotation that actually means it. |
| `doc-references-missing` | warn | A `.md` file names `mod.member` where `mod` is a real module in this tree and `member` is not one of its functions — prose describing something renamed or removed. Deliberately narrow: an unknown prefix (`vim.fn.expand`), a plugin name (`x.nvim`), a glob (`mod.*`) and a documented rename (`` `old` → `new` ``) are all excluded. See `core/docs.lua`. |
| `tools-spec-invalid` | warn | This repo's own `docs/install.json`/`docs/INSTALL.md` has a malformed entry — missing `bin`, empty `why`, or no `pkg` map. See `core/tools.lua`. |
| `undocumented-param` | info | A function has more parameters than `@param` lines (text-based heuristic, can be wrong on complex signatures — never fails `--check`). |
| `param-name-mismatch` | info | R5: at a shared position, a `@param` name and the signature's declared name differ — usually a renamed parameter whose doc line was never updated. Same heuristic caveats as `undocumented-param`. |
| `require-cycle` | warn | A cycle among **load-time** requires. |
| `require-not-declared` | warn | A `require()` of a module inside this tree's own namespace that no file in the tree declares. |
| `layer-violation` | warn | Opt-in via `opts.layers`: a module reaching into a layer it must not. |
| `dead-function` | info | Nothing in the tree appears to call this function. |

`dead-function` is built around a trap stated plainly: **a library consists of
functions with no internal caller by design** — that is what a library is. A
naive "no callers ⇒ dead" would flag most of the published API of any tree
worth mapping and get switched off the same day, so it fires in two tiers.

Always on, because there the statement genuinely holds: a **file-local**
function (`local function foo`) its own file never mentions again, and an
`@internal` function no call edge reaches — the tag is the author saying this
is not surface, so "nobody calls it" is a real finding there. Only with
`opts.dead_code` does it widen to *any* function with no caller in the tree,
because for an ordinary public function that is a question, not an answer.

Three things count as "used" so the check does not produce a confident wrong
answer: `local_refs` (a function passed as a *value* — `vim.system(cmd,
on_exit)` — has no call site naming it, and flagging every callback in the
tree is exactly the failure this check must avoid), a heuristic call edge
(for *this* question a guess that something is used is the safe direction),
and being someone's `@see` target. A colon-declared method
(`function Lru:put()`) is treated as qualified surface, not a private local —
`calls.lua` has no case for method-call syntax at all, so `self:put(...)`
never becomes a call edge, and every colon method in the tree would otherwise
be misreported the moment its only callers use `:`. Verified against this
repo's own `Lru:get`/`Lru:put`
([`lib.nvim`'s `lua/lib/lua/memo/lru.lua`](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/lua/memo/lru.lua)), which are the public
API and are called only from other files, only via `:`.

Never above `info`, and it can never fail `--check`: dynamic dispatch is
invisible to the scanner (`lib.nvim.require`'s metatable and lazy strategies
call things that appear nowhere in the source), so a confident verdict is not
available at any severity.

`param-name-mismatch` (R5) compares positionally, not by set membership —
Lua has no keyword arguments, so "the doc's third `@param` describes the
signature's third parameter" is the actual contract, and set membership would
happily accept two parameters silently swapped. One real edge case, verified
against this repo's own `Lru:get`/`Lru:put`: a colon-declared method's own
`self` is Lua's implicit sugar, invisible to the raw signature text, but
documenting it explicitly (`---@param self Foo`) is legitimate LuaCATS style
— left uncorrected, every such method would misreport its real parameters
shifted one position early, so the check drops a documented leading `self`
before comparing. Caught two real bugs on first run against this tree
(`lua/lib/nvim/progress/styles/{float,kit}.lua`'s `bind_cancel_on_escape`
had gained a `bufnr` parameter with no `@param` line for it, silently
misaligning every doc line after it — `undocumented-param` already flagged
the count, this named exactly which parameter needed a line).

`require-not-declared` exists because an unresolvable `require()` lands in
`requires_external` — the same field a genuine third-party dependency lands
in. That is the right home for `plenary.async`, which this scan cannot be
authoritative about, and silently the wrong one for
`documentation.brwose.trail`: a typo, a renamed module, or one deleted while a
caller kept asking for it. All three break at runtime, and none of them look
any different in the map from a dependency the scan was never meant to cover.

The separation is on the **first path segment**. A require whose leading
segment is one the tree declares as its own is a claim about this tree, and
this tree is exactly what the scan *can* be authoritative about. Whole
segment, never a raw string prefix, so `documentation` cannot match a
`documentationx.util`. Line numbers come from `requires_raw`, which is
internal to the scan pipeline and never serialized — checks run against the
in-memory IR right after the walk, so they are still there.

The one false positive left over is a project deliberately split across
repositories under one namespace, and it already had an answer before this
check existed: `opts.tag_files` is the declaration that a prefix lives in
another project's map. Anything it covers is skipped, matched the same way
`tagfiles.lua` matches it — two different notions of "covered by a tag file"
would be a bug waiting for whoever first configures one.

`require-cycle` excludes deferred requires — `require(...)` inside a function
body, the standard way this tree breaks initialisation order on purpose. Run
without that exclusion against lib.nvim, every cycle it reported was a
deliberate lazy load; a check that only ever fires on intentional code is one
people learn to skim past, so it would have cost the real ones too. The
distinction is made from the parse (any function body, not just top-level
declarations — a lazy require hides inside an anonymous
`__index = function(_, k)` just as often as inside a named function), and both
kinds remain real edges in the Deps view, drawn dotted when lazy.

Repo-specific checks are passed in via `opts.extra_checks`. lib.nvim adds one:

| Check | Severity | Catches |
|---|---|---|
| `type-not-exported` | error | A `---@field` on the aggregate `Lib` class that does not resolve at runtime. |

That last one exists because `lib.find_root` was declared on the `Lib` class
and wired into none of the export strategies — the published type was simply
false, and it was found by accident. The check resolves against
`require("lib")` rather than by scanning the strategy sources: an early regex
version produced a false positive on `json_decode_to_string_array`, which is
wired through `SPECIAL_HANDLERS` in a shape the pattern did not match.
Indexing the real table is ground truth.

## Determinism

Two decisions make `--check` possible:

- **No timestamp in the IR.** A `generated_at` field would make every
  regeneration a diff even when nothing changed.
- **Sorted-key JSON** via [`json.lua`](../lua/documentation/core/json.lua), not `vim.json.encode`, whose
  object key order is unspecified. Without it, two runs over an unchanged tree
  produced byte-different files and `--check` reported the map as stale
  immediately after generating it.

Output is byte-identical across runs on unchanged input.

## Why `--check` does not regenerate

A hook that regenerates and stages output produces diffs the author never
intended, and interacts badly with `--amend` and rebase. `--check` fails with
"module map is stale — run `:DocMap`" and leaves regeneration explicit.

`--check` fails on both staleness and error-severity drift. Enforcing drift
was originally opt-in, because the tree carried a backlog of it and a check
that is red before anyone touches anything gets disabled. That backlog is
cleared, so enforcement is the default and `--lenient` is the escape hatch.

## Git hook

```bash
git config core.hooksPath scripts/hooks   # once per clone
```

[`scripts/hooks/pre-commit`](../scripts/hooks/pre-commit) runs
`--check` when `lua/`, `docs/map/` or the generator changed, and prints the
findings plus the one command that fixes them. It never regenerates or stages
anything itself. Bypass with `git commit --no-verify`.

It stays local (`core.hooksPath`) rather than a versioned tool like `lefthook`
on purpose: adopting it in another plugin should cost that plugin nothing more
than copying one file, not a new dependency for every downstream consumer.
[REUSE.md](REUSE.md) is exactly what to copy.

## Why this is its own plugin

It was `lib.nvim.docmap` for its whole development, and the module was written
from the start to know nothing about lib.nvim's layout — `opts.root`,
`opts.source`, `opts.extra_checks` exist precisely so it does not. That made
the extraction a rename rather than a rewrite: the pipeline, the IR and every
renderer are unchanged, and what moved is the module path
(`lib.nvim.docmap.*` → `documentation.*`), the type namespace (`Lib.Docmap.*`
→ `Documentation.*`), the command names (`:LibMap`/`:LibBrowse` →
`:DocMap`/`:DocBrowse`), and `config.lua`, which went from *one repository's
options* to *defaults derived from any root*.

Two things did change in behaviour, both consequences of no longer being a
library's own submodule:

- **Root resolution.** `command.setup()` used to walk up from its own source
  file, because the tree it mapped was always the one it lived in. A plugin
  installed under a plugin manager resolving that way would map its own
  checkout, so the default became `vim.fn.getcwd()` — with `opts.root` as the
  explicit answer whenever "wherever the user is" is not good enough.
  (`getcwd()` itself did not survive contact with real use, either: it answers
  "where was Neovim started", not "which repository is the user looking at",
  and does not move when a buffer in another checkout is opened. `:DocMap`/
  `:DocBrowse` now resolve per invocation from the current buffer's file
  instead — see |documentation-root|. `install()`'s own `opts.root` is
  unaffected; it was always the caller's to set.)
- **The repo-specific check moved out.** `type-not-exported` (lib.nvim's
  aggregate-`Lib`-class check) was in `config.lua`; it was never generic and
  belongs to the repository that needs it, passed in through
  `opts.extra_checks` like any other. Nothing here has a repo-specific check
  any more.

`lib.nvim` remains a **runtime dependency** — `notify`, `fs.*`, `ui.kit`,
`usercmd`, `map`, `debounce`, `autocmd`, `cross.uv.spawn_capture`. Vendoring
those was considered and rejected: it buys a standalone plugin at the price of
a second maintenance site for code that already exists, and every other plugin
in this family already depends on lib.nvim.
