# Commands

Two commands, split along one line: `:DocMap` **writes or verifies artifacts**,
`:DocBrowse` only ever **reads**. That is why the editor-side browser is not a
`:DocMap browse` subcommand — folding a read-only viewer into a command whose
bare form rewrites files on disk is the kind of surprise that gets a command
bound to a key and then regretted.

Neither exists until `setup()` runs. Rename either with `opts.command_name` /
`opts.browse_command_name` — which is what lets a plugin that generates its own
map coexist with this one instead of silently overwriting its command
(`usercmd.create` defaults to `force = true`, so a collision is not an error,
just a bug).

## Which repository do they act on?

With no `opts.root`, **both commands resolve one per invocation** from the file
behind the current buffer: up to the nearest ancestor holding a `root_markers`
entry (`.git` by default, matching a worktree's `.git` *file* too), falling back
to the working directory for a buffer with no file. So the question they answer
is "which project am I looking at", not "where was this Neovim started".

Every report names the repository it acted on — `lib.nvim: wrote 3 artifacts
(…)`. That is not decoration: without a subject, "Wrote 3 artifacts" is a claim
the reader cannot check.

Setting `root` pins every invocation to one tree, which is what a consuming
plugin generating its own map wants.

> Before this, the root was resolved once in `setup()`. Because the plugin is
> usually `cmd`-lazy, "once" meant *the first `:DocMap` of the session* — and
> every later invocation regenerated that first repository regardless of which
> tree the user was in. Silently, because the report named no repository. Both
> halves of that bug are fixed above, and either alone would have been enough
> to notice it.

A handle is installed per root and reused, so switching between repositories
costs a scan only the first time each is seen. Completion never installs one:
pressing `<Tab>` in a repository this session has not scanned offers the action
names and no module names, rather than blocking the editor on a full scan for a
candidate list.

---

## `:DocMap`

### `:DocMap`

Regenerate `module_map.json`, `index.html`, `overview.md` (and `coverage.svg`
with `opts.badge`) into `out_dir`. Prints the repository it acted on, what it
wrote, the node counts, test coverage and documentation coverage, then the
drift findings.

### `:DocMap check`

Regenerate **in memory** and compare byte for byte against what is committed.
Writes nothing. Findings go to the **quickfix list**, not to a message: each
one names a real file, and a list of locations you can jump through is worth
more than a wall of text you have to search by hand.

Fails on staleness *and* on error-severity drift.

### `:DocMap annotate [--write|--sidecar]`

Scaffolds a `---@module` header — and, when the file returns a table, a
`---@class` block with one `---@field` per exported name — for every file
`check`'s own `missing-module-tag` finding lists. Closes the gap between that
finding being reported and it being fixed: previously the only path from "the
check told me" to "the file says something true" was typing the header by
hand, for every file, one at a time.

No flag (the default, same as `--dry-run`) writes nothing: it opens a scratch
buffer previewing every generated block, one `-- path` separator per file.
`--write` splices the block into each file in place, immediately above
`local M = {}` (or at the top of the file, for the rare export that is not a
plain table) — never anywhere below it. `--sidecar` writes the same block to
`<path>.annot.lua` next to the original instead, for review before merging it
in by hand.

Deliberately a starting point, not a finished annotation: types are best
guesses — `fun(...)` reconstructed from a function's own already-parsed
`@param`/`@return`, the referenced `---@class` name when a field's own value
already carries one, `table`/`any` otherwise — and the one-line summary is a
`TODO` for a human to fill in. A wrong confident type would be worse than an
honest placeholder.

`--write`/`--sidecar` open the quickfix list on every file touched, so the
result is as easy to jump through and review as `check`'s own findings are.

### `:DocMap full`

`:DocMap` plus LuaLS enrichment — parsed `@class`/`@alias` detail, type-reference
edges and inheritance edges merged into the IR. Opt-in per invocation because a
full-tree `lua-language-server --doc` run costs several real seconds.

Without it the Hierarchy tab still works off plain parent/child structure; the
Types and Inheritance views say so explicitly rather than rendering blank.

If `lua-language-server` is not on `PATH`, this degrades to an `info`-severity
`luals-unavailable` finding rather than failing the scan.

### `:DocMap open`

Open the generated HTML in the system browser. Prefers the local server when
one is running (see `serve`), because the History tab needs an origin that
`fetch` is allowed on.

### `:DocMap graph <kind> [name]`

The same page as `open`, opened **at a state** instead of at the root — the
page's whole navigable state lives in its URL fragment, so this needs no
second rendering path.

```vim
:DocMap graph deps
:DocMap graph calls my.module
:DocMap graph types
```

`name` resolves against a declared `@module`, a raw node id, *or* the module
path a **namespace**'s location implies — a directory without `init.lua`
declares no module, yet its dotted path is exactly what people type, and
namespaces are the aggregation points a dependency graph is most useful at.

### `:DocMap why <a> <b>`

The shortest require path between two modules → **quickfix list**. Every hop
*is* a location: the edge carries the line its `require` is written on, so each
entry jumps straight to the line that creates that link. The summary says up
front whether the path is load-time throughout or goes through a lazy require
somewhere — usually the difference between "has to go" and "is fine".

### `:DocMap dot <kind> [name]`

The require or call graph as Graphviz **DOT**, in a scratch buffer. A third
renderer for the same edges, because the other two cannot do what Graphviz
does: the HTML page lays boxes out in BFS layers and cannot route an edge
around anything, and Mermaid is rendered by the code host.

Deliberately **not** wired to a `dot` binary — that would add an external
dependency and a "dot not found" failure mode to a feature whose entire output
is text. Yank it, `:w` it, or pipe it through `:%!dot -Tsvg`.

### `:DocMap mermaid [tree|deps]`

The module tree, or the require graph, as **Mermaid** source in a scratch
buffer. The renderer already existed — `overview.md` embeds it, because
GitHub draws mermaid fences and does not run the HTML page's JavaScript —
this is the way to ask for it on its own. `markdown` filetype, not
`mermaid`: the output is a fenced block, so that is what the buffer holds.

### `:DocMap consumers [dir]`

**Who actually uses this library.** Reads every `*/docs/map/module_map.json`
under `dir` (the parent directory by default, where sibling checkouts live)
and joins them against this project's own map. The join key is the module
path: a consumer's `requires_external` holds exactly the paths its own scan
could not resolve internally, which is what a foreign library looks like
from inside it, so neither side needs a table of the other's names.

Three answers, and the middle one is why it exists. Against `lib.nvim` and
29 sibling maps: **107** modules required by at least one consumer, **108**
required only by the library itself, **33** referenced by nobody. A two-way
used/unused answer reports 141 as unused — every one of those 108 wrongly.

**`unreferenced` does not mean dead.** It means no consumer among the maps
supplied: a project not in the set, a map not regenerated since its last
require was added, and a user who never committed a map are all invisible
here and all perfectly normal. The report says so itself rather than leaving
a reader to act on a number that is a floor.

### `:DocMap diff [ref]`

What a revision changed about the **shape** of the tree: modules and functions
added or removed, dependencies gained or lost, load-time cycles introduced,
blast radii that moved. `HEAD` by default; everything between `ref` and the
working tree.

Needs no generation step — every commit already carries its own artifact, so
`git show <ref>:docs/map/module_map.json` is the whole retrieval.

Comparing against an **older schema** suppresses the dependency, cycle and
impact sections with the reason stated, rather than reporting every dependency
in the tree as "added".

### `:DocMap impact [ref]`

Where those changed lines **radiate to** → quickfix list. Each touched function
appears at its declaration, interleaved with its call sites at the call,
indented — the call sites being the actionable half.

A bare `:DocMap impact` answers "what does my uncommitted work affect"; on a
clean tree, `impact HEAD~1` is "what did the last commit affect".

Files nothing could be attributed to come last: they explain why the count is
lower than the diff looks, but they are not findings. When a span had to be
approximated (an artifact predating `line_end`), the summary says so out loud
instead of implying precision it does not have.

### `:DocMap churn [rev-range]`

Modules that are both **frequently changed** and **complex** → quickfix list,
highest first. Adam Tornhill's refactoring-risk signal from *Your Code as a
Crime Scene*: neither factor alone is actionable. A module edited fifty times
that is five lines of constants is a config file, and a three-hundred-point
parser nobody has touched in two years is finished. What costs real time is
the intersection — complicated code that keeps having to change.

Each row carries both numbers and the module's single most complex function,
because the score says which module and never where to start reading.

```vim
:DocMap churn                 " all history
:DocMap churn HEAD~200..      " one range
```

Merges are excluded (they list everything either side changed, counting one
edit twice and rewarding long-lived branches) and so is `out_dir` — in a
repository that commits its own map it is regenerated by nearly every commit,
so it would outrank everything real by an order of magnitude. Paths that
changed but back no scanned module are counted and reported rather than
silently dropped.

**Not an Analysis-tab panel, and it cannot become one.** It needs `git log`,
and git data cannot enter the committed artifact: `--check` byte-compares
committed against freshly-generated output, so a map carrying history
invalidates itself on the commit that embeds it. The same wall the History tab
hit. Live-computed here instead, exactly like `:DocMap impact`.

A **rename resets a module's history**: counting is per path, so a file moved
yesterday looks untouched since the beginning of time. `git log --follow`
takes a single pathspec and is therefore no use for a whole-tree ranking. The
commit column is what makes that visible rather than silent, and it corrects
itself as history accumulates.

**A third column, when this machine has telemetry.** `runtime-analysis.nvim`
knows what actually ran; churn cannot. Complex, churning and hot is a
*refactoring* candidate; complex, churning and cold is a *deletion*
candidate — and without the third number those two rows render identically
while calling for opposite actions. Measured on this repository:
`editor.browse.view` (complexity 383) carries *47 calls, none in the last
week*, while `core.check` (complexity 360, one row below it) carries *37 722
calls, 4 839 this week*.

Three things it deliberately does not do:

* **It does not change the order.** Telemetry is *this machine's* usage.
  Folding it into the score would make a ranking that reads as a property of
  the code into one that is partly a property of whoever last ran it — two
  developers would get two different orders for one repository and neither
  would be wrong. The column separates the rows; the sort stays put.
* **It never says "unused".** A module cold here may be the hot path for
  every other user of the plugin. The wording is *"not called in your
  sessions"*, and a module that ran but not lately reads differently again.
* **No telemetry means no column**, not a zero. A module telemetry never
  matched is absent from the join entirely: "nobody measured this" and
  "measured it and saw nothing" are different facts, and only the second one
  licenses deleting anything.

### `:DocMap pick`

Fuzzy-find any module or function in the map and land on its source line.

```vim
:DocMap pick
```

**The interaction `:DocBrowse` does not have.** The browser's `/` is a fuzzy
jump *inside* the browser — it moves the cursor to a row and leaves you
there, which is right when you are exploring. This is the other one: *I know
the name, get me there.* It ends in the file, and the browser never opens.

Entries read as `module` and `module#M.fn`, the same two shapes the
browser's own jump builds, so a name typed in one place is the name typed in
the other. On this repository that is 913 entries.

**Which picker.** [`pickers.nvim`](https://github.com/StefanBartl/pickers.nvim)
first, if it is installed and it resolves an engine — telescope, fzf-lua or
snacks. That buys fuzzy matching over several hundred entries *and* the
engine's own native file previewer, because an entry carrying a `file` gets
one for free. Otherwise `lib.nvim`'s `kit.select` with `respect_override`,
which defers to whatever you wired into `vim.ui.select`
(telescope-ui-select, fzf-lua, dressing) and falls back to the kit's own
chooser when you wired nothing.

Neither is a hard dependency, and neither has to be configured. A reader
with `pickers.nvim` but no engine installed gets the kit and **no error**:
`engines.load()` would have told them to install telescope, which is right
for `:Pickers` and wrong here, so this asks whether an engine exists before
asking for one.

### `:DocMap untested`

Functions **this machine actually ran** that no spec names → quickfix list,
most-run first. The one useful cell of coverage × telemetry: *"this ran four
thousand times and no spec mentions it"* is a test backlog sorted by
evidence rather than alphabetically.

```vim
:DocMap untested
```

It **repairs `core/coverage.lua`'s stated blind spot in one direction**. That
module derives `tested` from bare-name mentions under `tests_dir` and says
outright that a function exercised only *indirectly* never lights up. It
still does not — but a function telemetry watched running is no longer
invisible, so the two blind spots no longer overlap.

**Read the list as "no spec names it", not as "untested".** On this
repository the top entries are internal helpers reached through a public
entry point that specs do call — `check.declared_param_names`, 33 843 calls.
That is a true and useful reading rather than a false positive: a name in a
spec is what makes a failure localise to the function that caused it. It is
not a claim that the code is unexercised.

The other three cells are not produced. "Tested and called" is fine; "tested
and never called" is a question about the test; "untested and never called"
is `dead-function`'s territory and has its own suppression rules, and a
second verdict beside an existing one would eventually disagree with it.

**A report, never a gate.** Runtime counts cannot enter the committed
artifact — same byte-comparison wall as `churn` — and a *check* built on them
would fail on one developer's machine and pass on another's, which
`runtime-analysis.nvim`'s own `IDEAS.md` §1.5 refuses on its own terms: a
warning that appears on one machine and not another is worse than no
warning.

The score is `commits × complexity`, and that is a scalarization with the
weakness every scalarization has — a large enough value on one axis outranks a
moderate value on both. Both columns are on every row, so when the order looks
wrong the numbers next to it say why.

### `:DocMap checklist [all]`

The hand-verified **ledger** → quickfix list: items whose accuracy was
manually checked, cross-referenced against `git log` to flag which ones are
now **stale** (the cited path changed since the verification date) or
**unverified** (no verification date at all). Defaults to showing only what
needs attention; `:DocMap checklist all` lists everything, including entries
that are still current — the "is this ledger healthy" view rather than the
"what do I do now" one.

Not an Analysis-tab panel, for the same reason `churn` cannot be one: the
verdict depends on `git log`, and git data cannot enter the committed
artifact without invalidating `--check`'s byte-compare on the very commit
that embeds it. The ledger *content* does bake into `module_map.json` (it is
just parsed Markdown); only the stale/unverified verdict is computed live,
here and by the serve tier's `/api/checklist` route.

### `:DocMap plugins`

Every recognized **lazy.nvim spec** in the tree → quickfix list, sorted by
repo. Instant, unlike `impact`/`churn`: the specs already sit on
`ir.nodes[*].plugins`, extracted during the scan that produced the live
handle — no git, no second pass.

Exists for the shape of tree this map was previously blind to: a Neovim
*config*, where most of `lua/plugins/*.lua` is `return { {...}, {...} }`
with no function in sight — invisible to every other command and panel.
Each row carries the repo, which triggers load it (`event`/`cmd`/`keys`/`ft`,
or "no trigger — loads at startup" when none is set), and the file it came
from. A repo declared in more than one file is flagged — the last one
lazy.nvim imports silently wins, and nothing else in this map could ever
surface that.

Scoped to lazy.nvim's spec shape specifically; packer.nvim and vim-plug
specs look different and are not recognized. See
[`core/plugins.lua`](../lua/documentation/core/plugins.lua) for exactly what
counts as a spec — in particular, `return { "repo", event = "…" }` (one
plugin) is read correctly as one entry, not as several with `event`'s value
mistaken for a second repo, and a bare-string list is only accepted as
plugins when every string is shaped like `owner/repo`.

### `:DocMap bindings`

Every recognized **keymap, user command and autocmd** in the tree →
quickfix list. Instant for the same reason `plugins` is: the registrations
already sit on `ir.nodes[*].bindings` from the scan that produced the live
handle.

The rest of what a Neovim *config* is made of, after `plugins` above. Rows
carry the identifying text (`[n/v] <leader>x`, `:Foo`, `BufWritePre`), the
`desc` when set, and the file and line it came from.

**Sorted by left-hand side so collisions land adjacent.** The same
`<leader>x` bound in two files is a real and genuinely hard-to-find config
bug — whichever module loads last silently wins — flagged `[bound more than
once]`, the same service `plugins` does for a repo declared twice. Counted
per distinct (mode, lhs) pair: the same lhs in normal and visual mode is
two bindings, not a clash. Buffer-local registrations are excluded from
collision counting entirely, since shadowing a global mapping inside an
ftplugin is the intended idiom.

**If a file that visibly binds keys yields nothing, the wrapper is not
declared.** The `vim.*` APIs are recognized unconditionally; a config's own
helper (`map(...)`, `usercmd.create(...)`, or a bare `local
nvim_create_autocmd = api.nvim_create_autocmd` — all three are real shapes
from one real config) must be named in `opts.bindings.wrappers`. See
[`core/bindings.lua`](../lua/documentation/core/bindings.lua) for why that
is declared rather than guessed, and
[`docs/FEATURES/CORE.md`](FEATURES/CORE.md) for the measurement behind it.

### `:DocMap endpoints`

Every recognized **call-based route registration** in the tree → quickfix
list, sorted by path. Instant, like `plugins` and `bindings`: the routes
already sit on `ir.nodes[*].endpoints`, extracted during the scan that
produced the live handle — no git, no second pass.

Recognizes call-based routing (Express/Fastify/Koa-shaped registrations)
only; file-based routing (Next.js/SvelteKit/Nuxt/Remix) belongs in a
Hierarchy view instead and is not what this lists — see
[`core/endpoints.lua`](../lua/documentation/core/endpoints.lua) for exactly
what counts as a route.

### `:DocMap tools`

This repo's own **`lib.nvim.deps` manifest** (`docs/install.json`, falling
back to `docs/INSTALL.md`) → quickfix list. Same shape as `plugins`: the
manifest is read once, during the scan that produced the live handle
(`ir.tools`), no second pass.

A different ecosystem convention from `plugins` — not "what does this repo
depend on", but "what external CLI tools does it optionally lean on, and
why". Each row carries the tool's binary name, `[required]` when set, the
`why` the manifest declares, and which package managers ship it. A malformed
entry (missing `bin`, empty `why`, no `pkg` map) is listed too, and also
raises a `tools-spec-invalid` finding — see
[`core/tools.lua`](../lua/documentation/core/tools.lua).

Declared only, deliberately: whether a tool is actually installed on *this*
host is never checked here, or baked into the map at all — that answer
differs by machine and would make `--check`'s byte-compare depend on who
last regenerated it. lib.nvim's own `:Lib deps show <plugin>` already
answers "is it installed", live.

### `:DocMap serve` / `:DocMap serve stop`

Start (or stop) the local map server, which is what enables the **History tab**
in the browser.

Why a server at all: a page opened as `file://` gets an opaque origin, and
`fetch()` refuses the `file:` scheme for CORS requests outright. "Compute this
commit when the reader clicks it" therefore needs an origin.

Security posture, enforced rather than documented and hoped for:

- binds `127.0.0.1` on an OS-assigned port, never `0.0.0.0`;
- every `<sha>` is checked against `^[0-9a-f]{7,40}$` **before** it reaches git
  — a whitelist, not an escape, because the value becomes a subprocess argument
  and `--upload-pack=…` is a perfectly valid-looking path segment. `HEAD` is
  refused too;
- static serving takes a bare filename, so no request can walk out of `out_dir`;
- `VimLeavePre` tears the socket down.

### `:DocMap helptags`

Regenerate this plugin's own `doc/tags`.

### `:DocMap all [full]` / `:DocMapAll` / `:DocMapAllFull`

Generate every project in `opts.generate_all.projects` — one real headless
Neovim subprocess per project (`documentation.generate_all.run()`), chained
sequentially so exactly one is ever running, never blocking this session.
One project failing does not abort the rest; the closing notification names
every one that failed.

**Registered only when `opts.generate_all.projects` is non-empty.** This
plugin has no notion of "which repos a consumer's config manages" and never
reads one — `opts.generate_all` is plain data (`{ projects = {{root, title},
...} }`) a caller's own plugin spec supplies, typically derived from that
caller's own plugin-list abstraction. With nothing configured, none of
`all`/`:DocMapAll`/`:DocMapAllFull` exists at all; `:DocMap all` on an
unconfigured setup warns rather than erroring.

`:DocMapAll` and `:DocMapAllFull` are standalone aliases for `:DocMap all`
and `:DocMap all full`, registered by the same `setup()` call, reached for
often enough once configured to earn command names of their own rather than
a remembered subcommand.

**Fast by default, LuaLS enrichment on request (2026-08-15).** `:DocMap
all`/`:DocMapAll` run a plain scan for every project — no `[full]`/`:DocMap
all full` needed the way a single-repo `:DocMap` already works. `:DocMap all
full` / `:DocMapAllFull` opt every project in that run into the same LuaLS
enrichment `:DocMap full` gives one repo (`@class`/`@alias` detail, type
edges) — costs seconds *per project*, so worth reaching for deliberately
across two dozen repositories rather than paying it on every bulk
regeneration. Before this split, the bulk path always ran enriched; a
config relying on that (`opts.generate_all.autoload`'s own background
first-generation pass, notably) is unaffected — `autoload` still always
enriches, since it is establishing a project's map for the first time, not
a routine re-run.

`opts.generate_all.autoload = true` additionally checks, once at `setup()`
time, whether each configured project already has a `module_map.json`; any
that do not get generated automatically (async, non-blocking — the same
mechanism as `all` itself, just self-triggered). Off by default: writing
into `docs/map` inside a repository on every editor start without being
asked is exactly the kind of uninvited, hard-to-notice-until-`git status`
side effect this plugin otherwise refuses to produce. Opting in is the
explicit request that default declines to infer on its own.

```lua
require("documentation").setup({
  generate_all = {
    projects = {
      { root = "/repos/lib.nvim", title = "lib.nvim" },
      { root = "/repos/markdown.nvim", title = "markdown.nvim" },
    },
    autoload = true, -- generate any of the above that has no map yet
  },
})
```

---

## `:DocBrowse`

The map inside the editor. Explicitly **not** the HTML diagram in a terminal —
boxes with connecting curves need pixels, and a fixed cell grid produces a
worse version of a page that already exists. This is a *navigator over the same
edges*: the hierarchy is a drill-down list, Deps and Calls are lists.

Three things justify it next to the generated page, all things the page cannot
do at all: jump to the source at the line (`gd`), fill the quickfix list
(`gq`), and be live.

| Invocation | Does |
|---|---|
| `:DocBrowse` | Read `module_map.json` off disk (~10ms). |
| `:DocBrowse live` | Install a watching handle instead — rescans on every write (~0.65s once). |
| `:DocBrowse <module>` | Open centered on one module. |
| `:DocBrowse history` | Open on the commit list. |
| `:DocBrowse trail` | Open on the pinned positions. |

### Keys

| Key | Does |
|---|---|
| `1`…`6` | Switch mode: structure · deps · calls · types · history · trail |
| `j` / `k` | Move |
| `<CR>` | Descend |
| `-` / `<BS>` | Up |
| `<C-o>` / `<C-i>` | Navigation history back / forward |
| `h` / `l` | Edge direction (in / out) |
| `+` / `_` | Depth |
| `gd` | Jump to the source |
| `gq` | Fill the quickfix list |
| `gI` | Impact — the transitive `required_by` closure |
| `gO` | Open the HTML page at this position |
| `gD` | The opened commit's diff |
| `p` | Pin / unpin the entry under the cursor |
| `d` | Unpin (Trail) |
| `S` | Save this trail under a name (Trail) |
| `L` | Load a saved trail, adding to this one (Trail) |
| `X` | Forget a saved trail (Trail) |
| `f` | Filter this list in place (`-negate`, `"phrase"`; empty clears) |
| `/` | Search |
| `?` | This table, in a float, for the current mode |
| `q` | Close |

**Trail** (`6`) is deliberately not the same thing as `<C-o>`/`<C-i>`. The
history stack answers "where was I a moment ago" — automatic, ordered by time,
truncated by the next move. A trail answers "where do I want to get back to" —
deliberate, and nothing but an unpin removes an entry. Reading a dependency
graph produces dozens of history stops and about four places worth returning
to.

The working trail persists across Neovim restarts on its own, in
`stdpath("state")/documentation.nvim/trails.json` — state, not the repository.
`S` names a copy of it, `L` loads one back **additively** (replacing would
silently destroy the trail built this session) and `X` forgets a saved one
without touching the pins on screen.

A pin records a **view**, not just a subject: the mode and the axes it was
taken in, all restored by `<CR>`. Pins are keyed by repository root, so they
survive closing and reopening the browser.

`?` renders from the same table `bind()` installs from, so it cannot describe
a key the browser does not have or omit one it does — the spec asserts exactly
that rather than leaving it to a comment. Keys the current mode ignores are
marked rather than hidden: "why did `+` do nothing" is the question someone
opens the overlay to answer.

`history` mode calls git directly, so none of the `file://` origin problem
applies to it — the server exists to get the *browser* past a restriction the
editor never had. Both read the same `history.lua` analysis and show the same
two caveats, so their answers agree by construction rather than by review.

Full detail: [`lua/documentation/editor/browse/README.md`](../lua/documentation/editor/browse/README.md).
