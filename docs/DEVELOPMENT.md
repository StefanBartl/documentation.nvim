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

## The five things CI runs

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
it, one stage per job, so the five keep their independent red/green marks and
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

### The `standalone` gate skips, and what that costs

The `standalone` gate runs the parser-less CLI build under a Lua that is **not**
the LuaJIT Neovim embeds. It needs PUC Lua on `PATH` with `lfs` and `dkjson`;
where it cannot find one it prints *skipped*, and the closing summary says so
— `4 gates passed, 1 skipped: standalone`, plus the sentence that matters: *a
skipped gate checked nothing.* The message names the interpreter it found, the
rock it could not load and the `luarocks install` line, because "no PUC Lua
here" and "a PUC Lua that cannot load the rocks" are different problems.

The skip stays a skip on purpose — a machine with Neovim and nothing else is
the common local case, and making that red is how a gate gets switched off.
What changed instead is how little is left behind it. Three real defects
reached a release through that gap, so the two checks that guard the shim are
built to run **without** PUC Lua wherever they possibly can:

| Check | Answers | Runs in |
|---|---|---|
| [`shim_contract_spec.lua`](../TESTS/shim_contract_spec.lua) | every `vim.*` path and method name `core/` calls, against what the shim provides — read off a real parse, not a grep | `tests` — always |
| [`shim_behavior_spec.lua`](../TESTS/shim_behavior_spec.lua) | the same inputs through the real `vim.*` and through the shim, outputs compared | `tests` — always |
| [`standalone/selfcheck_behavior.lua`](../standalone/selfcheck_behavior.lua) | the same corpus again, on PUC Lua with the real rocks | `standalone` — skippable |

The first answers *does it exist*, the second *does it do the same thing*, and
only the third needs the interpreter that is usually missing. All three read
one corpus, [`TESTS/fixtures/shim_behavior_cases.lua`](../TESTS/fixtures/shim_behavior_cases.lua),
so the shim never grows a second implementation with its own tests.

**A signature narrower than the editor's is a behavioural difference too.**
`vim.deepcopy(t, true)` is a legal call — `true` is Neovim's `noref` — and a
shim using that slot for something of its own raises on it. When adding to the
shim, match the editor's whole signature, options table included, rather than
only the part this tree happens to call today; a case in the corpus is what
keeps that honest.

A case whose `path` or `kind` is a typo resolves to nothing on *both* sides and
therefore agrees with itself. Both runners refuse such a case outright rather
than counting it — a check that reports green while checking nothing is the
failure this whole corner of the tree exists to prevent.

The PUC replay compares against expectations `ci.lua` writes out of the Neovim
running it, seconds earlier — never a committed golden file. A golden would
need regenerating by hand and would drift with the next Neovim release, at
which point it is evidence of nothing.

`luacheck` covers `standalone` as well as `lua`, `TESTS` and `scripts`. It did
not until 2026-09-17, which meant the entire parser-less build sat outside the
only gate that reads Lua for unused locals and undefined globals — the same
tree that has shipped a call to a `nil` value twice.

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

**One hundred and two specs**, every one driven by the tiny shared harness in
[`TESTS/harness.lua`](../TESTS/harness.lua) (`eq`, `ok`, `tmpfile`,
`read_lines` — no framework). The list in
[`TESTS/run.lua`](../TESTS/run.lua) is the inventory; a handful are worth
knowing by name before touching what they cover:

| Spec | Covers |
|---|---|
| [`docmap_spec.lua`](../TESTS/docmap_spec.lua) | `functions`, `check`, `scan`, the graph stages, `diff`/`history`, and the `install()` watch end to end. |
| [`lang_registry_spec.lua`](../TESTS/lang_registry_spec.lua) | `core/lang_registry.lua` — registration order, `reset()` recovering the real "lua" backend from Lua's own module cache rather than losing it. Its own file: it touches the process-wide singleton other specs' real scans depend on. |
| [`backend_contract_spec.lua`](../TESTS/backend_contract_spec.lua) | What every backend must keep, proved rather than asserted: a comment token is verified by *finding a marker*, `emits_calls` by running the backend over its own parity fixture. Also fails a backend with no parity fixture, so a twenty-fourth cannot drop out of the capability matrix silently. |
| [`scan_scope_spec.lua`](../TESTS/scan_scope_spec.lua) | `opts.exclude` and `opts.languages` — including the reset discipline, which is the half that fails silently. |
| [`docmap_browse_spec.lua`](../TESTS/docmap_browse_spec.lua) | `browse` — real floats, real buffers. |
| [`shim_behavior_spec.lua`](../TESTS/shim_behavior_spec.lua) | `standalone/vim_shim.lua` answering what the editor answers, input by input. Loads the shim *inside* Neovim (`_G.vim` unset for the duration, `lfs` adapted onto `vim.uv`, `dkjson` refused rather than faked) so the comparison needs neither PUC Lua nor a rock. See [the standalone gate](#the-standalone-gate-skips-and-what-that-costs). |
| `lang_*_spec.lua` | One per language backend. **Each skips when its grammar is absent**, which is the normal local state — see [`languages.md § Running the language specs`](languages.md#running-the-language-specs) for the `DOCMAP_<LANG>_PARSER` variable each one reads. |
| [`usrcmds_readonly_spec.lua`](../TESTS/usrcmds_readonly_spec.lua) | The `:DocMap` subcommands that read straight off the already-scanned IR — `why`, `graph`, `dot`, `mermaid`, `tools`, `bindings`, `plugins`, `endpoints`, `consumers` — none of which touch git. The algorithms one layer down (`core/deps.path`, `core/consumers.index`, …) already had literal-data coverage elsewhere; this is the command layer above them — usage errors, "nothing found" messages, collision/duplicate detection, sort order, and the `dot`/`mermaid` buffer-reuse-by-name regression. Literal `Documentation.IR` fixtures throughout, the same shape `docmap_spec.lua`'s churn/diff blocks use. |
| [`usrcmds_git_spec.lua`](../TESTS/usrcmds_git_spec.lua) | The four `:DocMap` subcommands that shell out to git — `churn`, `diff`, `impact`, `checklist` — against a real, disposable fixture repository (`git init`, real commits, pinned `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE`), the same posture `api_spec.lua` and `mcp_spec.lua`'s `docmap_checklist` block already take: a stubbed `vim.system` would prove the wiring reads the stub, not that the real command, pathspec exclusion and async callback chain work. Skips outright on a machine with no `git`. |

**What `bindings/usrcmds/*.lua` still has no direct spec, deliberately:**
`open.lua` shells out to a real system opener (`explorer.exe`/`open`/
`xdg-open`) — nothing to assert against without actually popping a browser
window. `serve.lua` binds a real listening socket for the life of the editor
session. `helptags.lua` writes this plugin's own `doc/tags` as a side effect
of running — sandboxing it would mean faking the one thing the command
exists to exercise. `untested.lua` is telemetry-only (`runtime-analysis.nvim`
data, opt-in, degrades to an info message with nothing installed) and its two
reachable branches without that dependency are the least consequential ones
in this directory. `generate.lua`/`generate_all.lua`/`browse.lua`/
`annotate.lua`/`bindings/usrcmds/init.lua` already have their own specs (see
`docmap_spec.lua`, `generate_all_spec.lua`, `usrcmds_generate_all_spec.lua`,
`browse_loaded_spec.lua`/`docmap_browse_spec.lua`, `annotate_spec.lua`,
`usrcmds_actions_spec.lua`).

**A green run does not mean every backend was exercised.** Without grammars,
the language specs report `ok` after their contract assertions and skip the
parse. Point at built grammars before trusting a language change:

```bash
DOCMAP_PYTHON_PARSER=/path/to/python.so nvim --headless -u NONE -l TESTS/run.lua
```

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

## The capability matrix

```bash
DOCMAP_TS_DIR=/path/to/grammars nvim --headless -u NONE -l scripts/parity.lua
```

Runs every backend over its own fixture in `TESTS/fixtures/parity/` and
prints what came back — the table in
[`languages.md § Parity`](languages.md#parity), measured rather than written
down. `--markdown` emits it ready to paste. A backend whose grammar is
missing is reported as `?` throughout rather than as a row of blanks:
"not measured" and "measured, absent" are different facts, and collapsing
them is what the audit exists to stop.

Rerun it after touching a backend, and paste the result if a cell changed.

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

### Regenerating from a `git worktree`

`.docmap.json` declares lib.nvim at `local_path: "../lib.nvim"`, resolved
relative to the **tree root** — which in a worktree is the worktree, not the
main checkout. A sibling checkout that `../lib.nvim` finds from
`repos/documentation.nvim` is therefore invisible from a worktree nested
anywhere else, and
[`core/external_repos.lua`](../lua/documentation/core/external_repos.lua)
silently falls back to the unverified flat shape: about 20 external links
degrade from `…/autocmd/init.lua` to `…/autocmd.lua`, the artifact differs by
roughly a hundred bytes, and `--check` calls the tree stale for something the
tree never said. Same failure the `map` job hit in CI, which is why the
workflow symlinks the dependency into place before generating.

So make `../lib.nvim` resolve from wherever you generate, rather than skipping
the regeneration. One directory symlink in the folder your worktrees live in
covers all of them, and needs no administrator on Windows:

```bash
ln -s /path/to/lib.nvim <worktree-parent>/lib.nvim
```

```powershell
cmd /c mklink /J <worktree-parent>\lib.nvim <path-to>\lib.nvim
```

`--check` reporting "up to date" from inside a worktree is the confirmation
that it resolved.

## Specs that read the committed map

A committed artifact is an *input* to the suite, and the UI half of
`TESTS/docmap_browse_spec.lua` mounts the real browser against it. That buys
coverage nothing synthetic can — but it also means the spec is reading a build
product whose shape it does not control, so it may assert only what the
artifact's contract guarantees.

The rule is: **derive the position from the artifact, never assume it.** The
failure that established it was a `p` (pin) assertion opened on `ir.root`,
which quietly assumed the root has an incoming dependency edge. It normally
does — but `ir.root` is whatever `source` names, and when that is a directory
which merely *contains* the plugin the root is a namespace nothing requires.
This repository shipped exactly that artifact from `8786299` to `ac2cbc5`
(rooted at `lua`, not `lua/documentation`). Deps then renders a single message
row, `p` refuses it by design, and the spec reported `expected 1, got 0` — a
statement about the committed JSON wearing the costume of one about the pin
path.

Two things made it expensive to read. The map commit carried `[skip ci]`, so
no CI run ever saw that artifact and the last green run belonged to the commit
before it — which looked like "passes on Linux, fails on Windows". And the map
was regenerated back to a well-formed root three commits later, so whether it
reproduced depended on which commit the tree happened to be sitting on — which
looked like flakiness. It was neither: given the artifact, the failure is
deterministic on every platform. When a spec in this half goes red, diff
`docs/map/module_map.json` against the last known-good regeneration before
reaching for the code.

The `gI` block in the same spec carries the other half of the rule: scan every
row for one that reports a figure rather than pinning the assertion to a fixed
module and a fixed window of rows.

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

  bindings/         keymaps.lua, usrcmds/, autocmds.lua, diagnostics.lua
    autocmds.lua    a manifest, not a creation site -- checkhealth and
                    docs/BINDINGS.md read it, but each autocmd is actually
                    created by the editor/ module that owns its lifecycle
                    (registry.lua's watch/callhierarchy/diagnostics hooks,
                    browse's CursorMoved, trail_store's and serve's
                    VimLeavePre). Deliberately not centralized: a shared
                    creation site would have to reach into three modules'
                    teardown paths for no benefit, since each hook is torn
                    down (or not) by the module that installed it.
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
has to stay runnable with no editor around it, and nothing but a check keeps a
boundary
like that from quietly rotting. Declaring the rule immediately found one real
violation — `tagfiles.lua` reached into `command.lua` for `find_node`, a
lookup that touches nothing but the IR, now `core/find.lua`.

Deliberately one-directional: the editor half reaching into the core is the
point of the core existing. `init.lua` sits outside the rule and reaches both,
which is what a facade is for.

**A third rule, added with `core/lang_registry.lua`**
(Phase 0 of the language work): `{ from = "documentation.core", to =
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
standalone build anyway, and each already appears in the portability count.

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

Design reasoning for every stage: [pipeline.md](pipeline.md).
