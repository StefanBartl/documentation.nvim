# Multi-language support — task breakdown

Not implemented. This is the task list and the considerations that came out
of scoping it, written down so the next pass does not re-derive them from
scratch. The cost analysis this breaks down lives in
[`docs/MULTILANG.md`](../MULTILANG.md) (what each language costs, and why);
the layer built on top of it lives in
[`docs/FRAMEWORK_CONVENTIONS.md`](../FRAMEWORK_CONVENTIONS.md) (ecosystem
conventions *within* a supported language, e.g. lazy.nvim specs for Lua,
file-based routers for JS/TS). Read both before starting any task below —
several of them only make sense in light of what those two documents already
ruled out.

Target scope, as decided: all five languages `docs/MULTILANG.md` costs out —
JavaScript/TypeScript, Python, Rust, Go, C. **Scope is not sequencing.**
Everything below still assumes one language lands, proves itself, and only
then does the next one start — the same reasoning `docs/MULTILANG.md`
already gives for JS/TS-first-Go-last. A roadmap naming five languages is
not an argument for building five at once; it is worse for it, given this
repository's own standard of "no half-finished implementations" — see
*Considerations* below for why that risk is real here specifically, not a
generic caution.

---

## Phase 0 — shared infrastructure (blocks every language)

None of the language-specific work below can start before this phase,
because it changes the shape every language backend plugs into.

- [ ] **Language-backend interface.** Five functions, one implementation per
  language, selected by file extension — `docs/MULTILANG.md`'s own sketch:
  given a file, return its module identity, its functions with doc blocks,
  its symbols, and its imports. `core/scan.lua`'s walk currently calls
  `functions.lua` unconditionally; this becomes a dispatch table keyed on
  extension, with Lua's existing `scan.lua`/`functions.lua`/`symbols.lua`/
  `deps.lua`/`calls.lua` becoming the first (and reference) implementation
  of the interface, not a special case beside it.
- [ ] **`core.lang.*` layering, enforced.** `docs/PORTABILITY.md` and
  `docs/DEVELOPMENT.md` already document why `documentation.core` /
  `documentation.editor` is a declared `layers` rule and not a convention —
  a boundary nothing checks is a boundary that rots. The same treatment
  applies here: language backends must not reach into each other
  (`core.lang.js` requiring `core.lang.python` is exactly the kind of
  coupling `layer-violation` exists to catch), and the shared `core/`
  modules (`check.lua`, `duplicates.lua`, `churn.lua`, the renderers) must
  not import any specific `core.lang.*` — they read the IR, never the
  backend that produced it. Write the rule at the same time as the first
  backend, the same order the `core`/`editor` split happened in, not after.
- [ ] **`Documentation.Node` grows an owning-scope concept.** Functions
  currently hang off the *module*. Python methods belong to a class, Rust
  functions to an `impl` block, Go methods to a receiver type. `docs/
  MULTILANG.md` names this as one of three real IR gaps; it is the one that
  touches every consumer of `Documentation.FunctionInfo` (`duplicates.lua`'s
  grouping, `churn.lua`'s per-module complexity sum, both Analysis-panel
  renderers, the Hierarchy tab's Calls view), so it has to land before any
  language that needs it, not be bolted on when Python arrives and breaks
  everything already reading `fn.name` as flat.
- [ ] **`Documentation.Node` allows one file, many modules.** Rust's `mod x
  { … }` and JS's multiple named exports both break the file-is-a-module
  assumption `scan.lua`'s walk is built on. The second of `docs/
  MULTILANG.md`'s three IR gaps, and the one that touches the walk itself,
  not just the parser — `id`/`path`/`source` currently assume a 1:1
  relationship between a node and a file.
- [ ] **Visibility as a first-class `Documentation.FunctionInfo` field.**
  `@internal` is a tag today; Rust has `pub`, Go has identifier
  capitalisation, TS has `private`. Third IR gap from `docs/MULTILANG.md`.
  Lower urgency than the two above — `dead-function` degrades gracefully
  without it (it already treats an untagged function conservatively) — but
  worth landing in the same pass since it touches the same struct.
- [ ] **`module_map.json` schema versioning, revisited.** `diff.lua`
  already tolerates older schema versions reading historical artifacts
  (`docs/DEVELOPMENT.md`'s determinism section). Adding a `language` field
  to every node and the three struct changes above is exactly the kind of
  change that check exists for — confirm the tolerance path still degrades
  rather than errors on a mixed old/new-schema `:DocMap diff` before any
  language backend ships, not after someone hits it.
- [ ] **A real per-language sample tree**, checked into `TESTS/fixtures/` or
  fetched by the runner, per language — not just hand-written snippets.
  Section *Considerations* below explains why this is not optional.

## Phase 1 — JavaScript / TypeScript

Sequenced first per `docs/MULTILANG.md`'s own conclusion: closest doc-tag
fit (JSDoc is JSDoc-shaped LuaCATS descended from), largest audience, and —
specifically — the language `docs/FRAMEWORK_CONVENTIONS.md`'s layer-2 work
(Next.js-style routing, React hooks) depends on, so getting this one right
pays twice.

- [ ] Treesitter grammar: `tree-sitter-javascript` + `tree-sitter-typescript`
  (the latter ships a `tsx` dialect too — needed if this ever reaches JSX,
  which `docs/FRAMEWORK_CONVENTIONS.md`'s routing work will).
  `core/functions.lua`'s query-based extraction is the reference shape;
  the node *type names* differ (`function_declaration` exists in both
  grammars but with a different field set — verify against a real parse
  before writing a query, the standing rule every existing extractor in
  this repo already follows, not a new one).
- [ ] Import extraction: ESM (`import x from "y"`) and CommonJS
  (`require("y")`) both need recognizing — unlike Lua's single `require()`
  idiom, real JS/TS trees mix both within one project, sometimes one file.
- [ ] JSDoc/TSDoc doc-block parsing: `@param`, `@returns`, `@see`,
  `@deprecated` map close to directly onto the existing `Documentation.
  FunctionInfo` shape. TypeScript's own types make `undocumented-param`
  partly redundant — `docs/MULTILANG.md` already calls this a feature, not
  a problem to solve; do not build a check that fights the type checker.
- [ ] Which of the fourteen existing checks port unchanged (the require-graph
  ones, README ones) vs. need a JS-specific variant (module-path
  conventions differ: no `@module` tag idiom exists in JS to check against)
  — audit check-by-check before assuming parity.

## Phase 2 — Python

- [ ] Docstring **style detection**: reST, Google, and NumPy conventions
  coexist across real Python codebases, sometimes within one. `docs/
  MULTILANG.md` flags this as two problems, not one — no universal format
  (needs a per-style parser with a detector, not one parser), and a
  docstring is a *runtime string* literal, not a comment block, so the
  parse is structured text inside a string node rather than tags in
  comments the way LuaCATS/JSDoc are.
- [ ] Decorators (`@property`, `@staticmethod`, a project's own) are a real
  shape with no Lua equivalent — decide whether they are metadata on
  `Documentation.FunctionInfo` or a check's own concern before writing the
  extractor, not after.
- [ ] Import extraction: `import x`, `from x import y`, relative imports
  (`from ..pkg import x`) against `sys.path` — closer to Rust's
  parent-declares-the-module problem than to Lua's flat `require`.

## Phase 3 — Rust

- [ ] `mod x { … }` is the sharpest instance of Phase 0's "one file, many
  modules" gap — a Rust module is declared by its *parent*, inverted from
  every other language here where a file declares its own identity.
  Confirm the Phase-0 IR change actually covers this shape specifically,
  with a real multi-module `.rs` file, before writing the extractor.
- [ ] `impl` blocks own methods — the Phase-0 owning-scope field's other
  real test case besides Python classes; a method's owner is not textually
  where the method is defined the way `M.foo` is in Lua.
- [ ] rustdoc (`///`) is prose Markdown with **no tag vocabulary at all**.
  `docs/MULTILANG.md` is explicit: the param-shaped checks
  (`undocumented-param`, `param-name-mismatch`) have nothing to compare
  against and do not port. `missing-summary` does. Do not build fake
  `@param` recognition against prose that was never structured that way.

## Phase 4 — Go

- [ ] godoc's *entire* checkable convention is "the comment starts with the
  identifier it documents." `docs/MULTILANG.md` calls this the worst fit of
  the five for a reason: this replaces six of Lua's fourteen checks with
  one. Confirm before starting that one check is still worth a whole
  backend — the honest answer may be "only once JS/TS and one other
  language have already proven the Phase-0 architecture is real," not on
  its own merits.
- [ ] Receivers (`func (r *Type) Method()`) are Go's version of the
  owning-scope problem — same Phase-0 field, third real test case.
- [ ] Package-per-directory (not per-file) is closer to Lua's own
  `init.lua`-marks-a-module convention than to JS/Python/Rust — likely the
  cheapest walk-level fit of the five once Phase 0 lands.

## Phase 5 — C

- [ ] Declaration vs. definition — a `.h` prototype and its `.c` body are
  two nodes referring to one function. `Documentation.FunctionInfo` today
  models one function as one node; decide whether this becomes a new
  `declares`/`defines` edge kind (parallel to the existing `require`/
  `call`/`type`/`extends` discriminated union in `ir.edges`) before writing
  the extractor — bolting a special case onto `FunctionInfo` itself would
  be the second undocumented shape this file warns against elsewhere.
- [ ] Doxygen `\param`/`@param` where present, absent where not — `docs/
  MULTILANG.md` calls this "free where present" since Doxygen's vocabulary
  is where LuaCATS's own ultimately descends from, but real C codebases
  vary enormously in whether they use it at all; the doc-coverage checks
  need to degrade honestly on a tree that never adopted it, the same way
  `coverage.lua` already degrades on a tree with no `tests_dir`.
- [ ] No package/module system to key `Documentation.Node.module` on at
  all — headers and translation units are the closest analogue, and the
  mapping is not obvious. Likely the hardest walk-level fit of the five;
  reasonable to leave last regardless of check-count arguments.

---

## Considerations

**Why "no half-finished implementations" is a real risk here, not a
generic caution.** This session's own `core/plugins.lua` work is the
concrete evidence: a feature that passed every hand-written fixture still
produced 235 false positives against one real config, from two shapes nine
fixtures did not think to cover. A language backend is `core/plugins.lua`'s
risk profile at ten times the surface area — five extractors instead of
one, against ecosystems this repository's own author has not necessarily
written thousands of lines in. **Phase 0's real-sample-tree task is not
bureaucracy; it is the only thing that would have caught the `plugins.lua`
bugs, and synthetic fixtures alone would not have.**

**Sequencing is not optional even though scope is "all five."** Each phase
above depends on Phase 0 being genuinely stable, which is only provable by
a language actually running against it — the first language is also
Phase 0's test. Starting two languages in parallel means finding Phase 0's
bugs twice, in two backends, at the same time, which is strictly more
expensive than finding them once.

**The IR changes are breaking**, the same way `core`/`editor` was — a
rename-shaped break was acceptable there because the plugin is unpublished.
Whether that is still true by the time Phase 0 starts is a fact to check,
not assume; if the plugin has users by then, the schema-versioning task
above stops being a nice-to-have and becomes the actual hard requirement
of the phase.

**This document itself may be wrong about node-type names, grammar
availability, or exact query shapes.** Every claim here is a task
description, not a verified fact — unlike `core/plugins.lua`'s design docs,
nothing in this file was checked against a real parse (there is no backend
yet to check it against). Re-verify each grammar-shape claim the way every
existing extractor in this repository already does, at the point that
phase actually starts, not from this document's word for it.
