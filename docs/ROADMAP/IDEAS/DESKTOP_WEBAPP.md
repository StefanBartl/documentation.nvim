# A polished desktop/web-app version — costed, then partly built

Raised 2026-08-11: "a Desktop/Webapp version, building on this concept, but
with everything refined, also with better View/UI/feature equipment."
Analysis, not a proposal — the same posture
[`PORTABILITY.md`](PORTABILITY.md)/[`MULTILANG.md`](MULTILANG.md) already
take, referenced from [`ROADMAP.md`](../ROADMAP.md) rather than repeated
there.

**Two different products are bundled under one idea, and they cost
completely different things.** "Desktop app" (single-user, local, packaged,
no editor open) and "web app" (hosted, reachable by more than one person)
share a UI layer but not a trust model or a distribution story. Splitting
them was this analysis's first finding, and it held: the desktop half
shipped, the web half did not, for exactly the reasons below.

**Status as of 2026-08-15: the desktop half is built and is a separate
repository, [`docmap-desktop`](https://github.com/StefanBartl/docmap-desktop).**
Read that repository's own `README.md`/`docs/ROADMAP.md`/`docs/USAGE.md`
for what it actually does; this document keeps only the reasoning and the
part that is still open (the web/hosted half).

---

## What already exists — more than the idea's framing assumed

[`docs/ECOSYSTEM.md`](../../ECOSYSTEM.md) §6 already answered
the adjacent question for runtime-analysis.nvim ("Neovim plugin, web app,
Electron app, or a compiled binary?") and found, measured rather than
guessed: **"a rich browser UI" was already solved twice in-house** —
documentation.nvim's own generated page (`core/render/html.lua`,
self-contained HTML+JS, no CDN, no build step) is one of the two examples
that analysis cites. Nine Analysis-tab panels, Compare, History, Index,
Features, Notes — most of "a webapp" colloquially means was, and remains,
available with zero desktop infrastructure at all.

## The desktop app — built (`docmap-desktop`)

The blocker this document originally recorded was generation, not display:
producing `module_map.json`/`index.html` without already being inside a
running Neovim session. That blocker is resolved —
[`PORTABILITY.md`](PORTABILITY.md) has the full, dated account — and
`docmap-desktop` is the shell built on top of the result, not a
reimplementation of it. Its own README states the split precisely: *"The
analysis" and "the view" are reused whole from documentation.nvim; what the
new repository adds is "a window, a project list, and the ability to move
between projects without opening a dozen files."*

**How this reconciles with [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md)'s
Phase 5, which records packaging as done via `luastatic` (a `docmap.exe`
built 2026-08-11):** these are not competing approaches. `luastatic`
produces the **engine** — a Neovim-free binary that scans a Lua tree and
writes a map, described in full in `PORTABILITY.md`. `docmap-desktop` is a
**Tauri application that runs that engine as a subprocess** and adds the
window/project-list/switcher layer around it, exactly the split
`docmap-desktop`'s own README describes ("this app runs it, it does not
replace it"). `PORTABILITY.md`'s own Step 4 onward — the `--api=` routes,
the Windows toolchain verification, the POSIX-path bugs found by building
under WSL — were all done *for* `docmap-desktop`'s benefit, and its own
`docs/HANDOVER.md` is cited from `PORTABILITY.md`'s Step 6 directly. Tauri
was the choice made for the shell (a native window via the OS webview,
~10 MB instead of Electron's ~150 MB); "open it in the user's default
browser," which this document originally floated as "arguably enough," was
superseded by that decision, not left unresolved.

Per docmap-desktop's own `docs/ROADMAP.md`/`docs/USAGE.md` (2026-08-15),
against the specific tasks this document costed:

| This document's task | Status in `docmap-desktop` |
|---|---|
| A project switcher | **Done** — a persisted project list, add/select/restart-survives, `Import from Neovim…` (reads the same project list `:MyPlugins` uses) and `Import from URL…` (shallow clone into a cache dir). |
| A shell to run in | **Done, decided as Tauri** — a native window via the OS webview, not "open in the browser." |
| Generation from the app | **Done** — runs the standalone engine as a subprocess, found on `PATH` or pointed at; grammars are optional and change fidelity, not success, exactly as `PORTABILITY.md` describes the parser-less fallback. |
| Packaging/distribution | **Done** — `cargo tauri build` produces an installer per platform (`.msi`/`.dmg`/`.deb`/`.AppImage`), published by a tag-triggered release workflow. |
| History (git-backed panels) | **Done** — the app is "a fourth host" for the generated page (alongside `file://`, `:DocMap serve`, and a static publish) and answers the same endpoints a local server would, because unlike the read-only cases it has the filesystem and can run `git`. |
| Telemetry / Loaded panels | **Correctly not attempted, and said so explicitly.** These numbers exist only because `runtime-analysis.nvim` instruments Lua functions while Neovim runs them — no desktop app can produce them, only read what a Neovim session already wrote. The tab stays reachable and explains this rather than hiding or erroring — the same rule [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md)'s Finding 3 states independently ("collection stays in-process, everything else can move"). |

**What `docmap-desktop` does not attempt, correctly:** reimplementing the
scan or the telemetry instrumentation itself (a "full standalone, not
standalone-*engine*" idea its own `docs/ROADMAP.md` records and explicitly
declines to schedule, for the same "two independent reimplementations to
keep behaviourally identical" reason `core/api.lua` was built to avoid at
smaller scale). It runs `documentation.nvim`'s engine and, where useful,
a personal Neovim config headless (for `Import from Neovim…`) — both
subprocess calls to something that already exists, not new analysis.

## The web app — still the least developed, unchanged verdict

Hosted, reachable by more than the person who generated it. This remains
the harder half, and the current architecture has an explicit, deliberate
answer that a web app would have to overturn:

> "Bind `127.0.0.1`, never `0.0.0.0`. This is a personal tool on a
> personal machine; there is no case where the network needs it."
> — `editor/serve.lua`'s own header comment.

That is not an oversight to lift; it is the whole reason the server has
never needed authentication, per-user isolation, or a trust boundary
between "whoever can reach this port" and "whoever owns this source code".
A real web app — even a small one, even self-hosted by one team — reopens
every one of those questions from zero: who can see which repo's map, how
a snapshot (telemetry, loaded) is scoped per viewer rather than per
machine, what happens when two people's `:DocMap serve` sessions would
otherwise collide. **`docmap-desktop` does not answer this either** — it
is a local, single-user application with no server exposed beyond its own
loopback subprocess calls, and its own `docs/HANDOVER.md` records the same
verdict directly: *"Phase 6 (Hosted Web, real) needs a multi-tenant trust
model that exists nowhere. The static half is done."*

**The honest reading of "web app" that costs the least:** the same static
page, published somewhere reachable (GitHub Pages, sketched as idea 6.3 in
[`IDEAS.md`'s backlog](IDEAS.md#63-publishing-the-map-to-github-pages)),
for the panels that don't need a server at all. Everything server-backed
(History, Telemetry, Loaded) stays a local, personal-machine feature under
this reading — which is arguably already "a web app" in the sense most
people mean when they say it about a docs site, and costs a publish
workflow, not a rewrite. This is the piece `docmap-desktop`'s own
`docs/HANDOVER.md` calls "done" (the static half); the full multi-tenant
version is not.

## What's cheap regardless of the above

Real UI/UX polish on the *existing generated page* — typography,
information density, empty/loading states — needs none of the
infrastructure above. This is [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md)
Phase 4, ongoing there, not tracked separately here.

## One application instead of several tools

A desktop application is a place where documentation.nvim's static
structure, runtime-analysis.nvim's runtime evidence, a profiler and
whatever comes later can be **one program** rather than several tools
alt-tabbed between. `docs/ECOSYSTEM.md` §7 deliberately made the
editor that meeting point for in-editor use — correct there, and it sets a
ceiling: anything joining this data in the editor has to be a Neovim
plugin in the same session. `docmap-desktop` is the second meeting point
with no such ceiling, exactly as
[`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md)'s Finding 3 argued
before the app existed. The constraint that keeps this honest is unchanged
and confirmed by `docmap-desktop`'s own scoping: telemetry **must** stay
in-process Lua (collection cannot move), but reading already has —
`telemetry.load(namespace)` reads a persisted namespace with no live
instance, which is exactly what `docmap-desktop`'s History panel and the
serve tier's Telemetry/Loaded panels both do.

## Verdict

1. **UI polish on the current page** — cheap, available now, tracked as
   `IMPLEMENTATION_PLAN.md` Phase 4, not here.
2. **A real standalone desktop app — done.** `docmap-desktop` ships: shell,
   project switcher, generation, packaging, and a fourth host for the
   git-backed panels. What is not attempted there (Telemetry/Loaded data,
   full standalone reimplementation of the analysis itself) is not
   attempted for a stated, correct reason — see the table above.
3. **A hosted web app — still the least developed of the three,
   unchanged.** The multi-tenant trust question has no answer sketched
   anywhere in this ecosystem, `docmap-desktop` included. Costed here only
   as "genuinely open, not merely unbuilt."

## Revisit if

**(2): spent — built.** Nothing left to revisit; see `docmap-desktop`'s
own `docs/ROADMAP.md` for its remaining, app-scoped backlog (a repository-URL
import beyond what already shipped, checklist execution via an agent, and
the "full standalone, not standalone-engine" idea it explicitly declines to
schedule).

**(3): if a genuine multi-person/multi-team use case shows up.** Unchanged.
The delivery-mode argument (`IMPLEMENTATION_PLAN.md`'s Finding 2) justifies
a *hosted* tier's existence in principle; the hardest question it raises —
a real multi-tenant trust model — remains entirely undesigned, in this
repository and in `docmap-desktop` alike. The static-publish slice (§6.3 in
`IDEAS.md`) remains the cheap, honest first step, and is the only part of
"web app" anyone has actually built.
