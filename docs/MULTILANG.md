# Other languages

What it would take to map a JavaScript, Python, Rust, Go or C tree, and how
much of the current code survives. Companion to
[`PORTABILITY.md`](PORTABILITY.md), which costs out the *other* axis (running
without Neovim). Both are estimates, neither is scheduled.

Measured against the tree after the `core`/`editor` split: 14 063 lines
excluding `@types/`.

---

## The number, and why it flatters

| | Lines | |
|---|---:|---|
| **Language-specific** — `scan`, `functions`, `symbols`, `deps`, `calls`, `luals` | 2 165 | 15 % |
| **Language-blind** — everything else in `core/`, plus all of `editor/` | 11 898 | 85 % |

85 % reuse is the headline and it is real, but it is not the whole cost. Three
things it hides, in increasing order of how much they hurt.

### 1. The 15 % is not one implementation, it is one per language

`deps.lua` resolves Lua's `require("a.b")`. For the others that is
`import`/`require`/`from … import`/`use`/`#include`, each with its own
resolution rules — Node's `node_modules` walk and `package.json` `exports`,
Python's `sys.path` and relative `from ..pkg import x`, Rust's `mod` tree
where a module is declared by its *parent*, Go's import paths against
`go.mod`, C's include paths. Roughly a `deps.lua` each, and Rust's is
genuinely harder than Lua's because the file does not name itself.

Same for `functions.lua` (520 lines of treesitter query plus doc-block
parsing) and `symbols.lua`. Call one language ~1 200–1 800 lines of the 2 165,
since `scan.lua`'s filesystem walk and `luals.lua`'s optional enrichment do
not repeat.

### 2. Treesitter makes the parsing uniform and the *queries* not

Grammars exist for all of these, and the plugin's queries are already tiny —
five of them, and every one is a single line:

```
(function_call name: (_) @callee) @call
(identifier) @id
[(function_declaration) (function_definition)] @fn
(comment) @comment
```

That is the good news: the *machinery* around queries — `shape_of`,
complexity counting, the deferred-require classification — is written against
node types, not against Lua. Swapping `"lua"` for `"python"` and the node
names is a real but bounded edit, and `scan.lua`'s treesitter usage is
already parameterised by a language string in exactly one place per query.

The bad news is that node names are not a shared vocabulary. Python has no
`function_declaration`; it has `function_definition` and, separately,
decorators that change what a function *is*. Rust has `function_item` plus
`impl_item` blocks that own methods — a concept Lua's IR has no field for.
Go has methods with receivers. C has declarations separate from definitions,
which the IR models as one thing.

### 3. The real problem is the doc-comment vocabulary, not the syntax

This plugin's checks are not "is this parseable". They are **"do the docs and
the code still agree"**, and that only means something where the docs make
*checkable claims*. Of its fourteen checks, six read LuaCATS tags directly —
`missing-module-tag`, `module-path-mismatch`, `missing-summary`,
`undocumented-param`, `param-name-mismatch`, `dead-see-target`.

How well those port varies more than anything else in this document:

| | Doc convention | Ports? |
|---|---|---|
| **JavaScript / TypeScript** | JSDoc / TSDoc — `@param`, `@returns`, `@see`, `@deprecated` | **Nearly free.** Almost the same tag vocabulary; LuaCATS is JSDoc-shaped by descent. TypeScript's own types make `undocumented-param` partly redundant, which is a feature. |
| **Python** | Docstrings: reST, Google or NumPy style | **Two problems.** No universal format, so the parser is per-style with a detector. And a docstring is a *runtime string*, so the parse is structured text inside a node, not tags in comments. |
| **Rust** | rustdoc `///` — prose Markdown, no tag vocabulary | **The param checks do not exist.** Rustdoc has no `@param`. `missing-summary` ports; `param-name-mismatch` has nothing to compare against. Types are in the signature, which is where the information already was. |
| **Go** | godoc — a comment starting with the identifier's name, no tags at all | **Worst fit.** The only checkable claim godoc makes is "the comment begins with the name it documents", which is one check this plugin does not have, replacing six it does. |
| **C** | Doxygen `\param`/`@param`, when used at all | **Free where present**, absent where not. Doxygen's vocabulary is where LuaCATS's ultimately comes from. |

So it is not one feature. **JS/TS is a weekend's work over the existing
design; Go would need a different set of checks, not a translation of these.**

---

## What survives untouched

The 85 % is not a rounding-up. Everything downstream of the IR never learns
what language produced it:

- **All five renderers** — `html.lua` (3 347 lines), `markdown`, `mermaid`,
  `dot`, `badge`. They draw modules, edges and functions, and none of those
  words is Lua-specific.
- **The whole editor half** (4 838 lines) — `:DocBrowse`, `:DocMap`, the
  server, the watcher, health.
- **Every analysis tool** — `duplicates`, `churn`, `coverage`, `doccoverage`,
  `diff`, `history`. `duplicates` is worth singling out: it groups by
  treesitter node-type sequence, so it works on *any* grammar the moment the
  scanner produces shapes, with no per-language code at all.
- **Eight of the fourteen checks** — the require graph ones (`require-cycle`,
  `require-not-declared`, `layer-violation`), the README ones, and
  `dead-function`.

`config.lua`, `json.lua`, `cli.lua` and `find.lua` are agnostic already.

---

## What the IR would have to grow

The current `Documentation.Node` assumes a shape Lua happens to have: one
module per file or per directory, functions attached to modules, requires
between modules. Three things do not fit:

- **Classes as an owning scope.** Lua's IR has `types_detail` but functions
  hang off the *module*. Python methods belong to a class, Rust functions to
  an `impl`, Go methods to a receiver type. Either functions grow an owner
  field, or every method reads as a free function.
- **Visibility as a first-class fact.** `@internal` is a tag here; in Rust it
  is `pub`, in Go the capitalisation of the identifier, in TS `private`.
  `dead-function` would get much sharper — and much less heuristic — with a
  real one.
- **One file, many modules.** Rust's `mod x { … }` and JS's multiple named
  exports break the file-is-a-module assumption `scan.lua` is built on. This
  is the one that touches the walk, not just the parser.

None is huge on its own. Together they are the reason the honest estimate is
not "15 % of the work".

---

## The shape it would take, if it were built

`scan.lua`'s walk, the IR, the checks that read edges, and every consumer stay
where they are. What becomes pluggable is a **language backend**: given a
file, return its module identity, its functions with doc blocks, its
symbols, and its imports. Five functions, one implementation per language,
selected by extension.

That is also the honest test of whether the current split is real. The
`core`/`editor` boundary is enforced by a layer rule today; a
`core`/`core.lang.*` boundary would need the same treatment, or the Lua
assumptions leak straight back into the shared half.

---

## Recommendation

**Not now, and if ever, JS/TS first.** It is the closest fit by doc
convention, the largest audience, and the one where the existing checks keep
their meaning without redefinition — which makes it the honest test of
whether the backend abstraction works, rather than a rewrite wearing one.

Go is the one to *not* start with, however tempting the ecosystem: godoc gives
this design almost nothing to check, and a map with no drift checks is a
diagram, which is a different product.

**A JS/TS backend is only layer 1.** [`FRAMEWORK_CONVENTIONS.md`](FRAMEWORK_CONVENTIONS.md)
costs out the layer above it — recognizing one ecosystem's structural
convention within an already-supported language, the same thing
`core/plugins.lua` already does for Lua + lazy.nvim. Next.js-style
file-based routing and React hooks, for the web-ecosystem case; strictly
sequenced behind everything in this document.
