# `documentation.bindings.usrcmds`

`:DocMap` and `:DocBrowse` — registration, dispatch, completion, and one file
per action.

| File | Action |
|---|---|
| [`init.lua`](init.lua) | `setup()`, the `ACTIONS` table, dispatch, completion. |
| [`generate.lua`](generate.lua) | bare `:DocMap`, `full`, `check` |
| [`open.lua`](open.lua) | `open` — and the opener `graph` reuses |
| [`graph.lua`](graph.lua) | `graph {deps\|calls} [module]` |
| [`dot.lua`](dot.lua) | `dot [deps\|calls] [module]` |
| [`why.lua`](why.lua) | `why <a> <b>` |
| [`diff.lua`](diff.lua) | `diff [ref]` |
| [`impact.lua`](impact.lua) | `impact [ref]` |
| [`churn.lua`](churn.lua) | `churn [range]` |
| [`serve.lua`](serve.lua) | `serve [stop]` |
| [`browse.lua`](browse.lua) | the whole of `:DocBrowse` |

## Dispatch

The first word of the argument selects a handler from `ACTIONS`; the rest is
passed to it verbatim. Only a genuinely **empty** argument regenerates.

That last sentence is the behavioural fix this split carried. The 700-line
if-chain this replaced tested each action's full pattern in turn and fell
through to the default — *regenerate the artifacts* — whenever none matched. So
`:DocMap graph` with its argument missing, or any typo at all, silently rewrote
files on disk and said nothing. Both now report what they expected.

## The context object

Every handler takes one `Documentation.Bindings.Ctx` rather than five
positional parameters: handlers use different subsets of it, and a positional
list would have to be extended in every handler each time one more field is
needed. It carries the resolved `cfg`, the live registry `handle`, `notify`,
the registered `command_name` (for messages — it is not always "DocMap"),
`open_map` and `find_node`.

## Everything stays lazy

`ACTIONS` values are thunks, not module paths, so a `:DocMap check` never loads
the churn, diff or DOT code. The same reason `documentation/init.lua` puts
`browse`, `diff`, `cli` and `history` behind `__index` metatables.
