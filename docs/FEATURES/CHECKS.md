# Checks

One drift check, not the full sixteen — [`docs/pipeline.md`](../pipeline.md)
"Drift checks" is the complete reference table. This file covers the one
check that started as its own roadmap item, because the defect class behind
it is worth knowing about on its own, not just as a row in a table.

## `type-vs-class` — a real LuaLS defect class, not a style nag

`---@type Foo` on a local table, when fields are *then* assigned to that
same table, produces LuaLS's `missing-fields` and "fields cannot be
injected" — a real diagnostic defect, not a style preference. `---@class X
: Foo` is the annotation that actually means "this table has these
fields"; `@type` means "this value has this type", which a table you are
about to mutate is not. The check fires only when the annotated local
genuinely has a field assigned to it after its literal — a `@type`
constant that stays untouched is not this bug, and is left alone.

**"Genuinely" used to be aspirational, not enforced — two real, wrong
attempts against one real config found both gaps:**

1. `---@type` only counts on the line immediately before the file's first
   real code line, because that is the only line it can validly apply to.
   The original version instead took the first `@type` tag anywhere in the
   leading comment run (reused from `scan.parse_header`'s general-purpose
   tag scan), so an `@alias` block — or any comments/blank lines — between
   the header and an unrelated LOCAL variable's own, entirely correct
   `@type` misattributed it to the module.
2. The annotated local's OWN name is what gets grepped for a field
   assignment now, not `#node.functions` (does this file have functions
   anywhere at all — a question with no connection to the annotated
   local). That proxy fired on a module whose real functions lived on a
   completely separate `local M = {}`, while the `@type`'d table two lines
   above it was a complete, static literal, never touched again.

Both were caught by re-running against a real config rather than trusting
the check's own report, and both now have a dedicated fixture in the test
below so neither regresses silently.

- **Module:** `core/check.lua` (`check_type_vs_class`)
- **Config:** none — always on, `warn` severity.
- **Docs:** [`docs/pipeline.md`](../pipeline.md) "Drift checks" table;
  [`TESTS/check_type_vs_class_spec.lua`](../../TESTS/check_type_vs_class_spec.lua)
  for the fixture-driven test, including the `alias_gap`/`separate_owner`
  regression fixtures for the two gaps above.
