# documentation.nvim

Doxygen for annotated Lua trees, as a Neovim plugin. Point it at a repository
whose files carry `---@module`, and it produces a **module map**: an
interactive HTML page, a Markdown overview, a deterministic JSON artifact, and
a set of drift checks that fail CI when the documentation and the code stop
agreeing.

```vim
:DocMap          " regenerate the artifacts
:DocMap check    " verify without writing — findings go to the quickfix list
:DocMap open     " open the generated page in the browser
:DocBrowse       " navigate the same map inside the editor
```

Grew inside [`lib.nvim`](https://github.com/StefanBartl/lib.nvim) as
`lib.nvim.docmap` and was extracted once it had nothing left to do with
lib.nvim. See [docs/PIPELINE.md § Why this is its own
plugin](docs/PIPELINE.md#why-this-is-its-own-plugin).

## What it produces

| Artifact | What it is |
|---|---|
| `docs/map/index.html` | The interactive map: **Tree**, **Hierarchy**, **Notes**, **Index**, **History** and **Analysis** tabs. Self-contained — no CDN, no build step. |
| `docs/map/overview.md` | The same tree as Markdown, so it renders on GitHub. |
| `docs/map/module_map.json` | The IR, byte-deterministic. What `--check` compares and what `:DocMap diff` reads out of old commits. |
| `docs/map/coverage.svg` | Optional (`opts.badge`): a doc-coverage badge, hand-rolled, no network call. |

The Analysis tab ranks the tree five ways over the same IR — test coverage,
documentation coverage, fan-in/fan-out, cyclomatic complexity, and structural
**duplicates**: functions whose parse-tree shape is identical, which is the one
kind of drift the require graph is blind to by construction (two modules that
each grew their own `read(path)` do not require each other).

The Hierarchy tab draws five graphs over the same IR — **Modules** (directory
hierarchy), **Types** (`@class`/`@alias` collaboration), **Inheritance**,
**Deps** (the require graph) and **Calls** (function-level caller/callee) —
with direction and depth controls, semantic zoom, right-click navigation and
real browser Back/Forward.

## Installation

Requires Neovim 0.10+ (`vim.uv`, `vim.treesitter`) and
[`lib.nvim`](https://github.com/StefanBartl/lib.nvim).

```lua
{
  "StefanBartl/documentation.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  cmd = { "DocMap", "DocBrowse" },
  opts = {},
}
```

`opts = {}` is enough: with no `root`, the commands map the current working
directory and `documentation.config` derives `source` from it (`lua/<name>`
when `lua/` holds exactly one candidate directory, `lua` otherwise).

Nothing registers a command until `setup()` runs — `require("documentation")`
alone never touches the user's editor, so a plugin can embed the pipeline
without also taking the commands.

## Configuration

Every option is a plain field on `Documentation.Opts`; the full list with
per-field documentation is in
[`lua/documentation/@types/init.lua`](lua/documentation/@types/init.lua).

```lua
{
  "StefanBartl/documentation.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  cmd = { "DocMap", "DocBrowse" },
  opts = {
    root = "/path/to/my-plugin",       -- default: vim.fn.getcwd()
    source = "lua/myplugin",           -- default: auto-detected under lua/
    title = "myplugin.nvim",           -- default: the root directory's name
    out_dir = "docs/map",
    repo_url = "https://github.com/me/my-plugin",
    branch = "main",

    luals = false,        -- opt-in LuaLS enrichment: @class/@alias detail,
                          -- type and inheritance edges. Costs seconds.
    badge = false,        -- also write coverage.svg
    tests_dir = "docs/TESTS",          -- auto-derived `fn.tested`
    dead_code = false,    -- widen `dead-function` to published functions too
    calls_heuristic = false,           -- guessed call edges, drawn dashed
    layers = {},          -- module-prefix layering rules
    tag_files = {},       -- cross-project links, Doxygen TAGFILES-style
    extra_checks = {},    -- your own drift checks
    command_name = "DocMap",
    browse_command_name = "DocBrowse",
  },
}
```

## Commands

Full reference: [docs/COMMANDS.md](docs/COMMANDS.md).

```vim
:DocMap                          " regenerate
:DocMap check                    " verify without writing -> quickfix
:DocMap full                     " regenerate WITH LuaLS enrichment
:DocMap open                     " open the HTML in the system browser
:DocMap graph deps               " …opened on the dependency graph
:DocMap graph calls my.module    " …on one module's call graph
:DocMap why my.a my.b            " shortest require path between two -> quickfix
:DocMap dot deps                 " the require graph as Graphviz DOT, in a buffer
:DocMap diff HEAD~5              " what changed about the tree's shape
:DocMap impact                   " …and where the changed lines radiate to
:DocMap churn                    " churn x complexity, hottest first -> quickfix
:DocMap churn HEAD~200..         " …over one range instead of all history
:DocMap serve                    " local map server (enables the History tab)

:DocBrowse                       " navigate the map inside the editor
:DocBrowse live                  " …re-scanning on every write
:DocBrowse my.module             " …opened on one module
:DocBrowse history               " …opened on the commit list
:DocBrowse trail                 " …opened on the pinned positions
```

Inside `:DocBrowse`, `?` shows the keys for the current mode. It renders from
the same table the browser installs its keys from, so it cannot drift from
them; keys the current mode ignores are marked rather than hidden.

`p` pins the entry under the cursor and `6` lists what has been pinned — a
**trail**, deliberately separate from `<C-o>`/`<C-i>`. The history stack
answers "where was I a moment ago"; a trail answers "where do I want to get
back to". A pin restores the whole view it was taken in, not just its subject.

Trails persist across Neovim restarts, in
`stdpath("state")/documentation.nvim/trails.json` — navigation state, never the
repository. `S` saves the current trail under a name, `L` loads one back
(adding to what is already pinned, never replacing it) and `X` forgets one.

`f` narrows the list on screen in place — `fs bar` for both terms, `"open url"`
for a phrase, `-spec` to exclude. Deliberately not `/`, which fuzzy-jumps
across the whole tree: this matches plain substrings, so `-spec` means nothing
containing "spec" survives. The status line always shows an active filter and
its hidden count, and `gq` exports what is on screen.

## Health

```vim
:checkhealth documentation
```

Checks the dependencies and the treesitter Lua parser, and then the part worth
running it for: the configuration a `:DocMap` issued right now would act on —
the resolved root, the auto-detected `source`, how many `.lua` files are
actually under it, and whether the committed map has fallen behind the sources.

`:DocMap` defaults its root to the current working directory, so "it mapped the
wrong repository" and "it says my tree has one module" are the same mistake
seen from two angles, and neither is visible from the command's own output.

## Headless / CI

```bash
nvim --headless -l scripts/gen_map.lua                    # regenerate
nvim --headless -l scripts/gen_map.lua --check            # stale or drift -> exit 1
nvim --headless -l scripts/gen_map.lua --check --lenient  # fail on staleness only
nvim --headless -l scripts/gen_map.lua --full             # + LuaLS enrichment
```

`--check` regenerates in memory and compares byte for byte; it writes nothing.
Output is deterministic across runs on unchanged input — no timestamp in the
IR, sorted-key JSON — which is the whole reason a byte comparison is a usable
staleness test.

Every gate CI runs, in one command:

```bash
scripts/ci.sh
```

To use it in your own plugin, copy two files and edit five lines:
[docs/REUSE.md](docs/REUSE.md).

## Live handle instead of files

`generate()` is one-shot. `install()` is the other half — a live
`Documentation.Handle` another plugin's code reaches for directly, instead of
parsing `module_map.json` off disk:

```lua
local handle = require("documentation").install({
  root = vim.fn.getcwd(),
  source = "lua/myplugin",
  watch = true,      -- rescan on BufWritePost under source/**.lua, debounced
})

handle.ir()                                -- current IR, in memory
handle.requires("lua/myplugin/fs")         -- require edges out
handle.callers("lua/myplugin/fs#M.read")   -- call edges in
handle.on_change(function(ir, findings) end)
handle.uninstall()
```

## Drift checks

The rendered map is the visible half; the checks are the half that catches
bugs. `missing-module-tag` and `module-path-mismatch` are errors;
`missing-summary`, `dead-readme-link`, `dead-see-target`, `require-cycle`,
`require-not-declared` and `layer-violation` are warnings; `missing-readme`, `unreferenced-module`,
`undocumented-param`, `param-name-mismatch` and `dead-function` are
informational. Each one's reasoning — especially `dead-function`'s, which has
to survive the fact that a library is *made of* functions with no internal
caller — is in [docs/PIPELINE.md § Drift checks](docs/PIPELINE.md#drift-checks).

Repository-specific checks go in `opts.extra_checks`.

## Documentation

| Document | Covers |
|---|---|
| [docs/PIPELINE.md](docs/PIPELINE.md) | Every stage, every design decision, and the measurement behind each one. |
| [docs/COMMANDS.md](docs/COMMANDS.md) | `:DocMap` and `:DocBrowse`, subcommand by subcommand. |
| [docs/REUSE.md](docs/REUSE.md) | Generating a map for your own plugin. |
| [docs/ANNOTATIONS.md](docs/ANNOTATIONS.md) | Which LuaCATS tags the scanner reads, and the two custom ones. |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Running the specs, the linters and the map locally. |
| [docs/ROADMAP/](docs/ROADMAP/) | [FEATURES.md](docs/ROADMAP/FEATURES.md) — what shipped and why it was built that way. [ROADMAP.md](docs/ROADMAP/ROADMAP.md) — what is open, and what was considered and turned down (with the condition that would reopen it). |
| [lua/documentation/browse/README.md](lua/documentation/browse/README.md) | The editor-side browser in detail. |
| `:help documentation.nvim` | The same, in Vim help format. |

## License

MIT. See [LICENSE](LICENSE).
