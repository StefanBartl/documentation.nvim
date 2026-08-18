# documentation.nvim — open items

What's actually still open. Everything shipped is recorded in
[`FEATURES.md`](../FEATURES/FEATURES.md) instead — commit hashes and design
decisions live there, not here. This file only holds things with no decision
yet; a decision to *not* build something lives inline in whichever document
raised the idea, not here (see each entry's own doc for its own rejection
table, where it has one).

Deeper reasoning, cost estimates and task breakdowns live in
[`IDEAS/`](IDEAS/) — this file is the index, not the analysis.

## Genuinely open

- **Multi-language support.** Extending the scanner past Lua — cost analysis,
  what 85% reuse actually hides, and a phased task breakdown (Phase 0/1,
  JS/TS, already built; everything past that still planning). See
  [`IDEAS/MULTILANG.md`](IDEAS/MULTILANG.md).
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
