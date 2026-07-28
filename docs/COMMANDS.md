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

---

## `:DocMap`

### `:DocMap`

Regenerate `module_map.json`, `index.html`, `overview.md` (and `coverage.svg`
with `opts.badge`) into `out_dir`. Prints what it wrote, the node counts, test
coverage and documentation coverage, then the drift findings.

### `:DocMap check`

Regenerate **in memory** and compare byte for byte against what is committed.
Writes nothing. Findings go to the **quickfix list**, not to a message: each
one names a real file, and a list of locations you can jump through is worth
more than a wall of text you have to search by hand.

Fails on staleness *and* on error-severity drift.

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

### Keys

| Key | Does |
|---|---|
| `1`…`5` | Switch mode: structure · deps · calls · types · history |
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
| `/` | Search |
| `q` | Close |

`history` mode calls git directly, so none of the `file://` origin problem
applies to it — the server exists to get the *browser* past a restriction the
editor never had. Both read the same `history.lua` analysis and show the same
two caveats, so their answers agree by construction rather than by review.

Full detail: [`lua/documentation/browse/README.md`](../lua/documentation/browse/README.md).
