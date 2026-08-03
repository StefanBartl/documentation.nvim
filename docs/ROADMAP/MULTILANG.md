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

- [x] **Language-backend interface.** Done (2026-08-03). `core/lang_registry.lua`
  dispatches by file extension; `core/lang/lua.lua` registers Lua as the
  reference implementation, a thin wrapper delegating to the
  `scan.lua`/`functions.lua` code that predates the interface, not a
  rewrite of either. Verified byte-accountable against the pre-change map —
  every diff on an existing node was the direct, explainable consequence of
  adding two new files, nothing else moved. See `FEATURES.md`'s own entry
  for the design and the bug the layer rule below caught while building it.
- [x] **`core.lang.*` layering, enforced.** Done alongside the interface, the
  same order the `core`/`editor` split happened in. One rule so far
  (`documentation.core` → `documentation.core.lang` forbidden); the
  cross-backend rule (`core.lang.js` must not require `core.lang.python`)
  is still just intent, not a written rule — there is only one backend to
  test it against, and this repository's own standard is not to add a rule
  unverified. Write it when Phase 1 gives it a second prefix to check.
- [ ] **`Documentation.Node` grows an owning-scope concept.** Functions
  currently hang off the *module*. Python methods belong to a class, Rust
  functions to an `impl` block, Go methods to a receiver type. `docs/
  MULTILANG.md` names this as one of three real IR gaps; it is the one that
  touches every consumer of `Documentation.FunctionInfo` (`duplicates.lua`'s
  grouping, `churn.lua`'s per-module complexity sum, both Analysis-panel
  renderers, the Hierarchy tab's Calls view), so it has to land before any
  language that needs it, not be bolted on when Python arrives and breaks
  everything already reading `fn.name` as flat. **Not blocking Phase 1**:
  modern JS/TS is overwhelmingly function-based (React function components
  and hooks, not classes), so the seam can prove itself on JS/TS first and
  this can land when Python's classes actually need it, not before.
- [ ] **`Documentation.Node` allows one file, many modules.** Rust's `mod x
  { … }` and JS's multiple named exports both break the file-is-a-module
  assumption `scan.lua`'s walk is built on. The second of `docs/
  MULTILANG.md`'s three IR gaps, and the one that touches the walk itself,
  not just the parser — `id`/`path`/`source` currently assume a 1:1
  relationship between a node and a file. **Not blocking Phase 1 either**:
  a JS/TS module IS its file, the same shape Lua already has (`index.js`
  playing `init.lua`'s role) — this is Rust's problem specifically, not a
  JS/TS one, and deferring it does not mean deferring Phase 1.
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
  language backend ships, not after someone hits it. Genuinely open: no IR
  field changed yet, since the interface work above added new *modules*
  (`core/lang_registry.lua`, `core/lang/lua.lua`) but no new *node* fields.
- [ ] **A real per-language sample tree**, checked into `TESTS/fixtures/` or
  fetched by the runner, per language — not just hand-written snippets.
  Section *Considerations* below explains why this is not optional.

## Phase 1 — JavaScript / TypeScript

Sequenced first per `docs/MULTILANG.md`'s own conclusion: closest doc-tag
fit (JSDoc is JSDoc-shaped LuaCATS descended from), largest audience, and —
specifically — the language `docs/FRAMEWORK_CONVENTIONS.md`'s layer-2 work
(Next.js-style routing, React hooks) depends on, so getting this one right
pays twice.

- [x] Treesitter grammar: `tree-sitter-javascript` + `tree-sitter-typescript`
  (the latter ships a `tsx` dialect too — needed if this ever reaches JSX,
  which `docs/FRAMEWORK_CONVENTIONS.md`'s routing work will). **(2026-08-03)**
  Node shapes verified against real parses (grammars built from source into
  a scratch directory, the user's own environment untouched) rather than
  assumed: `function_declaration`, `export_statement` (wraps `export` and
  `export default` identically, no distinguishing node),
  `lexical_declaration`/`variable_declaration` → `variable_declarator`,
  `arrow_function`/`function_expression`, `import_statement` (default/
  named/namespace), CommonJS `require()`, and the branch-relevant nodes
  `ternary_expression`/`switch_case`/`for_in_statement` (covers both
  for-of and for-in). Confirmed JS has no `elseif_statement`/
  `repeat_statement` — `else if` is a nested `if_statement`. See
  `core/lang/ecma.lua` and `docs/ROADMAP/FEATURES.md`'s ledger entry for
  this phase.
- [x] Import extraction: ESM (`import x from "y"`) and CommonJS
  (`require("y")`) both need recognizing — unlike Lua's single `require()`
  idiom, real JS/TS trees mix both within one project, sometimes one file.
  **(2026-08-03)** Both forms handled by `ecma.lua`'s `extract_requires`;
  a computed `require()` target or dynamic `import()` is not resolved,
  matching `deps.lua`'s own stated position on computed targets — not
  silently guessed at.
- [x] JSDoc/TSDoc doc-block parsing: `@param`, `@returns`, `@see`,
  `@deprecated` map close to directly onto the existing `Documentation.
  FunctionInfo` shape. TypeScript's own types make `undocumented-param`
  partly redundant — `docs/MULTILANG.md` already calls this a feature, not
  a problem to solve; do not build a check that fights the type checker.
  **(2026-08-03)** `@param`/`@returns`/`@return`/`@deprecated`/`@internal`/
  `@private` parsed by `ecma.lua`'s `parse_jsdoc`. Not yet parsed: `@see`,
  `@overload`, `@todo`/`@bug`/`@test`, `@example`, `@since`, `@generic` —
  real JSDoc-adjacent conventions left as an honest gap, the same as
  `core/plugins.lua` leaves an unreadable spec's `dependencies` at `{}`.
- [x] Which of the fourteen existing checks port unchanged (the require-graph
  ones, README ones) vs. need a JS-specific variant (module-path
  conventions differ: no `@module` tag idiom exists in JS to check against)
  — audit check-by-check before assuming parity. **(2026-08-03)** One
  check needed a variant, found by reasoning through its code before
  writing the JS backend: `missing-module-tag` assumed every language
  needs a declared name, which is only true of Lua. Fixed via
  `Documentation.LangBackend.module_tag` (default `true`, `false` for
  js/ts/tsx) and a registry-aware `wants_module_tag(node)` helper in
  `check.lua` — see `docs/ROADMAP/FEATURES.md`. The rest of the audit (the
  other thirteen checks against a real, non-trivial JS/TS tree) has not
  happened yet — this repository's own tree is still all-Lua, so nothing
  has exercised most of them against real JS/TS findings.
- [x] React function components and hooks: `ecma.lua` tags a function
  `is_hook` by the `^use[A-Z]` naming convention
  (`eslint-plugin-react-hooks`'s own signal), per
  `docs/FRAMEWORK_CONVENTIONS.md`'s conclusion that a *map* of hooks is the
  underserved half of React support. **(2026-08-03)** A seventh Analysis
  panel (`core/render/html.lua`'s `renderAnalysisHooks`) now surfaces it:
  every `is_hook` function across the tree, sortable/filterable the same
  way the other six panels are. `Documentation.FunctionInfo.is_hook` is
  now a declared, documented field on the type rather than an undeclared
  passenger. See `docs/ROADMAP/FEATURES.md`.
- [x] Calls extraction. **(2026-08-03)** `ecma.lua` now extracts every call
  site (`extract_calls`, a `(call_expression function: (_) @callee)` query
  structurally identical to `calls.lua`'s own Lua query) and per-file
  identifier counts (`identifier_counts`, for `local_refs`), attributed to
  the enclosing top-level function the same way Lua's `functions.lua`
  does. `calls.lua`'s own resolver (`M.build`) needed **zero JS-specific
  changes** — it already worked generically over `calls_raw`/
  `requires_raw`/`functions`, so a same-file bare call (`helper()`)
  resolves to a real `kind="call"` edge exactly like an unqualified Lua
  call would. Verified end to end against a real parse: extraction, then
  feeding the result through `calls.lua`'s unmodified resolver, confirming
  a real edge comes out. See `docs/ROADMAP/FEATURES.md`.

  Cross-file call resolution is explicitly **not** included: JS's named
  imports (`import { helper } from "./bar"`) bind the function directly
  into scope as a bare name, not through an alias-then-`.member` shape the
  way `local fs = require(...)` then `fs.read()` works in Lua —
  `calls.lua`'s alias/prefix resolution model has no equivalent branch for
  "this bare name came from a specific import," and `ecma.lua`'s
  `extract_requires` does not yet record which names an import bound.
  Real, valuable, and a separate task from same-file resolution — tracked
  here rather than guessed at.

- [x] Symbols extraction (module-scope non-function, non-`require` bindings
  — `const CONFIG = {...}`), a separate task from calls despite the two
  having shared one checklist item before the calls-extraction session.
  **(2026-08-03)** `ecma.lua`'s `extract_symbols` mirrors
  `documentation.core.symbols`'s own Lua scope and classification
  (table/constant/binding) exactly: excludes a function-shaped declarator
  (`as_function` already claims it) and a `require()` binding
  (`extract_requires` already claims it), classifies an `object`/`array`
  literal as `"table"` (by named-child count — verified against a real
  parse that `pair`, `shorthand_property_identifier` and `spread_element`
  all count as members, broader than Lua's own `field`-only count, and
  correctly so for JS's richer object-literal shapes) and a `number`/
  `string`/`true`/`false` literal as `"constant"` (JS has no single boolean
  node type — `true`/`false` are distinct, both verified). `null`/
  `undefined` (JS-only shapes, no Lua equivalent) fall through to
  `"binding"`, the same as any other unlisted Lua literal would. Unlike
  Lua, no export-table name is filtered out — JS/TS has no single
  chunk-level "this is the module" return the way `local M = {}` /
  `return M` is (see `ecma.lua`'s own header on module identity), so every
  qualifying binding is reported. See `docs/ROADMAP/FEATURES.md`.
- [ ] Class-method owning-scope: `ecma.lua` recognizes standalone functions
  only; a method inside a `class` body has no representation yet — the
  same Phase-0 owning-scope gap Python/Rust/Go will also need, not unique
  to JS/TS, deferred for the same reason.
- [ ] `.jsx` support: deliberately left to `js.lua` to extend (its own
  header says so) rather than claimed by `tsx.lua`, which the `tsx`
  grammar could technically parse — a `.jsx` file is JavaScript, not
  TypeScript, and conflating the two here would be a wrong module
  identity, not a shortcut.
- [ ] `module.exports = {...}` (the CommonJS export-object idiom): not
  recognized — a file using only this form contributes no functions today,
  the same honest gap as class methods.
- [x] This repository's own CI now installs JS/TS/TSX treesitter parsers.
  **(2026-08-03)** `.github/workflows/ci.yml`'s `tests` job builds all
  three grammars from source (`tree-sitter build`, both grammar repos ship
  pre-generated `parser.c` so no `tree-sitter generate` step is needed)
  into `.deps/ts-parsers`, and `TESTS/run.lua` appends
  `DOCUMENTATION_TS_PARSERS_DIR` to the rtp itself when set — optional,
  unlike `lib.nvim`, since `lang_js_spec.lua` already has a real skip path
  for the common case of a plain local run with no such variable set.
  `lang_js_spec.lua` now runs its real assertions in CI on every push,
  not just its skip path.

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
