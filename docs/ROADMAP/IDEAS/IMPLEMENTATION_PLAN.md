# V1 extension — implementation plan

Written 2026-08-11, across the four analyses in this folder
([`PORTABILITY.md`](PORTABILITY.md), [`DESKTOP_WEBAPP.md`](DESKTOP_WEBAPP.md),
`PROTOCOLS_AND_AGENTS.md`, `CHECKLIST_TASK_RUNNER.md`). Those documents each
cost *one* idea honestly and stop there, by design. This one does the thing
none of them can do alone: **draw the dependency graph across all four**, and
sequence accordingly.

It adds no new analysis of its own except where the cross-document view
produces a finding the individual documents could not — which happens twice,
and both times it changes the order of work.

**Two of the four are since absorbed and removed (2026-08-15).**
`PROTOCOLS_AND_AGENTS.md`'s MCP-server idea shipped as Phase 1 below and is
documented in [`docs/MCP.md`](../../MCP.md); `CHECKLIST_TASK_RUNNER.md`'s
idea shipped as Phase 2 below and is documented in
[`docs/CHECKLIST_FORMAT.md`](../../CHECKLIST_FORMAT.md). Both are kept as
plain names rather than links from here on, since the files themselves are
gone — the same convention this folder already used for the first one
before the second joined it. `PORTABILITY.md` and `DESKTOP_WEBAPP.md`
remain, the latter substantially updated 2026-08-15 to record that its
desktop half shipped as a separate repository,
[`docmap-desktop`](https://github.com/StefanBartl/docmap-desktop).
`IDEAS.md`'s own numbered backlog is a fifth, later addition with its own
effort/benefit assessment in
[`IDEAS_IMPLEMENTATION_PLAN.md`](IDEAS_IMPLEMENTATION_PLAN.md) — a
different scope from this document's four-document dependency graph, kept
separate rather than folded in here.

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

> **Superseded 2026-08-11, later the same day: the MSVC experiment was
> never needed, because the Windows failure does not reproduce.** Re-running
> the crashing call against the *same* mingw-built artifact — same file,
> built at 03:16, hours before the bug report that describes it was
> committed at 08:47 — passes, as does the whole pipeline, against a
> grammar built from source with no Neovim involved. Three candidate
> explanations were checked and none survives (static `libtree-sitter`,
> single `lua54.dll`, one compiler on both sides of the call), so the cause
> of the original observation is genuinely unexplained rather than fixed.
> Full detail and the exact output in
> [`PORTABILITY.md`](PORTABILITY.md#and-then-it-did-not-reproduce-on-windows-either-2026-08-11-later-the-same-day).
>
> **Consequence: Windows is no longer the critical path, because it is no
> longer a known-broken target.** The platform-priority reasoning above
> still stands as reasoning — Windows is what this is built for, so it is
> the platform whose breakage would matter most — it simply has no breakage
> left to prioritise. The MSVC probe stays on the shelf rather than struck
> out, in case the crash returns.
>
> The durable outcome is not the result but the harness:
> [`standalone/check_treesitter.lua`](../../../standalone/check_treesitter.lua)
> now answers this question on demand, on any machine, against a stated
> expected result — which is what the two prior hand-run investigations,
> whose commands were thrown away, could not do.

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
   ├─ Phase 1  MCP server                 DONE ✓   shipped 2026-08-11
   ├─ Phase 2  Checklist ledger, scope (b) DONE ✓  shipped 2026-08-11
   ├─ Phase 4  UI polish                  ongoing  no dependencies
   │     │
   │  Phase 3  Agent integration          DONE ✓  shipped 2026-08-11
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

### Phase 1 — MCP server — **done 2026-08-11**

The only one of `PROTOCOLS_AND_AGENTS.md`'s four ideas that is *cheap*, for
a checkable reason: the tool surface already exists, tested, as
`Documentation.Handle` (`ir`, `node`, `requires`, `required_by`, `callers`,
`callees`, `findings`, `rescan`). The server is a thin adapter over an
existing interface, not new extraction.

Built exactly as costed — stdio transport, `nvim --headless -l` host, eight
tools that are each a projection of a handle method. Full detail in
[`docs/MCP.md`](../../MCP.md); the code is `lua/documentation/mcp/`
(`tools.lua`, `protocol.lua`, `init.lua`), the entry point
`scripts/mcp_server.lua`, the tests `TESTS/mcp_spec.lua`.

Four things the estimate did not name, all decided while building:

- **`protocol.lua` is split from `init.lua`.** A message handler that reads
  and writes files can only be tested by starting a subprocess and talking
  to it; `protocol.dispatch(server, line)` is a function from a string to a
  string, so the spec drives the whole protocol — handshake, every tool,
  every error path — in-process. The transport is then a `while io.read`
  loop short enough to read.
- **Watching is off, and `docmap_rescan` exists because of it.** A watch
  callback firing mid-request would swap the IR out from under a tool call
  that had already read it, so a client could get a node list from one scan
  and edges from the next. Making the refresh an explicit tool moves that
  moment into the client's control.
- **No tool returns a raw IR node.** A node carries parser-internal and
  render-only fields an agent pays for in tokens and can almost never use;
  each tool returns a named projection instead, so growing the IR does not
  silently grow every tool result. The spec asserts this rather than
  trusting it.
- **A failing tool is a result, not a transport error.** An unknown node id
  comes back as `isError`, which the model sees and can correct, rather
  than a JSON-RPC error the client's plumbing swallows.

The costed risk stands unchanged and is now the only one: **MCP's spec is
still moving.** The mitigation held — nothing branches on the protocol
revision, because the surface used (`initialize`, `tools/list`,
`tools/call`, `ping`) is identical across every revision the server claims.
`protocol.SUPPORTED` is therefore a compatibility *claim*, deliberately
conservative: adding a revision means checking it, not guessing forward.

### Phase 2 — checklist ledger, scope (b) only — **done 2026-08-11**

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

Built as specified. `core/checklist.lua` (parser + `status` + `parse_history`),
`bindings/usrcmds/checklist.lua` (`:DocMap checklist [all]`), an
`/api/checklist` serve route and an Analysis panel; format documented in
[`docs/CHECKLIST_FORMAT.md`](../../CHECKLIST_FORMAT.md), dogfooded in
`docs/CHECKLIST/architecture.md`.

**A fourth decision the three above did not anticipate, and it overturned this
document's own placement suggestion.** `CHECKLIST_TASK_RUNNER.md` proposed "a
tenth Analysis panel". Analysis panels bake into the committed page, and
`core/churn.lua` had already established that git data cannot enter a
byte-compared artifact without the map losing its fixed point — so the
staleness verdict, which is the whole feature, could not live there. The
resolution splits content from verdict: the ledger is parsed Markdown and
bakes into `module_map.json` happily, while the verdict is computed live. The
panel therefore renders *completely* from `file://` and gains one column under
`:DocMap serve` — the inverse of Telemetry and Loaded, which are blank without
a server.

Two parser bugs were found by running against a real ledger rather than only
fixtures, and both are the kind only real data produces: multi-line items lost
everything after their first line, and a wrapped `<!-- @note -->` leaked into
the item text. Both fixed with tests.

Deliberately out of scope: **multi-repo**. `RULES/` spans 33 repos;
documentation.nvim scans one. That needs `IDEAS.md` §6.6/§6.7 (both
unbuilt), and until then the cross-repo view stays hand-maintained
Markdown — which is not obviously wrong for something this infrequent.

### Phase 3 — agent integration — **done 2026-08-11**

Fell out of 1 + 2 almost exactly as costed: Markdown carrying `@ref`/
`@verified` was already agent-readable, and the only genuinely new work was
a ninth MCP tool, `docmap_checklist`, giving structured access to the ledger
instead of asking an agent to parse Markdown itself — the same "structured
access instead of grepping" argument §1 already made for the IR and
findings, applied to the one corpus that hadn't been wired up yet.

The design constraint carried forward from `PROTOCOLS_AND_AGENTS.md` is
**enforced by omission, not by a check**: there is no `docmap_checklist_verify`
tool, and `mcp/tools.lua`'s own header now states the reason as a standing
rule for anyone tempted to add one — an agent that may write `@verified`
timestamps is an agent that can mark its own work as verified, and the
verifying actor and the verified actor must not be the same without a human
in between. `docmap_checklist` reads; nothing in the catalogue writes.

Verified against a real, disposable git repository with pinned commit dates
(`GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE`), not only against `core/checklist.lua`'s
existing pure-function coverage — the point being to exercise the plumbing
`checklist_spec.lua` cannot reach: `ctx.out_dir` arriving at the tool,
`handle.root` reaching the git subprocess, `status()` reached through the
full JSON-RPC round trip. Also exercised live over real stdio against a
running `nvim --headless -l scripts/mcp_server.lua` piped at this
repository's own checklist, matching `:DocMap checklist`'s own numbers
exactly (0 stale, 1 unverified, 7 current, of 8).

### Phase 4 — UI polish — **ongoing, first slice landed 2026-08-11**

Zero dependencies, and by `DESKTOP_WEBAPP.md`'s own assessment the highest
leverage per hour in this folder: typography, information density, a real
design pass over the Analysis panels' tables, better empty and loading
states. Needs none of standalone generation, packaging, or a trust model.
Can run in parallel with everything.

Deliberately no fixed end-state — this is a track, not a ticket. Each
slice below is scoped to what could be **measured against the real
rendered page and verified**, not what looked plausible from the CSS
alone; the session that shipped the first slice had no screenshot
capability, which set the risk bar: only change what could be confirmed
by real DOM measurements before and after.

**Slice 1 — sticky headers on the Analysis tables.** Measured first: the
"Tested" panel alone renders 79 rows with no `position:sticky` on
`.antable th`, so scrolling past the first screenful loses the column
labels entirely — a real, common case, not an edge one, on any tree past
a couple dozen modules. `.cmptable` (the Compare tab) already solved this
exact problem the same way (`position:sticky;top:0` plus an opaque
`background`), so this slice ports that proven pattern to `.antable`
rather than inventing a new one. Verified live, not just read off the
CSS: before the fix, the header's `getBoundingClientRect().top` moved
with the page; after, it pins at `0` once scrolled and the row that was
about to sit under it is correctly occluded by the header's own opaque
background, matching `.cmptable`'s existing, working behavior exactly —
confirmed by scrolling a served copy of this repository's own map (1213px
table width, 79 rows) with `document.elementFromPoint`-style checks
before and after.

**Deliberately not attempted in this slice**, and flagged rather than
silently skipped: a full typographic scale pass. Measured the same page's
CSS and found **16 distinct `font-size` values**, several only half a
pixel apart (`11px`/`11.5px`, `12px`/`12.5px`, `13px`/`13.5px`) — real
signal that the scale accreted rather than was designed, and exactly what
"typography, information density" in this phase's own brief points at.
Left alone here because it is a genuinely large, cross-cutting change
(6,600+ lines) with real risk of a visual regression that this repository
has no automated way to catch, and no screenshot tool was available this
session to catch it by eye either — the right shape for that work is its
own slice, with visual verification available, not folded into whatever
else happens to be in flight. Zebra striping on `.antable` rows was
considered for the same reason and set aside for the same one: it would
be a new visual pattern with no precedent elsewhere on this page, and
"looks right" is not verifiable without seeing it.

**Slice 3 — the typographic scale, consolidated (2026-08-12), with the
visual verification the slice above named as the missing piece.** The
user watched a real recording of the rendered page and reported the scale
does not read as a problem visually — nothing jars. Asked directly why
merge it at all, then: because "does not jar" is not the same claim as
"is deliberate," and a scale that accreted rather than was designed stays
a maintenance hazard even when it currently looks fine — the next author
adding a `12px` next to an existing `12.5px` has no signal either value
was already close to something. Fifteen values collapsed to ten
(`9.5/10.5/11.5/12.5/13/14/15/17/19/20px`), each merge moving the
*less*-used half-pixel value onto the *more*-used one (counted, not
guessed — `11.5px` at 26 uses absorbed `11px`'s 13, not the other way),
so the majority of rules render pixel-identical to before and only the
minority actually shifted. Zebra striping: asked, declined — "passt so
wie es ist," not pursued.

**Slice 2 — a loading state for the Loaded panel.** Found by actually
exercising the fetch-backed panels rather than reading their code and
assuming they matched each other: Telemetry shows `"Loading telemetry…"`
before its snapshot-list fetch starts; Loaded did not show anything before
its own. Reproduced live rather than inferred — an artificially delayed
`window.fetch` (3s) made the gap observable: switching the toolbar to
"Loaded" flipped the active button immediately, but `#anbody` kept
showing the *previous* panel's table, unchanged, for the length of the
request. That reads as the wrong panel's data on screen, not as "still
loading" — worse than a bare blank state. First attempt at verifying this
actually caught a second bug in the verification itself: the in-app
browser's navigation didn't bypass its HTTP cache, so an early check
silently re-tested the pre-fix page and looked like the fix had failed;
re-run with a cache-busting query string, confirmed clean.

The fix is scoped tighter than Telemetry's own pattern rather than copying
it verbatim: Telemetry re-fetches on every draw (its own live data changes
per view), so it shows `"Loading…"` unconditionally every time; Loaded
only fetches once per page load (`loadedSnapLoaded`), so the message is
gated on that same flag — otherwise every *subsequent* view of an
already-loaded panel would gain a needless flash that was never a problem
before this fix. Verified both directions: the first visit shows
`"Loading…"` during the delayed fetch, and a second visit in the same
session does not.

`docmap_checklist`'s own panel (Phase 2/3) was checked against the same
question and left alone on purpose, not overlooked: it already renders the
complete, correct ledger from the baked IR before its one-time fetch even
starts, and the fetch only *enriches* that with the staleness column — a
blocking "Loading…" there would replace real, useful content with a
spinner for data that was never missing.

**Slice 3 — the same bug, a second time, in the same panel's other
fetch.** Checking whether Slice 2's fix generalized turned up that it
hadn't fully: `drawAnalysisLoaded` makes *two* fetches, not one — the
snapshot list (once per page load) and, once a specific snapshot is
picked from the dropdown, that snapshot's own data (every time the picker
changes). Slice 2 only gated the first. Reproduced the same way: delay
`fetch`, pick a snapshot, and the *previous* render — the "choose a
snapshot above" message — stayed on screen for the length of the request,
which reads as "nothing happened" rather than "loading". Telemetry never
had this problem because its unconditional loading message covers every
fetch on every draw in one line; Loaded's gate needed widening rather
than copying that unconditional shape, since Loaded's first fetch really
is a one-time cost that a repeat visit shouldn't re-flash for. Fixed by
extending the same condition to also cover "a snapshot is selected, so
its data fetch is about to run" (`!loadedSnapLoaded || state.lsnap`), and
verified all three cases matter for on a fresh page load: first visit to
the panel shows the message, a second visit with nothing selected does
not (no needless flash), and picking a snapshot shows it again.

The methodological point worth keeping, not just the fix: finding this
came from asking "does the fix generalize to every fetch this panel
makes", not from re-running the same check that had already passed —
Slice 2's own verification would have stayed green forever without ever
exercising this second path.

**Slice 4 — the tab bar dragged the whole page sideways below 753px.**
Started by finishing the question Slice 3 opened: every `fetch()` call
site in the rendered page was enumerated (eight of them) and each checked
for a loading state. All eight now have one — Telemetry's unconditional
message covers its three, Slices 2/3 fixed Loaded's two, History already
had one before each of its two, and `docmap_checklist`'s omission is the
deliberate one documented above. That family is closed; nothing further
to fix there, which is a result worth recording rather than a gap.

The real defect surfaced from measuring the page at narrow widths
instead: **every one of the nine tabs overflowed the document
horizontally by 126–131px at a 600px viewport**, and in eight of nine the
widest offending element was the same one — `.tabs`, the main tab bar.
It is `display:flex` with `flex-wrap:nowrap` and `overflow-x:visible`, so
its ten buttons (752.6px intrinsic: 686.6px of buttons, 18px of gaps,
48px of padding) spill out of its own correctly-600px-wide box and drag
the document with them, with no ancestor clipping them.

Worth stating why this counts as a defect and not an invented
requirement, since that is the bar this phase set for itself: the page
already declares responsive intent explicitly — a
`<meta name="viewport">` tag plus **five** `@media (max-width:860px)`
rules that collapse `main`, `#tree`, `#detail`, `#hist-list` and
`#hist-detail` from two columns to one. That work was already invested
and then silently defeated: the columns collapse correctly and the tab
bar hauls the whole document sideways anyway, so the narrow layout still
could not be read without horizontal scrolling. Fixing it restores
behavior the page already pays for, rather than adding a new goal.

The fix is one property, and it is the page's own proven pattern rather
than a new one — the same discipline Slice 1 used in porting
`.cmptable`'s sticky header to `.antable`. This page already separates
two cases cleanly: **control rows wrap** (`.toolbar`, `.hctl`, `.links`,
`.qk-acts`, `.telpicker`, `.ixjump`, `.stats` — nine occurrences of
`flex-wrap:wrap`), while **intrinsically wide content scrolls in its own
container** (`.wrap`, `.cmp-scroll`, `.hist-diff`, the code blocks,
`#hgraph-wrap` — where wrapping would destroy meaning). `.tabs` is a
control row, and was the only one on the page missing `flex-wrap:wrap`;
`.toolbar`, which has it, sits eight lines below `.tabs` in the same
stylesheet. Notably `#hgraph` — 9408px wide on the Hierarchy tab — was
measured and found correctly contained by its own scroll parent, so the
giant graph was never the problem the tab bar was.

Verified in both directions on a served copy, with a cache-busting query
string from the start because Slice 2's own verification had already
been fooled once by the in-app browser's HTTP cache. At 600px: all nine
tabs go from 126–131px of overflow to **exactly 0**, all ten buttons stay
in the viewport, none collapses to zero width, and the bar becomes two
rows (35px → 71px). At 1280px: single row on all nine tabs, 35px bar
height, `scrollWidth` 1265 against a 1265px client width — byte-identical
to the pre-fix desktop measurement, and the active tab's underline
measured flush with its row's baseline. The property is inert above
~753px and engages only below, which also means it cannot interact with
the hardcoded `max-height:calc(100vh - 132px)` on the four panes: that
value is already overridden to `none` by the `max-width:860px` rules
everywhere a wrap can occur.

**Slice 5 — keyboard parity, applied to the one control it had skipped.**
Chosen because it is the remaining part of "UI polish" that is fully
verifiable without a screenshot: focus and activation are DOM facts, not
matters of taste. Measured across every tab by enumerating elements that
signal themselves clickable (`cursor:pointer`) and are not
keyboard-reachable. The sharpest result was on the Index tab: **481
anchors, 456 of them carrying `data-node`, and none focusable** — no
`href`, no `tabindex` — while on those very same rows all 456 `.marki`
("mark for comparison") toggles and all 456 `.sigi` (`ⓘ` annotations)
triggers *were* reachable. Every accessory keyboard-operable, the primary
action — follow the link — not.

The page had already named and solved this: "**Keyboard parity**" is its
own term, used in two places, and the complete pattern is three parts —
`tabindex="0" role="button"`, a focus style, and a delegated `keydown`
matching Enter/Space against `document.activeElement`'s dataset that
calls the same function the click handler does. `.marki`, `.sigi` and
`.doci` each have all three. So this slice ports an in-house pattern
rather than inventing one, exactly as Slices 1 and 4 did.

A second defect fell out of the same measurement, and it is the more
interesting one: `.feat-name`/`.feat-tab-name` already shipped
`tabindex="0" role="button"` — but their only listener was `click`. They
took a tab stop, announced themselves to assistive technology as
buttons, and did nothing when operated. `role="button"` does **not** make
a non-button element activate on Enter; that was confirmed by dispatching
real key events against the pre-fix page rather than asserted from spec
knowledge. Focusable-but-dead is worse than not focusable, because the
role is a promise.

Fixed with one delegated listener covering both cases, keyed on
`data-node`. It is disjoint from the two existing handlers by
construction — they key on `data-mark`/`data-sig`/`data-doc`, and no
element carries both — and delegated rather than bound per element for
the reason the graph's own click handler already gives: these lists are
rebuilt wholesale on redraw, so per-element binding stacks duplicates on
whatever survives. Plus `tabindex="0" role="button"` at the three `.nfn`
render sites and a `:focus-visible` outline ported from `.stat-link`'s.

**A measurement mistake worth recording, because it nearly shipped a
wrong claim.** The first verification used `location.hash` as the
success signal and reported that Space did not activate `.feat-name`.
That was an artifact: `navigate()` goes through `pushState`, and the test
harness had written `location.hash` synchronously just before, so the
read raced. Re-running against the actual rendered state — which `.view`
carries `active` — showed Enter *and* Space both working all along. The
pre-fix baseline was then re-established from the committed artifact
itself rather than from the flaky signal: `git show HEAD:docs/map/
index.html` contains three `.nfn` render sites with **zero** `tabindex`,
and exactly **two** Enter/Space handlers, keyed on `dataset.sig`/`doc`
and `dataset.mark` — none on `dataset.node`. Static proof of both halves.

Final state, verified on the rendered view rather than the URL: Index
links focus and navigate to the Tree view on both Enter and Space, at the
correct target node; `.feat-name` likewise; and neither existing handler
regressed — `.marki` still toggles `marki` → `marki on` and back without
navigating, `.sigi` still opens its popup, both staying on the Index tab.

**Slice 6 — roving tabindex for the long lists.** Slice 5 deliberately
stopped short of the rest of what it had measured: Tree rows (169),
History commits (100), Analysis rows (79) and the three sort headers. A
`tabindex` each, the way the Index's links got one, would have put ~440
Tab presses between the tab bar and the content — accessible on a
checklist, unusable in practice. That needed a different pattern and its
own decision, which is why it was flagged rather than folded in.

The pattern is roving tabindex: **one** tab stop per list, on the
container, and the arrows move within it, so exactly one element is
focusable at any moment. Implemented once as `rovingList(containerId,
itemSelector, activate, hooks)` and applied to `#tree`, `#hist-list` and
`#anbody` — all three of which exist in the initial HTML and are never
replaced. Delegated on those stable containers and never bound per item,
for the reason the graph's own click handler already gives: these bodies
are rebuilt wholesale on redraw and per-item binding stacks duplicates.
Items therefore carry no `tabindex` attribute at rest at all; `tabIndex =
-1` is set on one lazily, immediately before focusing it, which is also
what makes the whole thing survive a redraw with no re-wiring.

`offsetParent === null` is the visibility filter, and it earns its place
rather than being a formality: it excludes both rows inside a collapsed
`.kids` (`display:none`) and rows the search box hid via `style.display`,
so the arrows walk exactly what the eye sees. Verified by collapsing the
root and confirming the arrows no longer descend into it.

The Tree is a tree, not a flat list, so it passes a `horizontal` hook:
Right expands a collapsed node and otherwise steps into the first child,
Left collapses an open one and otherwise moves to the parent. It reuses
the twisty's own click handler rather than re-implementing the toggle, so
there stays one source of truth for what expanding means — including the
glyph swap.

Two scoping calls, both deliberate. The Analysis rows get roving focus
but **no** `listbox`/`option` roles: that body holds a real `<table>`,
and overriding table semantics with list roles would throw away the row
and column relationships a screen reader otherwise gets for free. And the
sort headers are *not* a roving list — three controls in a row are
genuinely three tab stops, so they get Slice 5's simpler treatment
(`tabindex`/`role`, a delegated Enter/Space that replays the click rather
than duplicating the ascending-vs-descending logic) plus `aria-sort`,
which is the one ARIA property a sortable column header actually owns and
which was already derivable from state at that point.

**A bug this slice's own verification caught, worth recording because
reasoning would not have found it.** `aria-expanded` is stamped by a
`syncTreeExpanded` pass hung off a click listener on `#tree`. The first
version used the bubble phase, and measurement showed the attribute still
reading `"true"` on a node that had just collapsed — for mouse clicks as
well as keyboard. The cause is that the twisty's own handler calls
`ev.stopPropagation()` (so expanding a node does not also select it), so
the one click that actually changes expanded state never reaches a
bubble-phase listener on the container. Moved to the capture phase, which
runs on the way down, before that stop. Confirmed afterwards for both
input methods, and confirmed that all 163 rows with children carry the
attribute while no leaf row does.

The fuller `tree`/`treeitem`/`group` role taxonomy is deliberately not
attempted. `aria-expanded` is unambiguous and measurable; the role
taxonomy is neither without a screen reader to check it against, and
getting it half-right is worse than leaving native semantics alone —
which is the same bar that keeps the typographic scale and zebra striping
out of this phase.

Verified: tab stops went from 77 to **78** on Tree (the container, not
169 rows), 16 → 17 on History, 30 → 34 on Analysis (container plus the
three sort headers) — zero items carry a `tabindex` at rest in any of the
three. Arrows move and reverse, Home/End jump, Enter selects the right
row in all three lists, Right/Left expand and collapse and traverse the
Tree, Enter on a sort header re-sorts, and the Slice 5 controls are
untouched: Index links still navigate, `.marki` still toggles, `.sigi`
still opens its popup.

### Phase 5 — standalone → desktop app *(unblocked on Linux and Windows, 2026-08-11)*

In order: full-fidelity standalone generation (the parser-less MVP in
`standalone/` already works for everything that does not need per-function
facts) → ~~a project switcher~~ → packaging via `luastatic`
(`PORTABILITY.md` confirmed this is the least interesting step, having
actually tried it).

**The project switcher is no longer part of this phase (decided
2026-08-11).** See "A switcher belongs to the shell" below: it is a
property of whatever hosts the map, not a feature of this plugin.

Worth keeping in view: "open it in the user's default browser" is already
what `:DocMap open` does, and is arguably shell enough — a browser tab *is*
the chrome most users of a dev tool already trust. Tauri/Electron is a
choice to defer, not a precondition.

**Prerequisite status (2026-08-11):** the real-parsing question this phase
was gated on is answered on both tested platforms — `lua-tree-sitter` runs
the full parse → query → cursor → captures → byte-offset pipeline on Linux
*and* natively on Windows, against a grammar built from source, with no
Neovim present. Verify on any machine with
`lua standalone/check_treesitter.lua <grammar> lua`. **macOS is out of
scope by decision, not by omission** — it is not a target for this
project, so it should stop appearing as an open question.

**First bullet: done (2026-08-11).** Full-fidelity standalone generation
works. [`standalone/treesitter.lua`](../../../standalone/treesitter.lua)
replaces the inert parser stub with a real `vim.treesitter`, and **no
`core/*.lua` file changed to accommodate it** — the Step 1 split holding
under a second host is the actual result here, tested rather than
asserted. Acceptance was a byte comparison rather than a judgement:
this repository's own map, generated both ways, is identical in all three
artifacts (`module_map.json` 953,400 B, `index.html` 1,504,097 B,
`overview.md` 13,433 B).

Two latent determinism bugs in the plugin itself fell out of it, both
invisible from inside Neovim: LuaJIT writes an integral float as `100`,
PUC Lua 5.3+ as `100.0`, and both leaked into the byte-compared artifact
via `core/json.lua` and `core/quicks.lua`. Since `--check` byte-compares
and a pre-commit hook fails on it, "same tree, different Lua, reads as
stale" was a real defect waiting for its first non-Neovim run. Detail in
[`PORTABILITY.md`](PORTABILITY.md#step-3-is-done-the-standalone-build-is-byte-identical-to-neovim-2026-08-11).

**Packaging: done 2026-08-11 for the parser-less build.** A single 1.5 MB
`docmap.exe` runs with nothing beside it — no Lua, no LuaRocks tree, no
Neovim, no `LUA_PATH`. `PORTABILITY.md` had rated this "the least
interesting step"; that was wrong, and its
[Step 2](PORTABILITY.md#step-2--a-binary--done-2026-08-11-and-it-was-not-the-least-interesting-step)
now records the three obstacles that only appear when you run it —
`luastatic` deriving module names from file paths (so a staging layout is
required), an unquoted `nm` call that breaks on any library path with a
space, and a C-compiler probe that fails on Windows even with `CC` set.

**And the build is a script, not a recipe (2026-08-11).**
[`scripts/package.lua`](../../../scripts/package.lua) runs manifest →
staging → `luastatic` → compile → verify, encoding every workaround so
none has to be rediscovered. Writing it turned up two further defects of
the same family, both silent until run: the same unquoted-command bug this
project had just criticised `luastatic` for, reproduced by accident one
file later; and a catch-all in the path mapping that registered every
module flat (`calls`, `check`, `init`), reported a successful build, and
produced a binary that died at its first `require`. The `verify` step
exists because a binary that links is not a binary that runs — and it is
what caught that one.

**The full-fidelity binary works: Phase 5 is done (2026-08-11).**
`docmap.exe` (1.7 MB) plus one grammar shared library (146 KB), with no
Lua, no LuaRocks and no Neovim, produces a map **byte-identical** to
`nvim --headless -l scripts/gen_map.lua` — verified by letting the binary
write into `docs/map` itself and diffing against the committed artifacts.

Two findings from it, both in
[`PORTABILITY.md`](PORTABILITY.md#the-full-fidelity-binary-works-too-2026-08-11):
`luastatic` registers a bundled C module by rewriting every underscore in
its `luaopen_` symbol to a dot, so `lua_tree_sitter` became
`lua.tree.sitter` and the binary silently fell back to the parser-less
path with a working binding compiled in; and the grammar stays an external
shared library on purpose, because `Language.load` resolves it by `dlopen`
at runtime and a static link has nothing to attach to.

**What was left in this phase was nothing, and the remaining choice was
made (updated 2026-08-15).** The shell — Tauri/Electron, or "open it in
the user's default browser", which `:DocMap open` already does — was a
choice to make rather than work that was blocked, and it was made: Tauri,
built as its own repository,
[`docmap-desktop`](https://github.com/StefanBartl/docmap-desktop), which
also picked up the project switcher named below. See
[`DESKTOP_WEBAPP.md`](DESKTOP_WEBAPP.md) for the current, dated account of
what shipped there and how it relates to the engine built in this phase.

#### A switcher belongs to the shell, not to this plugin (decided 2026-08-11)

The open question this plan carried — *is the project switcher a
documentation.nvim feature at all, or a property of whatever shell hosts
it?* — is answered: **the shell.** The principle it turns on is short:

> A switcher belongs wherever there is no editor to answer "which
> project?".

**In Neovim there is one, and it does not merely let you say which
project — it resolves it automatically.** `buffer_root()` in
`bindings/usrcmds/init.lua` walks up from the current buffer to the
nearest `.git`, *per invocation*. That function's own comment records the
bug that existed when the root was resolved once in `setup()` instead:
because the plugin is `cmd`-lazy, "once" meant the first `:DocMap` of the
session, and every later call silently regenerated that first repository.
So "which project" is not a question the editor path needs a UI for — the
place you are working *is* the answer, and a switcher there would be a
second, worse answer to a question already settled.

**A consequence worth stating explicitly, because it constrains any
future portal:** it must not be built into the per-repo artifact.
`index.html` cannot know how it was reached, so a switcher baked into it
would also appear in the case Neovim has already answered — including
`:DocMap serve`, which is equally "a browser opened from the editor". A
portal is therefore its own artifact, or nothing.

**Where it does belong:** the desktop shell (Phase 5's "a shell to run
in") and the hosted web tier (Phase 6). In the second there is no editor
even in principle, so a project list is not a nice extra there but a
requirement.

An editor-side picker remains *possible* — reading each known project's
committed `module_map.json`, or just opening its `docs/map/index.html` —
but is deliberately not planned. It must not go through `:DocBrowse`,
which needs an installed handle and therefore a full scan per repository;
and the need it serves ("show me a project I have no file open in") is
thin next to that cost.

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
- ~~**Whether the project switcher (Phase 5) is a documentation.nvim
  feature at all**, or a property of whatever shell hosts it.~~
  **Answered 2026-08-11: the shell.** A switcher belongs wherever there is
  no editor to answer "which project?", and in Neovim `buffer_root()`
  already answers it automatically. See
  [Phase 5](#a-switcher-belongs-to-the-shell-not-to-this-plugin-decided-2026-08-11).
- **Multi-repo scope**, deferred out of Phase 2 above, *looked* like the
  same question as the switcher, and the note here used to say two
  independent phases were stalling on "this tool models one repository at
  a time". Half of that is now resolved rather than stalled: for the
  switcher, one-repo-at-a-time turned out to be the correct design, not a
  limitation. Multi-repo scope does **not** inherit that answer — it is a
  question about the *analysis*, not about the shell, and `IDEAS.md`
  §6.6/§6.7 stays as load-bearing as before for it.
