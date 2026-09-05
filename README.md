> **Alpha stage — active development.** This repository is in its development phase — breaking changes are to be expected at any time. Pin a commit or tag if you depend on it.

# documentation.nvim

```
     _                                        _        _   _
  __| | ___   ___ _   _ _ __ ___   ___ _ __ | |_ __ _| |_(_) ___  _ __
 / _` |/ _ \ / __| | | | '_ ` _ \ / _ \ '_ \| __/ _` | __| |/ _ \| '_ \
| (_| | (_) | (__| |_| | | | | | |  __/ | | | || (_| | |_| | (_) | | | |
 \__,_|\___/ \___|\__,_|_| |_| |_|\___|_| |_|\__\__,_|\__|_|\___/|_| |_|
                                                                  .nvim
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-alpha-red)
[![CI](https://github.com/StefanBartl/documentation.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/StefanBartl/documentation.nvim/actions/workflows/ci.yml)

> **know your project**

> Pairs with [**lib.nvim**](https://github.com/StefanBartl/lib.nvim) — the
> utility library this grew out of and still builds on. If you are mapping a
> tree, you are probably about to want its `fs`, `ui.kit` and `usercmd` modules
> too; this plugin uses exactly those.
>
> Two companions complete the triangle:
> [`runtime-analysis.nvim`](https://github.com/StefanBartl/runtime-analysis.nvim)
> extends this plugin with live call-count telemetry from inside a running
> Neovim session — install it and the Telemetry/Loaded tabs below stop
> saying "no data".
> [`docmap-desktop`](https://github.com/StefanBartl/docmap-desktop) is the
> third leg, the same map read entirely outside Neovim, for anyone not
> sitting in the editor.

Point it at a repository and it produces a **module map**: an interactive
HTML page, a Markdown overview, a deterministic JSON artifact, and a set of
drift checks that fail CI when the documentation and the code stop agreeing.

It reads **twenty-three languages** — Lua, JavaScript, TypeScript, TSX,
Python, Ruby, PHP, C#, Go, Rust, Kotlin, Swift, Dart, Scala, Haskell,
Elixir, Erlang, OCaml, Zig, Java, C, C++ and assembly — through one backend
contract, so a tree that mixes them
comes out as one map rather than several. See
[Languages](#languages).

```vim
:DocMap          " regenerate the artifacts
:DocMap check    " verify without writing — findings go to the quickfix list
:DocMap open     " open the generated page in the browser
:DocBrowse       " navigate the same map inside the editor
```

Grew inside [`lib.nvim`](https://github.com/StefanBartl/lib.nvim) as
`lib.nvim.docmap` and was extracted once it had nothing left to do with
lib.nvim. See [docs/pipeline.md § Why this is its own
plugin](docs/pipeline.md#why-this-is-its-own-plugin).

## Table of Contents

- [What it produces](#what-it-produces)
- [Languages](#languages)
- [Installation](#installation)
- [Configuration](#configuration)
- [Commands](#commands)
- [Health](#health)
- [Headless, CI, and someone else's repository](#headless-ci-and-someone-elses-repository)
- [A live handle, an MCP server, a desktop app](#a-live-handle-an-mcp-server-a-desktop-app)
- [Drift checks](#drift-checks)
- [Documentation](#documentation)

## What it produces

| Artifact | What it is |
|---|---|
| `docs/map/index.html` | The interactive map: **Hierarchy**, **Index** (Tree / Functions / Modules), **Analysis**, **Compare**, **Features**, **Quicks**, **Notes**, **History** and **Findings** tabs. Self-contained — no CDN, no build step. |
| `docs/map/overview.md` | The same tree as Markdown, so it renders on GitHub. |
| `docs/map/module_map.json` | The IR, byte-deterministic. What `--check` compares and what `:DocMap diff` reads out of old commits. |
| `docs/map/coverage.svg` | Optional (`opts.badge`): a doc-coverage badge, hand-rolled, no network call. |
| `docs/map/overview.pdf` | Optional (`opts.pdf`): the same content as `overview.md`, via [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) (optional dependency). |

**Every one of these is a snapshot of the version that wrote it.** The page
is generated, not rendered live, so a tab or a panel that arrived in a
later release of this plugin reaches an existing map by *regenerating* it —
never by updating the plugin alone. That is the price of an artifact you
can commit, open offline and diff, and it is worth stating once rather than
being discovered.

This repository maps itself with the same tool, and publishes the result:
**<https://stefanbartl.github.io/documentation.nvim/>**. [docs/map/overview.md](docs/map/overview.md)
is the same tree as Markdown, rendered straight on GitHub.

The published copy is honest about what it can answer: Hierarchy, Index,
Analysis, Notes, Quicks and Compare need no server and work fully; History,
Telemetry and Loaded are computed on demand from git and from runtime data on
the machine that ran the scan, and say so when opened there. See
[docs/reuse.md § Linking to your own map from your README](docs/reuse.md#linking-to-your-own-map-from-your-readme)
to do the same in a plugin that depends on this one.

The tour of what each of those tabs shows, and why, is
[docs/tabs.md](docs/tabs.md); how each one is computed is
[docs/pipeline.md](docs/pipeline.md).

## Languages

Twenty-three backends behind one contract, so a repository that mixes them
produces one map rather than several — Lua, JavaScript, TypeScript, TSX,
Python, Ruby, PHP, C#, Go, Rust, Kotlin, Swift, Dart, Scala, Haskell, Elixir,
Erlang, OCaml, Zig, Java, C, C++ and assembly. A backend answers the same five
questions — which files it claims, where its sources live, what documents a
file, what documents a declaration, and what makes a declaration public — and
the map does not care which language answered.

The fourth of those is the one place these languages genuinely disagree rather
than merely differing in syntax: Go's visibility is capitalisation and the
compiler enforces it, while Lua reads an authoring convention (`@internal`)
that is a claim rather than a fact. Both are honest, and they are not the same
strength of evidence.

[docs/languages.md](docs/languages.md) has the per-language table, the
`Documentation.LangBackend` contract field by field, the measured parity
matrix, what a missing grammar costs, and what adding the twenty-fourth
actually takes.

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

Load it **lazily on the two commands**: `setup()` scans the tree, and a session
that never opens a map should not pay for one.

`opts = {}` is enough. With no `root`, the commands resolve one **per
invocation** from the file behind the current buffer — so opening a file in a
sibling checkout and running `:DocMap` maps *that* checkout. Set `root` to pin
every invocation to one tree instead, which is what a plugin generating its own
map wants.

vim.pack, mini.deps, packer and paq are in
[docs/installation.md](docs/installation.md), with the reason each one needs a
different lazy-loading shape.

## Configuration

Every option is a plain field on `Documentation.Opts`, and a repository can
state the ones that are facts about *itself* — `source`, `exclude`, `repo_url`,
`layers`, `checks` — in a `.docmap.json` at its root, which every host reads:
the Neovim plugin, the standalone binary, the GitHub Action and
`docmap-desktop`.

The full table, the `.docmap.json` precedence rules, switching a check off or
re-grading it, and rebinding `:DocBrowse`'s keys by *action* rather than by
key: [docs/configuration.md](docs/configuration.md).

## Commands

```vim
:DocMap                          " regenerate
:DocMap check                    " verify without writing -> quickfix
:DocMap open                     " open the HTML in the system browser
:DocMap why my.a my.b            " shortest require path between two -> quickfix
:DocMap pick                     " fuzzy-find any module or function
:DocMap diff HEAD~5              " what changed about the tree's shape
:DocMap churn                    " churn x complexity, hottest first
:DocMap serve                    " local map server (enables the History tab)

:DocBrowse                       " navigate the same map inside the editor
:DocBrowse live                  " …re-scanning on every write
```

Twenty-one `:DocMap` actions in all, and five ways to open `:DocBrowse`:
[docs/commands.md](docs/commands.md). Inside the browser, `?` shows the keys
for the current mode, rendered from the same table the keys are installed from,
so it cannot drift from them. Day-to-day use — which panel answers which
question, Trail versus filter versus fuzzy jump — is
[docs/WORKFLOW.md](docs/WORKFLOW.md).

## Health

```vim
:checkhealth documentation
```

Checks the dependencies and the treesitter Lua parser, and then the part worth
running it for: the configuration a `:DocMap` issued right now would act on —
the resolved root, the detected `source`, how many files are under it, and
whether the committed map has fallen behind the sources. Details, including the
declared external tools: [docs/health.md](docs/health.md).

## Headless, CI, and someone else's repository

```bash
nvim --headless -l scripts/gen_map.lua --check   # stale or drift -> exit 1
```

`--check` regenerates in memory and compares byte for byte; it writes nothing.
Output is deterministic on unchanged input — no timestamp in the IR,
sorted-key JSON — which is what makes a byte comparison a usable staleness
test.

On GitHub, adopting the check copies nothing: `action.yml` lives at this
repository's root, so `uses: StefanBartl/documentation.nvim@main` is the whole
integration. The editor, CI and pre-commit-hook shapes, and what a tree has to
look like for any of them: [docs/reuse.md](docs/reuse.md).

## A live handle, an MCP server, a desktop app

`generate()` writes the artifacts once. `install()` hands back a live
`Documentation.Handle` another plugin's code reads instead of parsing
`module_map.json` off disk — with optional rescan-on-write, native
call-hierarchy support (which LuaLS itself does not have) and drift findings as
`vim.diagnostic` entries. See [docs/api.md](docs/api.md).

The same handle reaches an agent that speaks
[MCP](https://modelcontextprotocol.io) — nine read-only tools over stdio, so
the agent asks *what calls this function* instead of grepping for the name and
guessing which hits are real. None of them writes `@verified`, which is
load-bearing rather than incidental: [docs/mcp.md](docs/mcp.md).

[`docmap-desktop`](https://github.com/StefanBartl/docmap-desktop) hosts
generated maps for several projects side by side for anyone not sitting in
Neovim, over a real `http://127.0.0.1` origin — so the Telemetry and Loaded
panels work there exactly as they do in the editor.

## Drift checks

The rendered map is the visible half; the checks are the half that catches
bugs. Two are errors (`missing-module-tag`, `module-path-mismatch`), twelve are
warnings and eight are informational, and each one's reasoning — especially
`dead-function`'s, which has to survive the fact that a library is *made of*
functions with no internal caller — is in
[docs/pipeline.md § Drift checks](docs/pipeline.md#drift-checks). Switch one
off or re-grade it in `opts.checks`; add your own in `opts.extra_checks`.

## Documentation

**Start at [docs/README.md](docs/README.md)** — the folder's own index, grouped
by the question you arrived with. The four to reach for first:

| Document | Covers |
|---|---|
| [docs/pipeline.md](docs/pipeline.md) | Every stage, every design decision, and the measurement behind each one. **The document to read before changing anything.** |
| [docs/commands.md](docs/commands.md) | `:DocMap` and `:DocBrowse`, subcommand by subcommand. |
| [docs/reuse.md](docs/reuse.md) | Generating a map for your own plugin — including the GitHub Action, which requires copying nothing. |
| [docs/languages.md](docs/languages.md) | The twenty-three backends, as a reference and as a contract. |

`:help documentation.nvim` is the same ground in Vim help format.

## License

MIT — see [LICENSE](LICENSE).
