# Languages

**Twenty-three backends.** This is the reference the rest of `docs/` assumed
somebody already had: which languages this tool reads, what each one answers
about itself, what a missing grammar costs, and what adding the twenty-fourth
involves.

The README's [`## Languages`](../README.md#languages) section is the
narrative version — the shapes the languages fall into and what each one
taught. This file is the *inventory*: every field of the contract, every
backend's answer to it, taken from `core/lang_registry.lua` rather than from
memory.

## Table of content

- [The seam](#the-seam)
- [What each backend answers](#what-each-backend-answers)
- [The contract, field by field](#the-contract-field-by-field)
- [Grammars](#grammars)
- [What a missing grammar costs](#what-a-missing-grammar-costs)
- [Parity](#parity)
- [Running the language specs](#running-the-language-specs)
- [Adding a backend](#adding-a-backend)

---

## The seam

Every stage of [`PIPELINE.md`](PIPELINE.md) that touches a source file goes
through one lookup: `lang_registry.for_file(filename)`. The walk in
`core/scan.lua` asks "who scans this filename" and "what marks a directory as
owning a module here" instead of assuming there is one answer, and the
registry hands back a `Documentation.LangBackend`.

Two rules hold that seam in place, and both are enforced rather than
documented:

- **`documentation.core` may not reach into `documentation.core.lang.*`.**
  A layer rule in the map's own checks catches it. `lang_registry.lua` is
  named that rather than `lang.init` precisely so the one module allowed to
  name every backend sits structurally *beside* the boundary instead of
  behind an exception written into the rule.
- **`KNOWN_BACKENDS` in `lang_registry.lua` is the only list of backend
  module names anywhere.** A twenty-fourth language is one more line in it,
  and still nothing outside that file names it.

Backends are required lazily, on the first lookup, because each one requires
the registry back to self-register — the circular-require shape that
deferring avoids.

---

## What each backend answers

Taken from `lang_registry.report()` plus the backend tables themselves.
`—` means the field is absent, which for `module file` and `glossary` is a
real answer and not a gap.

| Backend | Grammar | Extensions | Module file | `module_tag` | `param_docs` | Line comment | Block comment | Glossary |
|---|---|---|---|---|---|---|---|---|
| `lua` | `lua` | `.lua` | `init.lua` | **true** | *(true)* | `--` | `--[[ ]]` | yes |
| `js` | `javascript` | `.js` `.jsx` | `index.js` | false | *(true)* | `//` | `/* */` | yes |
| `ts` | `typescript` | `.ts` | `index.ts` | false | *(true)* | `//` | `/* */` | yes |
| `tsx` | `tsx` | `.tsx` | `index.tsx` | false | *(true)* | `//` | `/* */` | yes |
| `zig` | `zig` | `.zig` | — | false | **false** | `//` | — | — |
| `java` | `java` | `.java` | — | false | *(true)* | `//` | `/* */` | — |
| `c` | `c` | `.c` `.h` | — | false | *(true)* | `//` | `/* */` | — |
| `cpp` | `cpp` | `.cpp` `.cc` `.cxx` `.c++` `.hpp` `.hh` `.hxx` | — | false | *(true)* | `//` | `/* */` | — |
| `asm` | **none** | `.s` `.asm` `.nasm` `.inc` | — | false | **false** | `;` `#` `//` `@` | `/* */` | — |
| `python` | `python` | `.py` `.pyi` | `__init__.py` | false | true | `#` | — | — |
| `csharp` | `c_sharp` | `.cs` | — | false | true | `//` | `/* */` | — |
| `go` | `go` | `.go` | — | false | **false** | `//` | `/* */` | — |
| `rust` | `rust` | `.rs` | `mod.rs` | false | **false** | `//` | `/* */` | — |
| `php` | `php` | `.php` | — | false | true | `//` `#` | `/* */` | — |
| `ruby` | `ruby` | `.rb` | — | false | **false** | `#` | `=begin =end` | — |
| `kotlin` | `kotlin` | `.kt` `.kts` | — | false | true | `//` | `/* */` | — |
| `swift` | `swift` | `.swift` | — | false | true | `//` | `/* */` | — |
| `dart` | `dart` | `.dart` | — | false | **false** | `//` | `/* */` | — |
| `scala` | `scala` | `.scala` `.sc` | — | false | true | `//` | `/* */` | — |
| `haskell` | `haskell` | `.hs` `.lhs` | — | false | **false** | `--` | `{- -}` | — |
| `elixir` | `elixir` | `.ex` `.exs` | — | false | **false** | `#` | — | — |
| `erlang` | `erlang` | `.erl` `.hrl` | — | false | **false** | `%` | — | — |
| `ocaml` | `ocaml` | `.ml` `.mli` | — | false | true | — | `(* *)` | — |

*(true)* is an absent `param_docs`, which the code treats as `true` — the
conservative default that preserved the behaviour of every backend written
before the field existed. It is shown in parentheses rather than folded into
`true` because "never stated an opinion" and "stated yes" are different facts
about a backend, and only the second has been thought about.

**Four counts worth having in one place**, because several documents state
them in prose and one of them states them wrong:

- **Twenty-three backends, twenty-two languages with a grammar.** Assembly
  needs none, by design — see below.
- **Nine declare `param_docs = false`**: `zig`, `asm`, `go`, `rust`, `ruby`,
  `dart`, `haskell`, `elixir`, `erlang`. The other **fourteen** judge
  parameters. `ROADMAP/IDEAS/MULTILANG.md`'s decision text says eight and
  fifteen: it called Ruby "a different case again" in the prose — parsed and
  shown, not judged — and then left it out of the total, which it belongs in,
  because the field is `false` and that is what every consumer reads. The
  numbers the tool *reports* were never wrong: `doccoverage`'s
  `judges_params` is derived from the field, not from the sentence.
- **Only `lua` sets `module_tag = true`.** Everywhere else the file path *is*
  the module identity, so `check.lua` never reports a missing `@module` for a
  language that has no such concept.
- **Six backends name a module file**, in four conventions: Lua's `init.lua`,
  the ECMA family's `index.{js,ts,tsx}`, Python's `__init__.py` and Rust's
  `mod.rs`. Everywhere else a directory is a namespace and every file is its
  own module.

---

## The contract, field by field

`Documentation.LangBackend` is declared in
[`lua/documentation/@types/init.lua`](../lua/documentation/@types/init.lua),
which carries the full rationale per field. What follows is the working
summary — what a backend must decide, and what happens when it decides wrong.

**Required.**

| Field | What it decides |
|---|---|
| `name` | The registered identifier, kept on the table too so the registry can re-register a cached backend by name without re-executing its module. |
| `is_source(filename)` | Whether this backend claims a bare filename. Registration order breaks a tie, so `for_file` stays deterministic and `--check` stays reproducible. |
| `detect_source(root)` | Where this language's sources live under `root`, or **`nil` when the backend sees no evidence of itself**. Asked in registration order, first non-`nil` answer wins. A backend that answers unconditionally makes every later one unreachable — the bug this field was added to fix, back when `detect_source` was a Lua-only heuristic returning `"lua"` for every tree, and a JavaScript repository died on `source directory not found`. |
| `parse_header(path)` | The file's own declaration: module path (however the language spells it), summary, body, tags. |
| `scan_file(path)` | The eight-value tuple — functions, calls, requires, symbols, plugins, endpoints, line count, bindings. Destructured positionally by every caller, which is why `bindings` was *appended* after `lines` rather than inserted beside its two ecosystem siblings. A backend with no equivalent convention returns `{}` there, never `nil`. |

**Optional, and each absence is a real answer.**

| Field | Absent means |
|---|---|
| `extensions` | "Would rather not say" — the page treats it as *no glossary* rather than guessing one. Redundant with `is_source` by construction and kept anyway, because a predicate cannot be enumerated. |
| `module_file` | No directory-owns-a-module convention; every source file is its own node. |
| `grammar` | **No parser needed** — not the same as a parser that is missing, and `lang_registry.report()` keeps the two apart. |
| `glossary` | Decorate nothing. Falling back to another language's keywords would explain `goto` in a file where it means something else. |
| `line_comments` / `block_comments` | This backend's files are **not scanned for marker comments at all** — the honest default, because `#` opens a comment in Python and a preprocessor directive in C, and guessing wrong attributes a `TODO:` to a line that has none. |
| `module_tag` | Treated as `true`, the pre-existing behaviour. |
| `param_docs` | Treated as `true`, same reason. `false` makes `doccoverage.params_documented` vacuously true and silences `undocumented-param` — a check that reports the absence of something the language cannot have produces a *wrong* number, not a low one. |
| `code_prelude` | This language's file is code from the first byte. **PHP is the only exception**: source outside `<?php` is inline HTML, so `// TODO: x` on its own contains no comment at all. Read by `backend_contract_spec.lua`, which builds the smallest file that could hold a marker; real callers pass whole files and never need it. |

`TESTS/backend_contract_spec.lua` fails a backend that omits any of the
required half, and it verifies the comment tokens the only way that proves
anything — by **finding a marker** in a probe file built from `code_prelude`
plus the declared token, rather than by asserting the field is non-empty.

---

## Grammars

Inside Neovim, grammars come from the runtimepath and nothing needs
configuring. Outside it — the standalone build — `standalone/treesitter.lua`
resolves each one at the moment it is first needed, in this order:

1. `$DOCMAP_TS_<LANG>` — an explicit path to that one grammar, `LANG`
   uppercased.
2. `$DOCMAP_TS_DIR/<lang>.{dll,so,dylib}`.

Both are per-grammar rather than all-or-nothing: a `DOCMAP_TS_DIR` holding
only `lua.so` gives full fidelity for Lua and a degraded-but-honest result
for everything else. `DOCMAP_TS_DEBUG=1` prints why a resolution failed,
which used to be silent.

`grammar` is a separate field from `name` because the two genuinely differ —
`js` parses with `javascript`, `csharp` with `c_sharp`.

`scripts/build_engine_release.sh` builds **twenty-three grammar files for
twenty-two languages**: OCaml needs two, because `.ml` and `.mli` are
different languages to the parser.

**Assembly is the one backend with no grammar, by design.** GAS, NASM and the
ARM/MASM families are a fork rather than dialects, and a grammar is written
against exactly one side of it — a NASM file read by an x86-GAS grammar is
not a degraded parse, it is a confident wrong one. Everything that backend
needs is line-directed in all of those syntaxes, because assembly is
line-oriented by construction.

---

## What a missing grammar costs

`lang_registry.report()` is the capability handshake a host asks for before
trusting a build, and it reports **three** states rather than two:

| `grammar_loaded` | Meaning |
|---|---|
| `true` | Grammar resolved. Full fidelity. |
| `false` | This backend wants a grammar and could not get one. A complete module tree — hierarchy, summaries, require edges — and **no function-level data**. |
| `nil` | This backend needs no parser. Full fidelity, not a degradation. |

A host that collapsed `false` and `nil` would report a healthy backend as
broken, which is why they stay distinct all the way out to the report.

The probe is deliberately **not cached**: it is asked once per handshake, and
a cached "missing" would survive the user pointing at their grammars
directory — precisely the moment the answer is supposed to change.

---

## Parity

The rule the parity pass audits: **a capability Lua has, every language has —
in its own terms, not by pretending each language is Lua.** One row per
language, one column per capability, and a blank cell is only acceptable with
a sentence beside it naming what makes it blank.

**Every cell below was measured, not judged.** `scripts/parity.lua` runs each
backend over a real file of its own language in
[`TESTS/fixtures/parity/`](../TESTS/fixtures/parity) and reports what came
back. Regenerate it with:

```bash
DOCMAP_TS_DIR=C:/tools/docmap-grammars nvim --headless -u NONE -l scripts/parity.lua --markdown
```

| Language | File summary | Module identity | Declaration summary | Parameters | Returns | Visibility | Require edges | Call edges | Symbols | Markers | Glossary |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| `lua` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `js` | ✓ | — | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `ts` | ✓ | — | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `tsx` | ✓ | — | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `zig` | ✓ | — | ✓ | — | — | ✓ | ✓ | — | — | ✓ | — |
| `java` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | — | — | ✓ | — |
| `c` | ✓ | — | ✓ | ✓ | ✓ | ✓ | ✓ | — | — | ✓ | — |
| `cpp` | ✓ | — | ✓ | ✓ | ✓ | ✓ | ✓ | — | — | ✓ | — |
| `asm` | ✓ | — | ✓ | — | — | ✓ | ✓ | — | ✓ | ✓ | — |
| `python` | ✓ | — | ✓ | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ | — |
| `csharp` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ | — |
| `go` | ✓ | — | ✓ | — | — | ✓ | ✓ | — | ✓ | ✓ | — |
| `rust` | ✓ | ✓ | ✓ | — | — | ✓ | ✓ | — | ✓ | ✓ | — |
| `php` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ | — |
| `ruby` | ✓ | — | ✓ | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ | — |
| `kotlin` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ | — |
| `swift` | ✓ | — | ✓ | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ | — |
| `dart` | ✓ | — | ✓ | — | — | ✓ | ✓ | — | ✓ | ✓ | — |
| `scala` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ | — |
| `haskell` | ✓ | ✓ | ✓ | — | — | ✓ | ✓ | — | ✓ | ✓ | — |
| `elixir` | ✓ | ✓ | ✓ | — | — | ✓ | ✓ | — | ✓ | ✓ | — |
| `erlang` | ✓ | ✓ | ✓ | — | — | ✓ | ✓ | — | ✓ | ✓ | — |
| `ocaml` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ | — |

**Four columns are complete across all twenty-three**: file summary,
declaration summary, visibility and require edges. Markers are complete too,
after this pass fixed three languages where they were not — see below.

### Why each blank is blank

**Module identity — twelve blanks, every one a language fact.** The cell means
*the file states its own module name*; the blank means **the path is the
identity**, which is how those languages resolve imports in the first place.
JavaScript, TypeScript and TSX resolve ESM by path; Zig's `@import` is a path;
C and C++ `#include` a path; Python's import path is the file path; Ruby's
`require` names a path; Swift has no module name in a file at all (the module
is the build target); Dart's `library` directive exists and is close to
extinct in practice. Assembly has no module construct to state.

**Go is the one where the name genuinely exists and still cannot be used.** A
Go package is a *directory* — every `.go` file in it declares the same
`package foo` — so taking that as the module name would have three files
claiming one identity. It arrives at the same answer as Zig, C and assembly by
a completely different route.

Of the eleven fills, ten read a declaration (`---@module`, `package`,
`namespace`, `defmodule`, `-module`, a Haskell module header, an OCaml file
stem). **Rust is the eleventh and reads the filesystem**: a module path is
derived from the file's position under `src/`, which is why its fixture lives
in `TESTS/fixtures/parity/src/` — put anywhere else it measures "no identity"
and reports a fixture fact as a language fact.

**Parameters and returns — eight blanks, every one a language fact**, and they
are `param_docs = false` languages: Zig documents a declaration as a whole,
assembly's label has no parameter list, godoc has no tag vocabulary at all,
rustdoc's `# Arguments` is a Markdown heading rather than a form, dartdoc's
`[n]` is a cross-reference rather than a slot, a Haskell type signature has no
parameter names in it to match against, ExDoc describes arguments in prose,
and Erlang's `-spec` names types rather than parameters.

**Two things this column does not mean.** First, **the signature always
carries the parameters** — `fn.signature` is `widen(n int)` for Go the same as
for Lua, and the map shows it. What is missing is per-parameter *prose*.
Second, **Ruby has ✓ here and `param_docs = false`**, which looks like a
contradiction and is the most useful cell in the table: YARD's
`@param [Integer] x` is real, common and worth showing, so it is extracted and
displayed — but YARD is a gem and RDoc ships with the language with no
per-parameter form, so Ruby is *not judged* by it. That is why nine backends
declare `param_docs = false` while only eight have this cell blank.

**Glossary — nineteen blanks, a decision rather than a gap.** A backend
without one decorates nothing, which is the honest degradation; falling back
to another language's keywords would explain `goto` in a file where it means
something else. Adding one is per-language work with a maintenance cost, and
the two that exist were written because somebody hovers those words.

### The two blanks with no language behind them

These are the failure the parity pass was looking for, and it found them.
**Nothing in any of these languages makes either capability impossible.**
They are simply not built, they had no sentence anywhere before this pass, and
saying so is the point:

- **Call edges: four backends of twenty-three.** `lua`, `js`, `ts` and `tsx`
  return call sites; the other nineteen return `{}` from `scan_file`'s second
  slot. So the Hierarchy tab's Calls and Module Calls views, `:DocMap why`,
  the call-hierarchy LSP integration and `dead-function`'s call-edge tier all
  work in Lua and the ECMA family and are empty everywhere else. This is the
  largest single gap in the tool, it is invisible from any one language, and
  it took a table across all of them to see.
- **Symbols: the four oldest non-Lua backends.** `zig`, `java`, `c` and `cpp`
  return no module-scope symbols. Every backend written from Python onward
  does. Nothing decided this — the capability arrived after those four and
  never went back.

Both are now tracked in
[`ROADMAP/ROADMAP.md`](ROADMAP/ROADMAP.md). Neither is dressed up as a
language limit, because it is not one.

### What the audit fixed on the way

Building the matrix found four defects, all of the same shape: **a capability
that reported nothing rather than reporting a problem.**

- **Markers were invisible in Haskell, Kotlin and Dart doc comments.**
  `markers.lua` recognises comment nodes by name, and its list held `comment`,
  `line_comment` and `block_comment`. Haskell's grammar emits `haddock` for a
  `-- |` block — swallowing the plain `--` lines that follow it, so a marker
  on the second line of a documented declaration was gone. Kotlin emits
  `multiline_comment` for every `/* */` and every KDoc block, which the
  backend *declares* in `block_comments` and nothing ever read. Dart emits
  `documentation_comment` for `///`, which is where Dart writes almost
  everything. All three are the **doc** comment of their language — exactly
  where a `TODO:` about a declaration goes.

  It failed quietly in the way that module's own header already warns about:
  the parser answered, so the text fallback never ran, so the file simply had
  no markers. And `haskell.lua` already knew about `haddock` nodes and
  reassembles runs by row — **one module learned the fact and the other did
  not**, which is the more useful half of this finding.

  `backend_contract_spec.lua` could not have caught it. It proves a comment
  token works by building the smallest file that could hold a marker, and the
  smallest file always lands in a plain `comment` node. Finding this needed a
  file with a *documented declaration* in it, which is what a parity fixture
  is.

- **A block comment's closer was part of the note.** `/* TODO: cap it */` was
  reported as the text `cap it */` and rendered that way into the Notes tab.
  Only the parser path: the text fallback slices a line at the closer before
  the matcher ever sees it, so one path was right and the other was not.

Both are regression-tested in `TESTS/markers_spec.lua`.

- **OCaml's visibility needs two grammars, and one of them fails silently.**
  Not a code defect — a trap worth knowing. Visibility lives in the sibling
  `.mli`, which is a different language to the parser. A host holding
  `ocaml.dll` and not `ocaml_interface.dll` parses the `.ml` perfectly, cannot
  read the interface, concludes there is no `.mli`, and reports **every
  declaration as public**. Not an error and not a degraded parse: a confident
  wrong answer about the one question that file exists to settle. The audit's
  own first run hit it.

---

## Running the language specs

Every backend spec **skips** when its grammar is absent, which is the normal
local state and not a failure. To run one for real, point at a built grammar
through that backend's own variable:

```bash
DOCMAP_PYTHON_PARSER=/path/to/python.so nvim --headless -u NONE -l TESTS/run.lua
```

One variable per backend, named `DOCMAP_<LANG>_PARSER`:
`DOCMAP_C_PARSER`, `DOCMAP_CPP_PARSER`, `DOCMAP_CSHARP_PARSER`,
`DOCMAP_DART_PARSER`, `DOCMAP_ELIXIR_PARSER`, `DOCMAP_ERLANG_PARSER`,
`DOCMAP_GO_PARSER`, `DOCMAP_HASKELL_PARSER`, `DOCMAP_JAVA_PARSER`,
`DOCMAP_KOTLIN_PARSER`, `DOCMAP_OCAML_PARSER`,
`DOCMAP_OCAML_INTERFACE_PARSER`, `DOCMAP_PHP_PARSER`, `DOCMAP_PYTHON_PARSER`,
`DOCMAP_RUBY_PARSER`, `DOCMAP_RUST_PARSER`, `DOCMAP_SCALA_PARSER`,
`DOCMAP_SWIFT_PARSER`, `DOCMAP_ZIG_PARSER`.

OCaml has two because `.ml` and `.mli` are two grammars. Lua, JavaScript,
TypeScript and TSX have none in that list — Neovim ships those grammars, so
their specs run unconditionally.

See [`DEVELOPMENT.md`](DEVELOPMENT.md) for the rest of the local loop.

---

## Adding a backend

1. Write `lua/documentation/core/lang/<name>.lua`, registering itself with
   `lang_registry.register` at the bottom of the file.
2. Add one line to `KNOWN_BACKENDS` in `core/lang_registry.lua`.
3. Add the grammar to `scripts/build_engine_release.sh`.
4. Write `TESTS/<name>_spec.lua`, gated on `DOCMAP_<LANG>_PARSER`.
5. Add a row to this file's table and to the README's language table.
6. Record what it cost and what it taught in
   [`ROADMAP/IDEAS/MULTILANG.md`](ROADMAP/IDEAS/MULTILANG.md).

**Measured cost**, so the estimate is not a guess: roughly 230–430 lines of
backend, 120–200 of spec, one grammar, and about half a day — most of it
spent deciding the contract answers rather than writing extraction.

**And the step that is not optional: run it against somebody else's
repository.** Fourteen backends were added in one run and every single
measurement against real code changed something. Go's test functions inflated
the public API two and a half times. Rust's workspace crates resolved one
member's import to another member's file. C#'s `#if` blocks hid ten
functions. Python's typed splats vanished from every annotated signature.
OCaml documents *below* its declarations, and the first version found 0 of
50. Fixtures caught none of those. **A backend that has not been run against
code you did not write is not finished.**

---

## Where the rest lives

- [`ROADMAP/IDEAS/MULTILANG.md`](ROADMAP/IDEAS/MULTILANG.md) — the
  per-language record: what each cost, the contract answers it had to give,
  and the measurements that changed several designs. Also the languages that
  are *available* rather than scheduled, and the four decisions taken
  2026-08-20.
- [`FRAMEWORK_CONVENTIONS.md`](FRAMEWORK_CONVENTIONS.md) — the layer *above*
  this one. Plugin specs, route registrations and keymaps are ecosystem
  conventions, not language features, which is why `scan_file` returns them
  as separate tuple slots a backend may leave empty.
- [`ANNOTATION_TAGS.md`](ANNOTATION_TAGS.md) — the Lua/LuaCATS half:
  annotating your own plugin so this tool has something to read.
