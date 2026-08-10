# Checks

One drift check, not the full sixteen — [`docs/PIPELINE.md`](../PIPELINE.md)
"Drift checks" is the complete reference table. This file covers the one
check that started as its own roadmap item, because the defect class behind
it is worth knowing about on its own, not just as a row in a table.

## `type-vs-class` — a real LuaLS defect class, not a style nag

`---@type Foo` on a module's own `local M = {}`, when fields are *then*
assigned to that same table, produces LuaLS's `missing-fields` and "fields
cannot be injected" — a real diagnostic defect, not a style preference.
`---@class M : Foo` is the annotation that actually means "this table has
these fields"; `@type` means "this value has this type", which a table you
are about to mutate is not. The check fires only when the module table
genuinely has fields assigned to it — a `@type`-annotated constant that
stays untouched is not this bug, and is left alone.

- **Module:** `core/check.lua` (`check_type_vs_class`)
- **Config:** none — always on, `warn` severity.
- **Docs:** [`docs/PIPELINE.md`](../PIPELINE.md) "Drift checks" table;
  [`TESTS/check_type_vs_class_spec.lua`](../../TESTS/check_type_vs_class_spec.lua)
  for the fixture-driven test.
