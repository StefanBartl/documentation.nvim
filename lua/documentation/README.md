# `documentation`

The pipeline: scan → LuaLS enrichment (opt-in) → check → render.

The design record for every stage — what it does, what it deliberately does
not do, and the measurement behind each decision — is
[`docs/pipeline.md`](../../docs/pipeline.md). It lives there rather than here
because it is the longest document in the repository and readers reach for it
from the README, not from inside `lua/`.

| Stage | Module | Produces |
|---|---|---|
| Scan | [`scan.lua`](core/scan.lua) | `Documentation.IR` — hierarchy, summaries, links |
| Scan | [`functions.lua`](core/functions.lua) | `node.functions` — per-function docs via `vim.treesitter` |
| Scan | [`symbols.lua`](core/symbols.lua) | `node.symbols` — module-scope tables, constants, bindings |
| Graph | [`deps.lua`](core/deps.lua) | `kind="require"` edges |
| Graph | [`calls.lua`](core/calls.lua) | `kind="call"` edges |
| LuaLS | [`luals.lua`](core/luals.lua) | class/alias detail, `kind="type"`/`"extends"` edges |
| Check | [`check.lua`](core/check.lua) | `Documentation.Finding[]` |
| Render | [`render/`](core/render/) | HTML · Markdown · Mermaid · DOT · badge |
| Encode | [`json.lua`](core/json.lua) | deterministic JSON |
| Diff | [`diff.lua`](core/diff.lua) | what one revision changed about the shape |
| History | [`history.lua`](core/history.lua) | changed lines → functions → callers |
| Live | [`registry.lua`](editor/registry.lua) | `install()`/`uninstall()` |
| Serve | [`serve.lua`](editor/serve.lua) | the loopback map server |
| CLI | [`cli.lua`](core/cli.lua) | `--check`/`--full` |
| Commands | [`bindings/usrcmds/`](bindings/usrcmds/init.lua) · [`browse/`](editor/browse/README.md) | `:DocMap` · `:DocBrowse` |
| Bindings | [`bindings/`](bindings/) | key-override rule · the autocommand manifest |
| Options | [`config/`](config/init.lua) | defaults + the merge rule |
| Health | [`health.lua`](editor/health.lua) | `:checkhealth documentation` |

Two rules worth knowing before changing anything here:

- **The IR is the contract.** Renderers never touch the filesystem, and the
  scanner never knows what will be drawn.
- **`diff.lua` and `history.lua` are pure** — text and IRs in, a structure
  out; no git, no filesystem. Everything that shells out lives in
  `command.lua` and `browse/init.lua`, which is what keeps the shape of the
  answers testable without a repository.
