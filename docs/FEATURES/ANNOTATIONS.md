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
