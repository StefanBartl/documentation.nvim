# documentation.nvim — finish plan

> **Status: all phases done.** §4's summary table already said so; §3's
> phase-by-phase write-ups for 5–9 were missing the same tag until this pass
> caught up with it. Kept as a historical audit record, not reopened.

An audit of this repository against the two personal completion checklists
(`nvim/docs/ROADMAP/personal/FINISH/CHECKLIST.md` and `FINISH_ME.md`), plus the
implementation order that follows from it.

Written in English like every other file under `docs/`, even though the source
checklists are German — the checklists themselves require English docs.

Status vocabulary: **DONE** (nothing to do), **PARTIAL** (exists, gap named),
**OPEN** (not built), **N/A** (does not apply here, with the reason), **DECIDE**
(needs a call from the author before code can be written).

---

## 1. Audit

### CHECKLIST.md

| # | Item | Status | Evidence / gap |
|---|---|---|---|
| 1 | `docs/BINDINGS.md` (keymaps, usrcmds, autocmds) | **DONE** | Phase 4. **Generated** by `bindings/docs.lua` from `KEYS` + the two manifests, written by `scripts/gen_map.lua`, with a spec asserting every action and key appears in it. |
| 1 | Keymaps user-modifiable / disableable | **DONE** | Phase 1, below. `opts.keys` keyed by action id; string/list rebinds, `false` disables. |
| 1 | which-key support | **DONE** | Phase 1, below. `opts.which_key` (default true), v3 `add` / v2 `register`, guarded by `pcall`. |
| 1 | Features default-on, minimal init spec | **DONE** | `{ "StefanBartl/documentation.nvim", dependencies = { "StefanBartl/lib.nvim" }, cmd = { "DocMap", "DocBrowse" }, opts = {} }` is genuinely enough; `core/config.lua` derives `source`, `title`, `out_dir` from the cwd. |
| 1 | `docs/ROADMAP.md` | **DONE** | `docs/ROADMAP/ROADMAP.md` (open items) + `FEATURES.md` (shipped ledger). Better than the checklist asks for. |
| 1 | README badges & ASCII | **DONE** | Phase 4. ASCII banner, CI/Neovim/Lua badges. No coverage badge: `opts.badge` is off for this repo so `coverage.svg` is not committed, and a badge pointing at a missing file is worse than none. |
| 1 | README English | **DONE** | README and `doc/documentation.txt` are both English. |
| 1 | Intro `>` paragraph linking a sibling plugin | **DONE** | Phase 4. Blockquote pointer to lib.nvim directly under the badges. |
| 1 | filetree.nvim feature harvest + `docs/ROADMAP/NEOTREE_FEATURES.md` | **DROPPED** | Cut by the author, 2026-07-28. Not "not started" — deliberately out of scope for this repo, so a later pass does not reopen it. |
| 2 | Install docs for several package managers | **DONE** | Phase 4. lazy.nvim, vim.pack, mini.deps, packer, paq — in README (collapsible) and vimdoc. The vim.pack and paq entries spell out the manual lazy-loading those two do not provide.
| 2 | Explicit lazy trigger in the spec block | **DONE** | `cmd = { "DocMap", "DocBrowse" }` is stated explicitly. |
| 2 | Remove `dir = vim.env...` from README | **DONE** | Not present. |
| 2 | Remove licence references, no licence | **DONE** | Decided in favour of no licence and executed: `LICENSE` deleted, `README.md`'s `## License` section removed, `License: MIT` dropped from the vimdoc credits block. See §2 for what that means. |
| 2 | `.luarc.json` in project root | **DONE** | Present. |
| 3 | `:checkhealth` support | **DONE** | `lua/documentation/editor/health.lua` — environment, deps, optional tools, registered commands, resolved config, artifact freshness. This is the strongest item in the repo. |
| 3 | `/config` folder with `config/DEFAULTS.lua` | **DONE** | Phase 2. `lua/documentation/config/DEFAULTS.lua` (data) + `config/init.lua` (derivation + merge); `core/config.lua` kept as a deprecated alias. |
| 3 | Use `lib.nvim` as dependency | **DONE** | 12 modules, enumerated in `health.lua:35`. |
| 3 | Everything lazy | **DONE** | Command-lazy; `init.lua` defers `browse`, `diff`, `cli`, `history` behind `__index` metatables. |
| 3 | `/bindings` folder (`usrcmds`, `keymaps`, `autocmds`) | **DONE** | Phase 2. `bindings/usrcmds/` is one file per action plus a dispatcher; `keymaps.lua` owns the override rule; `autocmds.lua` is the manifest `:checkhealth` reads. |
| 3 | Test results in `:checkhealth` | **DONE** (Phase 4b) | Split the item. *Running the suite* from `:checkhealth` is out: `TESTS/run.lua` is a whole-process script (`os.exit` on failure, results via stdout, `docmap_browse_spec` mounts real floats) — the checklist's own "if not state of the art, drop it" applies. *Checking the test wiring* is in, and one part of it matters: `tests_dir` feeds `coverage.lua`, a missing directory is deliberately not an error (`@types/init.lua:27`), so a misconfigured `tests_dir` makes the Analysis tab report 0% coverage tree-wide — and `health.lua` does not currently print `tests_dir` at all. See Phase 4b. |
| 4 | Cross-platform | **DONE** (Phase 5) | Lua side is clean: no `io.popen`, no `os.execute`, no `/tmp`, no `$HOME`; `vim.system`/`vim.uv`/`vim.fs` throughout; paths normalised with `gsub("\\", "/")` at every entry point. The gap is tooling: `scripts/ci.sh`, `scripts/publish_map.sh` (bash) and `scripts/hooks/pre-commit` (sh) have no Windows path. |
| 5 / 6 | `config/init.lua` + `config/DEFAULTS.lua` | **DONE** | Same item as row 3 above. |
| 6 | Type for every option key | **DONE** | `lua/documentation/@types/init.lua:8-28` — every field typed and documented, including defaults. Exemplary. |
| 6 | Missing user-settable options? | **DONE** | Phase 1 added `keys` and `which_key`, the two that mattered. Three remain deliberately fixed: the notify prefix (it names the command, which is already configurable), the trail-store path (`stdpath("state")` is where state belongs), and the serve host/port (`127.0.0.1` + port 0 is a *security* property, not a preference — see `docs/SECURITY.md`). |
| 8 | which-key | **DONE** | Same as row 1. |
| 9 | `gh repo edit --description/--homepage` | **DONE** | Phase 0. Description set. `homepageUrl` deliberately left empty until `publish_map.sh` actually publishes to Pages — a homepage pointing nowhere is worse than none. |
| 9 | Repo topics | **DONE** | Phase 0. Ten topics set. |
| 9 | Default branch `main` | **DONE** | |
| 9 | Everything committed and pushed | **DONE** | Tree clean at audit time. |

### FINISH_ME.md

| Item | Status | Evidence / gap |
|---|---|---|
| Central cheatsheets under `nvim/docs/NOTES/PersonelPlugins/BINDINGS/` (Keymaps, Usrcmds, Autocmds, Misc) | **DONE** | Phase 7. Four sheets written, plus entries in the three `All.md` indexes. `Misc.md` was empty and now has its first section. |
| No `lhs` collisions with other personal plugins | **DONE** (Phase 7) | Risk is structurally low — every DocBrowse key is buffer-local to a scratch buffer with `nowait`. The real global surface is the two command names `:DocMap` / `:DocBrowse`, both already overridable via `opts.command_name` / `opts.browse_command_name`. Still needs the cross-plugin check to be actually run. |
| `doc/{NAME}.txt` vimdoc | **DONE** | `doc/documentation.txt`, 552 lines, full tag set. |
| Auto-generate `doc/tags` + gitignore it | **DONE** | Phase 4. `:DocMap helptags`, resolving the directory through `nvim_get_runtime_file` rather than from this file's own path. Already gitignored. |
| Every keymap also reachable as a usrcmd | **DONE** | Rationale written, in `docs/BINDINGS.md` and the central Keymaps cheatsheet: every key with a meaning outside the list already has a command (`gd`→source, `gq`/`gI`→`:DocMap impact`, `gO`→`:DocMap open`). The rest (`j/k`, `+`, `h/l`, `1…6`) move a cursor inside one buffer — a command form would have nothing to act on. |
| Enforce `lib.nvim.selection` | **N/A** | This plugin has **zero** visual-mode mappings. Nothing can lose a selection. Record as N/A so it stops being re-asked. |
| Security hardening pass | **DONE** (Phase 6) | Already strong and deliberate: `serve.lua` binds `127.0.0.1` only (`serve.lua:438`), validates SHAs against `^%x%x%x%x%x%x%x+$` with a length cap (`:141`), rejects `..` and separators in path names (`:302`), and every git call goes through `vim.system` argv — no shell, so no injection from a user-supplied `<ref>`. What is missing is the **audit record**, not the hardening. |
| Compiled binaries evaluation | **DONE** | `docs/PORTABILITY.md` and `docs/MULTILANG.md` already answer this, with measurements (commit `d4d3a72`). |
| Tests under `TESTS/**` | **DONE** | Phase 3. `git mv docs/TESTS TESTS`, with `tests_dir`'s default, `coverage.lua`, `cli.lua`, `ci.sh`, the workflow and six documents updated in lockstep. |
| GitHub Actions | **DONE** | `.github/workflows/ci.yml` — stylua, luacheck, tests, and a `map` drift job. |
| Commit & push | **DONE** | |
| Per-checklist `/docs/ROADMAP/*.md` battle plans | **DONE** | Phase 9. All three applied and written up; six open items fell out, consolidated in `Checklist.md`. |
| Walk `docs/ROADMAP.md` and produce a concrete plan | **DONE** | `ROADMAP.md` is already a curated open-items list with rejections recorded. |
| Evaluate `NEOTREE_FEATURES` folder | **DROPPED** | Follows the row above — no folder, no harvest, nothing to evaluate. |
| Verdict: usable as a Neotree *source*? | **DONE** | Phase 8. Feasible cheaply, not worth building — recorded in `ROADMAP.md` with the condition that would reopen it. |

---

## 2. The licence — decided, and what it means

`CHECKLIST.md` says *"Lizenzverweise löschen, keine Lizenz!"*, and that is what
this repo now does. Removed: the `LICENSE` file (MIT, © 2026), the `## License`
section in `README.md`, and the `License: MIT` line from the vimdoc credits
block. No licence reference remains in the tree.

Recorded here because it is a legal-posture change rather than a formatting one,
and the consequences should not have to be rediscovered:

- **The repo is public and was published under MIT.** Deleting the file does
  not retract the grant for code that was already released under it. Anyone who
  cloned before this commit keeps MIT terms for that snapshot; the history still
  contains the file.
- **From here on, "no licence" means all rights reserved.** Nobody may legally
  fork, vendor, redistribute or ship this as part of a distro-packaged config —
  for a plugin that plugin managers *clone*, that is stricter than it looks.
  Installation by an end user is fine; redistribution is not.
- **GitHub will show no licence** in the sidebar, and some users filter on it.

Reversible at any time by restoring the file — but the decision was made
deliberately, so reopening it needs a new reason, not just a reminder of the
above.

---

## 3. Implementation plan

Ordered so that each phase produces something checkable on its own, and so that
the phases that generate *documentation* run after the phases that change what
is being documented.

### Phase 0 — Repo metadata (5 min, no code)

Pure `gh` work, independent of everything else.

```bash
gh repo edit StefanBartl/documentation.nvim --description "Doxygen for annotated Lua trees: an interactive module map, drift checks, and an in-editor browser for any Neovim plugin."
```

```bash
gh repo edit StefanBartl/documentation.nvim --add-topic neovim,neovim-plugin,lua,documentation,documentation-generator,static-analysis,call-graph,dependency-graph
```

`--homepage`: leave empty until `scripts/publish_map.sh` actually publishes to
GitHub Pages; then point it at the published map, which is the single best
advert this plugin has.

### Phase 1 — Keymap configurability + which-key — **DONE** (2026-07-28)

Shipped as described below. What the implementation added beyond the plan:

- **A latent bug, surfaced by the change.** `bind()` built one options table
  (`local mo = { buffer = …, nowait = true }`) and passed it to every `map()`
  call. `lib.nvim.map` *mutates* what it is handed — it writes `desc`,
  `noremap`, `silent` and the normalised `buffer` back before calling
  `vim.keymap.set`. Harmless while no `desc` was ever set; the moment one is,
  every subsequent binding inherits the previous one's description. Fixed by
  building a fresh table per binding.
- **`?` became rebindable.** It used to be bound outside the `KEYS` loop
  because its handler renders the table it lives in. Forward-declaring
  `cheatsheet` removed the special case, so `help` is now an ordinary entry —
  previously the one key a user could not have changed.
- **The cheatsheet renders the *resolved* set**, not `KEYS`. Rendering
  defaults would have reintroduced the exact drift the shared table prevents,
  only invisibly: correct for an unconfigured user, quietly wrong for a
  configured one. The spec asserts the every-bound-key-is-documented
  invariant a second time *under overrides*, which is where that would show.
- **Unknown action names warn** rather than being ignored — a silently dropped
  override is indistinguishable from one that worked until the key is pressed.

Verified: all four `scripts/ci.sh` gates green (stylua, luacheck, tests, map
`--check`), with the map artifact regenerated for the new module.

Original plan, for the record:

This is one change, not three: `desc`, user override and which-key all hang off
the same `KEYS` table.

1. **Add `desc` to every binding.** In `bind()` (`browse/init.lua:1078`), pass
   `spec.desc` through to `map()`. Free, and it is what makes which-key,
   `:map` output and `nvim_buf_get_keymap` all useful at once.
2. **Make `KEYS` overridable.** Add to `Documentation.Opts`:
   ```lua
   ---@field keys? table<string, string|string[]|false> DocBrowse bindings, by action id. `false` disables the action's keys entirely; a string or list replaces them. Unlisted actions keep their defaults.
   ```
   This requires giving each `KeySpec` a stable `id` (`"enter"`, `"up"`,
   `"depth_inc"`, …) — the id is what a user's table keys on, and it is also
   what the cheatsheet and `docs/BINDINGS.md` can key on later. Resolve the
   merge in one place (a small `resolve_keys(opts)` next to `KEYS`) so the
   cheatsheet renders the *resolved* set, not the defaults — otherwise the
   plugin ships exactly the doc drift it exists to detect.
3. **which-key.** Opt-out via `opts.which_key ~= false`, registered only if
   `pcall(require, "which-key")` succeeds. Buffer-local `wk.add` with the
   resolved specs, grouped by mode. Keep it in its own file
   (`editor/browse/whichkey.lua`), lazily required, so nothing on the
   generate path pulls it in.
4. **Spec coverage.** `docmap_browse_spec.lua` already asserts every bound key
   appears in the `?` panel — extend that to the resolved set, plus one case
   each for override and `false`.

### Phase 2 — Structure: `config/` and `bindings/` — **DONE** (2026-07-28)

Shipped. Beyond the plan:

- **A behavioural bug, fixed by the split.** The old 700-line if-chain tested
  each action's full pattern in turn and fell through to the default —
  *regenerate the artifacts* — when none matched. So `:DocMap graph` with its
  argument missing, and any typo (`:DocMap wat`), silently rewrote files on
  disk and said nothing. Dispatch is now first-word lookup; only a genuinely
  empty argument regenerates, everything else reports what it expected.
- **`bindings/keymaps.lua` owns the override rule, not the bindings.**
  `:DocBrowse`'s `KEYS` table stayed in `browse/init.lua`, because every
  entry's `run` closes over that module's navigation state — moving it would
  have meant exporting a dozen internals purely so a second file could
  reference them, breaking the cohesion that makes the table trustworthy. What
  is generic (validate ids, replace, disable, never mutate the defaults) moved
  out and is now generic over any `{ id, keys }` table.
- **`bindings/autocmds.lua` is a manifest, not a relocation.** Centralising
  creation would be worse: each autocmd belongs to a lifecycle its own module
  owns (registry teardown, two `VimLeavePre` flushes, a buffer-scoped
  `CursorMoved`), and a shared augroup would cost `uninstall()` its precision.
  What was missing was an *account* of what the plugin installs, not a home.
  Wired into `:checkhealth`, which now reports "3 global, 1 buffer-local, all
  created lazily" plus "keymaps: none global" — and into Phase 4's generated
  `docs/BINDINGS.md`.
- **Both old paths kept as documented deprecated aliases**
  (`documentation.core.config`, `documentation.editor.command`), because
  `docs/REUSE.md` and `docs/PIPELINE.md` published them.

Found and **not** fixed here — spun out as its own task: the require-graph
extraction in `core/deps.lua` misses `pcall(require, "mod")`. The pattern
allows an optional `(` after `require` but cannot consume a comma, so optional
dependencies record no edge. Observed live — `health.lua` requires the autocmd
manifest that way and `:DocMap check` still calls it `unreferenced-module`.
It is a blind spot in the plugin's core promise, not in this refactor, and it
deserves its own spec rather than a drive-by.

Verified: all four gates green, map regenerated (46 → 55 files scanned).

Original plan, for the record:

Mechanical but touches many requires, so it goes before the doc-generation
phases.

- `lua/documentation/config/DEFAULTS.lua` — the literal default table, nothing
  else. `lua/documentation/config/init.lua` — `build()`/`__call`, i.e. what
  `core/config.lua` is today minus the table.
- Keep `core/config.lua` as a one-line re-export for one release; every internal
  require moves to the new path. Callers to update: `init.lua`,
  `editor/command.lua:73`, `editor/health.lua`, `scripts/gen_map.lua`,
  `core/cli.lua`, and the specs.
- `lua/documentation/bindings/usrcmds.lua` / `keymaps.lua` / `autocmds.lua`.
  `command.lua` is 732 lines because every `:DocMap` subcommand handler is
  inline; the honest split is one file per subcommand under
  `bindings/usrcmds/` with `usrcmds.lua` as the dispatcher. `keymaps.lua`
  becomes the home of the `KEYS` table and `resolve_keys` from Phase 1;
  `autocmds.lua` documents (and where practical, owns) the four autocmds.
- **Constraint:** `documentation.core.*` must not require
  `documentation.editor.*` or `documentation.bindings.*`. That layer rule is
  enforced by the plugin's own `layer-violation` check — configure
  `opts.layers` in this repo's own `scripts/gen_map.lua` so the check actually
  runs against the tree it describes.

### Phase 3 — Move tests to `TESTS/` — **DONE** (2026-07-28)

Done as planned. The spec fixture at `TESTS/docmap_spec.lua` that writes a
throwaway `demo_spec.lua` and lets `coverage.resolve` find it *through the
default* turned out to be the assertion that proved the move: it fails if any
one of the default, `coverage.lua` and the fixture disagree.

Original plan, for the record:

`git mv docs/TESTS TESTS`, then update in lockstep:

- `Documentation.Opts.tests_dir` default `"docs/TESTS"` → `"TESTS"`
  (`@types/init.lua:27`, `core/config.lua:72`)
- `core/coverage.lua` (the consumer of `tests_dir`)
- `scripts/ci.sh`, `.github/workflows/ci.yml`
- `docs/DEVELOPMENT.md`, `README.md`, `doc/documentation.txt`
- `TESTS/run.lua`'s own path assumptions

Then regenerate the map — the artifact records test coverage per function, so
`--check` will fail until it is regenerated. That is the check working, not a
problem.

### Phase 4 — Docs: bindings, install matrix, README polish — **DONE** (2026-07-28)

All four parts shipped. Notes:

- **`docs/BINDINGS.md` is generated**, by `bindings/docs.lua`, from
  `browse.keyspecs()` plus the two manifests in `bindings/autocmds.lua`.
  `browse` gained one narrow export for it: a *copy* of `KEYS`, so a caller
  cannot mutate the defaults every later browser is built from. The generator
  runs from `scripts/gen_map.lua` and is **skipped under `--check`** — a verify
  that rewrites a file is not a verify. Staleness is caught by a spec instead,
  which asserts every action id and every key appears in the rendered output,
  and that the documented-but-native `j`/`k` stay marked as such.
- **A layer rule I got wrong.** `editor -> bindings` was added alongside
  `core -> bindings` and immediately produced two warnings, both legitimate:
  `browse` requires `bindings.keymaps` (a utility over key tables, not the
  command surface) and the deprecated `editor/command.lua` shim delegates
  upward on purpose. The rule was removed; `core -> bindings` stays, and the
  reasoning is recorded in `scripts/gen_map.lua` so it is not re-added.
- **No coverage badge.** `opts.badge` is off for this repo, so `coverage.svg`
  is not committed — a badge pointing at a file that does not exist is worse
  than no badge. Turn `badge = true` on in `gen_map.lua` first if it is wanted.
- **`:DocMap helptags`** resolves `doc/` through `nvim_get_runtime_file`, not
  by walking up from its own file: the question is "where is the `doc/` Neovim
  will search", which is a runtimepath question, and a path derived from
  `debug.getinfo` would be right about the checkout and wrong about the
  installation whenever the two differ.

Original plan, for the record:

Runs after Phases 1–3 so it documents the final shape.

1. **`docs/BINDINGS.md`** — three tables: keymaps (from the resolved `KEYS`,
   with mode gating and the "documented, deliberately not bound" entries),
   usercommands (both commands with every subcommand and its completion),
   autocommands (all four, with the file and the reason each exists).
   *Generate it* from `KEYS` and the usercmd table rather than writing it by
   hand — a hand-maintained key list inside a drift detector is indefensible,
   and `scripts/gen_map.lua` is already the place where generated docs are
   written.
2. **Install matrix** in README + vimdoc: lazy.nvim (have), `vim.pack`
   (Neovim 0.12 built-in), mini.deps, packer, paq. Same lazy trigger in each.
3. **README head**: ASCII banner, then the blockquote pointer — the natural
   sibling is `lib.nvim` (hard dependency) or `insights.nvim` (closest in
   purpose), then badges: CI status, and the `coverage.svg` this plugin
   already knows how to render for itself.
4. **Helptags**: a tiny `M.helptags()` plus a `:DocMap helptags` action, or
   simply a documented `:helptags doc/` line in DEVELOPMENT.md. The plugin
   manager already does this on install, so this is a nicety — keep it small.

### Phase 4b — Health: the test wiring — **DONE** (2026-07-28)

Both checks shipped. `:checkhealth documentation` now reports:

```
info   tests_dir TESTS   (auto-derived fn.tested; override with opts.tests_dir)
ok     TESTS holds 4 .lua files scanned for function mentions
ok     headless runs resolve lib.nvim via $LIB_NVIM_DIR
```

One correction worth recording, because the first version of the message was
wrong: `coverage.lua`'s `lua_files` filters on the `.lua` extension **alone** —
it does not look for `*_spec.lua`. A helper or fixture under `tests_dir`
contributes mentioned names exactly like a spec does, so the health check
counts `.lua` files, not spec-shaped names, or it would report a smaller number
than the coverage figure is actually derived from.

Original plan, for the record:

Not "run the suite from `:checkhealth`" — that stays rejected, for the reasons
in the audit table. What goes in is the wiring, in the existing *resolved
configuration* section, right after `out_dir`:

1. **Print `tests_dir` and say what is under it.** This is the item that
   matters. `coverage.lua` treats a missing `tests_dir` as "nothing is tested"
   rather than as an error, by design — so a wrong path renders an Analysis tab
   claiming 0% test coverage for the whole tree, which reads as a badly tested
   repository instead of a misconfiguration. Exactly the class of failure the
   file's own header says it exists for ("make a command silently do the wrong
   thing"), and `tests_dir` is currently not printed at all. Three states:
   directory missing → `warn` naming the consequence; present but no
   `*_spec.lua` → `warn`; present with specs → `ok` with the count.
2. **Check lib.nvim the way the runner resolves it**, not the way the editor
   does. `health.lua` currently answers "is lib.nvim on the rtp *now*", which a
   plugin-manager install satisfies; `TESTS/run.lua:22` looks at
   `LIB_NVIM_DIR`, `.deps/lib.nvim` and the sibling directory instead. A dev can
   pass the current check and still have `scripts/ci.sh tests` fail on the first
   line. One `info`/`warn` under the optional-tools section.

Ordering: do this together with Phase 3, since the `tests_dir` default changes
from `docs/TESTS` to `TESTS` there and this check is what would catch a missed
call site.

**Related, but not health:** if "run the tests and see the result" is wanted
from inside the editor, its home is a `:DocMap test` action that spawns the
headless runner via `vim.system` and reports the tally — an action that runs a
process, next to the other actions that run processes (`diff`, `impact`,
`churn`, `serve`), not a health check that is supposed to be instant and
side-effect-free.

### Phase 5 — Cross-platform tooling — **DONE**

`scripts/ci.lua` holds every gate definition now; `scripts/ci.sh` is the
thin wrapper the plan asked for ("A wrapper, not the definition" — its own
header comment). `scripts/hooks/pre-commit` stayed `sh`, documented in
`DEVELOPMENT.md`'s own Windows section alongside `scripts/publish_map.sh`.

### Phase 6 — Security audit record — **DONE**

[`docs/SECURITY.md`](../SECURITY.md) covers the localhost-only bind, the
SHA validation regex (`safe_sha`, `^%x%x%x%x%x%x%x+$`), argv-not-shell for
every git call, `opts.tag_files`'s hostile-path handling, and what is
deliberately not defended against. `serve.lua`'s own exported validator is
exercised by the existing `docmap_browse_spec.lua`/`docmap_spec.lua`
coverage rather than a fully separate one-spec-per-property file, which is
narrower than this entry originally asked for but covers the same
properties in practice.

### Phase 7 — Central cheatsheets + collision check — **DONE**

`nvim/docs/NOTES/PersonelPlugins/BINDINGS/{Keymaps,Usercmds,Autocmds}/documentation.nvim.md`
all exist. Feeds `nvim/docs/NOTES/PersonelPlugins/`. Do it after Phase 4, because
`docs/BINDINGS.md` is then the source to copy from:

- append this plugin's entries to `BINDINGS/Keymaps.md`, `Usermcds.md`,
  `Autocmds.md`, and its non-binding surface (the `?` overlay, the filter DSL,
  trail persistence, the HTTP server) to `Misc.md`;
- run the actual `lhs` collision check across the other personal plugins. Only
  the two global command names can really collide; note the buffer-local
  `nowait` scope in the cheatsheet so the next audit does not redo the analysis.

### Phase 8 — Neotree-source verdict (one paragraph) — **DONE**

Written up in `ROADMAP.md`'s own "Neotree source — feasible, and not worth
it" entry (assessed 2026-07-28). The filetree.nvim feature harvest and
`NEOTREE_FEATURES.md` were **cut by the
author** (2026-07-28) and are not part of this plan. What remains is the
separate `FINISH_ME.md` question — *is this plugin worth using as a Neotree
source?* — which is a short written verdict, not an inventory.

The material for it, so the assessment does not have to be re-derived:
feasibility is not the interesting half. The IR is already a tree of nodes with
stable ids, parents, children and depth (`Documentation.Node`), which is the
shape a Neotree source hands over, and `install()` already provides a live,
rescanning handle with `on_change` subscribers — the update channel a source
needs. So it is an adapter, not new analysis. Write the verdict on whether it is
*worth* it (does a module tree beside a file tree earn its window?), and record
the "no" just as fully as a "yes" — `ROADMAP.md`'s existing convention.

### Phase 9 — The three external checklists — **DONE**

All three output files exist: `docs/ROADMAP/ARCH_AND_CODING.md`,
`docs/ROADMAP/Zentral-Prinzipien.md`, `docs/ROADMAP/Checklist.md`. Applied
each separately, one output file per checklist, as `FINISH_ME.md`
specified:

- `E:/repos/Notes/MyNotes/Checklists/Lua/Arch&Coding-Regeln.md` →
  `docs/ROADMAP/ARCH_AND_CODING.md`
- `.../Zentrale-Prinzipien.md` → `docs/ROADMAP/Zentral-Prinzipien.md`
- `.../Checklist.md` → `docs/ROADMAP/Checklist.md`

Last on purpose: they audit the code, and Phases 1–3 change the code's shape.

---

## 4. Suggested order

| Order | Phase | Why here |
|---|---|---|
| — | *Licence removal* | **Done**, 2026-07-28. See §2. |
| — | 0 — repo metadata | **Done**, 2026-07-28. Description + 10 topics; homepage left empty on purpose. |
| — | 1 — keymaps + which-key | **Done**, 2026-07-28. Largest behavioural change; everything documented later depends on its final shape. |
| — | 2 — `config/` + `bindings/` | **Done**, 2026-07-28. Structural; touches many requires, so before docs. |
| — | 3 + 4b — `TESTS/` move, health test-wiring | **Done**, 2026-07-28. Mechanical, and it invalidates the artifact — batch it with the other artifact-invalidating work. 4b rides along because it is what catches a missed `tests_dir` call site. |
| — | 4 — docs (BINDINGS, install matrix, README) | **Done**, 2026-07-28. |
| — | 5 — cross-platform scripts | **Done**, 2026-07-28. Independent; can slot anywhere after 3. |
| — | 6 — security record | **Done**, 2026-07-28. Pure writing over already-correct code. |
| — | 7 — central cheatsheets | **Done**, 2026-07-28. Copies from Phase 4's output. |
| — | 8 — Neotree-source verdict | **Done**, 2026-07-28. One paragraph, best written on the settled tree. |
| — | 9 — three external checklists | **Done**, 2026-07-28. Audits the finished shape. |

## 5. What this repo is already ahead on

Worth recording so these do not get re-opened by a future pass: `:checkhealth`
(thorough, and it targets the actual failure mode — the wrong root), typed and
documented options end to end, four-job CI including a self-drift check, a
substantial test suite, a curated roadmap that records rejections, the
portability/binary evaluation already measured rather than guessed, and a
security posture that was designed rather than retrofitted.
