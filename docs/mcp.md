# MCP server

An MCP ([Model Context Protocol](https://modelcontextprotocol.io)) server that
exposes this repository's module map to a coding agent — the module tree, the
require graph, the call graph, and the documentation-drift findings, as tools
the agent can call instead of grepping.

Shipped 2026-08-11 as Phase 1 of the V1 extension plan.

## Running it

```
nvim --headless -l scripts/mcp_server.lua
```

Not meant to be run by hand — an MCP client spawns it as a subprocess and
talks JSON-RPC over its stdin/stdout. Run interactively it looks like it has
hung, because it is doing exactly what it should: waiting for a line.

Configure it in the client with the repository as the working directory. The
shape below is what most clients use; the field names vary:

```json
{
  "mcpServers": {
    "documentation": {
      "command": "nvim",
      "args": ["--headless", "-l", "scripts/mcp_server.lua"],
      "cwd": "/path/to/your/repo"
    }
  }
}
```

`scripts/mcp_server.lua` is thin on purpose and hardcodes only *this*
repository's layout (`source = "lua/documentation"`). Another plugin copies
the file and changes the options table at the bottom — the same arrangement
`scripts/gen_map.lua` already uses, and for the same reason.

## Tools

| Tool | Answers |
|---|---|
| `docmap_modules` | Every module in the tree: id, kind, declared `@module`, one-line summary. `prefix` scopes to a subtree, `limit` caps the result. |
| `docmap_node` | One module: summary, header prose, documented functions, what it requires and is required by. |
| `docmap_requires` | Require edges out of a module — what it depends on. |
| `docmap_required_by` | Require edges into a module. The question to ask before changing an export. |
| `docmap_callees` | Call edges out of one function, keyed `<node id>#<declared name>`. |
| `docmap_callers` | Call edges into one function. The question to ask before changing a signature. |
| `docmap_findings` | Drift findings — missing summaries, stale references, undocumented exports. Filter by severity, check id or node. |
| `docmap_rescan` | Re-scan from disk and report the new counts. |
| `docmap_checklist` | The hand-verified ledger, with the same staleness verdict `:DocMap checklist` computes — real `git log`, not the baked map. `state` filters (`stale`/`unverified`/`uncited`/`current`/`all`); default is stale + unverified. Read-only — see below. |

## Five decisions worth knowing about

**Answers come from a scan held in memory, and file watching is off.** A watch
callback firing mid-request would swap the IR out from under a tool call that
had already read it, so an agent could get a node list from one scan and edges
from the next. `docmap_rescan` exists precisely so that moment is the client's
choice rather than an invisible race — call it after editing files.

**No tool returns a raw IR node.** A node carries parser-internal and
render-only fields (`symbols`, `stats`, `types_detail`) that an agent pays for
in tokens on every call and can almost never use. Each tool returns a named
projection instead, so growing the IR does not silently grow every tool
result. `TESTS/mcp_spec.lua` asserts this rather than trusting it.

**A failing tool is a result, not a transport error.** An unknown node id comes
back as an `isError` tool result, not a JSON-RPC error. MCP draws that line
deliberately: a JSON-RPC error is handled by the client's plumbing and the
model never sees it, whereas `isError` reaches the model, which can then
correct the argument it got wrong. A bad id is the model's mistake to fix, so
it has to be the model that hears about it.

**There is no tool that writes `@verified`.** `docmap_checklist` reads the
ledger; nothing in this catalogue can mark an item verified. Stated directly
in `PROTOCOLS_AND_AGENTS.md`: an agent that could write `@verified` timestamps
could mark its own work as verified, and the verifying actor and the verified
actor must not be the same one without a human in between. The write path is
a person editing Markdown — see
[docs/checklist_format.md](checklist_format.md).

**stdio, not a port.** With stdio there is nobody to authenticate: the client
*is* the parent process, and the trust boundary is the one the operating
system already draws around a subprocess. That is why this was the cheap
protocol to build first — it sidesteps every question the hosted-web-app idea
drowns in. It also means
one absolute rule: **stdout carries the protocol and nothing else**, one JSON
object per line, no framing headers (that is LSP; MCP delimits by newline). A
stray `print()` anywhere in the process corrupts the stream, which is why
every diagnostic — including `vim.notify` — is pinned to stderr.

## Layout

| File | Role |
|---|---|
| `lua/documentation/mcp/tools.lua` | The tool catalogue. The only place that knows what a `Documentation.Handle` can answer. |
| `lua/documentation/mcp/protocol.lua` | JSON-RPC 2.0 dispatch. No stdio, so tests drive the whole protocol in-process. |
| `lua/documentation/mcp/init.lua` | The transport: install the handle, read lines, write lines. |
| `scripts/mcp_server.lua` | This repository's entry point. |
| `TESTS/mcp_spec.lua` | Handshake, every tool, every error path — driven through `protocol.dispatch` with real JSON on both sides. |

The split between `protocol.lua` and `init.lua` is what makes the server
testable: a message handler that reads and writes files is a program you can
only test by starting a subprocess and talking to it, whereas
`protocol.dispatch(server, line)` is a function from a string to a string.
