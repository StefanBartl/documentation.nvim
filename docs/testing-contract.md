# Which specs does a change touch? (the testing contract)

A test runner that wants to run only the specs a change can affect needs three
things the module map already holds: which file is which module, who requires
whom, and which specs require what. `require("documentation.testing")` answers
that in one call, and says out loud what it could **not** work out, because a
selection that silently leaves a spec out is worse than running everything.

- [The call](#the-call)
- [The answer](#the-answer)
- [Reading the answer safely](#reading-the-answer-safely)
- [Other repositories (consumers)](#other-repositories-consumers)
- [Specs in the map](#specs-in-the-map)
- [From the shell](#from-the-shell)
- [Versioning](#versioning)

The plugin does not require any test runner and never will: a runner finds this
module with a soft `pcall(require, ...)` and falls back to running everything
when it is absent, when it returns `nil`, or when the answer says it cannot be
trusted. [`affected-specs.schema.json`](affected-specs.schema.json) is the
machine-readable form of everything below.

## The call

```lua
local res, err = require("documentation.testing").affected_specs({
  root = "/path/to/repo",           -- required
  changed = { "lua/x/a.lua" },      -- repository-relative, or absolute inside root
  since = "origin/main",            -- optional: also the files changed since a revision
  spec_roots = { "spec/extra" },    -- optional: extra spec directories or files
  consumers = "/path/to/checkouts", -- optional: cross-repository answer
  verify = false,                   -- optional: settle "stale" by a rescan
})
```

It returns `nil, err` only when no answer is possible at all: bad options, or
no module map (`:DocMap` first). Everything weaker is an answer that says so.

How it works, in order:

1. Every changed file is mapped to a node of `docs/map/module_map.json` (by the
   node's `path` or `source`).
2. The node and everything that requires it, transitively, is *affected*
   (`core/deps.lua`'s `impact`).
3. A spec **covers** a module when it requires it, or requires a module that
   loads it. The specs are `TESTS/**/*_spec.lua` (the `tests_dir` option) plus
   `spec_roots`; a directory called `fixtures` is never searched.
4. The selection is every spec that covers an affected module, plus every
   changed spec file.

`changed` entries that are not a path inside the repository (`../x`, an absolute
path elsewhere, a NUL byte, a non-string) are refused and reported as a gap;
they never reach the file system. `since` must be a plain revision (`HEAD~3`,
`origin/main`): anything shaped like an option is refused.

## The answer

```lua
{
  version = 1,
  specs = { "TESTS/b_spec.lua", ... },     -- run these
  modules = { { id=, module=, path=, role="changed"|"dependent", specs={...} }, ... },
  unplaced_specs = { "TESTS/dyn_spec.lua" }, -- specs the graph cannot place: run these too
  ignored = { "README.md" },                -- changed files that cannot affect a spec
  complete = true,                          -- may a narrowed selection be trusted?
  graph = {
    version = 1, map = "docs/map/module_map.json",
    generated_at = "2026-10-06T12:00:00Z",  -- commit time of the map
    commit = "<sha of the commit that last changed the map>",
    head = "<sha of HEAD>",
    stale = false, stale_reason = nil,
    dirty = false,                          -- uncommitted source changes exist
    verified = nil,                         -- true: stale was settled by a rescan
    gaps = { { kind=, path=, module=, reason=, message= }, ... },
  },
  cross_repo = { { repo = "consumer.nvim", measured = true, specs = {...}, ... }, ... },
}
```

`modules[i].specs` is the covering set of that one module; `specs` is the union
for all of them. `generated_at` and `commit` are read from git, not from the map
file: the map is byte-deterministic (`--check` compares it byte for byte), so it
cannot carry a timestamp of its own.

### Gaps

Every `gaps` entry is something the graph could not tell:

| `kind` | Meaning | Blocks `complete` |
|---|---|---|
| `changed_not_in_graph` | A changed source file that is not in the map (new file, stale map, a directory the scan does not read). Its dependents are unknown. | yes |
| `test_support_changed` | A file under the spec directory that is not a spec (a helper, a harness). Any spec may use it. | yes |
| `invalid_path` | A `changed` entry refused (see above). | yes |
| `invalid_spec_root` | A `spec_roots` entry refused or missing. | yes |
| `spec_unreadable` | A spec file could not be read (too large, unreadable). | yes |
| `changed_module_without_spec` | A changed module that no spec requires, directly or through another module. The change selects nothing for it. | no |
| `spec_unplaced` | A spec the graph cannot place: it requires a module by a computed name (`reason = "dynamic_require"`: it may depend on anything), or none of its requires is in the map (`reason = "no_graph_module"`). Also listed in `unplaced_specs`. | no |

## Reading the answer safely

A narrowed selection is only as good as the graph behind it. The rules for a
caller:

- `complete = false` (a stale graph or a blocking gap): do not narrow; run
  everything.
- `unplaced_specs` are never provably unaffected. Run them with the selection
  (or run everything).
- `graph.stale = true` means code under the source tree was committed after the
  map was written, or the age could not be established (no git: the reason says
  so). With `verify = true` a stale verdict is settled exactly: the tree is
  scanned and the map is accepted when its graph (nodes and require edges)
  equals that scan's. It costs a scan, so it is off by default.
- Do not make affected-selection the default of a CI gate: a graph that is
  missing a dynamic `require` can only under-select, and CI is where an
  under-selection costs the most.
- Static analysis does not see a `require` built from a variable. A module
  loaded only that way has no edge in the graph, so a change to it selects no
  specs. This is a property of the graph, not of this call; a run of everything
  is the backstop.

## Other repositories (consumers)

With `consumers` set to a directory of sibling checkouts (the same option the
`consumer-require-missing` check uses; it can also come from `.docmap.json`),
the same question is asked of every checkout that has a Lua tree:

- a checkout with a readable committed map: every module that requires an
  affected module is affected, so are its dependents, and so are the checkout's
  specs that cover them or require the affected module directly. It is listed
  only when something is affected (`measured = true`, `specs`, `modules`,
  `stale` for its own map, `uncovered = true` when affected but no spec covers
  it, `unplaced_specs`);
- a checkout without a usable map is listed as `measured = false` with a
  `reason`. **Not measured is not "not affected".** A consumer that is not in
  the directory at all is invisible by definition.

The consumer's `specs` are relative to the consumer's own root.

## Specs in the map

`require("documentation.testing").spec_state({ root = ... })` is the opposite
question: which modules have specs, and how did the last run of them end.

```lua
{ version = 1,
  nodes = { [id] = { specs = {...}, spec_count = 2, indirect_count = 5, last_status = "fail" } },
  totals = { modules = 135, with_specs = 82, indirect_only = 21, without_specs = 32 },
  status = { kind = "result-ir"|"history", ts = ... }, notes = { ... } }
```

`specs` are the specs that require the module directly; `indirect_count` counts
those that only reach it through other modules. `last_status` is the worst
status of the direct specs in the last run, and absent when no run is known.

To show this in the generated page and `overview.md`, set `spec_state = true`
(in `setup()` or `.docmap.json`). The page's detail panel then has a **Specs**
section, and the Markdown table gets a **Specs** column; a module with no
specs says `no specs`. With the option off (the default) every generated file
is byte-for-byte what it was before. The committed `module_map.json` never
carries it, because the last status differs per machine.

The last run is read from `spec_state_file` (host option, not settable by a
repository): a testing.nvim Result-IR written with `--json`, or its run history.
When unset, the history testing.nvim keeps under `stdpath('state')` is used if
it exists. The history only remembers failures, so a spec file with no
remembered failure has no status (unknown, not "passed"). The file is
**untrusted input**: it is size-capped, decoded defensively, every value is
checked, and a value is only ever used as a lookup key against the spec files
this plugin found itself. A file that cannot be used is reported in `notes`
and the map simply shows no status.

## From the shell

```sh
nvim --headless -l scripts/affected_specs.lua --since origin/main
nvim --headless -l scripts/affected_specs.lua --changed lua/a.lua,lua/b.lua --verify
```

One JSON document on stdout; exit code 0 when an answer was produced (read
`complete`), 2 when none is possible (reason on stderr: run everything).

## Versioning

`version` (and `graph.version`) is the version of the shape described here.
Fields are only ever added within a version; a change that removes or
reinterprets a field raises it. A caller must treat an unknown `version` as "no
answer" and run everything.
