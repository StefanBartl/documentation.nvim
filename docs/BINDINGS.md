# Bindings

Every key, user command and autocommand this plugin installs.

**Generated** by `documentation.bindings.docs` from the tables that
actually drive the plugin — do not edit by hand. Regenerate with
`nvim --headless -l scripts/gen_map.lua`.

## User commands

| Command | Arguments | What it is |
|---|---|---|
| `:DocMap` | `[check\|full\|open\|graph\|why\|dot\|diff\|impact\|churn\|plugins\|serve\|helptags]` | Generate or verify the module map. The bare form writes artifacts. |
| `:DocBrowse` | `[live] [history\|trail\|module]` | Navigate the same map inside the editor. Only ever reads. |

Both names are configurable — `opts.command_name` and
`opts.browse_command_name` — so a second `setup()` call (a plugin
generating its own map) does not overwrite this one.

## Keymaps

**The plugin installs no global keymaps.** Every binding below is
buffer-local to the `:DocBrowse` scratch buffer and set with `nowait`,
so it can only ever shadow a key *inside* that buffer.

Modes (`1`…`6`): structure, deps, calls, types, history, trail. These are positional and deliberately not
rebindable — see `Documentation.Browse.KeyAction`.

| Keys | Action | Modes | Does |
|---|---|---|---|
| `j` `k` | `move` | all | move; the detail pane follows *(native Vim key, not bound)* |
| `<CR>` | `enter` | all | descend a level, or follow the edge |
| `-` `<BS>` | `up` | all | up a level (×count) |
| `<C-o>` | `back` | all | back through the visit history (×count) |
| `<C-i>` | `forward` | all | forward through the visit history (×count) |
| `h` | `dir_in` | deps, calls | direction: incoming edges |
| `l` | `dir_out` | deps, calls | direction: outgoing edges |
| `+` | `depth_inc` | deps | depth +1 (×count) |
| `_` | `depth_dec` | deps | depth -1 (×count) |
| `gd` | `goto_source` | all | open the source at the line (closes) |
| `gq` | `quickfix` | all | current list into the quickfix list (closes) |
| `gI` | `impact` | all | blast radius into the quickfix list (closes) |
| `gO` | `open_page` | all | open the generated page here |
| `gD` | `commit_diff` | history | the opened commit's diff |
| `p` | `pin` | all | pin / unpin the entry under the cursor |
| `d` | `unpin` | trail | unpin |
| `S` | `trail_save` | trail | save this trail under a name |
| `L` | `trail_load` | trail | load a saved trail (adds to this one) |
| `X` | `trail_delete` | trail | forget a saved trail |
| `f` | `filter` | all | filter this list in place (-negate, "phrase"; empty clears) |
| `/` | `search` | all | fuzzy jump across modules and functions |
| `?` | `help` | all | this list |
| `q` `<Esc>` | `close` | all | close |

Rebind or disable any of them with `opts.keys`, keyed by the **Action**
column — not by the default key, so a rebinding survives a change of
defaults. `false` disables an action; it then still appears in the `?`
cheatsheet, marked `(disabled)`.

## Autocommands

All created lazily. Requiring `documentation` installs none of them.

### `BufWritePost` — global

**Owner:** `documentation.editor.registry`  
**Lifetime:** Created by `install()` when `opts.watch` is set; removed by `uninstall()`.

Rescan the tree after a write under `source/`, debounced by `opts.watch_ms`, so a live handle's IR and every `on_change` subscriber stay current. Filtered by `fs.is_subpath` rather than by an autocmd glob pattern — a pattern would have to match the user's path spelling exactly, and a mismatch fails silently.

### `CursorMoved` — buffer

**Owner:** `documentation.editor.browse`  
**Lifetime:** Created by `bind()` on the browser's list buffer; dies with the buffer when the browser closes.

Drive the detail pane from the cursor, so `j`/`k` stay native keys and counts and `scrolloff` keep behaving.

### `VimLeavePre` — global

**Owner:** `documentation.editor.browse.trail_store`  
**Lifetime:** Created by `attach()` on the first browser open; idempotent, lives for the session.

Flush pinned trails to `stdpath('state')`. Never into the repository — a trail has no more claim on the project than a jumplist has, and committing it would give `--check` an opinion about where one person happened to look.

### `VimLeavePre` — global

**Owner:** `documentation.editor.serve`  
**Lifetime:** Created by `start()`; removed by `stop()` along with its augroup.

Shut the local map server down with the editor, so no listening socket outlives the Neovim session that opened it.
