---@module 'documentation.bindings.autocmds'
--- The plugin's autocommands, as a manifest — **not** as a place they are
--- created from.
---
--- Centralising the creation would be worse than leaving it where it is. Each
--- of these belongs to a lifecycle its own module owns: the watch autocmd is
--- torn down by `registry.uninstall`, the two `VimLeavePre` hooks flush state
--- their own modules are the only writers of, and the browser's `CursorMoved`
--- is scoped to a buffer that only exists while a browser is mounted. A single
--- `autocmds.lua` that created all four would have to reach into three modules'
--- teardown paths to do it, and the augroup identity that makes uninstall
--- precise would be shared rather than per-handle.
---
--- What was missing was not a home — it was an *account*. Nothing listed what
--- this plugin installs in a user's editor, which is a fair question to be able
--- to answer without grepping. `docs/BINDINGS.md` is generated from this table,
--- and `:checkhealth` can read it.
---
--- Accuracy is not enforced by the type system, so treat the `owner` field as
--- the contract: if you add an autocmd, add it here, and the generated
--- `docs/BINDINGS.md` will pick it up.

local M = {}

-- `Documentation.Bindings.AutocmdInfo` is declared in `bindings/@types`.

---@type Documentation.Bindings.AutocmdInfo[]
M.list = {
  {
    events = { "BufWritePost" },
    owner = "documentation.editor.registry",
    scope = "global",
    lifetime = "Created by `install()` when `opts.watch` is set; removed by `uninstall()`.",
    why = "Rescan the tree after a write under `source/`, debounced by `opts.watch_ms`, so a live handle's IR and every `on_change` subscriber stay current. Filtered by `fs.is_subpath` rather than by an autocmd glob pattern — a pattern would have to match the user's path spelling exactly, and a mismatch fails silently.",
  },
  {
    events = { "BufReadPost", "BufNewFile" },
    owner = "documentation.editor.registry",
    scope = "global",
    lifetime = "Created by `install()` when `opts.callhierarchy` is set (`ensure_callhierarchy`); removed by `uninstall()`.",
    why = "Attach the second, narrow in-process LSP client (`editor/callhierarchy.lua`) to a Lua buffer opened under `source/` — answers `textDocument/prepareCallHierarchy`/`callHierarchy/incomingCalls`/`outgoingCalls` and injects a caller/callee count into hover, alongside whatever real language server (LuaLS) is already attached. Same `fs.is_subpath` scoping as the watch autocmd above.",
  },
  {
    events = { "BufReadPost", "BufNewFile" },
    owner = "documentation.editor.registry",
    scope = "global",
    lifetime = "Created by `install()` when `opts.diagnostics` is set (`ensure_diagnostics`); removed by `uninstall()`.",
    why = "Publish `Documentation.Finding[]` as native `vim.diagnostic` entries (`bindings/diagnostics.lua`) on a Lua buffer opened under `source/`, plus one `handle.on_change` subscription for live refresh on a watch-triggered or manual rescan. Same `fs.is_subpath` scoping as the watch autocmd above.",
  },
  {
    events = { "CursorMoved" },
    owner = "documentation.editor.browse",
    scope = "buffer",
    lifetime = "Created by `bind()` on the browser's list buffer; dies with the buffer when the browser closes.",
    why = "Drive the detail pane from the cursor, so `j`/`k` stay native keys and counts and `scrolloff` keep behaving.",
  },
  {
    events = { "VimLeavePre" },
    owner = "documentation.editor.browse.trail_store",
    scope = "global",
    lifetime = "Created by `attach()` on the first browser open; idempotent, lives for the session.",
    why = "Flush pinned trails to `stdpath('state')`. Never into the repository — a trail has no more claim on the project than a jumplist has, and committing it would give `--check` an opinion about where one person happened to look.",
  },
  {
    events = { "VimLeavePre" },
    owner = "documentation.editor.serve",
    scope = "global",
    lifetime = "Created by `start()`; removed by `stop()` along with its augroup.",
    why = "Shut the local map server down with the editor, so no listening socket outlives the Neovim session that opened it.",
  },
}

---The user commands this plugin registers, for the same reason as above:
---something has to be able to state the surface without reading `setup()`.
---Names are the defaults; `opts.command_name` / `opts.browse_command_name`
---override them.
---@type { name: string, args: string, why: string }[]
M.usrcmds = {
  {
    name = "DocMap",
    args = "[check|full|open|graph|why|dot|diff|impact|churn|plugins|tools|endpoints|serve|helptags|annotate|all]",
    why = "Generate or verify the module map. The bare form writes artifacts.",
  },
  {
    name = "DocBrowse",
    args = "[live] [history|trail|endpoints|module]",
    why = "Navigate the same map inside the editor. Only ever reads.",
  },
  {
    name = "DocMapAll",
    args = "",
    why = "Standalone alias for `:DocMap all` — generate every opts.generate_all.projects entry. Registered only when that option is configured.",
  },
}

return M
