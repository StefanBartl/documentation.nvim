# IDEAS.md backlog — effort, benefit, quick wins

Written 2026-08-15. Deliberately **not** a sequel to
[`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md), which covers a
different scope: `PORTABILITY.md`, `DESKTOP_WEBAPP.md` and the two
now-absorbed documents (`PROTOCOLS_AND_AGENTS.md`, `CHECKLIST_TASK_RUNNER.md`).
That document is referenced from here for two items only (§6.3, §6.6/§6.7)
because [`IDEAS.md`](IDEAS.md) itself names them as load-bearing for
multi-repo scope. Everything else below is `IDEAS.md`'s own numbered
backlog, assessed after stripping what has since shipped (§3.4, §4.1,
removed there on 2026-08-15 — see that file's changelog-by-diff).

**Method.** Effort is a rough size (S: a session or less, M: a few
sessions, L: a real project), not a time estimate — this repository's own
convention already warns that "no half-finished implementations" makes
S/M/L honesty matter more than precision. Benefit is judged against the
filter `IDEAS.md`'s own intro states: *"this plugin's value is detecting
where documentation and code stop agreeing"* — a feature that makes a
disagreement visible outranks one that makes the map prettier, at equal
effort. Quick win means small effort **and** real benefit **and** no open
design question blocking it — missing any of the three, it is not flagged
even if it looks cheap.

---

## At a glance

| § | Idea | Effort | Benefit | Quick win? |
|---|---|---|---|---|
| ~~1.1~~ | ~~Fenced code blocks checked against the API~~ | — | — | **Built**, as `doc-references-missing` — listed as a candidate because nobody came back to say so, the same way 6.3 was. It fires on real prose: it caught `IDEAS.md`'s own illustrative `documentation.core.scan.something`, which had been a standing warning in every CI run of this repository |
| ~~1.2~~ | ~~`@example` blocks that do not parse~~ | — | — | **Built 2026-08-18.** Cheap as rated; the "High" benefit was not: no tree in this ecosystem uses `@example`, so it has never fired on real code |
| 1.3 | API-surface breaking-change detection | M | Medium–High | No — "public" is undefined |
| 1.4 | Tests naming a function that no longer exists | S | Medium | Candidate |
| 1.5 | Orphaned `@class`/`@alias` | S | Medium | Candidate |
| 1.6 | `@since` / version-tag drift | S | Low (unused convention) | No |
| 1.7 | Cross-repo checks over `tag_files` | S–M | Medium | **Precondition met** — 33 `.nvim` repositories, ~30 with a committed map, one shared `lib.nvim`. See `ROADMAP/WORKPLAN.md` Part 4 |
| 2.1 | Annotation adoption panel (generated) | M | High | No — needs `TAGS` table refactor first |
| 2.2 | Public API surface panel | S–M | Medium–High | Candidate |
| 2.3 | Ownership / bus factor command | S | Low (single-author repo) | No |
| 2.4 | Coupling and cohesion metric | M | Speculative | No |
| ~~2.5~~ | ~~Unused requires check~~ | — | — | **Built 2026-08-18** as `unused-require`. 144 aliased requires here, none unused — the floor was measured before it shipped |
| 3.1 | Compare two artifacts visually, in-page | M–L | Medium | No |
| ~~3.2~~ | ~~Copy-link for the current view~~ | — | — | **Built 2026-08-18.** Reads `location.href` rather than re-serialising state, so there is no second answer to "what is this view called" |
| 3.3 | Print/PDF stylesheet | S | Low–Medium | Candidate |
| 4.2 | Picker integration (`pickers.nvim`/telescope) | S–M | Medium | Candidate |
| 4.3 | `K` — look up notation under cursor | S | Medium | Candidate (pairs with ReferenceTab.md) |
| 4.4 | Breadcrumb in the statusline | S | Low | No |
| 5.1 | File-based routing (Next.js/SvelteKit/Nuxt/Remix) | M | Medium | No |
| 5.2 | OpenAPI generation from endpoints | S–M | Uncertain | No — value gap named honestly by the idea itself |
| 5.3 | Vue/Svelte SFC conventions | L | Speculative | No |
| 5.4 | ORM models and migrations | L | Speculative | No |
| ~~6.1~~ | ~~SARIF output for CI~~ | — | — | **Built 2026-08-18** as `--sarif=<path>`. Findings carry no line, contrary to that section's claim, so every result points at line 1 and the run says so |
| 6.2 | A GitHub Action | S | Medium–High | Candidate |
| ~~6.3~~ | ~~Publish the map to GitHub Pages~~ | — | — | **Already built** before this pass — `.github/workflows/pages.yml`. Listed as open because nobody checked |
| ~~6.4~~ | ~~Mermaid export~~ | — | — | **Built 2026-08-18** as `:DocMap mermaid [tree|deps]`. The renderer already existed; only the way to ask for it was missing |
| 6.5 | Workspace symbols from the IR | — | Low | No — recorded rejection, not reopened |
| ~~6.6~~ | ~~Generic CLI entry, no per-repo copy~~ | — | — | **The need is met, by a different mechanism than the sketch.** `standalone/docmap.lua` takes a root and maps an arbitrary repository from anywhere, with no per-repo copy — and it is what `docmap-desktop` runs. The sketched in-Neovim CLI stays unbuilt and unasked-for |
| 6.7 | REUSE.md recipe for "many repos, one config" | S | Low–Medium | No — depends on 6.6 |
| 7 | Scale and performance (four items) | — | Unknown | No — not a problem yet |
| 8.2 follow-up | Checklist trend/history data | S–M | Medium | No — needs (b) actually in use first |
| ~~9~~ | ~~Schema versioning + payload-contract test~~ | — | — | **Built 2026-08-18**, both halves — `ir` against `to_json` and `ir` against `html.lua`'s payload list. The first run of the first half caught `endpoints`, missing from the artifact since `core/endpoints.lua` shipped |

---

## The quick wins, in the order worth doing them

> **All five below have shipped** — verified against `lua/` on 2026-08-19,
> not from memory: `example-does-not-parse` and `unused-require` are
> checks in `core/check.lua`, SARIF is `core/render/sarif.lua`, the
> copy-link button is in the generated page, and Mermaid is
> `core/render/mermaid.lua`, called by the Markdown renderer for both the
> tree and the dependency graph.

> The ordering below is kept as written rather than deleted: it is the
> record of *why* they were done in that order, and the reasoning is the
> part worth re-reading when the next batch is rated.

**1. `@example` blocks that do not parse (§1.2).** Extraction and rendering
already exist; running the extracted content through the Lua parser and
reporting a syntax error is close to free, and unambiguous — no judgement
call, no false-positive class to design around. The cheapest real check in
the whole backlog.

**2. SARIF output for CI (§6.1).** The findings already carry file, line,
severity and message — this is a serialiser plus a CI step, not analysis.
It is also the one item in the integrations section with an immediate,
externally-visible payoff: every drift check would land inline on the pull
request that caused it, on GitHub's own code-scanning surface.

**3. Unused requires (§2.5).** The IR already has both the require edges
and the symbol references; this is the mirror image of the existing
`require-not-declared` check, in the direction that check does not cover.
No new extraction.

**4. Copy-link for the current view (§3.2).** The whole page state already
lives in the URL fragment (`:DocMap graph`, `gO` already exploit this).
Adding a button that hands the reader that URL is close to a one-line
change for a real, recurring need — "look at this specific thing" in a PR
comment or a chat message.

**5. Mermaid export (§6.4).** `dot.lua`'s edge-walking already produces
Graphviz; Mermaid is the same edges through a third serialiser. The
specific reason it earns "quick win" over just being "another export
format": GitHub renders Mermaid inline, so a dependency graph can live in a
README or PR comment and be looked at rather than downloaded — a real
capability gap DOT does not close.

**6. Publish the map to GitHub Pages (§6.3).** The page is already
self-contained, offline-capable HTML with no build step, which makes it a
static site by construction. A workflow that publishes on push is close to
free, and it is the same "static-publish slice" both
[`DESKTOP_WEBAPP.md`](DESKTOP_WEBAPP.md) and `IMPLEMENTATION_PLAN.md`
already point to as the cheap honest first step toward "a web app" —
building it here would make that pointer land somewhere real instead of at
a still-open idea.

**7. Schema versioning + a payload-contract test (§9).** Not glamorous, but
this is the fix for a bug class that has already happened twice
(`duplicates`, then `docs` — a new IR field reaching the JSON artifact but
not the page's own embedded payload, silently disabling a panel, per
`FEATURES.md`'s own incident record). A single builder or an assertion
that the two key sets match ends the class rather than waiting for a third
incident to document.

---

## Candidates worth a second look, not flagged outright

**Fenced code blocks checked against the API (§1.1).** Real value — a
README's copy-pasted example calling a renamed function is worse than
prose mentioning it — and 80% of the extraction machinery already exists
(`core/docs.lua` scans every `.md`, `code_spans()` exists). Held back from
"quick win" only because the new part (parsing a Lua fence with treesitter
and resolving calls conservatively, qualified names only) is real work, not
because the value is in question.

**Tests naming a function that no longer exists (§1.4).** `tests_dir`
already feeds `fn.tested` in one direction; the reverse is the same drift
class `doc-references-missing` already catches for prose, applied
somewhere it is more likely to rot unnoticed. Small, well-scoped, no open
design question — a strong second-wave candidate once the quick wins above
are done.

**Orphaned `@class`/`@alias` (§1.5).** Structurally identical to
`unreferenced-module`, which already exists, one level down. Cheap once
LuaLS enrichment has run (it already has, for other checks).

**Public API surface panel (§2.2).** Directly useful for the thing this
ecosystem keeps doing — extracting a module into its own plugin
(`lib.nvim.docmap` → documentation.nvim, `lib.nvim.telemetry` →
runtime-analysis.nvim, both preceded by exactly this question answered by
hand). Not flagged as an outright quick win because it consolidates three
existing views (Index, Documentation coverage, Deps) rather than reading
one new source, which is more integration work than the S-effort items
above.

**Print/PDF stylesheet (§3.3).** A `@media print` block, not a feature —
genuinely cheap. Held at "candidate" rather than "quick win" only because
nothing in this backlog has measured demand for it the way the quick-win
items above have a stated, recurring need behind them.

**Picker integration (§4.2) and `K` — look up notation (§4.3).** Both
small and both real, but both compose with
[`ReferenceTab.md`](ReferenceTab.md)'s own implementation-plan section
(added 2026-08-15) rather than standing alone — `K` is explicitly that
document's editor-side counterpart. Sequencing them together, or right
after, avoids building the same "look something up" interaction twice from
two different starting points.

**A GitHub Action (§6.2).** `REUSE.md` already documents the "copy two
files, edit five lines" path; packaging it as an Action removes the
copying step entirely. Not flagged outright only because it is worth doing
once §6.1 (SARIF) exists, so the Action's output is immediately useful to
GitHub's own code-scanning UI rather than only to a log.

**Generic CLI entry (§6.6).** Real motivating case (the author's own
multi-dozen-personal-plugin config), and `core/cli.lua`'s `M.run` already
does not care where its `opts` came from — the sketch in `IDEAS.md` is
close to complete. Two open questions block calling this a quick win
outright: whether flag parsing belongs in this plugin at all versus
staying a REUSE.md recipe, and whether an optional `.docmap.lua` config
file is worth the surface over "just pass flags every time." Worth
resolving those two before writing code, not after.

---

## Not recommended, or explicitly not now

- **§1.6 `@since` drift** — nearly free *if* the convention were adopted,
  but this tree does not use `@since` today. Building a check for a
  convention nobody uses inverts the plugin's own filter (detecting real
  disagreement, not manufacturing a checkable surface).
- **§1.7 cross-repo `tag_files` checks** — real value in a multi-repo
  ecosystem, which this plugin's own author runs, but genuinely needs a
  second live multi-repo case to validate against beyond the one
  cross-link already in production. Revisit once §6.6/§6.7 (or
  `docmap-desktop`'s own multi-project handling) gives a second real
  target.
- **§2.1 annotation adoption panel** — the highest-value panel idea in the
  backlog by its own account, but genuinely gated on the `TAGS` table
  refactor [`ReferenceTab.md`](ReferenceTab.md) already names as a
  precondition for its own tag-reference panel. The two ideas should be
  built together or not at all — building the `TAGS` table twice for two
  panels that both need it would be the exact kind of duplication this
  plugin's own conventions warn against.
- **§2.3 ownership/bus factor** — real on a team, reports "1" everywhere
  on a single-author repository, which is what this repository currently
  is. Not worth building until there is a second author to measure.
- **§2.4 coupling/cohesion, §5.3 Vue/Svelte SFCs, §5.4 ORM models** — each
  speculative on its own terms already (the source document says so): easy
  to compute and hard to act on, or gated behind a use case (a frontend or
  data-model-heavy repository) that has not shown up.
- **§5.2 OpenAPI generation** — the source document is honest that this
  cannot produce the part that makes OpenAPI valuable (request/response
  schemas), which is why it sits at "uncertain" rather than "low effort,
  build it." Revisit if a consumer of the endpoint inventory actually asks
  for it.
- **§6.5 workspace symbols** — already a recorded rejection in `IDEAS.md`
  itself ("probably not," since `lua-language-server` already answers
  this for most readers). Not reopened here.
- **§7 scale and performance** — all four items are honest about being
  unscheduled because there is no problem yet. The one worth doing without
  a trigger is the last bullet already named there: measuring against a
  large real tree, since that is what would turn the other three from
  speculative into scoped.
- **§8.2 follow-up (checklist trend data)** — real, and explicitly named
  by the now-absorbed `CHECKLIST_TASK_RUNNER.md` as the natural next
  question, but gated on the ledger actually being used long enough to
  have a trend worth showing. This repository's own ledger
  (`docs/CHECKLIST/architecture.md`) is eight items with no history yet —
  build this once there is data to plot, not before.

---

## What this document deliberately does not cover

`IDEAS.md` §8.1 and §8.3 (the desktop/web-app and protocols/agent-integration
product-shape ideas) are each large enough to carry their own document —
[`DESKTOP_WEBAPP.md`](DESKTOP_WEBAPP.md) and the now-absorbed
`PROTOCOLS_AND_AGENTS.md` — and are not re-assessed here for the same
reason `IMPLEMENTATION_PLAN.md` does not repeat them either. The Reference
tab (§4.3's editor-side counterpart) has its own implementation-plan
section in [`ReferenceTab.md`](ReferenceTab.md), added the same day as this
document, rather than here — it was already a full analysis, not a
backlog line.
