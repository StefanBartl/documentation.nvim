# `documentation.editor`

The half that touches a running editor: live handles, the in-editor browser,
the local map server, and the health check.

Everything here may reach down into [`core/`](../core/) — that is what the core
exists for. The reverse is forbidden and
[checked](../../../scripts/gen_map.lua): `documentation.core` may not require
`documentation.editor`.

## What is where

| File | What |
|---|---|
| [`registry.lua`](registry.lua) | `install()` / `uninstall()` — a live handle per repository root: an in-memory IR, optional rescan-on-write, `on_change` subscribers. |
| [`browse/`](browse/README.md) | `:DocBrowse`, the editor-side map navigator. Its own README. |
| [`serve.lua`](serve.lua) | The loopback map server. Only thing here that opens a socket; see [SECURITY.md](../../../docs/SECURITY.md). |
| [`health.lua`](health.lua) | `:checkhealth documentation`. |
| [`command.lua`](command.lua) | **Deprecated alias** for `documentation.bindings.usrcmds`. |

## The registry is the coordination point

There is at most one handle per normalised root, and `:DocMap` goes through it
rather than scanning on its own. That is what keeps the command, a consuming
plugin's `install()` subscriber and an open `:DocBrowse` looking at the *same*
IR instead of three stale copies of it.

Normalising the root matters more than it sounds: the registry keys on it, and
a trailing slash or a Windows backslash would make two spellings of one
repository look like two repositories with two handles and two watchers.

## Nothing runs unless asked

Requiring `documentation` installs no command and no autocommand. Every
autocommand in this directory is created lazily by the function that owns its
teardown — the watch autocmd by `install()` (and only with `opts.watch`), the
server's shutdown hook by `start()`. The full account is in
[`bindings/autocmds.lua`](../bindings/autocmds.lua), which `:checkhealth`
reads.

## Where the side effects live

The rule that makes `core/` testable is that everything impure ends up here or
in `bindings/`:

- **git** — the commit list and per-commit diffs in `browse` and `serve`; the
  `diff`/`impact`/`churn` commands' git half is in `bindings/usrcmds/`, and
  each calls a pure function in `core/` for the actual analysis.
- **windows and buffers** — `browse/`, through `lib.nvim.ui.kit`.
- **sockets** — `serve.lua`, loopback only.
- **user-visible messages** — `lib.nvim.notify`, never from `core/`.
