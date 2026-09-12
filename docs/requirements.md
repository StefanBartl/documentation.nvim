# Requirements

| | |
| --- | --- |
| Neovim | **0.10+** — `vim.uv` and `vim.treesitter` |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | required — `notify`, `fs.*`, `ui.kit`, `usercmd`, `map`, `debounce`, `autocmd`, `cross.uv.spawn_capture` |
| A Treesitter parser per language | required for that language's backend; a missing grammar costs precision, not the map — see [languages.md](languages.md) |

Optional, each detected at runtime and degrading to nothing when absent:

| | |
| --- | --- |
| `git` | The History tab, `:DocMap diff` and `:DocMap churn` |
| [runtime-analysis.nvim](https://github.com/StefanBartl/runtime-analysis.nvim) | The Telemetry and Loaded tabs |
| [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) | `opts.pdf` — `overview.md` rendered to PDF |
| [nvzone/menu](https://github.com/nvzone/menu) | A host for the context-menu entries — see [integrations.md](integrations.md) |

The full list of declared external tools, including how `lib.nvim.deps`
offers to install what is missing, is in [health.md](health.md).
