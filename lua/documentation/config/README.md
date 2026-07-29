# `documentation.config`

Where a `Documentation.Opts` comes from.

| File | What it holds |
|---|---|
| [`DEFAULTS.lua`](DEFAULTS.lua) | The plugin-side defaults, as a flat table. No logic. |
| [`init.lua`](init.lua) | `detect_source()`, `build()`, and the merge rule. |

Three fields are deliberately **not** in `DEFAULTS.lua`, because none of them
can be stated without a repository in hand:

- `root` — every entry point supplies it (a lazy spec, `install()`, or the cwd).
- `source` — derived by `detect_source()`: `lua/<name>` when `lua/` holds
  exactly one candidate directory, plain `lua` otherwise.
- `title` — the root directory's basename.

`build(root, overrides)` layers those three over `DEFAULTS`, then the caller's
overrides over both, then re-normalises `root` — after the merge, not before,
because an override may have changed it.

## Why it is not under `core/`

`documentation.core` is the pipeline: scan → check → render. The option table
is read by the pipeline, by the editor half and by the command layer alike, so
a base module every layer depends on is not part of any one of them.
`documentation.core.config` remains as a deprecated alias, because
[`docs/REUSE.md`](../../../docs/REUSE.md) published that path.

## Auto-detection is deliberately shallow

One `lua/<name>` probe, no walking, no guessing at nested trees. A wrong guess
that looks confident is worse than an obvious default the user overrides once
in their spec — and `:checkhealth documentation` prints what was resolved, so a
wrong one is visible rather than mysterious.
