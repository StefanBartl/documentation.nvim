# V1 extension — implementation plan

Written 2026-08-11, across the four analyses in this folder
([`PORTABILITY.md`](PORTABILITY.md), [`DESKTOP_WEBAPP.md`](DESKTOP_WEBAPP.md),
[`PROTOCOLS_AND_AGENTS.md`](PROTOCOLS_AND_AGENTS.md),
[`CHECKLIST_TASK_RUNNER.md`](CHECKLIST_TASK_RUNNER.md)). Those documents each
cost *one* idea honestly and stop there, by design. This one does the thing
none of them can do alone: **draw the dependency graph across all four**, and
sequence accordingly.

It adds no new analysis of its own except where the cross-document view
produces a finding the individual documents could not — which happens twice,
and both times it changes the order of work.

## What this folder is, after the ECOSYSTEM.md move

`ECOSYSTEM.md` used to sit here and accounted for roughly half its line
count, while being almost entirely **shipped work** (steps 1–8 of its own
sequencing; only step 9 remains, gated on the serve tier). It now lives in
[`../FEATURES/ECOSYSTEM.md`](../FEATURES/ECOSYSTEM.md) with the other
decision records. What remains in this folder is genuinely open.

---

## Finding 1 — one blocker, four projects

The four documents arrive independently at the same wall, and **no document
states this** because each one only sees its own half:

| Project | Blocked on |
|---|---|
| `PORTABILITY.md` — full-fidelity standalone | a working Lua binding to `libtree-sitter` |
| `DESKTOP_WEBAPP.md` — desktop app | the same |
| `PROTOCOLS_AND_AGENTS.md` §2 — WASM (variant a) | the same, *twice* (a WASM Lua runtime cannot load a native `libtree-sitter` at all) |
| `PROTOCOLS_AND_AGENTS.md` §4a — native runner host | the same |

`PORTABILITY.md` establishes that both bindings fail **on Windows** —
`ltreesitter` does not compile (a real upstream `_WIN32` defect),
`lua-tree-sitter` compiles after two local packaging fixes and then
segfaults in `tree:root_node()`. It also says plainly what has *not* been
done: **neither binding was ever tested on Linux or macOS**, the two
packaging bugs are platform-neutral, and the segfault hypothesis (a mingw
struct-by-value ABI problem with the 32-byte `TSNode` return) is
Windows-specific by its own terms.

**This is one experiment, and it is cheap.** WSL with Arch and `gcc` is
present on the development machine; `lua`/`luarocks` are one `pacman -S`
away. Call it 1–2 hours.

**Both outcomes are a result**, which is the actual argument for doing it
first:

- **It works on Linux** → the desktop app and the full standalone stop being
  blocked and become plannable projects. The mingw-ABI hypothesis is
  confirmed, and the Windows story becomes a known, separable problem
  (target Linux/WSL first, or fix the binding upstream).
- **It segfaults there too** → four items are closed with evidence instead
  of drifting indefinitely as "maybe someday". This repository's own
  convention already treats that as an outcome: *"a documented rejection is
  as much a result as a shipped feature"* ([`../ROADMAP.md`](../ROADMAP.md)).

Nothing below Phase 0 depends on its result, so it blocks no other work.

## Finding 2 — the delivery mode is itself a feature, and the analyses missed it

`DESKTOP_WEBAPP.md` argues the desktop/web tier is mostly redundant because
*"a rich browser UI was already solved twice in-house"*. That is a correct
answer to the question it asked — **can you view a map in a browser** — and
the wrong question for the idea it was costing.

The question it did not ask: **can someone who does not use Neovim analyse
their Lua project at all?** Today, no. `:DocMap` needs an editor session;
`scripts/gen_map.lua` needs `nvim --headless`. "Install a thing, or open a
website, point it at a Lua project, get a map" is a *different product* from
"open Neovim, run `:DocMap`, then open the file it wrote" — not a nicer
skin on the same one. The delivery mode **is** the feature, and it addresses
an audience the current shape structurally cannot reach.

Two consequences that change verdicts recorded elsewhere in this folder:

- **The desktop half is squarely Phase 0's question.** It needs standalone
  generation and nothing else new — no trust model, no multi-tenancy, no
  auth. `DESKTOP_WEBAPP.md`'s own verdict already calls the UI half "mostly
  exists"; a project switcher and packaging are the remaining work *after*
  the parser question resolves. If Phase 0 succeeds, this is the single
  largest genuinely-new capability available in this folder.
- **It names the use case `PROTOCOLS_AND_AGENTS.md` §2 set as WASM's own
  revisit condition.** That document parks WASM with: *"Revisit if a 'paste
  a repo URL, get a map' web service is ever actually wanted — that is the
  use case that would make it the right tool rather than an interesting
  one."* The web half of this idea **is** that use case. WASM moves from
  "answering a question nobody has asked" to "answering a question that has
  now been asked" — which makes it *relevant*, not *cheap*: it still
  inherits the treesitter problem twice, and the hosted trust model is still
  undesigned. It is correctly last, but it is no longer parked.

The `127.0.0.1`-only posture is worth restating precisely, because it is
easy to read as an obstacle and it is not: it is a deliberate property of
the *current, single-user, personal-machine server*, and the reason that
server never needed auth. A hosted service does not "lift" it — a hosted
service is a different program that would have its own trust model from
line one. Nothing about building one invalidates the local server's choice.

---

## The phases

```
Phase 0  treesitter binding on Linux      1–2 h    decides 4 projects
   │
   ├─ Phase 1  MCP server                 days     no dependencies
   ├─ Phase 2  Checklist ledger, scope (b) days     no dependencies
   └─ Phase 4  UI polish                  ongoing  no dependencies
         │
      Phase 3  Agent integration          small    needs 1 + 2
                                                    │
   (if Phase 0 succeeds)                            │
      Phase 5  Standalone → desktop app   large     needs 0
      Phase 6  Hosted web tier            largest   needs 0 + a trust model
```

Phases 1, 2 and 4 depend on nothing and can run in any order or in parallel.
Only 3, 5 and 6 have real preconditions.

### Phase 0 — the experiment

Build `lua-tree-sitter` under WSL/Arch (applying `PORTABILITY.md`'s two
documented packaging fixes: build from a `--recurse-submodules` checkout,
add `tree-sitter/lib/src` to `incdirs`), compile `tree-sitter-lua` with the
one `gcc` command that document already verified works, and call
`tree:root_node()`.

Record the result in `PORTABILITY.md` either way — that document is already
the place this question is tracked, and it explicitly asks for this test.

### Phase 1 — MCP server

The only one of `PROTOCOLS_AND_AGENTS.md`'s four ideas that is *cheap*, for
a checkable reason: the tool surface already exists, tested, as
`Documentation.Handle` (`ir`, `node`, `requires`, `required_by`, `callers`,
`callees`, `findings`, `rescan`). The server is a thin adapter over an
existing interface, not new extraction.

- **stdio transport.** Sidesteps every question the hosted-web-app idea
  drowns in — no ports, no auth, no trust boundary; the agent spawns the
  server as a subprocess.
- **Host: `nvim --headless -l`.** Sufficient for this ecosystem's own use.
  A standalone host is a Phase-0-dependent improvement, not a precondition.
- **Risk:** MCP's spec is still moving. The mitigation is what the adapter
  already is — thin.

### Phase 2 — checklist ledger, scope (b) only

`CHECKLIST_TASK_RUNNER.md`'s own recommendation, followed exactly: build
**(b)**, the curated ledger with staleness detection, and not **(a)**, the
auto-checkable items. (a) re-derives a narrower version of the existing
16-check catalogue with extra syntax; (b) is the part that is actually new,
and the `RULES/` corpus that motivated the idea is entirely (b)-shaped.

Three decisions that document raises and deliberately leaves open should be
settled **before** building, since two of them change the schema:

1. **Boolean, or thresholds?** Nothing named so far needs more than boolean
   → boolean.
2. **Staleness via working-tree mtime, or a real `git log` walk?**
   `core/churn.lua` already faced this exact choice — adopt its answer
   rather than re-deriving one.
3. **Verification by hand-editing Markdown, or a command?** The `RULES/`
   precedent was hand-edited throughout, and no need for more has been
   stated → hand-edit.

Deliberately out of scope: **multi-repo**. `RULES/` spans 33 repos;
documentation.nvim scans one. That needs `IDEAS.md` §6.6/§6.7 (both
unbuilt), and until then the cross-repo view stays hand-maintained
Markdown — which is not obviously wrong for something this infrequent.

### Phase 3 — agent integration

Nearly falls out of 1 + 2: Markdown carrying `@ref`/`@verified` is already
agent-readable, and the MCP server gives structured access to the IR and
findings instead of grepping.

One design constraint, carried forward from `PROTOCOLS_AND_AGENTS.md`
because it is exactly the kind of thing that gets lost in enthusiasm: **an
agent that may write `@verified` timestamps is an agent that can mark its
own work as verified.** The verifying actor and the verified actor must not
be the same without a human in between.

### Phase 4 — UI polish

Zero dependencies, and by `DESKTOP_WEBAPP.md`'s own assessment the highest
leverage per hour in this folder: typography, information density, a real
design pass over the Analysis panels' tables, better empty and loading
states. Needs none of standalone generation, packaging, or a trust model.
Can run in parallel with everything.

### Phase 5 — standalone → desktop app *(only if Phase 0 succeeds)*

In order: full-fidelity standalone generation (the parser-less MVP in
`standalone/` already works for everything that does not need per-function
facts) → a project switcher (genuinely unscoped; touches state and URL
scheme, not just a screen) → packaging via `luastatic` (`PORTABILITY.md`
confirmed this is the least interesting step, having actually tried it).

Worth keeping in view: "open it in the user's default browser" is already
what `:DocMap open` does, and is arguably shell enough — a browser tab *is*
the chrome most users of a dev tool already trust. Tauri/Electron is a
choice to defer, not a precondition.

### Phase 6 — hosted web tier *(largest, least developed)*

Now justified by a real use case (Finding 2) rather than parked, but still
the most expensive item here and the only one whose hardest question has no
answer sketched anywhere in this ecosystem: a multi-tenant trust model —
who sees which repo's map, how a snapshot is scoped per viewer rather than
per machine, what happens when two sessions collide.

The cheapest honest version remains what `DESKTOP_WEBAPP.md` identifies:
publish the *static* page (`IDEAS.md` §6.3, GitHub Pages) for the panels
that need no server, and keep everything server-backed (History, Telemetry,
Loaded) local. That is a publish workflow, not a rewrite, and it delivers a
real slice of "go to a website" without answering the trust question at all.
The full version — "paste a repo URL, get a map" — additionally needs
Phase 0 *and* WASM or a server-side generation tier.

---

## Not building, and why

These are recorded so the questions do not get re-litigated from a blank
slate. Two of the four verdicts below were revised by Finding 2 and are
marked accordingly.

| Idea | Verdict | Why |
|---|---|---|
| **WebSocket / WebTransport** | **No, unchanged** | All five endpoints are request/response-shaped; nothing on the page pushes. The protocol must follow a push-shaped feature, and none has been decided. WebTransport would additionally require TLS certificates on a `127.0.0.1`-only server to solve nothing. |
| **WASM** | **Revised — relevant, not cheap** | Its own revisit condition ("paste a repo URL, get a map") is now a stated want (Finding 2). Still inherits the treesitter problem twice and does not by itself answer the hosting trust model. Correctly last, no longer parked. |
| **Hosted web app** | **Revised — justified, still hardest** | The delivery mode is a real feature (Finding 2), so this is no longer "answering nothing". The multi-tenant trust model remains genuinely undesigned — the honest first step is the static-publish slice above. |
| **Native checklist runner (rewrite in Rust/Go/C++)** | **No, unchanged** | Not compute-bound — Markdown parsing plus `git log` per cited path. The "standalone binary" half is Phase 0/5's question, and has nothing to do with language choice. |
| **Checklist scope (a) alone** | **No, unchanged** | Re-derives a narrower version of the existing check catalogue with extra syntax. Composes fine *after* (b); not worth building first or alone. |

---

## Open questions this plan does not answer

- **Which platform the desktop app targets first**, if Phase 0 succeeds on
  Linux but the Windows binding stays broken. Shipping Linux-only, fixing
  the binding upstream, and vendoring a patched binding are three different
  answers with different costs; none is obviously right yet.
- **Whether the project switcher (Phase 5) is a documentation.nvim feature
  at all**, or a property of whatever shell hosts it. It has no analogue in
  the current single-repo model.
- **Multi-repo scope**, deferred out of Phase 2 above, is the same shape of
  question as the project switcher — worth noticing that two independent
  phases both stall on "this tool models one repository at a time", which
  may mean `IDEAS.md` §6.6/§6.7 is more load-bearing than its own section
  suggests.
