# Modern protocols, WASM, and agent integration — costed, not decided

Raised 2026-08-11, as part of "implement the standalone version; take
along that cutting-edge technology & tools should be used, new
future-protocols where possible". Four distinct ideas came out of that,
and they are **not one project** — they differ in cost by more than an
order of magnitude and in maturity by more than that. Analysis, not a
proposal; same posture as [`DESKTOP_WEBAPP.md`](DESKTOP_WEBAPP.md) and
[`CHECKLIST_TASK_RUNNER.md`](CHECKLIST_TASK_RUNNER.md) in this folder.

**The filter, stated up front, because it disqualifies more than it
admits:** "new protocol" is not a value in itself. This ecosystem's own
[`ECOSYSTEM.md`](../FEATURES/ECOSYSTEM.md) §6 already rejected a
separate-binary/web-app tier once, on measured grounds (nothing here is
compute-bound; a rich browser UI already exists twice in-house). An idea
below earns its place only if it answers a question the current shape
cannot — not because the technology behind it is current.

---

## 1. MCP server — the strongest of the four

Expose the scanner as a [Model Context Protocol](https://modelcontextprotocol.io)
server, so an AI agent (Claude Code and anything else speaking MCP) can
call it as a tool: "what does this repo's module graph look like", "which
functions have drift findings", "what calls `M.foo`".

**Why this one is genuinely strong, on this project's own filter:** the
IR is already a structured, deterministic, machine-readable artifact
(`module_map.json`), and `core/cli.lua` already exposes the whole
pipeline as a function that does not care where `opts` came from. An MCP
server is a *thin adapter over an interface that already exists* — much
closer to `docs/ROADMAP/IDEAS/IDEAS.md` §6.1's SARIF idea (a serialiser
and a CI step, not analysis) than to anything requiring new extraction.
It also answers a real question the current shape genuinely cannot: an
agent working in a repo today has to shell out to `:DocMap` and parse
human-formatted output, or read `module_map.json` and re-derive
everything the graph queries already answer.

**What it would actually need:**

- A transport. MCP's stdio transport is the obvious first target — no
  ports, no auth, no trust boundary (the agent spawns the server as a
  subprocess). This sidesteps every question the "hosted web app" idea in
  [`DESKTOP_WEBAPP.md`](DESKTOP_WEBAPP.md) drowns in, which is most of why
  it is cheaper than it sounds.
- A tool surface. The natural set already exists as
  `Documentation.Handle`'s own methods — `ir`, `node`, `requires`,
  `required_by`, `callers`, `callees`, `findings` — plus `scan_full`. That
  is a real, tested API, not one that would need inventing.
- A host process. **This is the one real open question**, and it is the
  same one [`DESKTOP_WEBAPP.md`](DESKTOP_WEBAPP.md) hits: either
  `nvim --headless -l` hosts it (trivial, but then the "AI agent" needs
  Neovim installed — usually true for this ecosystem's own user, not in
  general), or it rides on the standalone CLI, which is currently blocked
  on the treesitter binding problem [`PORTABILITY.md`](../PORTABILITY.md)
  documents. Not blocking for a first version aimed at this ecosystem's
  own use.

**Honest caveat:** MCP is young and its spec is still moving. A server
written against today's spec will need maintenance. That is an argument
for keeping the adapter thin — which it naturally is, given the surface
above already exists — not an argument against.

**Rank this first** of the four, and note it is the only one of the four
that is *cheap*.

---

## 2. WASM as a distribution target

Compile the scanner to WebAssembly so it runs in a browser or an edge
runtime with no native binary at all.

**Precedent in-house, which is why this is not speculative:**
`mdview.nvim` already ships a real WASM component (`native/wasm-render`,
Rust + comrak + ammonia, compiled to `wasm32-unknown-unknown`). So the
toolchain question is answered by example rather than by hope.

**But the precedent does not transfer as directly as it looks.** mdview's
WASM component is *Rust* compiled to WASM. This scanner is *Lua*. Running
it in WASM means either (a) compiling a Lua interpreter to WASM (Wasmoon,
Fengari, or `lua.vm.js`-style) and running the existing sources on top,
or (b) rewriting the pipeline in a WASM-first language. (a) inherits the
exact treesitter problem [`PORTABILITY.md`](../PORTABILITY.md) documents —
plus a second one, since a WASM Lua runtime cannot load a native
`libtree-sitter` at all; it would need `web-tree-sitter` (which exists,
and is itself WASM) bridged into the Lua runtime, a bridge nobody has
built. (b) is a rewrite.

**What it would buy, honestly assessed:** the generated page is already
self-contained, offline-capable HTML that needs no server for most panels.
So WASM does not unlock "view a map in a browser" — that already works.
It would unlock "*generate* a map in a browser, from source the browser
can see", which is a genuinely different capability and a much narrower
want. Nothing in this ecosystem has asked for it.

**Verdict: real, well-precedented, and currently answering a question
nobody has asked.** Revisit if a "paste a repo URL, get a map" web
service is ever actually wanted — that is the use case that would make it
the right tool rather than an interesting one.

---

## 3. WebSocket / WebTransport for the serve tier

Replace or supplement `editor/serve.lua`'s plain HTTP with a persistent
connection — WebSocket today, WebTransport (HTTP/3, QUIC) as the newer
option.

**What the current tier actually does, checked rather than assumed:**
`editor/serve.lua` serves static files plus five JSON endpoints
(`/api/commits`, `/api/commit/<sha>`, `/api/telemetry`,
`/api/telemetry/snapshots`, `/api/loaded[…]`), each a discrete
request/response the page fetches on demand. **Every one of those is a
natural fit for request/response and a poor fit for a persistent
stream.** Nothing on the page today pushes: there is no live-updating
panel, no server-initiated event, no subscription.

**So the honest version of this idea is not "upgrade the transport" but
"add a feature that would need one".** The only candidate visible today
is live-updating panels — a Telemetry panel that ticks upward while you
watch, a Loaded view that refreshes as modules load. That is a real
feature idea (and a genuinely nice one), but it is a *feature* proposal,
not a protocol one, and it should be judged as such: is watching call
counts increment live actually useful, or is it a demo? `runtime-analysis.
telemetry`'s own premise (docs/ROADMAP.md §3.5 there — installed, cheap,
left running for a week; not a live profiler) argues it is closer to the
latter.

**WebTransport specifically:** mdview.nvim already implements it
(`native/server/webtransport.go`), so the ecosystem has the expertise —
but mdview needs it for a genuinely streaming workload (live markdown
push on every keystroke). This project has no such workload. Adopting
HTTP/3 + QUIC for five on-demand JSON endpoints, on a `127.0.0.1`-only
personal-machine server, would add TLS-certificate machinery (WebTransport
requires it, even locally) to solve nothing.

**Verdict: no, on current requirements.** Revisit only if a real
push-shaped feature is decided on first — the protocol follows the
feature, not the other way around.

---

## 4. A native checklist runner (C/C++/Rust/Go) with agent integration

The largest of the four: take
[`CHECKLIST_TASK_RUNNER.md`](CHECKLIST_TASK_RUNNER.md)'s idea, implement
it as a native binary rather than in-editor Lua, and wire it to AI agents
so an agent can be handed a checklist and work through it.

**Two independent proposals wearing one sentence**, and separating them
is the main contribution of this section:

**(a) Native implementation.** Rewriting the checklist runner in
Rust/Go/C++ buys speed and a standalone binary.
[`CHECKLIST_TASK_RUNNER.md`](CHECKLIST_TASK_RUNNER.md)'s own analysis
already found the honest shape of that feature is a *curated ledger with
staleness detection* — Markdown parsing, `git log`/hash comparison per
cited path, and rendering. None of that is compute-bound; the same
argument [`ECOSYSTEM.md`](../FEATURES/ECOSYSTEM.md) §6 already made against a
separate binary applies unchanged. A native rewrite would buy a
standalone binary — which is [`DESKTOP_WEBAPP.md`](DESKTOP_WEBAPP.md)'s
problem, already scoped there, and currently blocked for reasons that
have nothing to do with language choice.

**(b) Agent integration — the interesting half.** "Write a prompt so
agents can work through the checklist" is a genuinely different idea, and
notably it **does not need (a) at all**. A checklist that is Markdown
with `@ref`/`@verified` metadata (the sketch in
[`CHECKLIST_TASK_RUNNER.md`](CHECKLIST_TASK_RUNNER.md)) is *already*
agent-readable — an agent can read the file, visit each `@ref`, and
report. What would actually help is the MCP server in §1: give an agent
structured access to the IR and the findings, and "work through this
checklist" becomes a task it can do against real data rather than by
grepping.

**So the sequencing falls out on its own:** §1 (MCP) is the enabler for
(b); (b) needs no native rewrite; (a) is a separate, already-scoped,
currently-blocked question. The one thing not to do is treat all three as
one project — which is exactly what the original framing invited.

**Also worth stating plainly**, since it is the kind of thing that gets
lost in enthusiasm: an agent that can *edit* a checklist's `@verified`
timestamps is an agent that can mark work as verified without verifying
it. Whatever gets built here, the verification record and the thing
doing the verifying should not be the same actor without a human in
between. Not a reason against; a constraint on the design.

---

## Summary

| Idea | Verdict | Why |
|---|---|---|
| **MCP server** | **Strongest; cheap** | Thin adapter over an interface that already exists (`Documentation.Handle`, `core/cli.lua`); stdio transport sidesteps every trust question; answers something the current shape genuinely cannot. |
| **Agent-driven checklists** | Follows MCP | Needs no native rewrite. Enabled by the MCP server above; the Markdown format is already agent-readable. |
| **WASM** | Real, unneeded | Well-precedented in-house (mdview), but inherits *two* treesitter problems and answers a question nobody has asked. |
| **WebSocket / WebTransport** | No, on current requirements | Every existing endpoint is request/response-shaped. The protocol should follow a push-shaped feature, and no such feature has been decided on. |
| **Native checklist runner** | Separate, already-scoped | Not compute-bound; the "standalone binary" half is `DESKTOP_WEBAPP.md`'s problem, currently blocked for unrelated reasons. |

## Revisit if

MCP: whenever someone wants an agent to answer questions about a repo's
structure without shelling out — the most likely of these to become real,
and the cheapest to try. The rest: only once a feature that genuinely
needs them is decided on first.
