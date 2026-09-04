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
- [Owning scope](#owning-scope)
- [Running the language specs](#running-the-language-specs)
- [Adding a backend](#adding-a-backend)

---

## The seam

Every stage of [`pipeline.md`](pipeline.md) that touches a source file goes
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

**A caller can narrow the set.** `opts.languages` (or `--languages=lua,go`)
is an allow list over the names in the table below; `opts.exclude` (or
`--exclude=<path>`) drops paths. Both are scan-scoped rather than
registrations being removed, and `lang_registry.report()` deliberately
ignores them — the capability handshake answers for the *build*, not for one
project's preferences, and a host that saw a backend disappear from it would
conclude the binary cannot read that language. See
[`reuse.md § Narrowing what gets read`](reuse.md#narrowing-what-gets-read).

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
  parameters. The original decision text said eight and
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

## What documents a declaration, and what makes it public

The table above is what each backend *is*; this one is what each language
*means*. Both are needed: the first says which grammar and which comment
syntax, the second says what a reader of the map is actually looking at.

| Language | Extensions | What documents a declaration | What makes it public |
|---|---|---|---|
| **Lua** | `.lua` | LuaCATS `---` block, `@param`/`@return`/`@see` | anything without `@internal` |
| **JavaScript** | `.js`, `.jsx` | JSDoc `/** … */` | anything without `@internal`/`@private` |
| **TypeScript** | `.ts`, `.mts`, `.cts` | JSDoc | same |
| **TSX** | `.tsx` | JSDoc | same |
| **Python** | `.py`, `.pyi` | a docstring — the first *statement*, in reST, Google or NumPy style | not a leading `_`, unless `__all__` says otherwise |
| **C#** | `.cs` | XML doc comments — `/// <summary>`, `<param name="x">` | `public`; an unmarked class member is private, an unmarked interface member is public |
| **Go** | `.go` | the plain comment block above it — godoc has no tags at all | **capitalisation**, enforced by the compiler |
| **Rust** | `.rs` | `///` above the declaration; rustdoc has no tags either | `pub`; `pub(crate)` and `pub(super)` are restricted, not published |
| **PHP** | `.php` | PHPDoc `/** @param int $x … */` | not `private` and not `protected` — an unmarked method is **public** |
| **Ruby** | `.rb` | the comment block above it — RDoc prose, with YARD tags read where present | `private`/`protected`, which are **positional statements** rather than modifiers |
| **Kotlin** | `.kt`, `.kts` | KDoc `/** @param x … */`, plus `@property` | not `private`/`protected`/`internal` — an unmarked declaration is **public** |
| **Swift** | `.swift` | `///` Markdown, where a parameter is a **bullet**: `- Parameter x:` | `open`/`public`; an unmarked declaration is `internal`, meaning module-only |
| **Dart** | `.dart` | `///` Markdown prose; dartdoc has no per-parameter form | **a leading `_`**, which the compiler enforces rather than merely suggests |
| **Scala** | `.scala`, `.sc` | Scaladoc `/** @param x … */`, plus `@tparam` | not `private`/`protected` — there is no `public` keyword to ask for |
| **Haskell** | `.hs`, `.lhs` | Haddock `-- |` above the type signature | **the module's export list**, stated once in the header rather than per declaration |
| **Elixir** | `.ex`, `.exs` | `@doc` — a module attribute the compiler stores, not a comment | `def` vs `defp`; `@doc false` is public-but-undocumented |
| **Erlang** | `.erl`, `.hrl` | EDoc `%% @doc` above the spec or the function | `-export([f/2])` — an export list that names an **arity**, not just a name |
| **OCaml** | `.ml`, `.mli` | ocamldoc `(** @param x … *)`, usually *below* the declaration | the sibling **`.mli` file** — an export list that lives in another file |
| **Zig** | `.zig` | `///` above the declaration | `pub` |
| **Java** | `.java` | Javadoc, with `@param`/`@return`/`@throws`/`@deprecated` parsed | `public` |
| **C** | `.c`, `.h` | any comment directly above it, Doxygen or not | not `static` |
| **C++** | `.cc`, `.cpp`, `.cxx`, `.hpp`, `.hh`, `.hxx` | same | not `static`, and not under `private:`/`protected:` |
| **Assembly** | `.s`, `.asm`, `.nasm`, `.inc` | the comment above the label, or trailing it | `.globl` / `global` / `PUBLIC` |

**The fourth column is worth reading as a spectrum**, because it is the one
place these languages genuinely disagree rather than merely differing in
syntax. Go is at one end: visibility is capitalisation, the compiler enforces
it, and nobody can be wrong about it. Zig, Java, C#, C, C++ and assembly
state it in a keyword, so the backend reads a fact. Lua and the ECMA family have no such keyword
at the granularity this map needs, so they read an authoring convention —
`@internal` — which is a claim the author made rather than one the compiler
enforces. Both are honest; they are not the same strength of evidence, and
a reader comparing two projects should know which they are looking at.

C++'s access specifier is *positional* — everything after `private:` is
private until the next one, `class` starts private and `struct` starts
public — so it is tracked while walking rather than read off the member,
because there is nothing on the member node to read.

**What documents a *file*** differs the same way and is worth knowing,
because it is what fills the map's summaries: Lua's `---@module` block,
Zig's `//!`, a Javadoc block above `package`, a Doxygen-style header in C
and C++ (deliberately strict, so a license banner never becomes a file
summary), and in assembly the top comment block — with the same banner
filter, reached by content because assembly has no punctuation to reach it
by.

**Three shapes of documentation convention now exist here, and it is worth
knowing which one you are reading.** LuaCATS, JSDoc, Javadoc and Doxygen are
*tag* formats. Python's docstrings are *prose with sections*. C#'s XML doc
comments are *markup* — the only one that names a parameter by attribute
rather than by position, and the only one this tool parses with patterns
rather than a real parser, because a doc comment is a fragment and an XML
parser would reject most real ones as malformed.

**Python is the one language here whose documentation is not a comment.**
A docstring is a string literal the interpreter keeps, so it is found by
*position* — the first statement — rather than by adjacency, and a "TODO"
inside one is prose the author published rather than a marker. Its style
forks three ways (reST, Google, NumPy) and is detected per docstring, since
one repository routinely mixes them.

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

The same report also carries **`calls`** per backend — whether that backend
produces call sites at all. Five of the twenty-three do. It is there so a
host can say *why* a Calls panel is empty: "this project has no calls" and
"this build has no call extraction for this language" look identical on
screen and are not the same fact. Unlike `grammar_loaded` it is a plain
boolean, because there is no third state to keep apart, and
`backend_contract_spec.lua` fails any backend whose flag disagrees with what
it actually returned for its own parity fixture. The flag describes what is
built, not what is possible — it disappears as backends gain the capability.

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
| `zig` | ✓ | — | ✓ | — | — | ✓ | ✓ | — | ✓ | ✓ | — |
| `java` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ | — |
| `c` | ✓ | — | ✓ | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ | — |
| `cpp` | ✓ | — | ✓ | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ | — |
| `asm` | ✓ | — | ✓ | — | — | ✓ | ✓ | — | ✓ | ✓ | — |
| `python` | ✓ | — | ✓ | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ | — |
| `csharp` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ | — |
| `go` | ✓ | — | ✓ | — | — | ✓ | ✓ | ✓ | ✓ | ✓ | — |
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

- **Call edges: five backends of twenty-three**, and `go` is the fifth as of
  2026-08-20. The other eighteen return `{}` from `scan_file`'s second slot,
  so the Hierarchy tab's Calls and Module Calls views, `:DocMap why`, the
  call-hierarchy LSP integration and `dead-function`'s call-edge tier are
  still empty there. This remains the largest single gap in the tool; it was
  invisible from any one language and took a table across all of them to see.

  **What Go cost that Lua and the ECMA family did not**, and why the fifth
  backend is the pattern for the other eighteen rather than a copy of the
  first four: the call *extractor* was the easy half — the same query shape,
  the same two inputs. The resolver was not. **A Go package is a directory**,
  so an unqualified `double(n)` in `widget.go` may name a function declared in
  `helper.go` beside it, with nothing at the call site saying so — and since
  Go declares no `module_file`, those are two IR nodes. A file-scoped resolver
  therefore misses the *majority* of a Go call graph, not a margin of it:
  measured against `aws/smithy-go`, 883 call edges, **397 of them across files
  of one package**. That is what `LangBackend.call_scope = "package"` is, and
  it is a language guarantee rather than a heuristic, so those edges are
  `exact`. A name two files of one directory declare is dropped rather than
  guessed — real Go would not compile, so the case means the directory is not
  one scope (`widgets` beside `widgets_test`), and a confident wrong edge is
  exactly what `calls_heuristic` stays opt-in to avoid.

  **A qualified `other.Bump` still does not resolve**, and that is a stated
  limit rather than an oversight: a Go import path is absolute against the
  module graph, so placing it inside this tree needs `go.mod`'s module line —
  a build file, not a source one — or a suffix match, which is a guess.
  `parse_header` already takes that position for the require edge. The callee
  text is emitted regardless, so the day the module line is read, nothing in
  the backend changes.
- ~~**Symbols: the four oldest non-Lua backends.**~~ **Closed 2026-08-20.**
  `zig`, `java`, `c` and `cpp` returned no module-scope symbols; every
  backend written from Python onward did. Nothing had decided it — the
  capability arrived after those four and never went back — which is why it
  took a table across all of them to see. Each one needed the language's own
  answer to "what *is* a module-scope binding here", and no two were the
  same: a top-level `const`/`var` in Zig (minus the `@import` bindings, which
  are dependencies and already edges), a **field** in Java and C++ because
  neither has module scope at all and everything lives in a type, and in C a
  `#define` beside the file-scope declarations, because `#define` is the one
  idiom every C project uses for a threshold.

The first is tracked as open work, and is not dressed up as a language limit, because it is not one.

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

## Owning scope

`Documentation.FunctionInfo.owner` names the class, `impl` block, trait,
receiver type or inline module a function is declared in, and `owner_kind`
says which of those it is. Both are set at the record site, where the parse
tree still exists — the same place the qualified `name` is built, from the
same local.

**The kind is the construct as the language names it**, not a normalised
"type". Rust settled that: `Widget::new`, `Doer::go` and `inner::helper` are
written identically and are an inherent method, a trait method and an inline
module's function. `Documentation.ScopeKind` therefore has `impl`, `trait`
and `module` as separate values, plus `receiver` for Go — which has no
enclosing block at all, because the owner is written on each method.

Where the construct differs from a class only in what the compiler generates
around it, it is reported as `class`: a Java `record`, a Scala `case class`, a
Dart `mixin`, a Swift `actor`. The field answers "what groups these members",
and those group them exactly as a class does.

### Which backends set one

| Sets an owner | |
|---|---|
| `python` | `class` |
| `rust` | `impl`, `trait`, `module` (`mod x { … }`) |
| `js` / `ts` / `tsx` | `class` |
| `go` | `receiver`, `interface` |
| `java` | `class`, `interface`, `enum` — including constructors, whose `name` is deliberately *not* qualified |
| `csharp` | `class`, `interface`, `struct`, `enum` |
| `kotlin` | `class`, `interface`, `object`, `enum` — a companion object's members are the type's |
| `swift` | `class`, `struct`, `enum`, `protocol`, `extension` |
| `scala` | `class`, `trait`, `object` |
| `php` | `class`, `interface`, `trait`, `enum` |
| `ruby` | `class`, `module` — both nest, and both are reported as the nested path |
| `dart` | `class`, `enum`, `extension` |
| `elixir` | `module` — every function has one, and a `.ex` file routinely holds several `defmodule`s |
| `cpp` | `class`, `struct`, from the enclosing body only |

**C++ reads the body, never the name's own prefix.** An out-of-line
`void Thing::go() {}` and a namespace-qualified `void A::f() {}` are written
identically, and this backend cannot tell a type from a namespace at that
point — so the qualified `name` stays what it was and no owner is invented
for it. Every declaration in a header, which is where a C++ class's surface
actually is, sits inside the body and is owned.

### Which do not, and why

**Three are language facts.** `lua`, `asm` and `erlang` have no construct to
read: their functions live at file scope. Lua's dotted `function M.foo()` is
the module table — the node itself — and reporting `M` as an owner would
invent a scope in every Lua file in every tree. C reaches the same answer
through `cfamily.lua`, which sets an owner from a class or struct body that C
never has.

**Three are gaps, and are gaps rather than facts.** Each would need walk
plumbing the backend does not have today, and none could be verified against
a real parse when this landed:

- `haskell` — a `class` declaration's methods, and an `instance` body's.
- `ocaml` — `module X = struct … end`. The walk descends into the binding
  already; it carries no scope while it does.
- `zig` — `const S = struct { … }`, which is how Zig writes a namespace. The
  owner is the *binding's* name, not a node of the struct's own.

### What a scope is not

A node. A scope has no summary, no coverage, no edges and no id — a Rust
`mod x { … }` grouped this way is still read as part of its file. That is the
open half of `MULTILANG.md`'s Phase 0 ("one file, many modules"), unchanged.
What the owner closes is attribution: members are attributed to the thing that
owns them instead of lying beside their neighbours.

The grouping itself is derived, not stored — `documentation.core.scopes` for
Lua-side consumers, and the same grouping in JavaScript on the generated page.
`module_map.json` carries `owner`/`owner_kind` and nothing built from them.

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
6. Record what it cost and what it taught.

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

- The per-language record: what each cost, the contract answers it had to give,
  and the measurements that changed several designs. Also the languages that
  are *available* rather than scheduled, and the four decisions taken
  2026-08-20.
- [`framework_conventions.md`](framework_conventions.md) — the layer *above*
  this one. Plugin specs, route registrations and keymaps are ecosystem
  conventions, not language features, which is why `scan_file` returns them
  as separate tuple slots a backend may leave empty.
- [`annotation_tags.md`](annotation_tags.md) — the Lua/LuaCATS half:
  annotating your own plugin so this tool has something to read.
