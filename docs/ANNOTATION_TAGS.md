# Annotation tags: what documentation.nvim reads, and why

A field guide for **annotating your own plugin** so `documentation.nvim` has
something to work with. For each tag: which part of the pipeline consumes it,
what you get in return, and what happens if you leave it out.

The companion document [`ANNOTATIONS.md`](ANNOTATIONS.md) is the *inventory* —
which tags a particular tree happens to use, counted. This one is the
*contract* — what the tool does with each tag. Read this before annotating,
that one when auditing.

Everything below was verified against the source at the time of writing;
[`core/functions.lua`](../lua/documentation/core/functions.lua) `parse_doc_block`
and [`core/scan.lua`](../lua/documentation/core/scan.lua) `parse_header` are the
two functions that decide what is understood.

---

## The one tag that is not optional

### `@module` — the file's identity

```lua
---@module 'myplugin.core.parser'
--- Turns source text into an AST.
```

Read by `scan.parse_header`. Everything else in the pipeline keys off it:

| Consumer | What it does with it |
|---|---|
| Node identity | `node.module` — the name shown everywhere instead of a path |
| `missing-module-tag` check | **error** severity when absent |
| `require`/call graph | Edge endpoints are resolved to module paths |
| `:DocMap graph\|why\|dot <module>` | The name you type to address a module |
| `:DocBrowse <module>` | Same |
| `@see` resolution | Targets resolve against `module` and `module.function` |
| `layer-violation` | Rules are **prefix matches on `@module`**, not on paths |

Without it a file is still scanned, but it is a path in a tree rather than a
module in a graph, and `--check` fails. The quoted form matters — the parser
requires `'…'` or `"…"`.

**The line immediately after it is the module summary.** `parse_header` takes
the first sentence of the prose block following `@module` as `node.summary`
(what the Tree tab, the Markdown overview and the box in the graph all show),
and the rest as `node.body`. So the first sentence is a headline, not a
throat-clearing "This module…".

---

## Function-level tags

All parsed by `functions.lua` from the doc block directly above a top-level
function. A function with **no** doc block at all is not collected — it does
not appear in the map's Functions list, in the call graph's function view, or
in any coverage number.

### `@param` — the only tag with a structural check behind it

```lua
---@param path string Absolute path.
---@param opts MyPlugin.Opts? Optional.
```

Three checks read it, and they are the only checks in the tool that compare a
claim against the *code* rather than against another claim:

- **`undocumented-param`** (info) — fewer `@param` lines than declared
  parameters. Skipped for `@internal` functions.
- **`param-name-mismatch`** (info) — an `@param` name that does not match the
  parameter at that position. Colon-method `self` is exempt, because Lua's
  sugar means it never appears in the signature text.

Both are **info**, not warn, and that is deliberate: they describe
documentation that is incomplete rather than a tree that is broken, so they do
not fail `--check`. `missing-summary` (warn) is a **module**-level check, not a
function-level one — it fires when a node has no prose under its `@module`.

It also **defines documentation coverage**: `doccoverage.is_documented` counts
a function as documented when it has a non-empty summary *and* its parameters
are fully and correctly named — the function's own prose, not its module's.
That number is the Analysis tab's Documentation panel, the `coverage.svg`
badge, and the figure `:DocMap` prints.

`@return` is deliberately **not** part of that definition. A signature carries
no count of return values, so there is nothing structural to check against —
only "did the author write a line", which is not worth a coverage number
pretending to be precise.

### `@return` — rendered, not checked

```lua
---@return string content
---@return string? err
```

Shown in the detail pane and the Index tab. No check, for the reason above.

### `@internal` — the public/private boundary

```lua
---@internal
---Rebuilds the cache. Not part of the published surface.
local function rebuild(state) end
```

Four consumers, which is more than any other optional tag:

1. `undocumented-param` skips it — an internal function's documentation bar is
   the author's own.
2. `doccoverage` excludes it — so the coverage number describes the *published*
   API rather than every helper.
3. `diff.lua` counts it among helpers instead of listing it as an API change.
4. **`dead-function` checks it unconditionally.** An ordinary exported function
   only gets that scrutiny under `opts.dead_code`, because a library consists of
   functions with no internal caller by design. An `@internal` function with no
   caller is unambiguously dead.

Without it, "is this public?" is guessed from the name shape — `M.compare`
looks public, `node_set` looks private. That guess is decent and it is still a
guess. This is the highest-leverage optional tag in the set.

### `@deprecated` — the migration hint

```lua
---@deprecated use `parse_file` instead
```

Renders as a badge in the detail pane, a tag in the Index, an explicit warning
block, and its own **Notes-tab list** — the whole set of deprecations in the
tree on one page, which is the view that makes a deprecation campaign
finishable. The text after the tag is treated as the migration hint, so write
one.

### `@see` — cross-references, with a check

```lua
---@see myplugin.core.lexer
---@see M.parse_file, myplugin.util.trim
```

Comma-separated targets, repeatable. Rendered as **clickable links** when the
target resolves, and the `dead-see-target` check (**warn**) flags it when it
does not — the same treatment README links get from `dead-readme-link`.

A target resolves against a node's `@module` path, a qualified
`module.bare_name`, or a function's raw declared name as written (`M.parse`).
This is the closest thing the tool has to Doxygen's cross-referencing, and it
is the tag most worth adopting after `@internal`.

### `@todo` / `@bug` / `@test` — the Notes tab

```lua
---@todo make this async
---@todo and handle cancellation
---@bug leaks a handle when the path is missing
---@test covered by parser_spec.lua
```

**Repeatable** — one list entry per occurrence, so two todos stay two todos.
Each collects into its own Notes-tab list, sorted by location then line, the
way Doxygen's `\todo`, `\bug` and `\test` feed its Todo/Bug/Test lists.

Deliberately **not** findings: none of these is drift or an error, and routing
an author's own to-do list into an exit code CI fails on would be wrong.

Single-line each. A continuation line is dropped.

### `@example` — the only multi-line tag

````lua
---@example
--- local p = require("myplugin.parser")
--- local ast = p.parse_file("init.lua")
````

Everything until the next tag is captured, and rendered as its own fenced block
instead of being flattened into prose.

### `@since` — project history, not runtime

```lua
---@since 0.4.0
```

Renders as a badge. Deliberately **not** `@version`: LuaLS's `@version`
declares which *Lua runtime* a symbol needs (5.1 / 5.3 / JIT), a different
question from "since when has this existed in this project". Keeping them
separate avoids collapsing two meanings into one tag.

### `@raises` — an author-facing convention, not evaluated here

```lua
---@raises string When `opts.root` is missing, or `opts.source` names a
---directory that does not exist.
```

Not a LuaCATS standard tag, and — unlike every other tag on this page —
**not parsed, not rendered, not checked by `documentation.nvim` at all**
(confirmed: zero references across `core/functions.lua`, `core/scan.lua`,
`core/check.lua`, `core/render/*.lua`). It exists in this tree purely as
informal prose documenting what a function can `error()`, following the
same convention `@error` would if it were used instead. Worth writing when
a function's failure modes aren't obvious from its `@return`, but adopt it
case by case — same "not a mandate" posture this whole document opens
with — not as a tag `docmap` will ever badge or check for you.

### `@async` / `@nodiscard` — badges

Parsed as booleans, rendered as badges. No check behind either.

### `@generic` — collected, shown in signatures

```lua
---@generic T
---@param items T[]
---@return T?
```

Names are collected and travel with the function's signature.

### `@overload` — alternative call shapes, structurally parsed

```lua
---@overload fun(): nil
---@overload fun(cache: table<string, string>): boolean, string
---@param path string
---@param opts table?
---@return boolean
function M.read(path, opts) end
```

Lua has no real function overloading — one function, one body. `@overload`
documents that the function below it can *also* be called some other way
(commonly because it type-switches internally), not that a second
implementation exists somewhere to jump to.

The value is a LuaCATS `fun(...)` type literal, parsed into the same
`{ name, type, optional }` param shape and `{ type, name }` return shape the
primary signature uses — reusing that shape is what lets an overload render
through the exact same list markup as the function it belongs to, rather than
a second visual language for one tag. Repeatable: each `@overload` line
becomes one entry.

Renders two ways:
- a **badge** on the function row (`+N signatures`), visible before you open
  it — the point of parsing structurally instead of leaving it as opaque text
  is answering "does this have call variants" at a glance;
- an **"Also callable as" block** in the detail pane, one compact signature
  line plus its own param/return list per overload, indented under the
  primary one.

A parameter with no `name:` prefix (`fun(string)`, LuaCATS' anonymous
positional form) renders by its type rather than a placeholder name. A value
that is not `fun(...)` at all — someone typed something else, or a typo —
keeps its raw text and renders it verbatim rather than an empty, misleading
`M.foo()`; nothing errors over one unparseable annotation line.

**Not yet done:** `undocumented-param` (`@param` — the only tag with a
structural check behind it, above) still compares the raw signature's
parameter count against `@param` lines only. A function documented entirely
through `@overload` — no `@param` at all, its real parameter list living
inside the `fun(...)` literals — still fires a false `undocumented-param`.
Wiring that check to also credit an overload's parsed params is a small,
separate piece of work; parsing `@overload` was the precondition for it, not
the fix itself.

---

## Type-level tags — the LuaLS half

`@class`, `@alias`, `@field` and `@enum` are **not** parsed by this plugin's
own scanner. They are read by `lua-language-server --doc`, which
`documentation.nvim` runs **only under `:DocMap full`** (or `opts.luals =
true`) because a full-tree run costs real seconds.

What you get when it runs — see [`core/luals.lua`](../lua/documentation/core/luals.lua):

| Tag | Effect |
|---|---|
| `@class Name` | A type node in the **Types** view, attached to the file that declares it |
| `@class Child : Parent` | An `extends` edge — the **Inheritance** view is built entirely from these |
| `@field name type desc` | Field rows under the type, with the raw LuaCATS type text preserved |
| `@alias Name "a"\|"b"` | Same as a class, `kind = "alias"`; never carries `extends`, even when it aliases a class |
| Any type reference | A `"type"` edge — the collaboration graph in the Types view |

**Put them in a `@types/` directory.** A `@types/` folder is treated as an
*attribute of its module*, not a sibling node — types belong to the thing they
type, and promoting them would double the tree for no navigational gain. The
directory name is `opts.types_dir` (default `@types`).

Mark those files `---@meta`. `parse_header` recognises it, and it tells LuaLS
the file is pure declaration.

**If you never run `:DocMap full`**, the Types and Inheritance views say so
explicitly rather than rendering blank — but they render nothing. Annotating
types is only worth it if you intend to use those views.

---

## Module-header tags

| Tag | Status |
|---|---|
| `@module` | Required. See above. |
| `@meta` | Recognised; marks a declaration-only file. |
| `@brief`, `@description` | **Fallback only.** Used as the module summary *if* there is no prose after `@module`. Prefer plain prose. |
| Everything else | Collected into a `tags` table and **currently discarded** — see the gaps below. |

---

## Minimum viable annotation

If you are adopting this on an existing plugin and want the fastest path to a
useful map:

1. **`@module` on every file.** Without it, nothing else works and `--check`
   fails. This is the whole of the mandatory work.
2. **A summary sentence** under each `@module`. Turns a tree of names into a
   tree you can read.
3. **`@param` on your public functions.** Unlocks the three structural checks
   and the coverage number — the only place the tool can catch documentation
   that has gone *wrong* rather than merely missing.
4. **`@internal` on your helpers.** Makes the coverage number and
   `dead-function` describe your API rather than your implementation.

Then, when the case comes up: `@see` for cross-references, `@deprecated` when
you deprecate, `@todo`/`@bug` when you want them tracked somewhere you will
actually see them.

Everything else is optional and stays optional.

---

## Gaps: tags parsed but not surfaced

Read by the scanner and then goes nowhere. `@overload` used to be listed here
too — it moved up to [Function-level tags](#overload--alternative-call-shapes-structurally-parsed)
once parsing it structurally and rendering it stopped being a gap, though one
piece of the value it was meant to unlock (`undocumented-param` awareness of
overload-only signatures) is still open, and is noted there rather than here
so it stays next to the tag it depends on.

### Header tags collected and discarded

`parse_header` builds a `tags` table from every `@tag value` line in a module
header. Nothing reads it. `@brief`/`@description` are handled separately and
inline; every other header tag is parsed and dropped.

**Worth doing** as a precondition rather than for itself: a module-level
`@deprecated`, `@since` or `@see` currently has no effect, and the plumbing to
change that is already three-quarters built.

---

## Tags with real value that are not implemented

Ordered by what they would buy, not by how easy they are.

### `@module-see` / module-level `@see` — cross-references between modules

The function-level `@see` works and is checked. The module level has nothing —
you cannot say "this module supersedes that one" or "read this alongside that"
in a way the map understands, even though the header tags are already parsed
into a table that is thrown away.

**Why it is justified:** the require graph shows what a module *uses*, which is
not the same as what a reader should read next. A parser and its error-message
formatter may have no require edge between them and still be the two files you
always open together. That relationship exists in every codebase and there is
currently no way to state it.

Cheapest correct version: reuse the existing `@see` tag at header level, resolve
it with the same resolver, and run the same `dead-see-target` check over it.

### `@stability` — a promise, not a state

```lua
---@stability experimental
---@stability stable
---@stability internal
```

`@internal` is binary: published or not. Real plugins have a middle — an API
that exists, is documented, and may change.

**Why it is justified:** `diff.lua` already computes what changed about the API
surface between two revisions. It cannot currently distinguish "a stable
function's signature changed" (a breaking change worth a major version) from
"an experimental one changed" (expected). That is a distinction the tool has
all the data for and no vocabulary to express. A `@stability` value would let
`diff` grade its own output, which is the difference between a list of changes
and a release note.

Also renderable as a badge and filterable in the Index, both nearly free once
the tag is parsed.

### `@complexity` — a declared budget

```lua
---@complexity O(n log n)
```

The tool already computes **cyclomatic** complexity from the parse tree and
ranks by it. It knows nothing about *algorithmic* complexity, which is the one
readers actually care about at a call site.

**Why it is justified:** it is unverifiable by construction — which is exactly
why it is a documentation tag rather than an analysis. The value is the same as
`@param`'s: it puts a claim next to the code where a reader can see both. The
narrow version worth building is not the check but the *ranking*: a Notes-style
list of every function that declares a superlinear cost, which is a review
checklist nobody currently has a way to produce.

### `@invariant` — what must stay true

```lua
---@invariant `state.pins` is sorted by insertion order
---@invariant every id in `windows` is a live window handle
```

**Why it is justified:** this is the class of knowledge that is most expensive
to lose and least likely to be written down, because it does not fit `@param`
or `@return` — it is about the *relationship between calls*, not about one
call. Doxygen has `\invariant` for precisely this reason.

Implementation is trivial (repeatable, one line each, collect like `@todo`), and
the payoff is a Notes-tab list that reads as the contract of a module. The risk
is equally clear and should be stated: an invariant nothing enforces is a
comment that rots. It earns its place only if the project treats the list as
something to review, not as decoration.

### `@enum` for real runtime tables

Currently every "one of these values" is spelled `@alias Foo "a"|"b"|"c"`,
which describes the *shape of the strings*. When the values live in an actual
table (`M.LEVELS = { DEBUG = 1, INFO = 2 }`), `@enum` tells LuaLS the table
itself is the enum.

**Why it is justified, narrowly:** it is more accurate for that specific case,
and LuaLS understands it already, so the only work is on this plugin's side.
Not a blanket replacement for `@alias` — a case-by-case call.

### `@package` / `@private` / `@protected`

LuaLS's own visibility tags. `@internal` covers the same ground for this tool's
purposes and is the established convention here.

**Assessment: not worth adopting** unless a tree already uses them for LuaLS's
sake, in which case teaching `functions.lua` to treat them as `@internal`
aliases is a three-line change. Recommended only in that situation.

---

## What is deliberately not recommended

- **`@operator`** — metatable operator overloading. No effect on any view here.
- **`@source`** — the map already computes source links from `repo_url` +
  `branch`.
- **`@version`** — declares a *Lua runtime* requirement. Use `@since` for
  project history; see above for why they are not the same tag.
- **`@vararg`** — deprecated upstream in favour of `...`.
- **`@cast` / `@diagnostic` / `@type`** — real and useful, but they address
  LuaLS's type checker rather than this tool. Use them as needed; they are
  invisible here.

---

## A note on custom tags and your LSP

`lua-language-server` **ignores** annotations it does not know rather than
diagnosing them — verified with `--check --checklevel=Information` on 3.18.2
before `@todo`/`@bug`/`@test` were introduced here.

So a custom tag costs nothing in editor noise. It costs something else: every
custom tag is a small dialect only your tooling reads, and a reader coming from
another project has to learn it. The bar this project applied, and the one worth
keeping: **a custom tag is justified when the fact it records cannot be
expressed by a standard tag and something in the pipeline actually consumes
it.** `@internal` cleared that bar four times over. A tag that only renders a
badge probably has not.

---

## See also

- [`ANNOTATIONS.md`](ANNOTATIONS.md) — the inventory: which tags this tree uses, counted.
- [`REUSE.md`](REUSE.md) — pointing the generator at your own plugin.
- [`PIPELINE.md`](PIPELINE.md) — every stage and the reasoning behind it.
- [LuaCATS annotation reference](https://luals.github.io/wiki/annotations/) — the upstream spec.
