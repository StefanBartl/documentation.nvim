# `documentation.testing`

The provider side of the affected-selection contract: which specs does a change
touch, and which modules have specs. The user-facing description is
[`docs/testing-contract.md`](../../../docs/testing-contract.md); this page is
the map of the code.

| File | Does |
|---|---|
| [`init.lua`](init.lua) | `affected_specs(opts)` and `spec_state(opts)`; loads and sanitises the map, builds the spec coverage, the gaps, the cross-repository section. |
| [`specs.lua`](specs.lua) | Finds spec files (`TESTS/**/*_spec.lua` plus `spec_roots`, path-validated) and reads which modules each one requires, including computed requires. |
| [`freshness.lua`](freshness.lua) | `generated_at`, `commit`, `stale`: read from git, because the map itself carries no timestamp. |
| [`git.lua`](git.lua) | The few read-only git queries, argv only, revisions validated. |
| [`status.lua`](status.lua) | The last run of the specs (a testing.nvim Result-IR or run history), read as untrusted input. |
| [`@types/`](@types/init.lua) | The shapes of the answer. |

## Rules of this directory

- **No test runner is required, ever.** The answer's shapes are the contract;
  a runner that is missing is its caller's concern. Nothing here may
  `require("testing")`.
- **An unknown is a gap, never "unaffected".** Every branch that cannot decide
  adds a `gap` or marks the graph stale; a narrowed selection is only trusted
  when `complete` says so.
- **Everything from outside is untrusted.** Changed paths, `spec_roots`,
  `since`, the map's own fields, a consumer's map, the status file: validated
  where they enter, never used as a shell string, a pattern or an unchecked
  path.
- **Not part of the pipeline.** `core/` stays free of git and process calls; this
  directory shells out (git) and is only reached by an explicit call or by the
  opt-in `spec_state` option.
