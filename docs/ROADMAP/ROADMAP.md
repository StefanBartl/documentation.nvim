# documentation.nvim — open items

What's actually still open. Everything shipped is recorded in
[`FEATURES.md`](../FEATURES/FEATURES.md) instead — commit hashes and design
decisions live there, not here. This file only holds things with no decision
yet; a decision to *not* build something lives inline in whichever document
raised the idea, not here (see each entry's own doc for its own rejection
table, where it has one).

Deeper reasoning, cost estimates and task breakdowns live in
[`IDEAS/`](IDEAS/) — this file is the index, not the analysis.

**The resume point for work in progress is [`WORKPLAN.md`](WORKPLAN.md)** —
what is done, what is next, and everything agreed but not built, written so
the work survives a cold start in a new session.

## Genuinely open

- **Multi-language support.** Twenty-three backends built. What each reads is
  [`LANGUAGES.md`](../LANGUAGES.md); what each cost is
  [`IDEAS/MULTILANG.md`](IDEAS/MULTILANG.md). Sixteen further languages are
  *available* rather than scheduled — see that file's decision 4.
- **Call edges outside Lua and the ECMA family.** Found by the parity pass
  2026-08-20 and the largest single gap in the tool: `lua`, `js`, `ts` and
  `tsx` return call sites, and **the other nineteen backends return `{}`**.
  So the Hierarchy tab's Calls and Module Calls views, `:DocMap why`, the
  call-hierarchy LSP integration and `dead-function`'s call-edge tier are all
  empty in nineteen languages. **Nothing in any of those languages makes this
  impossible** — it is unbuilt, not blocked, and it had no sentence anywhere
  before the audit. Invisible from any one language; it took a table across
  all of them. See [`LANGUAGES.md § Parity`](../LANGUAGES.md#parity).
- **Module-scope symbols in the four oldest non-Lua backends.** `zig`, `java`,
  `c` and `cpp` return none; every backend written from Python onward does.
  Nothing decided this — the capability arrived after those four and never
  went back. Small next to the entry above, and the same kind of finding.
- **Running without Neovim.** Already works for "map a Lua project from the
  terminal"; costed separately is dropping the Neovim dependency entirely.
  See [`IDEAS/PORTABILITY.md`](IDEAS/PORTABILITY.md).
- **Interface languages (i18n).** A separate axis from the entry above,
  despite the shared word: the languages this tool *speaks* rather than the
  ones it reads. Three surfaces, of which the generated page is roughly 85 %
  of the work. See [`IDEAS/I18N.md`](IDEAS/I18N.md).
- **Reference tab — Lua syntax and LuaCATS tags.** Not built, verified against
  source. Two panels (a generated tag-adoption report, a static syntax crib
  sheet) plus a right-click "what is this" affordance, with a cheap
  curated-link-list fallback that ships independently of the rest. See
  [`IDEAS/ReferenceTab.md`](IDEAS/ReferenceTab.md).
