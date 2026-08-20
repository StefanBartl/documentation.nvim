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
