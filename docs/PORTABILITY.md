# Outside Neovim

Two questions that look like one: **can this map a Lua project that is not a
Neovim plugin** (yes, today, from the terminal) and **could it run without
Neovim installed at all** (not without one specific dependency, and this
document is the cost estimate).

The other axis — supporting languages other than Lua — is costed separately
in [`MULTILANG.md`](MULTILANG.md).

Measured against the tree at the time of writing: 33 files, 14 059 lines
excluding `@types/`, 221 `vim.*` call sites.

---

## What works today

Nothing in the pipeline knows about any particular repository. `opts.root` and
`opts.source` point it at any tree; every other assumption — module prefix,
directory layout, types directory, output directory — is an option with a
default. `nvim --headless -l` is a Lua interpreter that happens to ship a
parser, a filesystem library and a JSON codec, and `scripts/gen_map.lua` uses
it as exactly that. See [`REUSE.md`](REUSE.md) for the two files to copy.

The real precondition is not Neovim, it is **`---@module` on your files**.
Without those the scan produces an empty tree, and nothing else in the
pipeline has anything to work on.

Verified against [`lib.nvim`](https://github.com/StefanBartl/lib.nvim) — a
different repository, run from the terminal, no editor session:

```
nodes=271  functions=838  findings=90  duplicate groups=27
```

So "can I use this for my Lua project" is already answered. What follows is
the other question.

---

## What a Neovim-free port would cost

### The shape of the dependency

Of the 221 `vim.*` call sites, the largest group is the one that does not need
porting at all:

| | Sites | What happens to it |
|---|---:|---|
| **Editor-only** — `vim.api`, `vim.bo`, `vim.cmd`, `vim.ui`, `vim.health`, quickfix | 83 | **Deleted, not ported.** A CLI has no buffers. |
| **Stdlib helpers** — `vim.trim`, `split`, `tbl_*`, `list_extend`, `deepcopy`, `fs.dirname` | 52 | Five lines of Lua each. |
| **Filesystem / process** — `vim.uv`, `vim.system`, `vim.fs.dir`, `vim.fn.getcwd` | 38 | `luv` is the same library as a standalone LuaRocks package; `vim.uv` → `luv` is close to a rename. `vim.system` → `io.popen` or luv's spawn. |
| **JSON** — `vim.json.decode`/`encode`, `vim.NIL` | 23 | The deterministic *encoder* is already this repo's own ([`json.lua`](../lua/documentation/core/json.lua)) — only a decoder is missing. |
| **Treesitter** | 25 | The blocker. See below. |

The 83 editor-only sites are the number worth reading twice: they are not a
porting cost, they are a deletion. `editor/` — `browse/`, `command.lua`,
`registry.lua`, `serve.lua`, `health.lua` — comes to **4 873 of 14 059 lines (35 %)** and
simply do not come along.

### How much is already portable

**Ten files have zero `vim.*` today**: `editor/browse/filter.lua`,
`editor/browse/trail.lua`, `core/churn.lua`, `core/doccoverage.lua`,
`core/duplicates.lua`, `core/history.lua`, and four of the five renderers.
`core/render/html.lua` — 3 347 lines, the largest file in the tree — has
exactly one.

That is not luck. It is the same purity rule the specs are built on: data in,
a structure out, no window and no filesystem. It was adopted so the model
could be driven headlessly, and portability is a side effect of it.

The rest of the pipeline is thin on `vim.*` too — `scan.lua` 3, `deps.lua` 2,
`init.lua` 2, `tagfiles.lua` 1, `config.lua` 3, `coverage.lua` 3,
`check.lua` 5.

### The blocker is exactly one thing

`vim.treesitter`, 25 sites across six files: `functions.lua`, `calls.lua`,
`symbols.lua`, `coverage.lua`, `deps.lua`, `health.lua`.

Without a parser you lose everything that is **per function**: the function
list, call edges, module symbols, cyclomatic complexity, the structural
shapes duplicate detection groups by, and test coverage.

What survives is more than it sounds, because `deps.extract_source` is
**pattern matching over lines, not a parse** — treesitter is used there only
to classify a require as deferred or load-time. So a parser-less build still
produces:

- the module tree, headers, summaries and READMEs;
- the whole require graph, and with it `require-cycle`, `layer-violation` and
  `require-not-declared` (minus the deferred/load-time distinction, which
  would make the cycle check noisier);
- `missing-module-tag`, `module-path-mismatch`, `missing-readme`,
  `dead-readme-link`, `unreferenced-module`;
- the Markdown, DOT and Mermaid renderers.

Getting the parser back means the tree-sitter C library, a Lua binding, the
Lua grammar, and a shim for the Neovim API shape this code is written against
(`query.parse`, `iter_captures`, `get_node_text`, `get_string_parser`).
Standalone bindings exist; **how well any of them fits this code has not been
checked, and that is the first thing to verify before starting.** Everything
else in this document is arithmetic, that part is research.

### Summary

Roughly 113 of the 221 sites are mechanical, 83 are deleted rather than
ported, and 25 are the actual project. The core pipeline is already close to
editor-free; it hangs on a single dependency, and that dependency is the
scanner.

---

## The three-step version: split, bundle, link

The obvious plan is "separate the editor half, make a binary, bundle
tree-sitter". Each step is real, but they are not equally cheap and the third
one is not what it first looks like. Measured with `tree-sitter` CLI 0.26.9 and
this repository's own queries.

### Step 1 — the split, and enforcing it — **done**

It was already 35% done by accident of the purity rule. What was missing was
anything that *stopped* it re-merging: nothing prevented `scan.lua` from
requiring `browse/`.

The plugin already shipped the mechanism — `opts.layers` and the
`layer-violation` check — but it could not express this boundary against the
flat tree. The editor half was five separate module paths (`browse.*`,
`command`, `registry`, `serve`, `health`), not one prefix, and a rule from
`documentation` down to the browser would have flagged `browse/init.lua`
requiring `browse/view.lua`.

`documentation.core.*` / `documentation.editor.*` makes it one line, now
declared in `scripts/gen_map.lua`:

```lua
layers = { { from = "documentation.core", to = "documentation.editor",
             why = "the pipeline has to stay runnable without an editor" } }
```

The tool now checks its own split in its own CI, and the boundary cannot rot.
That was the whole argument for the rename — not tidiness, enforceability.
Declaring the rule found one real violation immediately: `tagfiles.lua`
reached into `command.lua` for `find_node`, a lookup that touches nothing but
the IR. It is `core/find.lua` now.

One-directional on purpose. The editor half reaching into the core is the
point of the core existing; only the other direction costs anything.
`init.lua` sits outside the rule and reaches both, which is what a facade is
for.

### Step 2 — a binary

`luastatic` links a Lua interpreter, your `.lua` sources and any C libraries
into one executable. Nothing here makes that hard; it is the least
interesting step.

### Step 3 — tree-sitter, and why the CLI is the wrong unit to bundle

The CLI does work, and `tree-sitter query` returns exactly the shape this code
reads from `iter_captures`: capture name, start and end `(row, col)`, and the
matched text. Verified against this repository's real complexity query.

It has two problems, one of degree and one of kind.

**Degree — process startup dominates, so batching is mandatory.** Measured:

| | Time |
|---|---:|
| First run (grammar compiled on demand) | 0.698 s |
| Warm, one file | 0.081 s |
| One invocation over 35 files | **0.229 s** |
| Per-file loop over the same 35 files | 2.482 s |
| One invocation over lib.nvim's 367 files | **0.592 s** |

Per-file is 10× worse than batched, so any design that parses a file at a time
— which is what `scan()` does today — is off the table. Even batched, this
repository issues **8 distinct queries**, so a full scan is ~8 invocations:
roughly 4.7 s over lib.nvim against 0.65 s for the entire in-process scan
today. Around 7×, for the query half alone.

Note also that the CLI compiles a grammar from source on first use, which
means a C toolchain on the *user's* machine — a heavier dependency than the
thing it was supposed to remove.

**Kind — queries are only half of what this code does.** There are 12 query
call sites, and **27 tree-navigation call sites** across `functions.lua`,
`calls.lua`, `symbols.lua` and `deps.lua`: `:child()`, `:child_count()`,
`:parent()`, `:type()`, `:range()`. `tree-sitter query` cannot serve any of
them. `shape_of` — the fingerprint duplicate detection is built on — walks
every node in a subtree, and `is_top_level` walks the parent chain. Recovering
those from `tree-sitter parse`'s S-expression output means writing a tree API
over parsed text, which is a component, not a shim.

**So: bundle the library, not the CLI.** The CLI is a Rust wrapper around
`libtree-sitter`, which is C — and `tree-sitter-lua`'s `src/parser.c` is
generated C. Both link into a `luastatic` binary natively, and you cannot link
a Rust executable into a C one anyway; bundling the CLI would mean embedding it
as a resource and exec'ing it at runtime. Linking the library gives one
artifact, no subprocess, no per-invocation cost, no C toolchain on the user's
machine, and — the part that decides it — **the full node API, so the 27
navigation sites survive**.

What that leaves is a Lua binding whose surface matches what this code calls.
That is the one genuinely unresolved question, and it is sharper than
"does a binding exist": does one exist shaped like `query.parse` /
`iter_captures` / `get_node_text` / `:child` / `:parent`, or does a shim have
to be written over it? Answer that before anything else in this document is
worth starting.

## Why this is not scheduled

Because the first question is already answered, and it is the one people
actually ask. `nvim --headless` is a dependency that CI installs in one step
and most Lua developers already have. A parser-less build would trade the
function-level half of the map — which is most of what makes the map worth
generating — for removing a dependency that costs almost nothing.

The case would change if the goal were a LuaRocks package usable from a
non-Neovim toolchain, or if a Lua binding to `libtree-sitter` turned out to
match the API surface this code is written against. Neither is true today.

**Step 1 is worth doing on its own merits, though**, and does not depend on any
of the rest: the split already exists, and making it enforceable costs a rename
plus one `layers` rule. Everything after it is optional.

Recorded so the estimate does not get made from scratch again.
