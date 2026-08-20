# EmmyLua/LuaLS annotation reference for this repo

A survey of which [LuaCATS](https://luals.github.io/wiki/annotations/) annotations this tree actually
uses, which real ones it doesn't, and which tags exist outside the spec entirely — written to inform
what `docmap` recognizes and what future source-code annotation is worth adding. Tag counts are exact,
from `grep -rhoE '^\s*---@[A-Za-z_]+' --include="*.lua" lua/ | sort | uniq -c | sort -rn` against this
repo, last run 2026-08-20; re-run it yourself if this drifts. It counts a tag
only in *annotation position* — a line beginning `---@` — so a tag named in
prose about tags (this file's own subject matter) does not inflate its own
count.

This is a reference and a recommendation, not a mandate — nothing here means "go retrofit all ~250
files." Adopt a tag when the concrete case for it comes up, not in bulk.

> **Annotating your own plugin?** Read [`ANNOTATION_TAGS.md`](ANNOTATION_TAGS.md) instead. That one is
> the *contract* — which part of the pipeline consumes each tag and what you get back. This one is the
> *inventory* — what one particular tree happens to use, counted. Contract before annotating,
> inventory when auditing.

## a) Standard tags already used heavily

**Recounted 2026-08-20**, over 125 files in `lua/`, with the exact command in
the intro. The previous table had been marked stale rather than fixed, which
made the drift visible and left it there — this is the fix.

> **This table is counted by hand and by text search, and the Analysis tab
> now answers a sharper version of the same question automatically.** Open
> **Analysis → Annotations** in any generated map: it reports, per tag, how
> many *functions* carry it, out of how many functions there are.
>
> The two measures are different on purpose and both are worth having. The
> table below counts **occurrences of the text**, which includes prose *about*
> a tag — that is how `@nodiscard` could read as 112 while no function in this
> tree carried one. The panel counts **functions**, which is the adoption
> question, and it cannot go stale because nobody writes it.
>
> Where they disagree, the panel is the one describing the code.

| Tag | Count | What it's for here |
|---|---|---|
| `@param` | 1311 | Function parameters |
| `@return` | 773 | Function return values |
| `@field` | 545 | Class/alias member declarations in `@types/` files |
| `@type` | 156 | Standalone variable typing |
| `@module` | 125 | This repo's own "module path" convention — required on every file, checked by `docmap`'s `missing-module-tag`. **One per file, and there are 125 files**, which is the whole point of the check. |
| `@class` | 87 | Structured types in `@types/` files |
| `@alias` | 10 | Named unions / enum-shaped string literals |
| `@raises` | 8 | Author-facing only, not evaluated by `documentation.nvim` — see [`ANNOTATION_TAGS.md` § `@raises`](ANNOTATION_TAGS.md#raises--an-author-facing-convention-not-evaluated-here). It was not in the table at all last time. |
| `@meta` | 6 | Marks `@types/init.lua` files as pure-definition, non-executable |
| `@generic` | 3 | Type-agnostic function signatures |
| `@internal` | 2 | Part of the implementation, not the published surface. Sharpens every "is this used" question — `undocumented-param` skips it and the coverage number excludes it. |
| `@cast` | 1 | Narrowing a variable's type mid-function |

**Two things the recount says that no single number does.**

`@param` overtook `@field`, and the ratios did not merely shrink — they
inverted. The old table was `@field` 1725 over `@param` 1459; it is now
`@param` 1311 over `@field` 545. The `config`/`bindings` split moved a great
deal of type surface out of `@types/` files and into ordinary annotated
functions, and this is where that shows as a number.

**`@nodiscard` went from 112 to zero**, which is the more interesting one:
the tag was in the "used heavily" row and is now used nowhere in this tree at
all. `@diagnostic` likewise — its one remaining occurrence is a *mention* in
prose, not an annotation. Both are counted where they belong below, among the
tags this tree does not use.

## b) Standard tags, unused in this repo (0 hits), with real value for `docmap`

**`@nodiscard` and `@diagnostic` now belong here**, which they did not at the
last pass — the first had 112 uses and the second 5, and both are at zero in
annotation position today. `@nodiscard` is the one worth a sentence: nothing
in this tree marks a return value as "must not be silently dropped" any more,
and whether that is a decision or an erosion is not something a count can
say. Recorded so somebody can decide which it was.

- **`@overload`** — no hits in this repo's own source (only in `TESTS/`
  fixtures, which this count deliberately excludes). Fully recognized as of
  the change that added this line: parsed into a structured param/return list
  — the same shape the primary signature uses — badged on the function row
  and rendered as an "Also callable as" block in the detail pane. See
  [`ANNOTATION_TAGS.md`](ANNOTATION_TAGS.md) for the full contract, including
  the one piece still open (`undocumented-param` does not yet credit an
  overload-only parameter list).
- **`@deprecated`** — no hits. `docmap`'s function scanner (see [`functions.lua`](../lua/documentation/core/functions.lua))
  recognizes it and renders a deprecation banner + surfaces it in the Functions section. High value:
  this is the single most Doxygen-shaped signal missing today.
- **`@see`** — no hits. Recognized as a cross-reference; `docmap` renders it as a clickable link when
  the target resolves to a known node/function, and the new `dead-see-target` check (mirrors the
  existing `dead-readme-link`) flags it when it doesn't. Core of "Doxygen-like" cross-referencing.
- **`@async`** — no hits. Recognized as a badge on a documented function once function-level scanning
  exists. Medium value on its own; only useful once functions are individually documented.
- **`@enum`** — no hits. This repo currently expresses "one of these string literals" via
  `@alias Foo "a"|"b"|"c"` (see e.g. `Documentation.Kind`). For a table that's a real *runtime* value (like
  `vim.log.levels`-shaped constants), `@enum` is more accurate than `@alias` — LuaLS then knows the table
  itself is the enum, not just its keys' string shape. Medium value, but a case-by-case call, not a
  blanket replacement for every `@alias`.
- **`@package`/`@private`/`@protected`** — no hits. Would let `docmap` distinguish public vs. internal
  *functions*, not just directories (today the only public/private signal is the `_`-prefix /
  `internal/`-directory convention at module granularity, documented in `doc/lib.nvim.txt`'s
  Conventions section). Medium value, but repo-wide adoption is a separate, later decision — not part
  of this change.
- **`@operator`/`@source`/`@version`/`@vararg`/`@as`** — no hits, low value for this repo specifically:
  no metatable operator overloading anywhere, no multi-Lua-version compatibility matrix to declare
  (`@vararg` is also deprecated upstream in favor of `...`). Listed for completeness, not actively
  recommended.

## c) Tags outside the LuaCATS spec

Already in informal use, tolerated by `scan.lua`'s header parser as an alternative to plain prose:

- **`@brief`** (8 hits), **`@description`** (10 hits) — competing convention for a module's leading
  summary line.

Recognized by [`functions.lua`](../lua/documentation/core/functions.lua):

- **`@example`** — a code sample attached to a function's doc block, rendered by `docmap` as its own
  fenced block instead of being flattened into prose. Many modules already informally embed a ` ```lua `
  fence in their module-level header prose; `@example` makes the same idea explicit and
  machine-readable at function granularity.
- **`@since`** — deliberately *not* `@version`: LuaLS's `@version` declares which Lua runtime a symbol
  requires (5.1/5.3/JIT/...), a different question from "since when has this function existed in this
  project." A separate tag avoids colliding those two meanings.

## `@todo` / `@bug` / `@test`

The three repeatable note tags, collected into the map's **Notes** tab the way
Doxygen's `\todo`, `\bug` and `\test` feed its Todo/Bug/Test lists. Each is
**repeatable** — one list entry per occurrence, so a function with two open
todos keeps both rather than having the second silently overwrite the first:

```lua
---Reads a file.
---@todo make this async
---@todo and handle cancellation
---@bug leaks a handle when the path is missing
---@test covered by fs_spec.lua
function M.read(path) end
```

Each entry is a single line. A continuation line is dropped, the same as it
already is under `@deprecated` — `@example` is the only multi-line tag here.

Two deliberate non-decisions:

- **Not `check` findings.** None of these is drift or an error, and routing
  them through findings would put an author's own to-do list into an exit code
  that CI fails on.
- **Safe to introduce.** `lua-language-server` does not know these tags, but it
  ignores unknown annotations rather than diagnosing them — verified with
  `--check --checklevel=Information` on 3.18.2 before they were added, since a
  tag that makes everyone's LSP complain would not be worth a list page.

## `@internal`

Marks a function as implementation rather than published surface. Recognised
by `docmap.functions` and used in four places: `undocumented-param` skips it,
`docmap.diff` counts it among helpers instead of listing it as an API change,
the HTML map badges it, and `dead-function` checks it unconditionally for a
missing caller (an ordinary exported function only gets that scrutiny under
`opts.dead_code`, since a library's whole point is functions with no
*internal* caller).

It exists because every "is this used" question otherwise has to guess from
the shape of the declared name — `M.compare` looks public, `node_set` looks
private. That guess is decent and it is still a guess; the tag makes it a
fact.
