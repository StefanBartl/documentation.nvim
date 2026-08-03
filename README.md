```
     _                                        _        _   _
  __| | ___   ___ _   _ _ __ ___   ___ _ __ | |_ __ _| |_(_) ___  _ __
 / _` |/ _ \ / __| | | | '_ ` _ \ / _ \ '_ \| __/ _` | __| |/ _ \| '_ \
| (_| | (_) | (__| |_| | | | | | |  __/ | | | || (_| | |_| | (_) | | | |
 \__,_|\___/ \___|\__,_|_| |_| |_|\___|_| |_|\__\__,_|\__|_|\___/|_| |_|
                                                                  .nvim
```

[![CI](https://github.com/StefanBartl/documentation.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/StefanBartl/documentation.nvim/actions/workflows/ci.yml)
![Neovim 0.10+](https://img.shields.io/badge/Neovim-0.10%2B-57A143?logo=neovim&logoColor=white)
![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)

> Pairs with [**lib.nvim**](https://github.com/StefanBartl/lib.nvim) — the
> utility library this grew out of and still builds on. If you are mapping a
> tree, you are probably about to want its `fs`, `ui.kit` and `usercmd` modules
> too; this plugin uses exactly those.

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

The Analysis tab ranks the tree six ways over the same IR — test coverage,
documentation coverage, fan-in/fan-out, cyclomatic complexity, structural
**duplicates** (functions whose parse-tree shape is identical, which is the one
kind of drift the require graph is blind to by construction — two modules that
each grew their own `read(path)` do not require each other), and **plugins**:
every lazy.nvim spec in the tree, which matters when `documentation.nvim` is
pointed at a Neovim *config* rather than a plugin — `lua/plugins/*.lua` is
mostly `return { { "author/repo", event = "…" } }` with no function in sight,
invisible to every other panel.

The Hierarchy tab draws five graphs over the same IR — **Modules** (directory
hierarchy), **Types** (`@class`/`@alias` collaboration), **Inheritance**,
**Deps** (the require graph) and **Calls** (function-level caller/callee) —
with direction and depth controls, semantic zoom, right-click navigation and
real browser Back/Forward.

## Installation

Requires Neovim 0.10+ (`vim.uv`, `vim.treesitter`) and
[`lib.nvim`](https://github.com/StefanBartl/lib.nvim).

<details open>
<summary><b>lazy.nvim</b></summary>

```lua
{
  "StefanBartl/documentation.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  cmd = { "DocMap", "DocBrowse" },
  opts = {},
}
```
</details>

<details>
<summary><b>vim.pack</b> (Neovim 0.12+, built in)</summary>

```lua
vim.pack.add({
  { src = "https://github.com/StefanBartl/lib.nvim" },
  { src = "https://github.com/StefanBartl/documentation.nvim" },
})

-- No lazy-loading layer here, so do it by hand: create the commands on first
-- use rather than at startup. `setup()` scans the tree, which is not something
-- to pay for in every session that never opens a map.
for _, name in ipairs({ "DocMap", "DocBrowse" }) do
  vim.api.nvim_create_user_command(name, function(a)
    vim.api.nvim_del_user_command("DocMap")
    vim.api.nvim_del_user_command("DocBrowse")
    require("documentation").setup({})
    vim.cmd(("%s %s"):format(name, a.args))
  end, { nargs = "*" })
end
```
</details>

<details>
<summary><b>mini.deps</b></summary>

```lua
local add, later = MiniDeps.add, MiniDeps.later
add({
  source = "StefanBartl/documentation.nvim",
  depends = { "StefanBartl/lib.nvim" },
})
later(function()
  require("documentation").setup({})
end)
```
</details>

<details>
<summary><b>packer.nvim</b></summary>

```lua
use({
  "StefanBartl/documentation.nvim",
  requires = { "StefanBartl/lib.nvim" },
  cmd = { "DocMap", "DocBrowse" },
  config = function()
    require("documentation").setup({})
  end,
})
```
</details>

<details>
<summary><b>paq-nvim</b> / manual <code>rtp</code></summary>

```lua
require("paq")({
  "StefanBartl/lib.nvim",
  "StefanBartl/documentation.nvim",
})

-- paq does no lazy-loading and runs no config hooks:
require("documentation").setup({})
```
</details>

`opts = {}` (or a bare `setup({})`) is enough: with no `root`, the commands map
the current working directory and `documentation.config` derives `source` from
it (`lua/<name>` when `lua/` holds exactly one candidate directory, `lua`
otherwise).

Whichever manager you use, load it **lazily on the two commands**. `setup()`
scans the tree, and a session that never opens a map should not pay for one.

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
    tests_dir = "TESTS",  -- auto-derived `fn.tested`
    dead_code = false,    -- widen `dead-function` to published functions too
    calls_heuristic = false,           -- guessed call edges, drawn dashed
    layers = {},          -- module-prefix layering rules
    tag_files = {},       -- cross-project links, Doxygen TAGFILES-style
    extra_checks = {},    -- your own drift checks
    command_name = "DocMap",
    browse_command_name = "DocBrowse",

    which_key = true,     -- register :DocBrowse's keys with which-key when
                          -- it is installed; a no-op when it is not
    keys = {},            -- rebind or disable :DocBrowse's keys, by action
  },
}
```

### Rebinding the browser's keys

`opts.keys` is keyed by *action*, not by the default left-hand side, so a
rebinding survives a change of defaults. A string or a list replaces an
action's keys; `false` turns it off.

```lua
keys = {
  quickfix = "gQ",              -- one replacement key
  filter   = { "F", "<C-f>" },  -- several
  pin      = false,             -- off entirely
}
```

Every binding is buffer-local to the browser window, so a replacement only has
to be free *inside* `:DocBrowse` — not in your global keymap. A disabled action
still appears in the `?` cheatsheet, marked `(disabled)`, because "where did
`p` go" deserves an answer. An unknown action name is reported rather than
ignored.

The action names are the `id` fields of the `KEYS` table in
[`lua/documentation/editor/browse/init.lua`](lua/documentation/editor/browse/init.lua),
enumerated as `Documentation.Browse.KeyAction` in
[`lua/documentation/editor/browse/@types/init.lua`](lua/documentation/editor/browse/@types/init.lua):
`move`, `enter`, `up`, `back`, `forward`, `dir_in`, `dir_out`, `depth_inc`,
`depth_dec`, `goto_source`, `quickfix`, `impact`, `open_page`, `commit_diff`,
`pin`, `unpin`, `trail_save`, `trail_load`, `trail_delete`, `filter`, `search`,
`help`, `close`.

The mode-switch keys `1`…`6` are deliberately not rebindable: they are
positional (`3` means "the third list") and are generated from the mode list,
so renumbering them individually would desynchronise them from what the status
line shows.

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
:DocMap plugins                  " every lazy.nvim spec in the tree -> quickfix
:DocMap serve                    " local map server (enables the History tab)
:DocMap helptags                 " regenerate this plugin's own doc/tags

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
| [docs/PORTABILITY.md](docs/PORTABILITY.md) | Mapping a Lua project that is not a Neovim plugin — and what a Neovim-free port would actually cost. |
| [docs/MULTILANG.md](docs/MULTILANG.md) | What supporting other languages would take, and how much of the code survives it. |
| [docs/FRAMEWORK_CONVENTIONS.md](docs/FRAMEWORK_CONVENTIONS.md) | The layer above language support — recognizing one ecosystem's structural convention (lazy.nvim specs today; Next.js-style file routing and React hooks costed as the web-ecosystem case). |
| [docs/ECOSYSTEM.md](docs/ECOSYSTEM.md) | **Architectural concept**, agreed, nothing implemented: where docs cross-references, API-endpoint inventory, hover previews and an API request runner each belong — and why the runtime half is its own plugin (`runtime-analysis.nvim`), a Neovim plugin rather than a binary, meeting this one in the editor rather than in the committed artifact. |
| [docs/ANNOTATION_TAGS.md](docs/ANNOTATION_TAGS.md) | **Annotating your own plugin**: what each tag buys you here, the minimum viable set, and which custom tags would be worth adding. |
| [docs/ANNOTATIONS.md](docs/ANNOTATIONS.md) | The inventory — which LuaCATS tags this tree actually uses, counted. |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Running the specs, the linters and the map locally. |
| [docs/ROADMAP/](docs/ROADMAP/) | [FEATURES.md](docs/ROADMAP/FEATURES.md) — what shipped and why it was built that way. [ROADMAP.md](docs/ROADMAP/ROADMAP.md) — what is open, and what was considered and turned down (with the condition that would reopen it). |
| [lua/documentation/editor/browse/README.md](lua/documentation/editor/browse/README.md) | The editor-side browser in detail. |
| `:help documentation.nvim` | The same, in Vim help format. |
