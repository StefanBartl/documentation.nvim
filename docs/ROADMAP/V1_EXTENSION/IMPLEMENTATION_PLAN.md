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

## Finding 3 — one application instead of several tools

Added 2026-08-11, and it is the strongest argument for the desktop tier so
far — stronger than Finding 2, because it survives even for someone who
*does* use Neovim.

Today this ecosystem is a set of cooperating plugins, and
[`../FEATURES/ECOSYSTEM.md`](../FEATURES/ECOSYSTEM.md) §7 decided
deliberately that they **meet in the editor**: documentation.nvim knows what
exists, runtime-analysis.nvim knows what ran, and `:DocBrowse`'s telemetry
mode is where the two cross. That decision was right for the editor, and it
quietly fixes the ceiling: everything that wants to join this data has to
be a Neovim plugin, loaded in the same session, speaking Lua.

A desktop application is a **second meeting point that has no such
ceiling** — static structure, runtime evidence, profiling data and whatever
comes later, in one program rather than three tools a reader alt-tabs
between. That is a product argument, not a packaging one, and nothing in
this folder had made it.

**The one hard constraint on it, stated precisely so the idea is not
oversold.** `ECOSYSTEM.md` §6 established that telemetry *cannot* be
anything but in-process Lua — it replaces entries in live function tables,
which requires being inside the same Lua state as the code being measured.
That has not changed and cannot. So the honest shape of a unified
application is:

- **Collection stays in-process.** A running Neovim (or, later, any other
  in-process agent) is what records call counts, timings and load order.
  A desktop app cannot do this for a Neovim session it is not inside.
- **Everything else can move.** Static analysis runs standalone already
  (Phase 0/5). And crucially, runtime data is *already* readable without a
  live instance: `runtime-analysis.telemetry.load(namespace)` reads a
  persisted namespace off disk with no instance at all, which is exactly
  what the existing Telemetry and Loaded panels already do through the
  serve tier.

So the unified app is a **viewer and analyser over everything**, with
collection remaining wherever the code actually runs. That is not a
watered-down version of the idea — it is the same split this ecosystem
already runs on, with the join moved somewhere that is not obliged to be a
plugin. A profiler fits the same shape: whatever collects it must be
in-process, but nothing forces the thing that *reads and correlates* it to
live in an editor.

## Platform priority: Windows first (decided 2026-08-11)

Stated by the author directly: this is primarily built for their own use,
and they primarily work on Windows. That **inverts the platform question**
from "which target is easiest" to "the one confirmed-broken target is the
one that matters", and it makes the Windows binding the critical path for
Phases 5 and 6 rather than a separable problem.

**Phase 0 improved that position substantially even though it ran on
Linux**, which is worth stating because it looks like the opposite: there
is now a **working build and a failing build of identical source**, and the
only variable between them is the toolchain. That is a controlled diff, not
a mystery — a much sharper debugging position than the one
[`PORTABILITY.md`](PORTABILITY.md) recorded when both platforms were
unknown.

The concrete next experiment follows directly from the recorded hypothesis
(a mingw struct-by-value ABI problem returning a 32-byte `TSNode`):
**rebuild the binding on Windows with MSVC instead of mingw.** If the
hypothesis holds, that alone fixes it, and it is the same size of
experiment Phase 0 was. Other options — patch and vendor the binding,
fix it upstream, or run generation inside WSL and ship the viewer natively
— stay open, but the MSVC test should come first because it is cheapest
and because its result narrows every other option.

The `127.0.0.1`-only posture is worth restating precisely, because it is
easy to read as an obstacle and it is not: it is a deliberate property of
the *current, single-user, personal-machine server*, and the reason that
server never needed auth. A hosted service does not "lift" it — a hosted
service is a different program that would have its own trust model from
line one. Nothing about building one invalidates the local server's choice.

---

## The phases

```
Phase 0  treesitter binding on Linux      DONE ✓   works on Linux
   │
   ├─ Phase 1  MCP server                 days     no dependencies
   ├─ Phase 2  Checklist ledger, scope (b) days    no dependencies
   ├─ Phase 4  UI polish                  ongoing  no dependencies
   │     │
   │  Phase 3  Agent integration          small    needs 1 + 2
   │
   └─ Phase 5  Standalone → desktop app   large    UNBLOCKED (Linux)
         │
      Phase 6  Hosted web tier            largest  needs 5 + a trust model
```

Phases 1, 2 and 4 depend on nothing and can run in any order or in parallel.
Only 3, 5 and 6 have real preconditions.

### Phase 0 — the experiment — **done 2026-08-11: it works on Linux**

Ran under WSL/Arch on the same machine the Windows failures were recorded
on, so the results differ by platform and nothing else. Full detail in
[`PORTABILITY.md`](PORTABILITY.md#that-next-step-was-taken-2026-08-11-it-works-on-linux);
the outcome in short:

- **`tree:root_node()` returns normally.** The Windows segfault is
  platform-specific, supporting that document's mingw struct-by-value
  hypothesis. Both of its documented packaging fixes were necessary and
  sufficient, which confirms the diagnosis rather than just repeating it.
- **The whole pipeline works**, not only the crashing call: parse → query
  → cursor → captures → byte offsets → source text, verified against a
  fixture returning exactly its expected captures.
- **`node:parent()` exists**, so the ~30-line shim costed for `ltreesitter`
  is not needed. The remaining shim is pure API *shape* (`range()`,
  `Point` vs. tuple, imperative cursor vs. generator, `get_node_text`) —
  all composable from methods that exist.
- **No LuaRocks and no root required** — plain `gcc` against system
  LuaJIT, the same shape a `luastatic` link would take.

**Consequence for this plan: Phases 5 and 6 are unblocked on Linux.**
Windows remains broken and — per "Platform priority" above — is the target
that actually matters here, so it is the critical path rather than a
footnote. The upside is that Phase 0 turned it into a *controlled* problem:
identical source, one build working and one not, toolchain the only
variable. The MSVC experiment named above follows directly from that.

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

### Phase 5 — standalone → desktop app *(unblocked on Linux, 2026-08-11)*

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

- ~~**Which platform the desktop app targets first.**~~ **Answered: Windows**
  (see "Platform priority" above). The open question underneath it is now
  narrower and technical: does an MSVC build of `lua-tree-sitter` avoid the
  segfault? That is the next experiment, and it decides between "fix the
  toolchain" and the more expensive fallbacks (patch and vendor, fix
  upstream, or generate inside WSL and ship the viewer natively).
- **Whether the project switcher (Phase 5) is a documentation.nvim feature
  at all**, or a property of whatever shell hosts it. It has no analogue in
  the current single-repo model.
- **Multi-repo scope**, deferred out of Phase 2 above, is the same shape of
  question as the project switcher — worth noticing that two independent
  phases both stall on "this tool models one repository at a time", which
  may mean `IDEAS.md` §6.6/§6.7 is more load-bearing than its own section
  suggests.
