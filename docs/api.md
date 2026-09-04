# API

Two entry points, and they answer different questions. `generate()` writes the
artifacts once and returns; `install()` hands back a live handle another
plugin's code reads instead of parsing `module_map.json` off disk.

The same handle is what the [MCP server](mcp.md) projects as tools for a coding
agent, and what [`hosting.md`](hosting.md) answers `--api=<route>` requests
from.

## `install()` -- a live handle

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
