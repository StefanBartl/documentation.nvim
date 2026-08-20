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

- **The `standalone` gate skips silently on most machines, and two bugs got
  in behind it.** `scripts/ci.lua` looks for PUC Lua on `PATH` with `lfs` and
  `dkjson`; where it does not find one it prints *skipped* and the run still
  reports five green gates. On 2026-08-20 a release build failed twice in a
  row on `core/` calling Neovim APIs the shim does not implement
  (`node:start()`, `vim.pesc`), both introduced that day, both invisible
  locally.

  **The third option shipped 2026-08-20 as `TESTS/shim_contract_spec.lua`**,
  and it was the right one for the stated reason: it runs on every machine,
  needing neither PUC Lua nor the `lua_tree_sitter` rock. It reads every
  `vim.*` path and every method name `core/` calls out of a *real parse* —
  grep reported 44 and 43 against the parser's 27 and 30, because this tree's
  doc-comments discuss `vim.*` constantly — then asks `vim_shim.lua` itself
  what it provides, by loading it with `lfs`/`dkjson` faked and `_G.vim`
  unset for the duration. (That last part is not optional: the shim opens
  `if _G.vim then return _G.vim end`, so a first attempt got Neovim's own
  table back and answered "yes" to everything, including names the shim
  demonstrably lacks.)

  **The gate is the unclassified name**, which is exactly the shape both
  defects had. Three `vim.*` paths are listed as legitimately absent, all
  `core/luals.lua`, all unreachable from the standalone binary because
  `--full` is Neovim-only — and the list is checked in both directions, so an
  entry the shim has since implemented fails too. Node methods are
  classified rather than loaded, and that limit is stated in the spec:
  enumerating them needs the rock. Mutation-checked against both historical
  shapes — a new `vim.*` call and a new `node:method()` call each fail it by
  name and by file.

  **What it does not fix:** the gate still skips silently, so local green
  still means "four gates and a shrug" for everything the contract cannot
  see — a shim function that exists but behaves differently, for one. The
  two cheaper options (fail rather than skip when the rocks are present;
  repeat the skip in the summary) remain open and are still worth taking.
- [x] ~~**A generated relative link can be wrong in the copy.**~~ Fixed
  2026-08-20. `render/markdown.lua` now rebases a summary's relative links
  into the artifact directory, and the measurement is why it was a generator
  fix rather than an edit to one header: **every** relative link in a summary
  was broken, not some — 4 of 4 here, 1 of 1 in `runtime-analysis.nvim`, 0 of
  0 in `lib.nvim`.

  The part worth keeping is the answer to "why does the Neovim-side check not
  report it": `docs.corpus` excludes `out_dir` explicitly, so
  `dead-readme-link` never reads generated output — correct, and it stays
  that way. You fix a generator; you do not lint what it wrote. It also
  explains the asymmetry: the standalone gate found this because it read the
  artifact as a plain file, an angle a check over the source tree does not
  have.

  `resolve_relative_link` moved to `docs.resolve_link` in the same change,
  since the check resolves a link to ask whether it is dead and the renderer
  resolves it to rewrite it — two copies of that walk being exactly the drift
  this plugin reports elsewhere.

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
