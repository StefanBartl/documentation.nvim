> **Beta stage — active development.** This repository is past its first shape and in
> active use, but the surface is not frozen: breaking changes are still possible. Pin a
> commit or tag if you depend on it.

# documentation.nvim

```
     _                                       _        _   _
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

## Documentation

**Start at [docs/README.md](docs/README.md)** — the folder's own index, grouped by
the question you arrived with. The four to reach for first:

| Page | Answers |
| --- | --- |
| [docs/pipeline.md](docs/pipeline.md) | Every stage, every design decision, and the measurement behind each one. **The document to read before changing anything.** |
| [docs/commands.md](docs/commands.md) | `:DocMap` and `:DocBrowse`, subcommand by subcommand |
| [docs/reuse.md](docs/reuse.md) | Generating a map for your own plugin — including the GitHub Action, which requires copying nothing |
| [docs/languages.md](docs/languages.md) | The twenty-three backends, as a reference and as a contract |

**Getting started**

- [Requirements](docs/requirements.md) — Neovim version, `lib.nvim`, and what each optional integration buys you.
- [Installation](docs/installation.md) — every plugin manager, with the reason each needs a different lazy-loading shape.
- [Quickstart](docs/quickstart.md) — the first thing to run after installing.
- [What you get](docs/what-you-get.md) — the artifacts it writes, and how this repository's own published map shows what a consumer sees.
- [Around it](docs/around-it.md) — how this plugin's scope differs from its siblings in the collection.

**Configuration and everyday use**

- [Configuration](docs/configuration.md) — every option, the `.docmap.json` precedence rules, and rebinding `:DocBrowse` by action rather than by key.
- [Tabs](docs/tabs.md) — what each panel of the generated page shows, and why.
- [Features](docs/FEATURES/README.md) — one page per area, with the reasoning behind each.
- [Lua API](docs/api.md) — `generate()`, `install()`, and the live `Documentation.Handle`.
- [MCP server](docs/mcp.md) — nine read-only tools over stdio, and why none of them writes.
- [Integrations](docs/integrations.md) — the context-menu bridge for `nvzone/menu`.
- [Health](docs/health.md) — what `:checkhealth documentation` reports, including the declared external tools.
- [Bindings cheatsheet](docs/BINDINGS.md) — every keymap, user command and autocommand.
- [Workflow](docs/WORKFLOW.md) — which panel answers which question: Trail versus filter versus fuzzy jump.

**The rest**

- [Ecosystem](docs/ecosystem.md) — how this plugin, `runtime-analysis.nvim`, `mdview.nvim` and `docmap-desktop` fit together.
- [Development](docs/DEVELOPMENT.md) — the toolchain, and the five things CI runs.
- [Contributing](docs/CONTRIBUTING.md) — ground rules, project layout, and how to add a language backend.
- [Feedback](https://github.com/StefanBartl/documentation.nvim/issues) — bugs, feature requests and usage questions.

`:help documentation.nvim` is the same ground in Vim help format.

---

## License

MIT — see [LICENSE](LICENSE).
