> **Beta stage — active development.** This repository is past its first shape and in
> active use, but the surface is not frozen: breaking changes are still possible. Pin a
> commit or tag if you depend on it.

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
![Status](https://img.shields.io/badge/status-beta-orange)
[![CI](https://github.com/StefanBartl/documentation.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/StefanBartl/documentation.nvim/actions/workflows/ci.yml)

> **know your project**

Point it at a repository and it produces a **module map**: an interactive HTML
page, a Markdown overview, a deterministic JSON artifact, and a set of drift
checks that fail CI when the documentation and the code stop agreeing.

It reads **twenty-three languages** through one backend contract, so a tree that
mixes them comes out as one map rather than several.

---

## Table of contents

- [Documentation](#documentation)
- [What it does](#what-it-does)
- [Around it](#around-it)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quickstart](#quickstart)
- [What it produces](#what-it-produces)
- [Languages](#languages)
- [Configuration](#configuration)
- [Drift checks](#drift-checks)
- [Headless, CI, and someone else's repository](#headless-ci-and-someone-elses-repository)
- [A live handle, an MCP server, a desktop app](#a-live-handle-an-mcp-server-a-desktop-app)
- [Integrations](#integrations)
- [Health check](#health-check)
- [Contributing](#contributing)
- [Feedback](#feedback)
- [License](#license)

---

## Documentation

**Start at [docs/README.md](docs/README.md)** — the folder's own index, grouped by
the question you arrived with. The four to reach for first:

| Page | Answers |
| --- | --- |
| [docs/pipeline.md](docs/pipeline.md) | Every stage, every design decision, and the measurement behind each one. **The document to read before changing anything.** |
| [docs/commands.md](docs/commands.md) | `:DocMap` and `:DocBrowse`, subcommand by subcommand |
| [docs/reuse.md](docs/reuse.md) | Generating a map for your own plugin — including the GitHub Action, which requires copying nothing |
| [docs/languages.md](docs/languages.md) | The twenty-three backends, as a reference and as a contract |

And the rest:

- [Installation](docs/installation.md) — every plugin manager, with the reason each needs a different lazy-loading shape.
- [Configuration](docs/configuration.md) — every option, the `.docmap.json` precedence rules, and rebinding `:DocBrowse` by action rather than by key.
- [Tabs](docs/tabs.md) — what each panel of the generated page shows, and why.
- [Features](docs/FEATURES/README.md) — one page per area, with the reasoning behind each.
- [Lua API](docs/api.md) — `generate()`, `install()`, and the live `Documentation.Handle`.
- [MCP server](docs/mcp.md) — nine read-only tools over stdio, and why none of them writes.
- [Health](docs/health.md) — what `:checkhealth documentation` reports, including the declared external tools.
- [Bindings cheatsheet](docs/BINDINGS.md) — every keymap, user command and autocommand.
- [Workflow](docs/WORKFLOW.md) — which panel answers which question: Trail versus filter versus fuzzy jump.
- [Ecosystem](docs/ecosystem.md) — how this plugin, `runtime-analysis.nvim`, `mdview.nvim` and `docmap-desktop` fit together.
- [Development](docs/DEVELOPMENT.md) — the toolchain, and the five things CI runs.
- [Contributing](docs/CONTRIBUTING.md) — ground rules, project layout, and how to add a language backend.

`:help documentation.nvim` is the same ground in Vim help format.

---

## What it does

A repository knows its own shape — which modules exist, what requires what, what
is documented and what only claims to be. None of that is written down anywhere a
person or a CI job can read, so it is rediscovered by hand every time somebody
new opens the tree.

documentation.nvim writes it down, as an artifact you can commit, open offline
and diff:

```vim
:DocMap          " regenerate the artifacts
:DocMap check    " verify without writing — findings go to the quickfix list
:DocMap open     " open the generated page in the browser
:DocBrowse       " navigate the same map inside the editor
```

The map is generated, not rendered live. That is the whole trade: an artifact you
can commit and diff, at the price that a tab added in a later release reaches an
existing map by *regenerating* it, never by updating the plugin alone.

This repository maps itself with the same tool and publishes the result:
**<https://stefanbartl.github.io/documentation.nvim/>**.
[docs/map/overview.md](docs/map/overview.md) is the same tree as Markdown,
rendered straight on GitHub.

The published copy is honest about what it can answer: Hierarchy, Index,
Analysis, Notes, Quicks and Compare need no server and work fully; History,
Telemetry and Loaded are computed on demand from git and from runtime data on the
machine that ran the scan, and say so when opened elsewhere. See
[docs/reuse.md § Linking to your own map from your README](docs/reuse.md#linking-to-your-own-map-from-your-readme)
to do the same in a plugin that depends on this one.

It grew inside [lib.nvim](https://github.com/StefanBartl/lib.nvim) as
`lib.nvim.docmap` and was extracted once it had nothing left to do with lib.nvim
— see
[docs/pipeline.md § Why this is its own plugin](docs/pipeline.md#why-this-is-its-own-plugin).

---

## Around it

> **[lib.nvim](https://github.com/StefanBartl/lib.nvim)** — the utility library
> this grew out of and still builds on. If you are mapping a tree you are
> probably about to want its `fs`, `ui.kit` and `usercmd` modules too; this
> plugin uses exactly those.
>
> **[runtime-analysis.nvim](https://github.com/StefanBartl/runtime-analysis.nvim)** —
> the counter-check. This plugin knows what exists and what is documented; that
> one knows what actually ran. Install it and the Telemetry and Loaded tabs stop
> saying "no data".
>
> **[docmap-desktop](https://github.com/StefanBartl/docmap-desktop)** — the third
> leg: the same map read entirely outside Neovim, over a real
> `http://127.0.0.1` origin, so the Telemetry and Loaded panels work there
> exactly as they do in the editor.
>
> **[pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim)** — renders
> `overview.md` to `overview.pdf` when `opts.pdf` is on.
>
> Everything except `lib.nvim` is soft: without them the map is generated
> unchanged, minus those panels. See [Requirements](#requirements).

---

## Requirements

| | |
| --- | --- |
| Neovim | **0.10+** — `vim.uv` and `vim.treesitter` |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | required — `notify`, `fs.*`, `ui.kit`, `usercmd`, `map`, `debounce`, `autocmd`, `cross.uv.spawn_capture` |
| A Treesitter parser per language | required for that language's backend; a missing grammar costs precision, not the map — see [docs/languages.md](docs/languages.md) |

Optional, each detected at runtime and degrading to nothing when absent:

| | |
| --- | --- |
| `git` | The History tab, `:DocMap diff` and `:DocMap churn` |
| [runtime-analysis.nvim](https://github.com/StefanBartl/runtime-analysis.nvim) | The Telemetry and Loaded tabs |
| [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) | `opts.pdf` — `overview.md` rendered to PDF |
| [nvzone/menu](https://github.com/nvzone/menu) | A host for the context-menu entries — see [Integrations](#integrations) |

The full list of declared external tools is in
[docs/health.md](docs/health.md).

---

## Installation

```lua
-- lazy.nvim
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

---

## Quickstart

Open a file anywhere in the repository you want mapped, and generate:

```vim
:DocMap
```

That writes the artifacts under `docs/map/`. Then look at them, or ask questions
of them:

```vim
:DocMap open                     " open the HTML in the system browser
:DocBrowse                       " navigate the same map inside the editor
:DocMap why my.a my.b            " shortest require path between two, to quickfix
:DocMap pick                     " fuzzy-find any module or function
:DocMap check                    " verify without writing, findings to quickfix
```

Twenty-one `:DocMap` actions in all, and five ways to open `:DocBrowse`:
[docs/commands.md](docs/commands.md). Inside the browser, `?` shows the keys for
the current mode, rendered from the same table the keys are installed from, so it
cannot drift from them.

Verify your setup any time with:

```vim
:checkhealth documentation
```

---

## What it produces

| Artifact | What it is |
| --- | --- |
| `docs/map/index.html` | The interactive map: **Hierarchy**, **Index** (Tree / Functions / Modules), **Analysis**, **Compare**, **Features**, **Quicks**, **Notes**, **History** and **Findings** tabs. Self-contained — no CDN, no build step |
| `docs/map/overview.md` | The same tree as Markdown, so it renders on GitHub |
| `docs/map/module_map.json` | The IR, byte-deterministic. What `--check` compares and what `:DocMap diff` reads out of old commits |
| `docs/map/coverage.svg` | Optional (`opts.badge`): a doc-coverage badge, hand-rolled, no network call |
| `docs/map/overview.pdf` | Optional (`opts.pdf`): the same content as `overview.md`, via [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) |

**Every one of these is a snapshot of the version that wrote it.** The tour of
what each tab shows, and why, is [docs/tabs.md](docs/tabs.md); how each one is
computed is [docs/pipeline.md](docs/pipeline.md).

---

## Languages

Twenty-three backends behind one contract, so a repository that mixes them
produces one map rather than several — Lua, JavaScript, TypeScript, TSX, Python,
Ruby, PHP, C#, Go, Rust, Kotlin, Swift, Dart, Scala, Haskell, Elixir, Erlang,
OCaml, Zig, Java, C, C++ and assembly.

A backend answers the same five questions — which files it claims, where its
sources live, what documents a file, what documents a declaration, and what makes
a declaration public — and the map does not care which language answered.

The fourth of those is the one place these languages genuinely disagree rather
than merely differing in syntax: Go's visibility is capitalisation and the
compiler enforces it, while Lua reads an authoring convention (`@internal`) that
is a claim rather than a fact. Both are honest, and they are not the same
strength of evidence.

[docs/languages.md](docs/languages.md) has the per-language table, the
`Documentation.LangBackend` contract field by field, the measured parity matrix,
what a missing grammar costs, and what adding the twenty-fourth actually takes.

---

## Configuration

Every option is a plain field on `Documentation.Opts`, and a repository can state
the ones that are facts about *itself* — `source`, `exclude`, `repo_url`,
`layers`, `checks` — in a `.docmap.json` at its root, which every host reads: the
Neovim plugin, the standalone binary, the GitHub Action and `docmap-desktop`.

The full table, the `.docmap.json` precedence rules, switching a check off or
re-grading it, and rebinding `:DocBrowse`'s keys by *action* rather than by key:
[docs/configuration.md](docs/configuration.md).

---

## Drift checks

The rendered map is the visible half; the checks are the half that catches bugs.
Two are errors (`missing-module-tag`, `module-path-mismatch`), twelve are
warnings and eight are informational, and each one's reasoning — especially
`dead-function`'s, which has to survive the fact that a library is *made of*
functions with no internal caller — is in
[docs/pipeline.md § Drift checks](docs/pipeline.md#drift-checks).

Switch one off or re-grade it in `opts.checks`; add your own in
`opts.extra_checks`.

---

## Headless, CI, and someone else's repository

```bash
nvim --headless -l scripts/gen_map.lua --check   # stale or drift -> exit 1
```

`--check` regenerates in memory and compares byte for byte; it writes nothing.
Output is deterministic on unchanged input — no timestamp in the IR, sorted-key
JSON — which is what makes a byte comparison a usable staleness test.

On GitHub, adopting the check copies nothing: `action.yml` lives at this
repository's root, so `uses: StefanBartl/documentation.nvim@main` is the whole
integration. The editor, CI and pre-commit-hook shapes, and what a tree has to
look like for any of them: [docs/reuse.md](docs/reuse.md).

---

## A live handle, an MCP server, a desktop app

`generate()` writes the artifacts once. `install()` hands back a live
`Documentation.Handle` another plugin's code reads instead of parsing
`module_map.json` off disk — with optional rescan-on-write, native
call-hierarchy support (which LuaLS itself does not have) and drift findings as
`vim.diagnostic` entries. See [docs/api.md](docs/api.md).

The same handle reaches an agent that speaks
[MCP](https://modelcontextprotocol.io) — nine read-only tools over stdio, so the
agent asks *what calls this function* instead of grepping for the name and
guessing which hits are real. None of them writes `@verified`, which is
load-bearing rather than incidental: [docs/mcp.md](docs/mcp.md).

[docmap-desktop](https://github.com/StefanBartl/docmap-desktop) hosts generated
maps for several projects side by side for anyone not sitting in Neovim.

---

## Integrations

### Context menu

`documentation.integrations.menu` contributes context-aware entries in the shape
[nvzone/menu](https://github.com/nvzone/menu) expects. documentation.nvim has
**no** dependency on `menu` and never opens a context menu itself; a host —
typically your own `<RightMouse>` dispatcher — composes these entries into its
own menu:

```lua
local items = require("documentation.integrations.menu").items()
-- prepend or append `items` to your own menu table, then menu.open(composed)
```

---

## Health check

```vim
:checkhealth documentation
```

Checks the dependencies and the Treesitter Lua parser, and then the part worth
running it for: the configuration a `:DocMap` issued right now would act on — the
resolved root, the detected `source`, how many files are under it, and whether
the committed map has fallen behind the sources. Details, including the declared
external tools: [docs/health.md](docs/health.md).

---

## Contributing

Clone the repository and either symlink it or add it to your runtime path.
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) has the ground rules and the project
layout, including what a twenty-fourth language backend involves;
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) has the toolchain and the five things
CI runs; [docs/pipeline.md](docs/pipeline.md) is the document to read before
changing anything.

Pull requests very welcome.

---

## Feedback

Your feedback is very welcome. Use the
[issue tracker](https://github.com/StefanBartl/documentation.nvim/issues) to
report bugs, suggest features or ask usage questions; anything more open-ended
fits a
[discussion](https://github.com/StefanBartl/documentation.nvim/discussions).

If you find this plugin useful, a ⭐ on GitHub supports its development.

---

## License

MIT — see [LICENSE](LICENSE).
