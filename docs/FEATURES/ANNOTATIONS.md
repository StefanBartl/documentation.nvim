# Annotations

Reading and generating LuaCATS annotations — the plugin's other half besides
scanning: not just "what is this tree", but "does the tree say what it means,
and can the map fix it when it doesn't". See
[`docs/ANNOTATION_TAGS.md`](../ANNOTATION_TAGS.md) for the full tag-by-tag
contract; this file covers the two capabilities that generate or resolve
something, not just parse it.

## `:DocMap annotate` — header generation

For any file with no `---@module` header at all, scaffold one: `@module`
derived from the file's own path, a `TODO` prose placeholder (not an invented
`@brief`/`@desc` — `docs/ANNOTATION_TAGS.md` itself calls those a fallback,
"prefer plain prose"), and — when the file returns a table — a `---@class`
block with one `---@field` per exported name. A field whose export already
has its own `---@class` block gets **referenced**
(`---@field rate_limits t.x.RateLimits`), not duplicated; a function field
gets a `fun(...)` type reconstructed from that function's own already-parsed
`@param`/`@return`.

Default is preview-only, in a scratch buffer — nothing is written until asked.

- **Module:** `core/annotate.lua` (`M.candidates`, `M.plan`, `M.apply`),
  `bindings/usrcmds/annotate.lua`
- **Usercmds:** `:DocMap annotate [--write|--sidecar] [--dry-run]` (see
  [BINDINGS.md](../BINDINGS.md#user-commands))
- **Docs:** [`docs/COMMANDS.md`](../COMMANDS.md) "`:DocMap annotate`" section.

## `@see` — validated, not just parsed

A `@see` target is checked against the real module/function index, not taken
on trust: `dead-see-target` (warn) fires when it resolves to nothing in this
tree. A target that *does* resolve renders as a clickable link in the
generated page, straight to the thing it names.

- **Module:** `core/check.lua` (`check_see_targets`)
- **Config:** none — always on.

## `@deprecated` — badge, index entry, migration hint

A function marked `---@deprecated <text>` gets its own badge next to the
signature, its own entry in the Notes tab's index (so every deprecated
function in the tree is one list), and the migration hint text itself shown
inline in the annotation popup — never just a boolean "this is deprecated"
with the *why-migrate-to-what* thrown away.

- **Module:** `core/functions.lua` (`parse_doc_block`), `core/render/html.lua`
- **Config:** none.

## `@generic`

Parsed and folded into the function's own displayed signature — a generic
function reads as generic in the map, the same way it reads in the source.

- **Module:** `core/functions.lua` (`parse_doc_block`)
- **Config:** none.

## Marker comments — `-- TODO:`, `// FIXME:`, `-- PERF:`

The Notes tab used to list only annotations: `---@todo`, `---@bug`,
`---@deprecated`, `---@test`, all of them attached to a function's doc
block. A repository whose author marks work the ordinary way — a
`-- TODO:` on the line that needs it — was told "Nothing carries
`---@todo` in this map", which is true and reads as "nothing left to do".

Marker comments are now read from the source text and listed in their own
half of the tab, grouped by keyword, each with its file, line and the
spelling the author actually typed.

The keyword set is [`todo-comments.nvim`](https://github.com/folke/todo-comments.nvim)'s,
alias for alias — `TODO`, `FIX`/`FIXME`/`BUG`/`FIXIT`/`ISSUE`, `HACK`,
`WARN`/`WARNING`/`XXX`, `PERF`/`OPTIM`/`PERFORMANCE`/`OPTIMIZE`,
`NOTE`/`INFO`, `TEST`/`TESTING`/`PASSED`/`FAILED` — so what is highlighted
in the buffer is what appears in the map. `KEYWORD(author):` keeps the
author.

**A keyword only counts inside a comment.** Which parts of a file are
comments comes from the grammar, not from a pattern: `--` opens a comment
everywhere on the line except inside a string, and this repository's own
renderer — which writes JavaScript inside Lua strings and documents the
syntaxes it recognises — was reported as carrying three to-dos that do not
exist. Without a grammar the module falls back to a text scan driven by the
backend's declared comment tokens, which is the standalone binary's state
when `DOCMAP_TS_DIR` points at nothing; the fallback's limits are written
down in its own tests.

- **Module:** `core/markers.lua` (`M.scan_source`, `M.scan_file`,
  `M.KEYWORDS`)
- **Backend contract:** `Documentation.LangBackend.line_comments` /
  `.block_comments` — a backend that declares neither is not scanned, rather
  than guessed at
- **Artifact:** `Documentation.Node.markers`, schema 4
- **Tests:** `TESTS/markers_spec.lua`

**Where they are counted, and where they are not.** The `FIX` family
(`FIX`/`FIXME`/`BUG`/`FIXIT`/`ISSUE`) also produces the `recorded-defects`
Quicks verdict, because that group says a line is wrong *now* rather than
that work is scheduled. It is a count and never a gate: a marker is the
author's claim about their own code, not something this tool measured, and
`:DocMap check` fails on nothing here. The other keywords are listed in the
Notes tab and nowhere else. See `docs/FEATURE_LOG.md` — *Recorded
defects*.

## The page takes its theme from `?theme=`

`index.html?theme=dark` renders dark, `?theme=light` light, anything else
— including no parameter — follows the operating system. Read in `<head>`
before any element exists, because a theme applied after first paint is a
flash of the wrong one.

It exists because a host embedding this page cannot reach into it: the
attribute `docmap-desktop` stamps on its own document never crosses the
origin boundary, so choosing dark there left a white page inside a dark
window. A query parameter is also the thing a person can type.

- **Module:** `core/render/html.lua`

## The page answers questions from a host, and takes no instructions

A `postMessage` channel with a fixed vocabulary: `export-svg` returns the
hierarchy diagram as a standalone SVG string, `state` returns the coarse
context the page already volunteers on navigation.

**Questions only.** There is no "go to this tab" and no "set this value" —
a host that wants the page somewhere navigates the frame's URL, which it
already controls and which the page validates on the way in. What a host
cannot do from outside is *read* a cross-origin document, which is the one
thing these verbs are for.

Unknown verbs are answered with silence rather than an error echoing the
input back; replies go to the asker's own origin, never `"*"`; a `"null"`
origin gets no answer at all.

- **Module:** `core/render/html.lua` (`buildSvg`, the `message` listener)
- **Consumer:** `docmap-desktop`'s File → Export current view…

## Eight tabs, and a second level under two of them

Hierarchy, Index, Analysis, Compare, Features, Quicks, Notes, History.

**Index owns Tree, Functions and Modules** — three ways of listing the same
repository, which used to be one top-level tab and two buttons inside
another. **Features owns whatever this repository promotes** with
`Tab: true`; those used to append themselves to the top bar, so a project
documenting five features pushed the eight permanent tabs onto a second
row.

`state.tab` is unchanged by the restructure: `tree` is still `tree` and a
promoted feature is still `feature-<slug>`, so every `#tab=` link ever
shared still lands where it did.

- **Module:** `core/render/html.lua` (`topTab`, `subTabs`, `renderSubTabs`)
