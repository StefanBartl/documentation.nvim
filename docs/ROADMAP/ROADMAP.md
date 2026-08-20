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
  [`IDEAS/MULTILANG.md`](IDEAS/MULTILANG.md). **Fifteen** further languages are *available* rather than scheduled —
  named, costed and ordered in that file's own table, which also records
  why the number was written as sixteen until now (Scratch was ruled out
  and the count was not updated).
- **Call edges outside Lua, Go and the ECMA family.** Found by the parity
  pass 2026-08-20 and still the largest single gap in the tool. **`go` closed
  it for one language on 2026-08-20**, deliberately as the pattern for the
  rest; **eighteen backends still return `{}`**, so the Hierarchy tab's Calls
  and Module Calls views, `:DocMap why`, the call-hierarchy LSP integration
  and `dead-function`'s call-edge tier are empty there. **Nothing in any of
  those languages makes this impossible** — it is unbuilt, not blocked, and
  it had no sentence anywhere before the audit.

  **What the first one taught, and it is not the extractor.** Go's query was
  a day's work; its *resolver* was the finding. A Go package is a directory,
  so an unqualified call may name a function in a sibling file, and Go has no
  `module_file` — so a file-scoped resolver misses nearly half a real Go call
  graph (`aws/smithy-go`: 883 edges, 397 across files of one package). The
  general lesson for the remaining eighteen: **ask what a language's *scope*
  is before writing its query**, because Lua and the ECMA family happen to
  make file and scope the same thing and taught nothing about it. Carried by
  `LangBackend.call_scope`, so the next language that needs it is one field.
  See [`LANGUAGES.md § Parity`](../LANGUAGES.md#parity).
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
