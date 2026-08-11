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

## Table of Contents

- [What it produces](#what-it-produces)
- [Installation](#installation)
- [Configuration](#configuration)
- [Commands](#commands)
- [Health](#health)
- [Headless / CI](#headless--ci)
- [Live handle instead of files](#live-handle-instead-of-files)
- [Drift checks](#drift-checks)
- [Documentation](#documentation)

## What it produces

| Artifact | What it is |
|---|---|
| `docs/map/index.html` | The interactive map: **Quicks**, **Tree**, **Hierarchy**, **Notes**, **Index**, **History**, **Analysis**, **Compare** and **Features** tabs. Self-contained — no CDN, no build step. |
| `docs/map/overview.md` | The same tree as Markdown, so it renders on GitHub. |
| `docs/map/module_map.json` | The IR, byte-deterministic. What `--check` compares and what `:DocMap diff` reads out of old commits. |
| `docs/map/coverage.svg` | Optional (`opts.badge`): a doc-coverage badge, hand-rolled, no network call. |
| `docs/map/overview.pdf` | Optional (`opts.pdf`): the same content as `overview.md`, via [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) (optional dependency). |

This repository maps itself with the same tool: **[docs/map/overview.md](docs/map/overview.md)**
renders straight on GitHub, no Pages required. `docs/map/index.html` is the
richer interactive version — open it locally, or see
[docs/REUSE.md § Linking to your own map from your README](docs/REUSE.md#linking-to-your-own-map-from-your-readme)
for the same pointer in a plugin that depends on this one.

The Analysis tab ranks the tree eight ways, seven of them over the same IR —
test coverage, documentation coverage, fan-in/fan-out, cyclomatic complexity,
structural **duplicates** (functions whose parse-tree shape is identical,
which is the one kind of drift the require graph is blind to by construction
— two modules that each grew their own `read(path)` do not require each
other), **plugins**: every lazy.nvim spec in the tree, which matters when
`documentation.nvim` is pointed at a Neovim *config* rather than a plugin —
`lua/plugins/*.lua` is mostly `return { { "author/repo", event = "…" } }`
with no function in sight, invisible to every other panel — and **tools**:
this repo's own [`lib.nvim.deps`](https://github.com/StefanBartl/lib.nvim)
manifest (`docs/install.json`/`docs/INSTALL.md`), declared only — never a
live "is this installed here" probe, since a static page has no host to
ask. The eighth, **telemetry**, is the odd one out on purpose: call counts
change between runs, so unlike the other seven it is never baked into the
page — `:DocMap serve` reads [`runtime-analysis.nvim`](https://github.com/StefanBartl/runtime-analysis.nvim)'s
own counts fresh on every open instead, the same on-demand shape the
History tab already uses for the one other thing that cannot live in a
static artifact.

The Hierarchy tab draws six graphs over the same IR — **Modules** (directory
hierarchy), **Types** (`@class`/`@alias` collaboration), **Inheritance**,
**Deps** (the require graph), **Calls** (function-level caller/callee) and
**Module Calls** (the same call graph collapsed module-to-module, edges
weighted by call count) — with direction and depth controls, semantic zoom,
right-click navigation and real browser Back/Forward. Right-click any box to
dim it (a "Hidden (N) — show all" pill clears them), shareable via the URL
the same way marks are — noise-reduction for a large tree, not a structural
re-layout. The Modules view also has a vertical zoom-style slider that hides
the top N levels of a deep tree, turning every node that used to sit at that
depth into its own parallel root — useful the moment a tree is several
directories deep before anything interesting starts.

The Deps and Module Calls views' `+ external` toggle answers *why* a
dependency is there, not just that it is: each external box's tooltip
breaks down exactly which functions were actually called and how often
(`plenary.async.run (2×)`), counted from the same call-resolution pass as
the internal call graph — no
second traversal. `opts.external_repos` turns the box into a working GitHub
link too, verified against a local checkout when you name one (`opts.tag_files`
does the same for another `docmap`-shaped project's own committed map).

The **Quicks** tab states the same tree in sentences instead of tables — *"Most
of your published API is never named in a spec — 12% — 9 of 72"* — negatives
first, five of each polarity. Every verdict carries a line saying what was
actually measured, including its blind spot, and links to the panel holding the
rows it came from; a number that sounds this confident has to be checkable, or
it breaks the same rule `calls_heuristic` and `dead_code` are off by default to
keep. A verdict appears only when it passes one of two cut points, so an empty
Quicks tab means every measure landed in the unremarkable band — a good
reading, not a broken one. Purity is deliberately *not* among them: nothing in
the IR records side effects, and the cheap approximations would be exactly the
confident guess this plugin refuses elsewhere.

The **Compare** tab holds whatever you marked with the `+` beside any function
or module. Its Matrix layout puts attributes down the side and marked objects
across, highlighting every row where they disagree — *"where do these four
differ"* has no other answer on the page. Marks travel in the URL and survive a
reload; a negative Quicks verdict offers **Mark all N** straight into it.

The **Features** tab reads a repo's own `docs/FEATURES/` folder, when it has
one — one card per `## Feature` section, its summary and whatever
`- **Key:** value` metadata the author wrote (`Module`, `Keymaps`, `Config`,
or anything else; there is no fixed vocabulary). An index over hand-written
prose, not a Markdown viewer — a `Module:` bullet that resolves to a real
node links straight into the Tree tab, the rest of the file stays exactly
where the author put it. A `- **Tab:** true` bullet promotes the rare,
especially-important feature out of the card list entirely and into its own
top-level tab, with everything after its metadata rendered through a small
Markdown subset instead of just linked out to. See
[`docs/FEATURES_FORMAT.md`](docs/FEATURES_FORMAT.md) for the format this
tab reads, and this repository's own [`docs/FEATURES/`](docs/FEATURES) for
a real (if deliberately small) example — including one promoted feature.

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

`opts = {}` (or a bare `setup({})`) is enough: with no `root`, the commands
resolve one **per invocation** from the file behind the current buffer — up to
the nearest `.git` — and `documentation.config` derives `source` from it
(`lua/<name>` when `lua/` holds exactly one candidate directory, `lua`
otherwise). Open a file in a sibling checkout and the next `:DocMap` maps that
checkout; both commands name the repository they acted on in their report. Set
`root` explicitly to pin every invocation to one tree instead, which is what a
plugin generating its own map wants.

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
    root = "/path/to/my-plugin",       -- default: resolved per invocation
                                       -- from the current buffer's repository
    root_markers = { ".git" },         -- how that resolution finds it
    source = "lua/myplugin",           -- default: auto-detected under lua/
    title = "myplugin.nvim",           -- default: the root directory's name
    out_dir = "docs/map",
    repo_url = "https://github.com/me/my-plugin",
    branch = "main",

    luals = false,        -- opt-in LuaLS enrichment: @class/@alias detail,
                          -- type and inheritance edges. Costs seconds.
    badge = false,        -- also write coverage.svg
    pdf = false,           -- also write overview.pdf (needs pdfport.nvim,
                           -- optional dependency; async, reported separately)
    tests_dir = "TESTS",  -- auto-derived `fn.tested`
    dead_code = false,    -- widen `dead-function` to published functions too
    calls_heuristic = false,           -- guessed call edges, drawn dashed
    layers = {},          -- module-prefix layering rules
    tag_files = {},       -- cross-project links, Doxygen TAGFILES-style
    external_repos = {},  -- GitHub links for third-party deps (module-prefix
                           -- -> "owner/repo", verified against a local
                           -- checkout when you name one)
    extra_checks = {},    -- your own drift checks
    command_name = "DocMap",
    browse_command_name = "DocBrowse",

    which_key = true,     -- register :DocBrowse's keys with which-key when
                          -- it is installed; a no-op when it is not
    keys = {},            -- rebind or disable :DocBrowse's keys, by action

    telemetry = true,      -- self-instrument this tree with runtime-
                            -- analysis.telemetry when it is installed; a
                            -- no-op when it is not. Set false to opt out.
    telemetry_namespace = nil,  -- default: opts.title -- the namespace both
                                -- this and :DocBrowse's telemetry mode use
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
:DocMap annotate                 " preview a ---@module header for every undocumented file
:DocMap annotate --write         " …and write it in place
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
:DocMap tools                    " this repo's own lib.nvim.deps manifest -> quickfix
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

With no `root` set, `:DocMap` resolves one from the current buffer, so "it
mapped the wrong repository" and "it says my tree has one module" are the same
mistake seen from two angles. The command's report names the repository it
acted on; this check shows the same answer before anything is written.

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
  watch = true,          -- rescan on BufWritePost under source/**.lua, debounced
  callhierarchy = true,  -- native in/outgoing-calls LSP support, alongside LuaLS
  diagnostics = true,    -- drift findings as vim.diagnostic, not only :DocMap check
})

handle.ir()                                -- current IR, in memory
handle.requires("lua/myplugin/fs")         -- require edges out
handle.callers("lua/myplugin/fs#M.read")   -- call edges in
handle.on_change(function(ir, findings) end)
handle.uninstall()
```

`callhierarchy = true` attaches a second, narrow LSP client alongside
whatever real language server is already there — off by default, costs no
new scan, answers only `textDocument/prepareCallHierarchy`/`callHierarchy/
incomingCalls`/`outgoingCalls` and a caller/callee count on hover. Built
because LuaLS itself has no call-hierarchy support at all (verified against
its source, and its own two-years-open feature request); Neovim's own
`vim.lsp.buf.incoming_calls()`/`hover()` already merge results from every
attached client, no new keybinding needed.

`diagnostics = true` publishes the same drift findings `:DocMap check`
already computes as native `vim.diagnostic` entries — a wavy underline and
sign-column mark while reading, not a separate list to open. No new LSP
client needed here at all, unlike `callhierarchy`: `vim.diagnostic.set()`
works directly on any already-open buffer. File-level granularity, the
same the quickfix list already has (`Documentation.Finding` carries no
line number); `info`-severity findings map to `vim.diagnostic.severity.HINT`
and are shown, where the quickfix list drops them.

`godbolt = true` (**experimental**, `generate()`-time, not `install()`) adds
a "⚙ Compiler Explorer ↗" link next to every module and function in the
generated page — a real `luac -l -l -p` bytecode disassembly, verified
against Compiler Explorer's own API and compiler source (`lua` is a real
language there, with five real interpreter versions), not a workaround.
Built entirely client-side from each function's already-serialized
`fn.snippet`, no new IR field; a module's own link concatenates its
functions' snippets, an approximation of the file rather than a
byte-perfect one, which is why this ships marked experimental.

## MCP server — the map as tools for a coding agent

The same `Documentation.Handle`, reachable from outside Neovim by an agent
that speaks [MCP](https://modelcontextprotocol.io):

```
nvim --headless -l scripts/mcp_server.lua
```

An MCP client spawns that as a subprocess and talks JSON-RPC over its
stdin/stdout — nothing listens on a port and nothing authenticates, because
with stdio the client *is* the parent process. Nine tools: `docmap_modules`,
`docmap_node`, `docmap_requires`, `docmap_required_by`, `docmap_callers`,
`docmap_callees`, `docmap_findings`, `docmap_rescan`, `docmap_checklist`. Each
is a projection of a handle method — the agent asks "what calls this
function" instead of grepping for the name and guessing which hits are real.
`docmap_checklist` is read-only in a way that is load-bearing rather than
incidental: no tool in this catalogue writes `@verified`, so an agent cannot
mark its own work as verified.

Client configuration, the tool table, and the five decisions worth knowing
about (why file watching is off, why no tool returns a raw IR node, why a
failing tool is a *result* rather than a transport error, why there is no
verify tool) are in [docs/MCP.md](docs/MCP.md).

## Drift checks

The rendered map is the visible half; the checks are the half that catches
bugs. `missing-module-tag` and `module-path-mismatch` are errors;
`missing-summary`, `dead-readme-link`, `dead-see-target`, `type-vs-class`,
`doc-references-missing`, `require-cycle`, `require-not-declared` and
`layer-violation` are warnings; `missing-readme`, `unreferenced-module`,
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
| [docs/WORKFLOW.md](docs/WORKFLOW.md) | Using it day to day: which panel answers which question, reading the Telemetry join's badges correctly, Trail vs filter vs fuzzy jump. |
| [docs/REUSE.md](docs/REUSE.md) | Generating a map for your own plugin. |
| [docs/CHECKLIST_FORMAT.md](docs/CHECKLIST_FORMAT.md) | The hand-verified ledger: a syntax for facts a scanner cannot decide, watched for staleness by their citation rather than re-derived. |
| [docs/CALL_HIERARCHY.md](docs/CALL_HIERARCHY.md) | Incoming/outgoing calls in Neovim, alongside LuaLS (which has none): setup, keymaps, and how to tell an unattached client from a function with no callers. |
| [docs/MCP.md](docs/MCP.md) | The MCP server: exposing the module tree, require graph, call graph and drift findings to a coding agent as tools. |
| [docs/ROADMAP/V1_EXTENSION/PORTABILITY.md](docs/ROADMAP/V1_EXTENSION/PORTABILITY.md) | Mapping a Lua project that is not a Neovim plugin — and what a Neovim-free port would actually cost. |
| [docs/ROADMAP/MULTILANG.md](docs/ROADMAP/MULTILANG.md) | What supporting other languages would take, and how much of the code survives it. |
| [docs/FRAMEWORK_CONVENTIONS.md](docs/FRAMEWORK_CONVENTIONS.md) | The layer above language support — recognizing one ecosystem's structural convention (lazy.nvim specs today; Next.js-style file routing and React hooks costed as the web-ecosystem case). |
| [docs/ECOSYSTEM.md](docs/ROADMAP/FEATURES/ECOSYSTEM.md) | **Architectural concept**, agreed, nothing implemented: where docs cross-references, API-endpoint inventory, hover previews and an API request runner each belong — and why the runtime half is its own plugin (`runtime-analysis.nvim`), a Neovim plugin rather than a binary, meeting this one in the editor rather than in the committed artifact. |
| [docs/ANNOTATION_TAGS.md](docs/ANNOTATION_TAGS.md) | **Annotating your own plugin**: what each tag buys you here, the minimum viable set, and which custom tags would be worth adding. |
| [docs/ANNOTATIONS.md](docs/ANNOTATIONS.md) | The inventory — which LuaCATS tags this tree actually uses, counted. |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Running the specs, the linters and the map locally. |
| [docs/ROADMAP/](docs/ROADMAP/) | [FEATURES.md](docs/ROADMAP/FEATURES/FEATURES.md) — what shipped and why it was built that way. [ROADMAP.md](docs/ROADMAP/ROADMAP.md) — what is open, and what was considered and turned down (with the condition that would reopen it). |
| [lua/documentation/editor/browse/README.md](lua/documentation/editor/browse/README.md) | The editor-side browser in detail. |
| `:help documentation.nvim` | The same, in Vim help format. |
