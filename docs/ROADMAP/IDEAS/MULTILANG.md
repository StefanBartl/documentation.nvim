# Multi-language support — cost analysis and task breakdown

Merged 2026-08-15 from two companion documents that had drifted apart under
mismatched relative links: this file (the task breakdown) and
`MULTILANG2.md` (the cost analysis it was meant to reference as
`docs/ROADMAP/MULTILANG.md` — a path that never existed; both documents
always lived here). One file now, in two parts: **what it would cost**
(unchanged reasoning, written first), then **the task list** derived from
it. Companion to [`PORTABILITY.md`](PORTABILITY.md), which costs out the
*other* axis (running without Neovim).

Both are estimates. Only Phase 0 and Phase 1 (JavaScript/TypeScript) below
are actually built; everything else remains planning.

---

## Part 1 — what it would cost

Measured against the tree after the `core`/`editor` split: 14 063 lines
excluding `@types/`. This measurement predates the JS/TS backend below, so
it is the *pre-Phase-1* baseline the task breakdown was scoped against.

### The number, and why it flatters

| | Lines | |
|---|---:|---|
| **Language-specific** — `scan`, `functions`, `symbols`, `deps`, `calls`, `luals` | 2 165 | 15 % |
| **Language-blind** — everything else in `core/`, plus all of `editor/` | 11 898 | 85 % |

85 % reuse is the headline and it is real, but it is not the whole cost.
Three things it hides, in increasing order of how much they hurt.

**1. The 15 % is not one implementation, it is one per language.**
`deps.lua` resolves Lua's `require("a.b")`. For the others that is
`import`/`require`/`from … import`/`use`/`#include`, each with its own
resolution rules — Node's `node_modules` walk and `package.json` `exports`,
Python's `sys.path` and relative `from ..pkg import x`, Rust's `mod` tree
where a module is declared by its *parent*, Go's import paths against
`go.mod`, C's include paths. Roughly a `deps.lua` each, and Rust's is
genuinely harder than Lua's because the file does not name itself. Same for
`functions.lua` (520 lines of treesitter query plus doc-block parsing) and
`symbols.lua`. Call one language ~1 200–1 800 lines of the 2 165, since
`scan.lua`'s filesystem walk and `luals.lua`'s optional enrichment do not
repeat.

**2. Treesitter makes the parsing uniform and the *queries* not.** Grammars
exist for all of these, and the plugin's queries are already tiny — five of
them, each a single line. The machinery around queries — `shape_of`,
complexity counting, the deferred-require classification — is written
against node types, not against Lua, so swapping `"lua"` for `"python"` and
the node names is a real but bounded edit. The bad news: node names are not
a shared vocabulary. Python has no `function_declaration`; it has
`function_definition` and, separately, decorators that change what a
function *is*. Rust has `function_item` plus `impl_item` blocks that own
methods — a concept Lua's IR had no field for (Phase 0 below closes this).
Go has methods with receivers. C has declarations separate from
definitions, which the IR models as one thing.

**3. The real problem is the doc-comment vocabulary, not the syntax.** This
plugin's checks are not "is this parseable" — they are "do the docs and the
code still agree", which only means something where the docs make
*checkable claims*. Of the sixteen checks that existed when this was
written, seven read LuaCATS tags directly. How well those port varies more
than anything else in this analysis:

| | Doc convention | Ports? |
|---|---|---|
| **JavaScript / TypeScript** | JSDoc / TSDoc — `@param`, `@returns`, `@see`, `@deprecated` | **Nearly free.** Almost the same tag vocabulary; LuaCATS is JSDoc-shaped by descent. TypeScript's own types make `undocumented-param` partly redundant, which is a feature. |
| **Python** | Docstrings: reST, Google or NumPy style | **Two problems.** No universal format, so the parser is per-style with a detector. And a docstring is a *runtime string*, so the parse is structured text inside a node, not tags in comments. |
| **Rust** | rustdoc `///` — prose Markdown, no tag vocabulary | **The param checks do not exist.** Rustdoc has no `@param`. `missing-summary` ports; `param-name-mismatch` has nothing to compare against. Types are in the signature, which is where the information already was. |
| **Go** | godoc — a comment starting with the identifier's name, no tags at all | **Worst fit.** The only checkable claim godoc makes is "the comment begins with the name it documents", which is one check this plugin does not have, replacing six it does. |
| **C** | Doxygen `\param`/`@param`, when used at all | **Free where present**, absent where not. Doxygen's vocabulary is where LuaCATS's ultimately comes from. |

So it is not one feature: JS/TS is close to a weekend's work over the
existing design; Go would need a different set of checks, not a
translation of these.

### What survives untouched

The 85 % is not a rounding-up. Everything downstream of the IR never learns
what language produced it:

- **All five renderers** — `html.lua`, `markdown`, `mermaid`, `dot`,
  `badge`. They draw modules, edges and functions, and none of those words
  is Lua-specific.
- **The whole editor half** — `:DocBrowse`, `:DocMap`, the server, the
  watcher, health.
- **Every analysis tool** — `duplicates`, `churn`, `coverage`,
  `doccoverage`, `diff`, `history`. `duplicates` groups by treesitter
  node-type sequence, so it works on *any* grammar the moment the scanner
  produces shapes, with no per-language code at all.
- **Nine of the sixteen checks** — the require graph ones
  (`require-cycle`, `require-not-declared`, `layer-violation`), the README
  ones, `dead-function`, and `tools-spec-invalid` (reads
  `docs/install.json`/`docs/INSTALL.md`, not source comments at all — the
  most language-agnostic check in the tree).
- `config.lua`, `json.lua`, `cli.lua` and `find.lua`, already agnostic.

### What the IR had to grow — closed by Phase 0 below

Three gaps, all now resolved by the language-backend interface:

- **Classes as an owning scope.** Python methods belong to a class, Rust
  functions to an `impl`, Go methods to a receiver type — Lua's IR had no
  field for this.
- **Visibility as a first-class fact.** `@internal` is a tag in Lua; Rust
  has `pub`, Go the capitalisation of the identifier, TS `private`.
- **One file, many modules.** Rust's `mod x { … }` and JS's multiple named
  exports break the file-is-a-module assumption `scan.lua` was built on.

### The shape it took

`scan.lua`'s walk, the IR, the checks that read edges, and every consumer
stayed where they were. What became pluggable is a **language backend**:
given a file, return its module identity, its functions with doc blocks,
its symbols, and its imports — selected by extension via
`core/lang_registry.lua`. That was also the honest test of whether the
`core`/`editor` split was real: a `core`/`core.lang.*` boundary needed the
same layer-rule treatment, or the Lua assumptions would leak straight back
into the shared half. It got it (Phase 0, done).

### Recommendation (as written, before any backend existed)

**Not scheduled by default, JS/TS first if ever built.** Closest fit by doc
convention, largest audience, and the one where the existing checks keep
their meaning without redefinition — which makes it the honest test of
whether the backend abstraction works, rather than a rewrite wearing one.
Go is the one to *not* start with, however tempting the ecosystem: godoc
gives this design almost nothing to check, and a map with no drift checks
is a diagram, which is a different product.

A JS/TS backend is only layer 1 — [`FRAMEWORK_CONVENTIONS.md`](../../FRAMEWORK_CONVENTIONS.md)
costs out the layer above it (Next.js-style file-based routing, React
hooks: recognizing one ecosystem's structural convention within an
already-supported language), strictly sequenced behind everything here.

**This recommendation was followed.** Phase 0 and Phase 1 (JS/TS) below
are built; Python/Rust/Go/C remain exactly what this section estimated,
untouched.

---

## Part 2 — task breakdown

The layer built on top of language support lives in
[`docs/FRAMEWORK_CONVENTIONS.md`](../../FRAMEWORK_CONVENTIONS.md) (ecosystem
conventions *within* a supported language, e.g. lazy.nvim specs for Lua,
file-based routers for JS/TS). Read it before starting Phase 2 or later —
several remaining tasks only make sense in light of what that document
already ruled out.

Target scope, as decided: all five languages Part 1 costs out —
JavaScript/TypeScript, Python, Rust, Go, C. **Scope is not sequencing.**
One language lands, proves itself, and only then does the next one start —
this repository's own standard of "no half-finished implementations"
applies at ten times the surface area to a language backend (see
*Considerations* below).

### Phase 0 — shared infrastructure (blocks every language) — **mostly done**

> **Since this section was written**, two things landed that every later
> language backend inherits, and both are contract rather than
> convenience: `line_comments`/`block_comments` on
> `Documentation.LangBackend`, read by `core/markers.lua`; and
> `TESTS/backend_contract_spec.lua`, which fails a backend that declares
> neither — because the default is to *skip* rather than guess, which is
> right and silent. A new language that forgets the field would otherwise
> scan clean and find no markers at all.

None of the language-specific work can start before this phase, because it
changes the shape every language backend plugs into.

- [x] **Language-backend interface — done (2026-08-03).**
  `core/lang_registry.lua` dispatches by file extension; `core/lang/lua.lua`
  registers Lua as the reference implementation, a thin wrapper delegating
  to the pre-existing `scan.lua`/`functions.lua` code, not a rewrite.
  Verified byte-accountable against the pre-change map. See
  [`docs/FEATURES/FEATURES.md`](../../FEATURES/FEATURES.md) for the design
  and the bug the layer rule below caught while building it.
- [x] **`core.lang.*` layering, enforced — done alongside the interface.**
  One rule so far (`documentation.core` → `documentation.core.lang`
  forbidden); the cross-backend rule (`core.lang.js` must not require
  `core.lang.python`) is still just intent, not a written rule — there is
  only one backend to test it against. Write it when Phase 2 gives it a
  second prefix to check.
- [ ] **`Documentation.Node` grows an owning-scope concept.** Functions
  currently hang off the *module*. Python methods belong to a class, Rust
  functions to an `impl` block, Go methods to a receiver type. Touches
  every consumer of `Documentation.FunctionInfo` (`duplicates.lua`'s
  grouping, `churn.lua`'s per-module complexity sum, both Analysis-panel
  renderers, the Hierarchy tab's Calls view), so it has to land before any
  language that needs it. **Not blocking Phase 1** (proven correct: modern
  JS/TS is overwhelmingly function-based, so the seam proved itself on
  JS/TS first) — needed when Python's classes actually arrive.
- [ ] **`Documentation.Node` allows one file, many modules.** Rust's `mod x
  { … }` and JS's multiple named exports both break the file-is-a-module
  assumption `scan.lua`'s walk is built on. **Not blocking Phase 1 either**:
  a JS/TS module IS its file, the same shape Lua already has — this is
  Rust's problem specifically.
- [x] ~~**Visibility as a first-class `Documentation.FunctionInfo` field.**~~
  Closed — and it closed by being *used* rather than by a refactor. `internal`
  was already the field; what this entry wanted was for it to carry a fact
  from the language rather than only the `@internal` tag, and five backends
  now fill it that way: Zig's `pub`, Java's `public`, C's `static`, C++'s
  positional access specifier, and assembly's `.globl`/`global`/`PUBLIC`.
  Lua and the ECMA family still read the tag, because those languages have
  no keyword at this granularity — which is a spectrum worth knowing about
  rather than a gap, and the README's language table now says so.
- [x] ~~**Per-parameter documentation is not universal either.**~~ Not
  foreseen here and found by measuring: `param_docs = false` on Zig and
  assembly, because judging a language by a convention it does not have
  produces a wrong number rather than a low one. Same shape as
  `module_tag = false`. See `doccoverage.by_language`, which is what made it
  visible.
- [x] ~~**`module_map.json` schema versioning, revisited.**~~ Closed. Two
  node fields have shipped since this was written — `language` (schema 3)
  and `markers` (schema 4) — and the tolerance path was verified rather
  than assumed both times: `diff.lua`'s check is written `>= 2`, not
  `== 2`, and was run against a real schema-2 artifact out of this
  repository's own history. `scan.M.SCHEMA` is now the single site the
  number lives at, because `--capabilities` reports it too and a second
  copy of a constant starts exactly that way.
- [~] **A real per-language sample tree**, checked into `TESTS/fixtures/`
  or fetched by the runner, per language — not just hand-written snippets.
  Not optional: this repository's own `core/plugins.lua` work is the
  concrete evidence a synthetic-fixture-only approach misses real bugs (see
  *Considerations*). **The polyglot one is built** —
  `TESTS/fixtures/polyglot/`, Lua beside JS/TS, which is the tree that would
  have caught the `detect_source` failure the day the JS backend shipped.
  A per-language tree for each *new* backend is still owed as that backend
  lands.

### Phase 1 — JavaScript / TypeScript — **done (2026-08-03), three gaps remain**

Sequenced first per Part 1's conclusion: closest doc-tag fit, largest
audience, and the language `docs/FRAMEWORK_CONVENTIONS.md`'s layer-2 work
depends on. Fully built and documented in
[`docs/FEATURES/FEATURES.md`](../../FEATURES/FEATURES.md) — grammar
(`tree-sitter-javascript`/`typescript`/`tsx`), import extraction (ESM +
CommonJS), JSDoc/TSDoc parsing, the fourteen-check audit
(`missing-module-tag` needed a variant, the other thirteen ported as-is),
React hooks as a seventh Analysis panel, calls extraction
(`calls.lua`'s resolver needed **zero** JS-specific changes), symbols
extraction, and CI now building all three grammars from source. Not
re-detailed here — read `FEATURES.md`'s own entries for the verification
evidence.

**All three gaps are closed, 2026-08-18.** Every node shape was re-verified
against a real parse first, as this document's own closing caution demands.

- [x] ~~**Class-method owning-scope.**~~ Methods are recorded as
  `Class.method` — the flat shape Lua already uses for `function M.foo()`,
  needing no new IR field and touching none of `duplicates.lua`,
  `churn.lua`, the Analysis renderers or the Calls view. **The Phase-0
  owning-scope field is still required and this is not a substitute for
  it**: Python's `self`-bound methods and Rust's `impl` blocks carry
  semantics a dotted name cannot express. This is the cheap correct answer
  for the one language where it is cheap. Accessors (`get x()`) are skipped
  rather than given a signature that reads as callable and is not.
- [x] ~~**`.jsx` support.**~~ Claimed by `js.lua`, exactly as `tsx.lua`'s
  header said it should be. Verified rather than assumed: the `javascript`
  grammar parses a real JSX component with **zero** ERROR nodes, so no
  second grammar was needed for it.
- [x] ~~**`module.exports = {...}`**~~ — the shorthand method form, a
  `function` value and an arrow value, each carrying its own JSDoc. A
  non-function property is not mistaken for one, and the indirect form
  (`module.exports = someIdentifier`) is deliberately **not** followed:
  tracing an identifier back to its assignment is exactly the guess
  `deps.lua` already refuses to make about computed requires.

**Cross-file call resolution — built 2026-08-18, and it had a prerequisite
this document did not name.** The stated gap was that `extract_requires`
never recorded *which names* an import binds, so a bare `helper()` had
nothing for `calls.lua`'s alias-then-`.member` model to resolve through.
True, and not the whole story: measured first, `./util.js` was being recorded
as an **external** module. `deps.module_index` keys on a declared `@module`
path, an ECMA node declares none (`ecma.lua`: "module identity is the file
path itself"), so no JS import could resolve to a node at all — the name
binding would have had nothing to bind *to*.

Both layers now exist:

- `deps.path_index`/`deps.resolve_relative` resolve `./`, `../`,
  extensionless and `dir/index.*` specifiers against node paths. Candidate
  extensions come from `lang_registry`, so a future backend resolves without
  `deps.lua` learning its name. Bare specifiers (`react`, `plenary.async`)
  are never resolved locally — guessing that `utils` might mean a file here
  is the invention this pipeline declines everywhere else.
- `Documentation.RawRequire.names` records what a named import binds
  (`import { a, b as c }` → `{ a = "a", c = "b" }`), and `calls.lua` matches a
  bare callee against it. Order matters and is deliberate: file-local first,
  then the import, then the heuristic — a file declaring its own `helper`
  *and* importing one means its own, and an import is an exact fact where the
  heuristic is a guess.
- `* as ns` is recorded as an `alias`, which is exactly what it is, so
  `ns.thing()` resolves through machinery that already existed.
- A **default** import is deliberately left unbound: it names the default
  export, not the module object, and treating it as an alias would resolve
  `def.thing()` against members that may not be reachable that way — a wrong
  answer dressed as a resolved one.

Verified on `TESTS/fixtures/polyglot/`: `src/parse.ts` requires
`src/util.js` as a node rather than an external, and the call edge
`polyglotFixtureSplit → polyglotFixtureJoin` lands with `exact` confidence.
This repository's own map gained only the edges of the new code itself and
lost none, which is the check that mattered — Lua's dotted requires are never
relative, so nothing about them moved.

### Phase 2 — Python — **not started**

- [ ] Docstring **style detection**: reST, Google, and NumPy conventions
  coexist across real Python codebases, sometimes within one. Two problems,
  not one — no universal format (needs a per-style parser with a detector),
  and a docstring is a *runtime string* literal, not a comment block, so
  the parse is structured text inside a string node rather than tags in
  comments the way LuaCATS/JSDoc are.
- [ ] Decorators (`@property`, `@staticmethod`, a project's own) are a real
  shape with no Lua equivalent — decide whether they are metadata on
  `Documentation.FunctionInfo` or a check's own concern before writing the
  extractor, not after.
- [ ] Import extraction: `import x`, `from x import y`, relative imports
  (`from ..pkg import x`) against `sys.path` — closer to Rust's
  parent-declares-the-module problem than to Lua's flat `require`.

### Phase 3 — Rust — **not started**

- [ ] `mod x { … }` is the sharpest instance of Phase 0's "one file, many
  modules" gap — a Rust module is declared by its *parent*, inverted from
  every other language here where a file declares its own identity.
  Confirm the Phase-0 IR change actually covers this shape specifically,
  with a real multi-module `.rs` file, before writing the extractor.
- [ ] `impl` blocks own methods — the Phase-0 owning-scope field's other
  real test case besides Python classes; a method's owner is not textually
  where the method is defined the way `M.foo` is in Lua.
- [ ] rustdoc (`///`) is prose Markdown with **no tag vocabulary at all**.
  The param-shaped checks (`undocumented-param`, `param-name-mismatch`)
  have nothing to compare against and do not port. `missing-summary` does.
  Do not build fake `@param` recognition against prose that was never
  structured that way.

### Phase 4 — Go — **not started**

- [ ] godoc's *entire* checkable convention is "the comment starts with the
  identifier it documents." Worst fit of the five for a reason: this
  replaces six of Lua's fourteen checks with one. Confirm before starting
  that one check is still worth a whole backend — the honest answer may be
  "only once JS/TS and one other language have already proven the Phase-0
  architecture is real," not on its own merits.
- [ ] Receivers (`func (r *Type) Method()`) are Go's version of the
  owning-scope problem — same Phase-0 field, third real test case.
- [ ] Package-per-directory (not per-file) is closer to Lua's own
  `init.lua`-marks-a-module convention than to JS/Python/Rust — likely the
  cheapest walk-level fit of the five once Phase 0 lands.

### Phase 5 — C (and C++) — **built 2026-08-19, out of order**

Built ahead of Phases 2–4 because it was asked for. The three open
questions below were the real content of this phase, and each got an
answer; they are kept, struck, with the answer attached, because the
answers are the part worth reading.

- [x] ~~Declaration vs. definition~~ — **decided per file, not per
  function, and no new edge kind.** In a header a prototype *is* the
  function (a header is the published surface and the file people read; a
  header reporting nothing would be the emptiest node on the map). In a
  source file only definitions are reported, since a forward declaration
  there duplicates the body below it. The two are deliberately *not*
  joined: `util.h`'s `add` and `util.c`'s `add` are two entries on two
  nodes with the include edge between them. Joining them still needs the
  `declares`/`defines` edge kind described here — this is the honest
  version that fits today's schema, not a substitute for it.
- [x] ~~Doxygen `\param`/`@param` where present~~ — both sigils accepted,
  as are `/**`, `/*!`, `///` and `//!`. **And the warning in this entry
  turned out to understate the problem, which measuring caught:** scanned
  against `antirez/sds` (1328 lines, 45 functions, nearly all commented)
  the Doxygen-only rule found **zero** summaries, because that codebase
  writes plain `/* ... */`. Degrading honestly there would have meant
  reporting a thoroughly documented C file as undocumented — wrong about
  the one thing the map exists to show. So a comment directly above a
  declaration documents it whatever its punctuation, with one filter
  (`looks_like_prose`) against commented-out code, and the *file* header
  rule still demands Doxygen style so a license banner never becomes a
  file summary. Same tree, after: 34 of 45.
- [x] ~~No package/module system~~ — **the path is the identity**,
  `module_tag = false`, a directory is a namespace. Zig established the
  shape and C agrees with it for free: the preprocessor works on paths, not
  on names. The "hardest walk-level fit" prediction was wrong, and worth
  recording as wrong — the hard part of C was documentation conventions,
  not identity.
- [x] ~~C++~~ — same file (`core/lang/cfamily.lua`), the way `ecma.lua` is
  shared by three registrations. What C++ adds: `Thing::go` as a written
  name (taken as written, not reconstructed), members declared inside a
  class body, and an access specifier that is *positional* — everything
  after `private:` is private until the next one, `class` starts private,
  `struct` starts public. That last one is tracked while walking because
  there is nothing on the member node to read.

### Requested out of phase order — Zig, Java, and what is left

Asked for directly on 2026-08-19, and built ahead of Phases 2–5 for a
reason worth writing down: **phase order was scoped by check-count, and a
request is a better signal than an estimate.** Both were built against a
real parse, with a grammar built from source for that purpose, which is the
bar Phase 1 set and the thing Phases 2–5 are explicitly warned not to claim
without.

- [x] ~~**Zig**~~ — `core/lang/zig.lua`, built 2026-08-19. The closest fit of
      any language added so far, because its documentation convention is
      part of the language rather than bolted onto comments: `//!` is the
      file's doc, `///` documents the declaration below it, and `pub` is
      visibility rather than a naming convention. `module_tag = false` — a
      Zig file's identity is its path.
- [x] ~~**Java**~~ — `core/lang/java.lua`, built 2026-08-19. The first
      backend whose doc convention is older and stricter than this tool's:
      Javadoc's `@param` / `@return` / `@throws` / `@deprecated` are parsed
      rather than guessed, and the parse is close to `ecma.lua`'s JSDoc
      because JSDoc descends from Javadoc. `package a.b.c;` plus the file
      stem gives a genuinely fully qualified module name — something no
      other backend here gets from the language itself — while
      `module_tag` stays `false`, since a package declaration is not a
      documentation tag and a file in the default package is legal.

**What Java cost, measured rather than estimated:** one backend file, one
spec, one grammar, and **one engine bug it exposed** — `core/markers.lua`
only recognised comment nodes named `comment`, so every grammar that names
them `line_comment` / `block_comment` (Java does) reported zero markers.
It failed in the quiet direction: the parser answered with an empty list,
which reads as "no comments in this file" rather than "this grammar was not
understood", so the text fallback never ran either. Caught by
`backend_contract_spec.lua`, which exists precisely because that spec
proves the comment token *works* instead of that it is declared.

- [x] ~~**C / C++**~~ — built 2026-08-19; both questions Phase 5 raised are
      answered there, with what measuring changed about the second one.
- [x] ~~**Assembly**~~ — `core/lang/asm.lua`, built 2026-08-19, the ninth
      backend, and the last of the five requested. The decision this entry
      was waiting for came back *build it, labels and includes*, and the
      building found the entry's own premises half wrong.

      **It is the first backend here with no tree-sitter grammar, and that
      is the design rather than a shortcut.** This entry called GAS/NASM/ARM
      a fork and it is right — which is exactly why a grammar is the wrong
      instrument: one is written against one side of the fork, so a NASM
      file read by an x86-GAS grammar is not a degraded parse but a
      confident wrong one. Everything this backend needs is line-directed in
      *all* of those syntaxes, because assembly is line-oriented by
      construction. `lang_registry.report()` already distinguished
      `grammar = nil` ("needs no parser") from `false` ("wanted one, did not
      get it"); until now nothing exercised the first, and
      `lang_registry_spec.lua` asserted every backend had a grammar. It now
      tests both branches, and `lang_asm_spec.lua` is the only language spec
      here that never skips.

      **What this entry got wrong: "no function-visibility concept."**
      `.globl`/`.global` (GAS, ARM), `global` (NASM) and `PUBLIC` (MASM) are
      explicit exports — a *stronger* signal than most languages here give,
      and unlike C it needs no header file to read it from. The other two
      premises held: no module system (so the path is the identity, as Zig
      established) and no documentation convention.

      **Two measurements changed the design, and both are the C lesson
      again.** Scanned against `nemasu/asmttpd` (2334 lines of real NASM):

      1. Reporting every label gave **129 "functions" for a program with
         about sixty**, because branch targets are labels too. The signal
         turned out to be layout, which every assembly file already uses: a
         routine's label sits in column zero, a branch target is indented
         with the instructions around it. asmttpd is 61 flush / 76 indented;
         `musl`'s 304 assembly sources are 579 flush / **zero** indented —
         so the rule removes noise where there is noise and costs nothing
         where there is none. After: 63.
      2. Reading only the comment *above* a label found **5 documented
         routines of 63** in a codebase that annotates nearly all of them —
         because it writes the calling convention *trailing* the label
         (`add_content_type_header: ;rdi - buffer, rsi - type`). That is the
         closest thing assembly has to a parameter list, and calling it
         undocumented would repeat the Doxygen-only mistake exactly. After:
         29 of 63.

      A label followed by a data directive (`.asciz`, `db`, `resb`) becomes
      a `SymbolInfo` rather than a function, as do `.equ`/`.set`/`equ` — so
      the map separates an assembly file's code from its data the way its
      author already did.

Every requested language is now built. What assembly knowingly does not see
is named in its own header rather than left to be discovered: NASM's
column-zero label without a colon, MASM's `name PROC`, and anything a macro
generates — each a "found nothing" rather than a wrong answer.

---

## The other 30 — requested 2026-08-19

**The ask, stated as given:** the two rankings that matter in practice —
TIOBE (search interest) and the Stack Overflow / GitHub Octoverse pair
(actual use and contributor activity) — thirty languages each. Every one of
them gets a backend.

Deduplicated across both lists and with the nine built ones removed, that is
**30 new languages**, listed below in the order they will be built. One is
struck before it starts, for a reason recorded rather than assumed.

**Where this sits in the running order:** second-to-last. Everything else
open in `docmap-desktop`'s `docs/WORKPLAN.md` comes first, this block comes
next, and the remaining documentation rewrite (that plan's §10.7) is last —
deliberately, so the docs are written once against the finished set rather
than rewritten thirty times.

### Four decisions taken before any of it was built

Taken up front because each one changes what gets written rather than how,
and finding them mid-implementation would mean discarding work.

1. **Scratch is not built, and the reason is that there is nothing to
   read.** A `.sb3` is a ZIP holding `project.json`; there is no source
   text, no comment syntax, no import, no visibility. A backend for it
   would share not one line with the other twenty-nine — no tree-sitter, no
   file scan, no comment extraction — which makes it a second tool wearing
   this one's contract. Recorded here so the next reader does not have to
   re-derive the same answer from the same evidence.
2. **Visual Basic means VB.NET (`.vb`).** VBA is the other language of that
   name and mostly lives *inside* a binary Office document this tool does
   not open; reading only the exported `.bas`/`.cls` would produce a map
   that is silently missing most of a project. VB.NET is plain text with
   `Module`/`Class`, real `Public`/`Private` visibility and `Imports` as a
   require edge, and fits the contract without an exception.
3. **SQL is one backend, not one per dialect.** It has no modules, no
   imports and no visibility — the same shape as assembly — and T-SQL,
   PL/SQL and PL/pgSQL are a fork rather than dialects. So: the file is the
   module, `CREATE FUNCTION`/`CREATE PROCEDURE` is the function, tables and
   views are symbols, and `\i`/`SOURCE` is the require edge. One
   statement-oriented scanner reading all of them beats three grammars
   drifting apart.
4. **Where no maintained tree-sitter grammar exists, the backend is a line
   scanner** — the instrument assembly already proved. Fortran, Ada, COBOL,
   Delphi/Object Pascal, MATLAB and VB.NET are all line- or
   statement-oriented and declare procedures with a keyword at the start of
   a line, which is exactly the shape that reads correctly without a parse
   tree. `lang_registry.report()` already distinguishes "needs no parser"
   from "wanted one and could not find it", so these are reported at full
   fidelity rather than as broken.

### The order, and why it is this one

Grouped by how much of the contract is already answered by the language
itself. The cheapest and most-used go first, so the seam is exercised hard
before it meets anything exotic.

**Wave 1 — a grammar exists and the contract answers are obvious.**
The ten highest-traffic languages on either list that are not already built.

- [x] ~~**Python**~~ — `core/lang/python.lua`, built 2026-08-20, the tenth
      backend and the first of these thirty. Everything this entry predicted
      held: docstrings are the doc source, `__all__` overrides the
      underscore, and `__init__.py` is the first `module_file` since Lua's
      `init.lua`.

      **Two decisions the entry did not anticipate.** The docstring
      convention forks three ways — reST, Google, NumPy — so the style is
      detected **per docstring** rather than per project, because one
      repository mixes them and a project-wide guess is wrong exactly on the
      function somebody wrote differently. And `self`/`cls` are dropped from
      the emitted signature: the map shows the *call* signature, and keeping
      the receiver would make every method in every Python project report an
      undocumented parameter forever, since no convention documents it.

      **Four bugs, and all four were silent — wrong answers, not missing
      ones.** One from the fixture: `owner and nil or exported` judged every
      *method* against the module's export list, because `x and nil` is
      falsy and the `or` branch runs — the `and`/`or`-return-operands trap
      the Lua glossary carries an entry for. Three more from scanning
      `psf/requests` (19 files, 257 functions):

      * A **typed splat** nests one level deeper, so `**kwargs: Unpack[T]`
        vanished from every annotated signature — and `requests`' whole
        public API is written that way.
      * **reST escapes the asterisks**, so a documented `\*\*kwargs` could
        never match the declared `**kwargs`: a `param-name-mismatch` on
        every reST-documented project.
      * A **reST section underline** joined its title, giving
        `requests.api ~~~~~~~~~~~~` as that module's summary. Assembly's
        banner filter, in a different alphabet.

      A fifth came from the spec rather than from a scan: a stray `
`
      survived into any description built by joining lines, which is every
      CRLF-saved Python file on Windows.

      **Measured on `psf/requests`:** 257 functions, 159 documented, 143
      parameters across 49 functions, 104 symbols, and 66 of 163 imports
      relative — which is to say resolvable to real edges inside the tree.
- [x] ~~**C#**~~ — `core/lang/csharp.lua`, built 2026-08-20, the eleventh
      backend. **The first documentation format here that is markup**, which
      makes three shapes in the tool now: tags (LuaCATS, JSDoc, Javadoc,
      Doxygen), prose with sections (Python), and XML. It is also the only
      one that names a parameter by *attribute* — `<param name="x">` states
      which parameter it documents, where Javadoc relies on the first word
      and a docstring on a section's layout.

      Parsed with patterns rather than an XML parser, deliberately: a doc
      comment is a fragment, not a document — unbalanced tags and
      `<see cref="T"/>` mid-sentence are ordinary — and an XML parser would
      reject a large share of the doc comments in any real project. The
      elements that carry structure are read; the markup that only decorates
      (`<c>`, `<see>`, `<paramref>`) is stripped, keeping the referenced name.

      **Visibility has two defaults, and missing the second one is an
      inversion rather than a near miss.** A *class* member with no modifier
      is private; an *interface* member with no modifier is public. The first
      version applied the class rule everywhere, and every method of every
      interface came back internal — on the one construct that exists to
      declare a published API. The fixture has an interface in it for exactly
      that reason.

      **The second real-code finding was the preprocessor.** `#if` wraps
      whatever it guards, so a `using` or a type inside one hangs off a
      `preproc_if` rather than off the compilation unit. Skipping those lost
      three of Serilog's thirty-six usings — and, more than that, ten
      functions and eleven symbols that live only inside a conditional
      branch. Every branch is walked now, including ones a given build would
      not compile: this map describes a repository, not one configuration
      of it.

      **What `using` cannot do**, stated in the backend rather than left to
      be discovered: a `using` names a *namespace*, not a file, unlike Java's
      `import a.b.C` which names a compilation unit. So C# `using` edges are
      almost all external, and the edge C# really has at file level is a type
      reference — which needs a resolution pass this pipeline does not run.

      **Measured on `serilog/serilog`:** 113 files, 590 functions (473
      public, 327 documented), 727 documented parameters, 370 symbols, 36 of
      36 usings, and 107 of 113 files carrying a fully qualified module name.
- [x] ~~**Go**~~ — `core/lang/go.lua`, built 2026-08-20, the twelfth
      backend. Everything this entry said held, and Part 1's much older
      verdict — that Go is the *worst fit* of the five it costed, because
      godoc has no tag vocabulary at all — held too, and is now measurable
      rather than predicted.

      **Visibility is the cheapest and most reliable of the twelve.**
      Capitalisation, enforced by the compiler: no keyword to find, no tag to
      trust, no export list to read, and nobody can be wrong about it.

      **Third `param_docs = false` language, and the first for this reason.**
      Assembly has no parameter list; Zig documents the declaration as a
      whole; **Go has parameters and documents them nowhere.** That leaves
      exactly one checkable claim, and godoc really does make it — *a doc
      comment begins with the name of the thing it documents* — which is
      machine-checkable and which no check in this tool tests yet. Recorded
      rather than built: a new check is a decision about what fails somebody's
      CI.

      **No module name, and this is the one language where the name exists
      and still cannot be used.** A package is a *directory*: every `.go` file
      in it declares the same `package foo`, so using that as the module name
      would have three files claiming one identity. The path is the identity,
      as with Zig, C and assembly.

      **The measurement changed one thing, and it was worth the scan.**
      Against `spf13/cobra`: Go's own test naming (`TestXxx`, `BenchmarkXxx`,
      `ExampleXxx` — all necessarily capitalised) made every test function
      look like published API. 184 exported functions in the sources, **289
      more** in the tests, so the published surface read two and a half times
      its real size; documentation coverage averaged 38% for a library whose
      sources are at 75%. The fix is a compiler fact rather than a
      convention: a `_test.go` file is excluded from the importable package
      entirely, so nothing declared there is API whatever its spelling. The
      tests stay in the map — Go puts them beside the code by design — they
      simply stop claiming to be API. After: 184 exported, 175 of them
      documented.

      Also here and not in the entry: an **interface's methods** are
      `method_elem` nodes with no body and no receiver, so they are missed by
      the function branch and an interface would have shown its name and
      nothing it promises. The lesson C# taught one backend earlier by
      getting the same construct backwards.
- [x] ~~**Rust**~~ — `core/lang/rust.lua`, built 2026-08-20, the thirteenth
      backend, and the one that meets Phase 0's last open item head-on.

      **`mod x { … }` is answered by qualifying the name, not by changing the
      IR** — the same move C++ made for `Thing::go` and Python for
      `Thing.go`. A function in an inline module is `x::helper`, an inherent
      method `Widget::new`, a trait method `Doer::go`. Nothing is missing
      from the map and nothing is mis-attributed. The Phase 0 item asking for
      `Documentation.Node` to hold several modules per file **stays open**,
      and the difference is worth being precise about: an inline module is
      not a node, so it has no summary, no coverage and no edges of its own.
      What is closed is the practical half.

      **Fourth `param_docs = false` language, and the only one this document
      predicted years in advance.** Part 1 costed rustdoc as "prose Markdown,
      no tag vocabulary" and concluded `param-name-mismatch` would have
      nothing to compare against. It does not. `# Arguments` is a Markdown
      heading some projects write and most do not.

      **The module path is derived from the file path**, which is what makes
      Rust the first of these thirty with a real internal dependency graph:
      `src/foo/bar.rs` is `foo::bar`, so `use crate::foo::bar::Thing`
      resolves to a node instead of landing in `requires_external`.

      **The measurement changed that design once, and prevented a wrong
      edge.** `clap-rs/clap` is a Cargo *workspace* with three members, and
      every member has its own `crate::` root — so a first version naming
      modules `crate::builder` gave one name to two different files, and a
      module index keyed on it would resolve one member's import to the
      other member's file. The crate name comes from the directory holding
      `src/` now, which is Cargo's own layout rule.

      **Two `use` shapes, one fixed and one deliberately left.** `use
      crate::a::{B, C}` kept its braces and matched nothing — fixed. `use
      crate::util::eq_ignore_case` imports a *function* from `crate::util`
      while `use crate::output::textwrap` imports the *module*, and both are
      `snake_case`: nothing in the path says which. The path is kept whole
      and the edge does not resolve, which under-claims rather than pointing
      at the wrong module.

      **Measured on `clap-rs/clap`:** 76 files, all 76 with a module path,
      1547 functions (515 public, 489 of those documented — 95%), 205
      symbols, and **295 of 317 crate-internal `use` edges resolving to a
      node**.

      One more thing, and it is the third time: **a trait member carries no
      visibility modifier of its own** — writing `pub` there is a compile
      error — so reading the absent modifier as private reported every method
      of every public trait as internal. C#'s interface and Go's interface
      were the first two. Three languages, three spellings, one meaning:
      *this declaration exists in order to be published.*
- [x] ~~**PHP**~~ — `core/lang/php.lua`, built 2026-08-20, the fourteenth
      backend. The three edges this entry named are told apart, and telling
      them apart turned out to be the interesting part: `use` is a *symbolic*
      import that loads nothing, `require`/`include` load a *file* at run
      time, and a project uses one or the other rather than both. **PHP is
      the first language here where both kinds produce edges in one map** —
      C has only the file kind, Java and C# only the symbolic one.

      Both resolve, differently. A `use` names a class, and PSR-4 *requires*
      the class name to match the file name — so `Acme\Other\Thing` matches
      the module this backend derives for `src/Other/Thing.php`. A `require`
      names a path and is rewritten `./`-relative, as assembly's `%include`
      is.

      **The default visibility runs opposite to C#'s, and that is worth more
      than a footnote.** A PHP method with no modifier is **public**. C#
      taught this tool that an absent modifier can mean private and that
      reading it wrong inverts an entire API; PHP is where the same absence
      means the opposite. So the rule is written as *not private and not
      protected* rather than as *has `public`* — the latter would report
      every unmarked method in every legacy PHP file as internal.

      **PHP is also the only backend where a keyword and an authoring
      convention are both available and both read.** PHPDoc's `@internal`
      keeps a `public` method out of the published surface, which is the
      convention layer Lua and the ECMA family live on, sitting over a
      language that also has real keywords.

      **Two findings, one from the fixture and one from the contract test.**
      `__DIR__ . '/helpers.php'` reads literally as `/helpers.php`, which
      would resolve against the top of the scanned tree — a real file,
      somewhere else; the slash there is a separator, not a root. And
      `backend_contract_spec.lua` reported PHP's own comment token as
      producing no marker — correctly, because **PHP source outside `<?php`
      is text**, so a bare `// TODO: x` is inline HTML with no comment node
      in it. The grammar was right and the question was wrong, so the
      contract gained `code_prelude`: what a minimal file of a language must
      begin with for its code to be code. Absent for all thirteen others.

      And for the fourth time in four backends: **an interface member is
      public and cannot be declared otherwise** — `private` on a PHP
      interface method is a fatal error. C#'s interface, Go's interface,
      Rust's trait, PHP's interface. Four languages, four spellings, one
      meaning.

      **Measured on `guzzle/guzzle`:** 68 files, all 68 with a fully
      qualified module name, 625 functions (269 public, 160 of those
      documented), 187 documented parameters with union types intact, 306
      symbols, and 109 of 286 `use` edges resolving to a node in the tree —
      with **zero** `require` edges, which is exactly what the header
      predicts of a PSR-4 project.
- [x] ~~**Ruby**~~ — `core/lang/ruby.lua`, built 2026-08-20, the fifteenth
      backend. The positional visibility this entry predicted is exactly
      that, tracked while walking as C++'s access specifier is — **and Ruby
      adds two spellings C++ has no equivalent of.** `private def foo` marks
      one definition without changing the default, and `private :foo` marks a
      method **by name**, possibly long after it was written. No other
      language here can change a declaration's visibility from somewhere else
      in the file, which is why methods are indexed by name as they are
      recorded. A class method after `private` is still public, since
      `private` affects instance methods only.

      **The naming is Ruby's own**: `Widget#add` for an instance method,
      `Widget.build` for a class method. They are different methods and can
      share a name, so merging them under `::` — as C++ and Rust do — would
      lose that.

      **`param_docs = false`, and this is the first backend to declare it
      while still parsing parameters.** YARD's `@param [Integer] x` is real,
      common and worth showing, so it is extracted and displayed. But YARD is
      a *gem*, not the language — RDoc ships with Ruby and has no
      per-parameter form at all — so judging Ruby by parameter documentation
      would report a project documenting beautifully in RDoc as documenting
      nothing. **Parse and display; do not judge.** A different position from
      Zig's, Go's, assembly's and Rust's, where there was nothing to parse.

      YARD's `@api private` is honoured as well, the authoring-convention
      layer PHP's `@internal` sits on.

      **Measured on `sinatra/sinatra`:** 7 files, 161 methods (132 public, 46
      of those documented), 50 symbols, 18 requires — and **zero YARD
      parameters**, because Sinatra documents in RDoc. That is precisely the
      project `param_docs = false` protects: its real summaries are extracted
      and shown, and it is not marked down for a convention it never adopted.
- [x] ~~**Kotlin**~~ — `core/lang/kotlin.lua`, built 2026-08-20, the
      sixteenth backend. The four visibilities collapse to two as this entry
      predicted — **but the interesting part is the default, which the entry
      did not name.** A Kotlin declaration with no modifier is `public`. C#
      says private for the same silence and Java says package-private: three
      languages that look alike on the page and disagree about what silence
      means. Most Kotlin declares no modifier at all, so the rule is written
      as *not private, not protected, not internal* — asking for the keyword
      would report an entire codebase as unpublished.

      **KDoc has one tag no other language here does:** `@property name`,
      which documents a constructor parameter that is also a property. It is
      read as a parameter, because in a `data class` that is the only place
      the fields are described — anything else would leave every data class
      in the language undocumented.

      One fixture finding: taking the *first declaration* for the file
      summary is wrong in Kotlin, because a top-level `const val` above the
      class is ordinary. A type is preferred over a function and a function
      over a property, so the summary describes the file rather than its
      first constant.

      Fifth language to need the interface default — after C#, Go, Rust and
      PHP.

      **Measured on `Kotlin/kotlinx.coroutines`** (the common source set):
      111 files, all 111 with a module name, 1164 functions (747 public, 360
      of those documented), 754 symbols, 370 imports, 93 file summaries.
- [ ] **Swift** — `.swift`. Markup comments (`///`), five access levels
      (`open`/`public`/`internal`/`fileprivate`/`private`) collapsing to
      two, and no import-by-path — a module is a build target, so the path
      is the identity here too.
- [ ] **Dart** — `.dart`. `///` doc comments, and visibility is a **leading
      underscore that the compiler enforces**, which makes Dart the one
      language where the underscore convention is a fact rather than a
      guess.
- [ ] **Scala** — `.scala`, `.sc`. Scaladoc, `private[x]` qualified
      visibility, `package` identity.

**Wave 2 — a grammar exists, the paradigm is further from what is built.**

- [ ] **Haskell** — `.hs`. Haddock (`-- |` and `-- ^`), and visibility is
      the **module export list** rather than a per-declaration marker,
      which is a shape nothing here has met: the header decides what the
      rest of the file publishes.
- [ ] **Elixir** — `.ex`, `.exs`. `@moduledoc`/`@doc` are genuinely
      first-class documentation — attributes the compiler keeps — and
      `def`/`defp` is real visibility. Closest fit in this wave.
- [ ] **Erlang** — `.erl`, `.hrl`. `-module`/`-export` is an export list
      like Haskell's; EDoc for prose.
- [ ] **OCaml** — `.ml`, `.mli`. The `.mli` interface file *is* the
      published surface, which is the header/source split C already forced a
      decision on — and here the language means it rather than implies it.
- [ ] **F#** — `.fs`, `.fsi`. Same interface-file shape, XML doc comments,
      and file *order* is semantically meaningful, which nothing else here
      has to model.
- [ ] **Julia** — `.jl`. Docstrings above the definition, `module`/`export`.
- [ ] **R** — `.R`, `.r`. Roxygen2 (`#'` with `@param`/`@return`) is a
      documentation tool with a generator behind it, the same class of fact
      Javadoc was; `NAMESPACE`'s export list is the visibility answer.
- [ ] **Perl** — `.pl`, `.pm`. POD is a documentation format that is *not*
      comments — it interleaves with code and has its own lexer, which is
      the first time a backend has to read two syntaxes in one file.
- [ ] **Groovy** — `.groovy`, `.gradle`. Groovydoc, JVM visibility. Its
      real use is CI/CD and Gradle builds, so this is a build-file mapper as
      much as a language one.
- [ ] **Solidity** — `.sol`. NatSpec (`/// @notice`, `@dev`, `@param`) is a
      documented standard, and visibility is four keywords the compiler
      requires on every function — the strictest visibility of anything in
      this list.

**Wave 3 — the shells, which are a language question people argue about.**
Included because both rankings list them and because a repository's
automation is part of what a map should show.

- [ ] **Bash** — `.sh`, `.bash`, `.zsh`. Functions exist; there is no
      module system and no visibility, so path identity as with Zig, and
      `source`/`.` is the require edge.
- [ ] **PowerShell** — `.ps1`, `.psm1`, `.psd1`. Comment-based help
      (`.SYNOPSIS`, `.PARAMETER`) is a real convention with `Get-Help`
      behind it; `Export-ModuleMember` and the `.psd1` manifest are the
      export list.

**Wave 4 — no maintained grammar, so a line scanner, per decision 4.**

- [ ] **Fortran** — `.f90`, `.f95`, `.f03`, `.f`, `.for`. `module`/`use`,
      `public`/`private` statements, and fixed-form source in the older
      extensions where column position is syntax.
- [ ] **Ada** — `.ads`, `.adb`. Specification and body in separate files —
      the OCaml/C shape again, and the third language to force that
      decision, which is worth watching for a pattern the IR should carry.
- [ ] **COBOL** — `.cob`, `.cbl`. Divisions and sections are the structure;
      `COPY` is the require edge. Fixed-form columns again.
- [ ] **Delphi / Object Pascal** — `.pas`, `.dpr`. `unit`/`interface`/
      `implementation` is a genuine published-surface split declared in one
      file, which is a shape neither C nor OCaml has.
- [ ] **MATLAB** — `.m`. One function per file by convention, so the file
      name *is* the function name. `.m` also being Objective-C's extension
      is a conflict to resolve when an Objective-C backend exists, not
      before.
- [ ] **Visual Basic (.NET)** — `.vb`. `Module`/`Class`, `Public`/`Private`,
      `Imports`, and XML doc comments.

**Wave 5 — the one decided into its own shape.**

- [ ] **SQL** — `.sql`. Per decision 3.

**Not built, and here is the reason:**

- [x] ~~**Scratch**~~ — see decision 1. Not a text language; there is
      nothing for this contract to read.

### And then: feature parity across all of them

- [ ] **The parity pass, once every backend exists.** The rule asked for is
      that a feature Lua has, every language has — *in its own terms*, not
      by pretending each language is Lua. So this is an audit with a table:
      one row per contract capability (file summary, declaration summary,
      parameters, returns, visibility, module identity, require edges, call
      edges, symbols, markers, glossary), one column per language, and every
      empty cell either filled or given a written reason that names what in
      the language makes it impossible.

      **The reasons matter as much as the fills**, and the languages already
      built prove it: assembly has no parameter list because a label has no
      calling convention to read, and inventing `()` would claim one. That
      is a filled-in reason, not a gap. A blank cell with no sentence beside
      it is the only real failure this pass is looking for.

---

## Considerations

**Why "no half-finished implementations" is a real risk here, not a
generic caution.** `core/plugins.lua`'s own history is the concrete
evidence: a feature that passed every hand-written fixture still produced
235 false positives against one real config, from two shapes nine fixtures
did not think to cover. A language backend is that risk profile at ten
times the surface area — five extractors instead of one, against
ecosystems this repository's own author has not necessarily written
thousands of lines in. Phase 0's real-sample-tree task is not bureaucracy;
it is the only thing that would have caught the `plugins.lua` bugs, and
synthetic fixtures alone would not have.

**Sequencing is not optional even though scope is "all five."** Each phase
depends on Phase 0 being genuinely stable, which is only provable by a
language actually running against it — the first language is also Phase
0's test. Starting two languages in parallel means finding Phase 0's bugs
twice, in two backends, at the same time, which is strictly more expensive
than finding them once. Phase 1 (JS/TS) already served as that test once;
Phase 2 will be the first real test of the owning-scope and
one-file-many-modules IR changes Phase 0 still has open.

**The IR changes are breaking**, the same way `core`/`editor` was — a
rename-shaped break was acceptable there because the plugin is unpublished.
Whether that is still true by the time Phase 2 starts is a fact to check,
not assume; if the plugin has users by then, the schema-versioning task
above stops being a nice-to-have and becomes the actual hard requirement
of the phase.

**Grammar-shape claims for the unbuilt phases (2–5) are unverified.** Every
claim in those sections is a task description, not a checked fact — unlike
Phase 1's entries, nothing in Phases 2–5 was checked against a real parse.
Re-verify each grammar-shape claim the way Phase 1's extractor already did,
at the point that phase actually starts, not from this document's word for
it.

---

## Part 3 — real numbers, 2026-08-16

Part 1's cost estimate was written before any backend existed. Phase 1 has
shipped since, and its own commit history is a real measurement, not a
second estimate. Recorded here rather than silently edited into Part 1,
because Part 1's number is exactly what this section checks, not something
to overwrite quietly.

### What Phase 1 actually cost

`git log` on `core/lang/ecma.lua` + `js.lua`/`ts.lua`/`tsx.lua`: Phase 0
(`core/lang_registry.lua`, `d21f9f0`) and all of Phase 1 — the backend
itself, calls extraction, symbols extraction, the Hooks Analysis panel,
endpoint extraction — landed between `d21f9f0` and `e4bf0a8`, **the same
day**, 2026-08-03.

`wc -l`: `ecma.lua` is 776 lines, covering all three grammars (JS, TS, TSX)
through one shared implementation parametrized by grammar name — `js.lua`/
`ts.lua`/`tsx.lua` are 10–17-line registrations, not separate
implementations. Part 1 estimated **1 200–1 800 lines for one language**
(§1, "Call one language ~1 200–1 800 lines of the 2 165"). The real number,
for three grammars at once, was 776 — under half the low end of that
estimate for a *single* grammar.

Why the estimate overshot, as far as this can be reconstructed after the
fact: it was scoped against `deps.lua` + `functions.lua` + `symbols.lua` as
three separate concerns, each with its own file-walking and error handling.
`ecma.lua` fuses all three into one pass over one treesitter tree per file,
which is cheaper than the sum of separate modules doing the same walk
three times — the same reason a single `scan_file` returning an eight-value
tuple is cheaper than four functions each re-parsing.

**What this does and does not license.** JS/TS was the cheapest case Part 1
itself identified — closest doc-tag fit, no owning-scope requirement, one
file = one module already. It is real evidence that the *interface* (the
six-field `Documentation.LangBackend` contract) is cheap to satisfy once
Phase 0's hard parts do not apply. It is not evidence that Python or Rust
will be equally cheap — both need Phase 0 work Phase 1 explicitly did not
require (owning-scope for Python's classes, one-file-many-modules for
Rust's `mod`). Treat the revised per-language numbers below as "scaled from
one real data point plus the same reasoning Part 1 already did", not as
measured the way Phase 1's own row is.

### Revised cost table

Phase 0's still-open items (owning-scope, one-file-many-modules,
visibility, schema versioning) are **shared cost**, paid once, not
per-language — estimated at 2–4 days total, blocking every phase that
needs any of them.

| Language | Cost *after* Phase 0 | Checks that apply (of 14) | Note |
|---|---|---|---|
| JS/TS/TSX | done, 1 day, measured | 13–14 | Reference case; needed none of Phase 0's open items |
| **C** | 2–3 days | ~11, where Doxygen is used at all | No owning-scope needed — could ship *without* waiting on Phase 0's harder items, the same way JS/TS did. Doxygen is where LuaCATS's own tag vocabulary descends from — closest doc-convention fit after JS/TS, not Python |
| Python | 3–4 days | ~12 | Needs owning-scope (classes). Extraction itself is the expensive part: three docstring styles (reST/Google/NumPy) need a per-style parser plus a detector, and a docstring is a runtime string literal, not a comment block — structured-text-inside-a-node parsing, not tag matching |
| C++ | 4–6 days | ~11 | Worse than C specifically: namespaces, classes, templates and overloading all break "one name = one function", which C does not have to deal with |
| Rust | 4–5 days | **~8** | Needs one-file-many-modules (`mod x { … }`, declared by the *parent*) — Phase 0's sharpest test case. rustdoc has no tag vocabulary at all, so `undocumented-param`/`param-name-mismatch` do not port, regardless of implementation cost |
| Go | ~2 days | **~7** | Cheapest to *build* of the five, but godoc's only checkable convention ("comment starts with the identifier") replaces six checks with one. Confirm the check-count math is still worth a backend before starting — Part 1's own conclusion, unchanged |

### Recommendation, revised

Part 1's ordering (Phase 2 Python, Phase 3 Rust, Phase 4 Go, Phase 5 C) was
written before Phase 0's real cost — and JS/TS's real *lack* of need for
most of it — was known. Worth reconsidering, not automatically committing
to: **C is a candidate for the next slot, ahead of Python**, on the same
logic that put JS/TS first — it does not need owning-scope, so it could
land the same way JS/TS did, proving the interface a second time on a
second grammar family (C-style braces vs. JS's) before Phase 0's harder,
riskier items (owning-scope, one-file-many-modules) get touched at all.
Python would then be the first backend that actually exercises those
Phase 0 items — a deliberate choice about *which* backend pays that cost
first, not an accident of list order.

This is a reconsideration to make explicitly with the project owner before
re-ordering Part 2's phase list, not a silent renumbering here — Part 1's
own "no half-finished implementations... at ten times the surface area"
caution applies exactly as much to re-sequencing as to scope.

---

## Part 4 — revised stage plan, 2026-08-18

Part 3 ends by asking for an explicit re-ordering decision rather than a
silent renumbering. This part is that decision, plus three things Parts 1–3
do not cover at all: polyglot trees, the host side (`docmap-desktop`), and
cross-language edges.

Stages are named rather than numbered from Part 2's list, because Part 2's
"Phase 5 — C" and a stage *called* C would collide the moment the ordering
Part 3 recommends is followed.

### Stage 1 — polyglot verification (small, first, blocks everything)

`scan.lua` already asks `lang_registry.for_file` per leaf (line 415) and
`lang_registry.all()` per directory (line 310). **A mixed tree is therefore
structurally supported today, and has never been measured.** That claim is
exactly the kind Part 2's own closing caution says to re-verify against a
real parse rather than take this document's word for.

- [ ] Scan a real Rust+JS tree (`docmap-desktop` itself) and a Lua+TS tree.
      The expected result is a map with JS nodes and no Rust nodes — what is
      actually being tested is whether that happens *honestly or silently*.
- [ ] Count files claimed by no backend, and put the count in the report.
- [ ] `--languages` / `:DocMap languages`: registered backends, which
      grammars loaded, unclaimed extensions with frequencies.
- **Acceptance:** a mixed tree produces a map whose report names the half it
  skipped. `3 812 .py files skipped, no Python backend` — the standing
  answer to silent degradation, applied to the one place it is now most
  likely.

**Measured 2026-08-18, and the walk was the wrong thing to doubt.** The
per-file dispatch is fine. What failed was one step earlier:
`config.detect_source` was a Lua heuristic and nothing else, returning
`"lua"` for any tree it did not recognise, so a three-file JS/TS repository
died on `scan.lua`'s own assert — `source directory not found: <root>/lua`.
The engine has read JavaScript since Phase 1 and no JavaScript repository
could be pointed at it. Fixed by asking the backends (each owns its own
heuristic, each declines rather than guessing) and by giving the walk the
vendored-directory skip list a `src`-or-root `source` makes necessary.

**The mixed tree is closed too, the expensive way.** `source` was one
directory, so a repository with `lua/` beside `src/` mapped whichever
backend answered first and said nothing about the other — verified against a
Lua+JS+TS fixture: one Lua module, `src/` never visited. `opts.source` now
takes a list, `config.detect_source` collects every backend's answer instead
of the first, and `scan.lua` walks each root.

Two decisions inside that, both about not breaking what already works:

- **A synthetic parent node, only when there is more than one root.**
  `ir.root` is one id and a dozen consumers read it as one (the tree view
  renders from it, the hierarchy centres on it, `check.lua` exempts it).
  Giving several roots a real parent — the repository directory they
  actually share — is cheaper and more honest than teaching every consumer
  that "the root" is sometimes a list. With one root there is no wrapper at
  all, so no existing map gains a meaningless "repository" node or shifts
  every node's depth by one.
- **A candidate containing another is dropped.** Lua answering `lua/thing`
  while ECMA falls back to the repository root for a stray `.js` would walk
  `lua/thing` twice and duplicate every node in it. The narrower answer
  wins: that loses the stray file and keeps the map correct, where the
  alternative loses nothing and breaks the map.

`meta.source` stays a string (the shared root when there are several);
`meta.sources` lists them and is emitted *only* when there is more than one,
so a single-root map is byte-identical to the ones generated before this.
Verified on this repository: same source, same root, same counts, same node
set, no depth changes.

### Stage 2 — the host side (`docmap-desktop`), parallel

Depends on Stage 1's third item only, not on any new backend, and is the one
strand that pays off even if no further language is ever built. Tracked in
detail in `docmap-desktop/docs/ROADMAP.md`; the engine-side half of it is one
change:

- [ ] `--capabilities` grows `languages: [{ name, grammar_loaded }]`, read off
      the registry the same way `routes` is read off `core/api.routes` —
      advertised without `standalone/docmap.lua` being told. Backward
      compatible: a missing field means "older engine", the same distinction
      `docmap-desktop`'s `server.rs` already draws for `--api`.

### Stage 3 — shared seams (blocks Python, Rust, Go)

Part 2's open Phase-0 items, plus two seams Parts 1–3 identify the *need* for
without naming as work.

- [ ] **3.1** `language` per node; schema version bump; verify `diff.lua`'s
      tolerance path against a **real** old artifact from this repo's history,
      not a synthesised one.
- [ ] **3.2** Owning scope on `Documentation.FunctionInfo` — four customers
      (Python classes, Rust `impl`, Go receivers, JS class methods), one
      field.
- [ ] **3.3** One file, many modules. Do not implement before a real
      multi-module `.rs` exists as a fixture.
- [ ] **3.4** Visibility as a field.
- [ ] **3.5** **A doc-convention registry, separate from `lang_registry`.**
      The language seam exists; the documentation seam does not. LuaCATS,
      JSDoc and Doxygen are one family with one tag vocabulary; rustdoc and
      godoc are prose with none. Modelled as a second registry, three
      languages share one parser and two need none — instead of five
      implementations, or worse, invented `@param` recognition in prose that
      was never structured that way. **The decision about where this seam
      sits has to be made before Rust, not during it.**
- [ ] **3.6** **Check profiles.** Each check declares which doc convention it
      requires; a check with no applicable convention reports *not
      applicable* rather than passing. Without this, the first tagless
      language produces a wall of false findings on its first run, and the
      only available response is disabling the check globally. See
      [`I18N.md`](I18N.md) Part 5 — that plan rewrites the same `add()`
      function, and the two changes must land in one pass.
- [ ] **3.7** Real per-language sample trees in CI. Not optional; this is the
      only thing that would have caught `core/plugins.lua`'s 235 false
      positives.
- [ ] **3.8** Write the cross-backend layer rule (`core.lang.x` must not
      require `core.lang.y`) — possible as soon as a second prefix exists.
- **Acceptance:** Lua and the three ECMA grammars produce byte-identical maps
  to before, except for the fields deliberately added.

### Stage 4 — next backend: C, ahead of Python

Following Part 3's revised recommendation rather than Part 2's original
order. C needs none of 3.2/3.3, so like JS/TS it can land beside Stage 3
rather than behind it, proving the backend interface a second time on a
second grammar family before the riskier IR surgery is touched. Doxygen is
where LuaCATS's vocabulary descends from, so it is also the first real
customer of 3.5.

Open question Part 2 already flags and this stage must answer first: a `.h`
prototype and its `.c` body are two nodes for one function, and there is no
module system to key `Documentation.Node.module` on. Decide both before
writing the extractor.

### Stage 5 — Python

The first backend that actually exercises 3.2, and the hardest test of 3.5: a
docstring is a runtime string literal, not a comment block, and three styles
(reST/Google/NumPy) coexist. Style detection per file with
`opts.lang.python.docstring_style` as an override; report "unknown" rather
than guess. Decide whether decorators are metadata on `FunctionInfo` or a
check's concern **before** the extractor, not after. Analysis panel:
decorators, the same shape as the existing React-hooks panel.

- **Acceptance:** a real Python repository — not fixtures — produces a map
  whose doc coverage survives a manual spot check, with all three docstring
  styles each verified against real code.

### Stage 6 — Rust

3.3's real test (`mod x { … }`, declared by the parent), 3.2's second, and
3.5's first prose-convention customer: `missing-summary` applies, the
param-shaped checks report *not applicable*. Panel: `impl`/traits, `unsafe`
blocks.

- **Acceptance:** `docmap-desktop/src-tauri` maps itself correctly.

### Stage 7 — cross-language bridges

Only meaningful here: after Stage 6, `docmap-desktop` is the first codebase
whose halves are *both* mapped — and the seam between them the obvious
remaining blind spot. Both graphs stop at the process boundary today.

- [ ] A `bridge` edge kind in `ir.edges`, parallel to `require`/`call`/
      `type`/`extends`.
- [ ] First recognizer, Tauri: `#[tauri::command] fn name` ↔ `invoke("name")`.
      Name-based, therefore fallible — exact matches only, near-matches are
      never guessed. The same position `calls.lua` already takes on computed
      targets.
- [ ] Rendering: its own edge kind in Deps and Calls, toggleable.
- [ ] `bridge-orphan`: a command nothing invokes, an `invoke` with no
      counterpart. Real bugs that nothing in this ecosystem can currently see.
- **Acceptance:** every `#[tauri::command]` in `docmap-desktop`'s
  `src-tauri/src/main.rs` finds its caller in `src/main.js`, against a hand
  count.

**The honest risk, recorded before building:** this is the stage most likely
to invent meaning where there is only a matching string. If exact-match-only
turns out to under-report badly on a real codebase, the answer is to report
less, not to loosen the match.

### Stage 8 — Go, and C++ if ever

Unchanged from Part 2's Phase 4 and Part 3's table, with one precondition
added: **not before 3.6 exists.** Go replaces six checks with one, which is
survivable as a profile and indefensible as a wall of false findings. Ask
once more at that point whether a map with almost no drift checks is still
this product or just a diagram — Part 1's question, still unanswered because
it cannot be answered until 3.6 makes the trade visible.

### Ordering

```
Stage 1 (polyglot verification)
├─ Stage 2 (host capabilities)            <- independently useful, parallel
├─ Stage 4 (C)                            <- needs none of Stage 3's hard items
└─ Stage 3 (shared seams)
   └─ Stage 5 (Python)
      └─ Stage 6 (Rust)
         └─ Stage 7 (bridges)
            └─ Stage 8 (Go)
```

One language at a time still holds — Stage 4 running beside Stage 3 is not
two languages at once, it is one language beside infrastructure it does not
depend on, which is the same shape Phase 1 already proved.

### The other axis, for the record

`docs/ROADMAP/IDEAS/I18N.md` plans the languages this tool *speaks* — tab
labels, findings, health output, the desktop app's buttons. Independent of
everything above except 3.6, as its own Part 5 records.
