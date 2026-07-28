# Outside Neovim

Two questions that look like one: **can this map a Lua project that is not a
Neovim plugin** (yes, today, from the terminal) and **could it run without
Neovim installed at all** (not without one specific dependency, and this
document is the cost estimate).

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
| **JSON** — `vim.json.decode`/`encode`, `vim.NIL` | 23 | The deterministic *encoder* is already this repo's own ([`json.lua`](../lua/documentation/json.lua)) — only a decoder is missing. |
| **Treesitter** | 25 | The blocker. See below. |

The 83 editor-only sites are the number worth reading twice: they are not a
porting cost, they are a deletion. `browse/`, `command.lua`, `registry.lua`,
`serve.lua` and `health.lua` come to **4 873 of 14 059 lines (35 %)** and
simply do not come along.

### How much is already portable

**Ten files have zero `vim.*` today**: `browse/filter.lua`,
`browse/trail.lua`, `churn.lua`, `doccoverage.lua`, `duplicates.lua`,
`history.lua`, and four of the five renderers. `render/html.lua` — 3 347
lines, the largest file in the tree — has exactly one.

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

## Why this is not scheduled

Because the first question is already answered, and it is the one people
actually ask. `nvim --headless` is a dependency that CI installs in one step
and most Lua developers already have. A parser-less build would trade the
function-level half of the map — which is most of what makes the map worth
generating — for removing a dependency that costs almost nothing.

The case would change if the goal were a LuaRocks package usable from a
non-Neovim toolchain, or if a standalone treesitter binding turned out to be a
drop-in. Neither is true today. Recorded so the estimate does not get made
from scratch again.
