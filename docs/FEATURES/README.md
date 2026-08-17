# Features

A `docs/FEATURES_FORMAT.md`-shaped catalog of this plugin's own signature
features, for the Features tab to render as its own first real test —
dogfooding, not a replacement for [`docs/FEATURES/FEATURES.md`](FEATURES.md),
which stays the *decision record* (why something was built the way it was,
what commit shipped it). This folder is the *user-facing* catalog: what the
feature is, which module and keys are behind it, today.

Deliberately not exhaustive — the point of this folder is a real,
representative sample for the parser and the tab to read, not full coverage
of every panel this plugin has. `docs/PIPELINE.md` remains the complete
reference.

## Files

- **[CORE.md](CORE.md)** — the map's own cross-cutting mechanisms: Compare
  marks, the Hierarchy hide/dim toggle, the ecosystem-convention Analysis
  panels (`plugins`/`tools`/`telemetry`, the last with snapshot picking and
  A/B diffing), the plugin-gated badge those last two share, and the
  Features tab itself.
- **[ANNOTATIONS.md](ANNOTATIONS.md)** — reading and generating LuaCATS
  annotations: `:DocMap annotate` header generation, `@see` validation,
  `@deprecated` badges, `@generic` signatures.
- **[CHECKS.md](CHECKS.md)** — the `type-vs-class` drift check (one of
  sixteen; `docs/PIPELINE.md` has the full table).
