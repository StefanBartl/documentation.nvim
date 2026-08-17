# Development

## Getting the dependency

`documentation.nvim` depends on
[`lib.nvim`](https://github.com/StefanBartl/lib.nvim) at runtime — `notify`,
`fs.*`, `ui.kit`, `usercmd`, `map`, `debounce`, `autocmd`,
`cross.uv.spawn_capture`. Inside Neovim your plugin manager supplies it. The
headless runners cannot assume that, so they look in three places, in
descending order of explicitness:

1. `$LIB_NVIM_DIR`
2. `<repo>/.deps/lib.nvim`
3. a sibling checkout, `../lib.nvim`

Pick whichever suits your tree. CI clones into `.deps/`.

```bash
export LIB_NVIM_DIR=/path/to/lib.nvim
```

## The four things CI runs

```bash
scripts/ci.sh
```

Or, identically and without a POSIX shell:

```bash
nvim --headless -l scripts/ci.lua
```

That is all of them, in order, stopping at the first failure. One gate at a
time by naming it — `scripts/ci.sh luacheck`, `nvim --headless -l
scripts/ci.lua luacheck` — which is also how `.github/workflows/ci.yml` calls
it, one stage per job, so the four keep their independent red/green marks and
their parallelism.

**What each gate *is* lives in [`scripts/ci.lua`](../scripts/ci.lua) and
nowhere else.** `ci.sh` is a three-line wrapper that picks the interpreter, and
the workflow calls the wrapper. A workflow — or a second script — spelling the
commands out again would be a second copy of them, which is the drift this
repository exists to detect.

The Lua entry point is not a curiosity, it is the cross-platform answer. This
plugin's own code is portable by construction (no `io.popen`, no `os.execute`,
`vim.system`/`vim.uv`/`vim.fs` throughout), but its tooling was bash, so a
Windows contributor's answer to "how do I run the checks" used to be "install
Git Bash". Neovim is already a hard requirement here; using it as the script
host costs nothing and removes that.

Two scripts remain shell, deliberately:

- [`scripts/hooks/pre-commit`](../scripts/hooks/pre-commit) is `sh`. Git for
  Windows ships one and runs hooks through it, so this works everywhere git
  does — and a hook has to be executable by *git*, not by whatever the
  contributor happens to have.
- [`scripts/publish_map.sh`](../scripts/publish_map.sh) is bash. It is a
  maintainer-side publishing utility, not a gate: nobody is blocked by it, and
  rewriting it would buy nothing.

One gate cannot come through `ci.lua` in GitHub Actions: stylua's action is
both the installer and the runner, so there is no binary on PATH to hand a
script. Its `args` in the workflow must therefore stay identical to what the
`stylua` gate does — the whole tree, not a list of directories.

The order is not cosmetic. A formatting failure is the cheapest one to find
and the least interesting; a stale map is the most likely to be a real finding
rather than a slip. Failing fast on the cheap one means the expensive checks
only run on code that is already tidy.

`stylua --check .` covers the **whole tree**, not a list of directories. The
list form is what let a file sit unformatted in `docs/EXAMPLES/` for as long
as it existed while every local run reported clean — CI used `.` and caught
it; nobody was reading CI, because it was green on Linux.

Which brings up the trap that only bites on Windows: `.stylua.toml` sets
`line_endings = "Unix"`, and with `core.autocrlf=true` a checked-out `.lua`
file arrives CRLF, so `stylua --check` rejects every line of it while the same
command passes on Linux CI. `.gitattributes` now pins `*.lua text eol=lf`, the
same rule `*.sh` already had. If you cloned before that landed, one
`git add --renormalize .` fixes your working tree.

## Tests

```bash
nvim --headless -u NONE -l TESTS/run.lua
```

Two specs, both driven by the tiny shared harness in
[`TESTS/harness.lua`](../TESTS/harness.lua) (`eq`, `ok`, `tmpfile`,
`read_lines` — no framework):

| Spec | Covers |
|---|---|
| [`docmap_spec.lua`](../TESTS/docmap_spec.lua) | `functions`, `check`, `scan`, the graph stages, `diff`/`history`, and the `install()` watch end to end. |
| [`lang_registry_spec.lua`](../TESTS/lang_registry_spec.lua) | `core/lang_registry.lua` — registration order, `reset()` recovering the real "lua" backend from Lua's own module cache rather than losing it. Its own file: it touches the process-wide singleton other specs' real scans depend on. |
| [`docmap_browse_spec.lua`](../TESTS/docmap_browse_spec.lua) | `browse` — real floats, real buffers. |

The runner prints one line per spec and exits non-zero on the first failure. It
writes to stdout directly rather than through `print`: `print` in a headless
Neovim goes through the message area, and a spec that opens a window forces a
redraw that swallows the pending newline, running two results together on one
line. `docmap_browse_spec` mounts real floats, so that is not hypothetical.

Adding a spec means adding its filename to the `specs` list in
[`TESTS/run.lua`](../TESTS/run.lua) — explicit, not globbed, so the order is
stable and a half-written file in the directory does not join the run by
accident.

**The watch test is worth reading before touching `registry.lua`.** It writes
through a real buffer with `vim.wait` pumping the event loop until the debounced
rescan lands, and it asserts *both* directions: a write under `source` rescans,
and a write outside it does not. The second matters more than it looks —
scoping this with an autocmd glob pattern is the obvious approach and silently
never fires on Windows, because Vim matches the raw OS-native buffer path
against a forward-slash pattern. The explicit `is_subpath` check replaced it,
and the test guards the opposite failure of over-matching.

## Regenerating this repository's own map

```bash
nvim --headless -l scripts/gen_map.lua           # regenerate
nvim --headless -l scripts/gen_map.lua --check   # verify
```

or `:DocMap` from inside a Neovim session with the plugin loaded — the same
code path, the same artifacts.

The artifacts under `docs/map/` are **committed**. That is what makes
`--check` a byte comparison and what makes `:DocMap diff <ref>` work without a
generation step: every commit carries its own map, so `git show
<ref>:docs/map/module_map.json` is the whole retrieval.

It also means a source change and its map regeneration belong in the same
commit. The pre-commit hook enforces exactly that:

```bash
git config core.hooksPath scripts/hooks   # once per clone
```

The committed map is generated **without** `--full`: `--check` compares it byte
for byte and would otherwise need `lua-language-server` installed to reproduce
it. Both class-based Hierarchy views say so explicitly when opened against such
an artifact instead of rendering blank.

## Determinism

Two rules, and breaking either one makes `--check` useless:

- **No timestamp in the IR.** A `generated_at` field would make every
  regeneration a diff even when nothing changed.
- **Sorted-key JSON** via [`json.lua`](../lua/documentation/core/json.lua), never
  `vim.json.encode`, whose object key order is unspecified. Without this, two
  runs over an unchanged tree produced byte-different files and `--check`
  reported the map as stale immediately after generating it.

If you add a field to the IR, add it to `M.to_json`'s explicit field list in
[`init.lua`](../lua/documentation/init.lua) — the ordering there is the
serialization contract, not an accident of table iteration.

## Layout

```
lua/documentation/
  init.lua          the public facade: generate/scan_full/install/setup
  @types/           Documentation.* LuaCATS definitions

  core/             the pipeline. No editor, and a layer rule says so.
    lang_registry.lua  which language backend owns a file — see below
    lang/lua.lua    Lua registered as a backend; thin, delegates to scan/functions
    scan.lua        filesystem walk + header parse   -> IR
    functions.lua   per-function docs via treesitter -> node.functions
    symbols.lua     module-scope tables/constants    -> node.symbols
    deps.lua        require edges
    calls.lua       call edges
    find.lua        name -> node id
    luals.lua       opt-in LuaLS enrichment
    check.lua       drift findings
    coverage.lua    fn.tested       doccoverage.lua  fn.documented
    duplicates.lua  functions grouped by structural shape  (pure)
    churn.lua       churn x complexity ranking             (pure)
    tagfiles.lua    cross-project link resolution
    json.lua        deterministic encoder
    diff.lua        structural diff between two IRs        (pure)
    history.lua     changed lines -> functions -> callers  (pure)
    config.lua      Documentation.Opts defaults + merge
    cli.lua         --check/--full entry point
    render/         html · markdown · mermaid · dot · badge

  editor/           everything that needs a running Neovim
    command.lua     :DocMap
    browse/         :DocBrowse (trail.lua pinned positions and filter.lua the
                    list filter, both pure — trail_store.lua is the only file
                    under it touching disk)
    registry.lua    install()/uninstall(), the watch
    serve.lua       the local map server
    health.lua      :checkhealth documentation
```

**The `core`/`editor` split is enforced, not conventional.** `scripts/gen_map.lua`
declares one layering rule against this repository's own map:

```lua
layers = {
  { from = "documentation.core", to = "documentation.editor" },
  { from = "documentation.core", to = "documentation.bindings" },
}
```

(Only that direction. `editor -> bindings` was tried and is wrong: `browse`
requires `bindings.keymaps` for the key-override rule — a utility over key
tables, not the command surface — and the deprecated `editor/command.lua` shim
delegates upward on purpose. A rule that flagged those would only teach people
to ignore the check.)

so `:DocMap check` — and therefore CI — fails if a core module ever requires
an editor one. That is the whole reason the directories exist: the pipeline
has to stay runnable with no editor around it (see
[PORTABILITY.md](ROADMAP/IDEAS/PORTABILITY.md)), and nothing but a check keeps a boundary
like that from quietly rotting. Declaring the rule immediately found one real
violation — `tagfiles.lua` reached into `command.lua` for `find_node`, a
lookup that touches nothing but the IR, now `core/find.lua`.

Deliberately one-directional: the editor half reaching into the core is the
point of the core existing. `init.lua` sits outside the rule and reaches both,
which is what a facade is for.

**A third rule, added with `core/lang_registry.lua`**
(`docs/ROADMAP/MULTILANG.md`'s Phase 0): `{ from = "documentation.core", to =
"documentation.core.lang" }`. `scan.lua`'s walk used to hardcode `"%.lua$"`,
`"init.lua"` and a direct call into `functions.lua` — every one of those is a
fact about Lua, not about how a walk works. The registry is the seam;
`core/lang/lua.lua` is Lua registered through it, a thin wrapper delegating to
the same `scan.lua`/`functions.lua` code that predates the interface, not a
rewrite of either.

The registry module is deliberately named `lang_registry`, not `lang.init` —
living inside `documentation.core.lang.*` would trip this very rule, since a
registry that legitimately knows about every backend is not the violation the
rule exists to catch. It sits beside the boundary, the same reason `init.lua`
sits outside the `core`/`editor` rule.

Declaring this rule caught a real violation on the first `--check`, the same
way the `core`/`editor` rule did: `scan.lua` originally required
`core/lang/lua.lua` directly, to trigger its self-registration. Moving that
require into the registry's own `KNOWN_BACKENDS` list — the one place allowed
to name a specific backend module — fixed it, rather than suppressing the
finding.

### The same rule applies to `lib.nvim`, and no check enforces it

`lib.nvim` splits the way this plugin does: `lib.lua.*` is pure Lua,
`lib.nvim.*` needs a running Neovim. So **a `lib.nvim.*` require inside
`core/` costs exactly what a `documentation.editor` require would** — it is
the same boundary, and `layer-violation` cannot see it, because the rule
matches module prefixes inside the scanned tree and `lib.nvim` is outside it.

Six such requires exist today, all of them earning their keep by wrapping a
real Neovim API rather than a language feature: `fs.read` (cli, tagfiles),
`fs.mkdirp` (init, luals), `fs.collect_recursive` (coverage) and
`cross.uv.spawn_capture` (luals). Every one of them would need replacing in a
standalone build anyway, and each already appears in
[PORTABILITY.md](ROADMAP/IDEAS/PORTABILITY.md)'s count.

What that rules out is the tempting direction: replacing small pure-Lua
helpers in `core/` with `lib.nvim.*` calls. That trades five lines of Lua for
a dependency edge on the Neovim half, and makes the port measurably more
expensive to buy tidiness. `lib.lua.*` is fair game — it comes along.

Two concrete near-misses found while auditing this, both worth stating so
they are not re-proposed:

- **`lib.nvim.fs.write.to_file` for the artifact writer.** It appends a
  trailing newline when the content lacks one. `index.html` legitimately ends
  in `>`, and `--check` byte-compares the file against the in-memory string,
  so the swap would report the map as stale immediately after generating it —
  permanently.
- **`lib.nvim.normalize.utils.normalize_path` for the 14 inline
  `gsub("\\", "/")` sites.** It expands environment variables and runs
  `vim.fs.normalize`, which resolves `..` and collapses separators. Node ids
  are repo-relative paths used verbatim as artifact keys; putting them
  through it would change the keys. `lib.nvim.cross.fs.separators.unify_slashes`
  *is* semantically identical — it is a bare `gsub` — but it is a five-segment
  require into the Neovim half for a one-line pure transform, which is the
  trade this section exists to refuse.

`core/diff.lua`, `core/history.lua`, `editor/browse/trail.lua` and
`editor/browse/filter.lua` are
pure — data in, a structure out; no git, no filesystem, and in the last two
cases no `vim` API at all. Everything that shells out lives in `command.lua` and
`editor/browse/init.lua`. That split is what keeps the shape of the answers testable
without a repository — the whole trail model is driven from the spec without
mounting a float — and it is worth preserving.

`editor/browse/trail_store.lua` is what that costs: persistence could have been three
`save()` calls inside `trail.lua`, and instead it is a separate module that
*subscribes* to `trail.on_change`. Keeping `trail.lua` pure is half the reason;
the other half is that a mutation added later cannot forget to persist. It
reaches disk only through `M.path()`, which is a function on the module rather
than a constant precisely so the spec can point the whole thing at a temp file
instead of writing into the real `stdpath("state")` while the suite runs.

Design reasoning for every stage: [PIPELINE.md](PIPELINE.md).
