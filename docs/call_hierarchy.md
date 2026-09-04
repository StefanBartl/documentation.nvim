# Call hierarchy in Neovim, with LuaLS attached

**The short version.** LuaLS has no call-hierarchy support — `callHierarchy`,
`incomingCalls`, `outgoingCalls` and `prepareCallHierarchy` appear nowhere in
its source, and its feature request
([LuaLS/lua-language-server#2832](https://github.com/LuaLS/lua-language-server/issues/2832),
opened August 2024) is still open and unstaffed. So `vim.lsp.buf.incoming_calls()`
in a Lua buffer normally does nothing at all. `opts.callhierarchy = true`
attaches a second, narrow LSP client *alongside* LuaLS that answers exactly
those four requests, backed by the module map's own call graph.

You do not replace LuaLS, you do not configure anything in LuaLS, and you do
not start a second process — the client runs in-process, backed by the IR
`install()` already holds.

## Setup

One line in the plugin spec. `callhierarchy` is an ordinary option, so
`setup()` forwards it to `install()` — there is no separate `install()` call to
write:

```lua
{
  "StefanBartl/documentation.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  opts = {
    source = "lua/myplugin",   -- the subtree to scan
    callhierarchy = true,      -- ← this
    watch = true,              -- rescan on save, so the graph tracks your edits
    diagnostics = true,        -- optional: drift findings as vim.diagnostic
  },
}
```

`watch = true` is not required but is what you want in practice: without it the
call graph answers against whatever was on disk when the handle was installed,
so a function you added this session is invisible until `:DocMap` or a manual
`handle.rescan()`.

## Keymaps

Neovim ships defaults for references, rename and code action (`grr`, `grn`,
`gra`) but **none for call hierarchy** — there is no built-in binding to press.
Add them yourself:

```lua
vim.keymap.set("n", "<leader>ci", vim.lsp.buf.incoming_calls, { desc = "Calls: incoming" })
vim.keymap.set("n", "<leader>co", vim.lsp.buf.outgoing_calls, { desc = "Calls: outgoing" })
```

Both open the quickfix list. Nothing else is needed: `vim.lsp.buf.incoming_calls()`
queries *every* attached client and merges the results, which is precisely why
this client can sit beside LuaLS instead of replacing it.

Hover needs no keymap at all — `K` already works, and the caller/callee count
is injected into whatever LuaLS's own hover returns:

```
**3** incoming calls · **1** outgoing call
```

### The runtime half, when there is one

With [`runtime-analysis.nvim`](https://github.com/StefanBartl/runtime-analysis.nvim)
installed and telemetry collected for this project's namespace, the hover
gains a third clause — how often the function was **actually entered**, in the
last seven days:

```
**3** incoming calls · **1** outgoing call · called **412**× in the last 7 days
```

Three readings, and the middle one is the reason the window exists rather
than a running total:

| What you see | What it means |
|---|---|
| `called **412**× in the last 7 days` | Alive, and how alive. |
| `**not called** in the last 7 days (9 310 recorded in total)` | A **cold path**. The total alone cannot say this — a function abandoned three weeks ago still carries a large one. |
| no third clause at all | No telemetry for this namespace, or none for this function. **Never** read as "not called": absence of runtime data is not evidence of death. |

**The case this was built for is the one where the first two counts are
zero.** A function nothing statically calls — bound as a callback value, or
reached through dynamic dispatch — used to produce no hover at all, which is
precisely static analysis's blind spot. It now hovers, and says the one thing
only runtime data can attest to.

Seven days because the question is "is this alive": a day is noise, and a
month is long enough that a path abandoned three weeks ago still reads as
busy. The window is `telemetry_join.RECENT_DAYS`, in one place.

The lookup is cached for two seconds. A hover fires on `K` and on every
`CursorHold`, and reading the telemetry file per keystroke would be felt —
while nothing in this process can observe another session appending to it, so
there is no event to invalidate on and no TTL that would make the number
live.

## Using it

Put the cursor **anywhere inside a function's body**, not necessarily on its
declaration line — the lookup walks the function's whole span, which is the
reason `line_end` is tracked in the IR at all.

| You want | Press |
|---|---|
| Who calls this function | `<leader>ci` → quickfix |
| What this function calls | `<leader>co` → quickfix |
| Just the counts, in passing | `K` (the normal hover) |
| The same thing as a graph | `:DocBrowse` → Hierarchy → Calls |

The quickfix entries carry each caller's own signature as `detail`, so the
list is readable without jumping into every hit.

## Verifying it actually attached

The failure mode is silent — if the client did not attach, `incoming_calls()`
opens nothing and looks identical to "this function has no callers." Check the
client list rather than guessing:

```vim
:lua =vim.tbl_map(function(c) return c.name end, vim.lsp.get_clients({ bufnr = 0 }))
```

You want to see **both** names:

```
{ "docmap-callhierarchy", "luals" }
```

If `docmap-callhierarchy` is missing, the usual causes, in order:

1. **The buffer is outside `source/`.** The client attaches only to Lua
   buffers under the scanned subtree — same scoping as the watch autocmd. A
   file in `scripts/` or `TESTS/` will not get it.
2. **`callhierarchy` was not set**, or was set on a second `setup()` for a
   different root. `:checkhealth documentation` reports the option's state.
3. **The handle was installed before the option existed** — the client attaches
   on `BufReadPost`, so a buffer already open when `setup()` ran needs a
   reload (`:e`).

## What it answers, and what it does not

Backed by `core/calls.lua`'s resolution, which is honest about its own limits
rather than guessing:

- **Resolved calls** — through a `require` alias, a module's own export table,
  or a local declaration — are exact, and carry a `confidence` field saying so.
- **Dynamic dispatch is invisible.** A call through a table built at runtime,
  a callback stored in a variable, or `_G[name]()` cannot be resolved by a
  parser and is not reported as a guess.
- **External calls are not call-hierarchy entries.** A call into another plugin
  shows up in the Deps graph's tooltip breakdown (`plenary.async.run (2×)`),
  not in incoming/outgoing calls, because the callee is not a node in this map.

So a **non-empty** result is trustworthy; an **empty** one means "nothing this
parser can see," not "nothing." That difference matters most in exactly the
case you would reach for it — deciding whether a function is safe to delete.
Cross-check with `:DocBrowse` → Analysis → dead code, and, if
`runtime-analysis.nvim` is installed, with the Telemetry panel, which knows
what actually ran rather than what statically resolves.

## Why a second client instead of a LuaLS patch

Neovim's LSP client accepts a Lua *function* as `cmd`, returning a
`vim.lsp.rpc.Client`-shaped table instead of spawning a process. That is the
whole extension point: the client below is a handful of request handlers over
`handle.callers` / `handle.callees`, with no process, no socket, and no new
scan. It declares only the capabilities it answers, so Neovim never routes a
`textDocument/completion` to it — LuaLS keeps completion, diagnostics, its own
hover and everything else.

Measured on this repository (2026-08-11), both clients attached to the same
buffer:

| Request | `docmap-callhierarchy` | `luals` |
|---|---|---|
| `textDocument/prepareCallHierarchy` | `M.encode` | *no answer* |
| `textDocument/hover` | caller/callee counts, plus recent call counts when telemetry has them | its own hover |

That table is the design in one line: the two clients answer disjoint
questions, and Neovim merges them.

## Related

- [docs/WORKFLOW.md](WORKFLOW.md) — where this fits among the other day-to-day
  questions, and why `opts.diagnostics` pairs with it.
- [docs/pipeline.md](pipeline.md) — how `core/calls.lua` resolves a call edge,
  and the four shapes it can and cannot see.
- `lua/documentation/editor/callhierarchy.lua` — the client itself, including
  the one sharp edge in Neovim's in-process `cmd` shape (its methods are
  called *without* an implicit `self`).
