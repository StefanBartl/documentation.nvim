# Merge checklist — applied to documentation.nvim

An audit against `E:/repos/Notes/MyNotes/Checklists/Lua/Checklist.md`: the
10-point quick check, the PR-review detail tables, the anti-pattern check and
the import/file-structure check.

Assessed 2026-07-28. English, like the rest of `docs/`. The algorithm and
bit-trick sections of the source checklist are not reproduced — nothing in this
plugin implements a sort, a balanced tree or a bit trick, so there is nothing to
check against them.

Companion audits: [`ARCH_AND_CODING.md`](ARCH_AND_CODING.md) (the coding rules) and
[`Zentral-Prinzipien.md`](Zentral-Prinzipien.md) (the ten-question pass).

---

## Quick check (10 points, before every merge)

| Status | Check | Verdict |
|---|---|---|
| ✅ | Error handling present | 🔴 CRITICAL — `pcall` at every external boundary (17 files); nothing fails silently. A failed LuaLS run becomes an info-severity *finding*, not a swallowed error. No central `safe_call`, deliberately: `Documentation.Finding[]` already **is** the domain error channel, and a second one would mean two ways to say "something went wrong". |
| ✅ | Type guards | 🔴 CRITICAL — the boundaries that matter (`safe_sha`, `safe_static_name`, every `pcall`-wrapped decode) plus, since item **A**, the whole published Lua API: `scan_full`, `generate`, `write_artifacts`, `install`, `browse.open`, `registry.install`, `scan`. |
| ✅ | Validate buffer/window | 🔴 CRITICAL — `is_valid()` before every use; `nvim_buf_is_valid` before the DOT-buffer wipe; `M.is_open()` re-checks the slot. |
| ✅ | No global state | 🔴 CRITICAL — luacheck clean over 58 files, no `_G.*`. Two documented module-level singletons (`browse.state`, `serve.current`), each because two of that thing on screen would fight over the same keys or the same lifecycle. |
| ✅ | Single responsibility | 🔴 CRITICAL — the one violation, a 732-line `command.lua`, was split into `bindings/usrcmds/` (one file per action) on 2026-07-28. |
| ✅ | UI cleanup | 🟡 — `browse.close()` is idempotent, unsubscribes and closes the group; `registry.uninstall` and `serve.stop` are the equivalents, both idempotent. |
| ✅ | Performance hotspots | 🟡 — `table.concat` + `put()` buffer in all 23 files that build strings; no concatenation in a loop anywhere. Tables are not pre-sized, because the scan's sizes are not knowable in advance. |
| ✅ | Annotations complete | 🟡 — `@module` on **every** tracked file (verified); 216/272 published functions fully documented (79%), measured by the plugin's own `doc-coverage` check against its own tree. |
| ✅ | Testability | 🟡 — the pure/impure split is the architecture. `diff`, `history`, `churn`, `duplicates`, `trail`, `view` and every renderer are pure. `snapshot()`/`SNAP_KEYS` give snapshot-restore. |
| ⚠️ | Import order | 🟢 — imports are hoisted and alphabetical per file, not ordered System → Debug → Utils → State → UI → Controller → Keymaps. See the note under *Import & file structure*. |

**Bonus — use the `lib` library:** verified by grep, 12 modules in use.
`lib.notify` everywhere (no bare `vim.notify` in `lua/`), `lib.map` everywhere
(no bare `vim.keymap.set`), `lib.usercmd`, `lib.autocmd`, `lib.debounce`,
`lib.cross.uv.spawn_capture`, `lib.ui.kit`, five `lib.fs` modules. Not used:
`lib.hover_select` — which **no longer exists**, having been absorbed into
`kit.chooser`; see item **Y** — `lib.lazy` (the
`__index` proxies achieve it with no dependency), `lib.memo` (nothing to
memoise).

---

## PR review detail

### 1. Safety and error handling

| Check | State |
|---|---|
| pcall/xpcall | ✅ every critical call |
| Structured errors | ⚠️ **not** as error *types* — as `Documentation.Finding[]` with `severity`/`check`/`node`/`message`, which is richer and is what the UI, the quickfix list and CI all consume. Revisit only if a caller needs to branch on an error kind; none does. |
| Explicit returns, no low-level notify | ✅ **verified** — `grep -rln notify lua/documentation/core/` returns nothing. |
| Guards before API | ✅ item **A**, done. |

### 2. Modularity and structure

| Check | State |
|---|---|
| Single responsibility | ✅ |
| No globals | ✅ |
| Pure functions | ✅ strongly |
| Internal helpers local | ✅ — two narrow exports exist *because* they are security properties that must be testable without a socket, and both say so. |
| Tools/registry | ✅ `editor/registry.lua`, keyed by normalised root |
| `/config` folder with `DEFAULTS.lua` | ✅ shipped 2026-07-28 — `config/DEFAULTS.lua` (data only) + `config/init.lua` (derivation + merge) |

### 3. Buffer/window management

All ✅: handles bound first then validated, `is_valid` before every API call, a
uniform API through `lib.nvim.ui.kit` rather than hand-rolled windows, and
idempotent cleanup. **Race conditions:** deferred callbacks re-validate — the
`on_change` subscriber checks `M.is_open()` before touching state, and
`CursorMoved` does the same.

### 4. UI state management

| Check | State |
|---|---|
| Central `ui_state` with getters/setters | ⚠️ adapted — the state table lives in `browse`, the only module that reads it. A separate module would split state from its sole consumer for no gain. |
| Snapshot/restore | ✅ `snapshot()` + the `SNAP_KEYS` history stack, which is also what `<C-o>`/`<C-i>` walk. |

### 5. Documentation and annotations

Header tags ✅, function tags ✅, aliases and `@field` instead of inline
monsters ✅ (`@types/init.lua` is exemplary: every option typed *and* its
default stated in the field text). Comment convention (`#` in `@alias`) ✅ —
used in `Documentation.Kind` and `Documentation.Browse.KeyAction`.

### 6. Testability

DI ✅ — `Documentation.Opts` is injected everywhere; nothing reads a global
config. Pure functions ✅. Test entry ✅ — `TESTS/run.lua`.

### 7. Tooling

| Check | State |
|---|---|
| Lua LS settings | ✅ `.luarc.json` with `diagnostics.globals = ["vim"]` |
| Formatter/linter in CI | ✅ stylua + luacheck, plus tests and a self-drift `map` gate — four jobs in `.github/workflows/ci.yml`, all defined once in `scripts/ci.lua` |

---

## Anti-pattern check

| Pattern | Present? |
|---|---|
| Global state | ❌ none |
| API without guards | ❌ none found |
| String concat in a loop | ❌ none — verified by grep |
| Closures in a loop | ⚠️ one shape: `bind()` creates one closure per binding. That is ~25 closures created **once**, at mount, not per event — not a hot path. The frequent-event handler (`CursorMoved`) is a single closure created once. |
| Many small temporary tables | ⚠️ the scan allocates per file. Inherent to building an IR; a table pool would trade clarity for an allocation count that has never shown up as a problem. |

## Import & file structure

| Point | State |
|---|---|
| Import order | ⚠️ alphabetical, hoisted to the top of each module — not the checklist's seven-stage order. **Deliberate:** most modules here import 2–5 things, and a seven-stage convention over three requires is ceremony that makes a missing import harder to spot, not easier. Alphabetical is mechanically checkable; the staged order is not. Recorded rather than adopted. |
| File header | ✅ `@module` + description on every file |
| Project-wide `@types` folder | ✅ item **C**, done — four now (`documentation/`, `core/`, `bindings/`, `editor/browse/`). One documented exception: `Browse.KeySpec` stays beside the `KEYS` table it types. |

---

## Consolidated open items — all closed (2026-07-29)

The six items this audit and its companions produced are done.

- **A — argument checks on the published API.** ✅ One `assert_opts` helper in
  `documentation/init.lua`, applied to `scan_full`, `generate`,
  `write_artifacts` and `install` (`browse.open`, `registry.install` and
  `scan` already asserted). Deliberately *only* at that boundary: inside the
  pipeline LuaLS already catches a wrong argument from the annotations, and
  asserts on 270 internal functions would be noise that never fires. What LuaLS
  cannot see is a caller outside this repository. Verified — `generate(nil)`
  now says "opts must be a table, got nil" instead of indexing nil three frames
  deep.
- **B — `@raises` on the functions that raise.** ✅ Four of them, which is all
  there are: `assert_opts`, `scan_full`, `write_artifacts`, `generate`,
  `install`. Everything else returns `ok, err`, which is the better shape and
  needs no tag — the point of the item was to make the annotation say which is
  which.
- **C — per-level `@types`.** ✅ `core/@types/` (churn, duplicates) and
  `bindings/@types/` (Ctx, AutocmdInfo) created; the browse types (Filter,
  FilterTerm, Pin) moved into the `browse/@types/` file that already existed.
  One exception, stated in `bindings/@types`: `Documentation.Browse.KeySpec`
  stays beside the `KEYS` table it types, because the prose attached to it
  explains the *table* — why `only` is presentation rather than a binding
  condition, why `run == nil` means "documented, deliberately not bound" — and
  splitting that from what it explains would cost more than consistency gains.
- **D — READMEs for `core/` and `editor/`.** ✅ Both written. `core/`'s states
  the IR contract, the enforced layer rules and why determinism forbids git
  data in the IR; `editor/`'s states why the registry is the coordination point
  and where every side effect lives.
- **X — a debug switch.** ✅ `opts.debug` plus `core/timing.lua`. The split is
  the point: `core` **collects** durations, `bindings/usrcmds/generate.lua`
  **reports** them — so the no-notify-in-core rule survives. Off by default and
  free when off (`measure` is a direct call, no clock read). First run on this
  tree: `scan` 357 ms (88.5%), `coverage` 35 ms, `check` 8 ms, everything else
  under 2 ms.
- **Y — `lib.hover_select` vs `kit.chooser`.** ✅ Resolved, and the premise was
  stale: **`lib.nvim.ui.hover_select` no longer exists.** Its own successor
  says so — `lib.nvim.ui.kit.select`'s header records that the chooser
  "absorbed and replaced the former lib.nvim.ui.hover_select module (now
  removed)". So there was nothing to migrate to.

  But looking produced a real finding. This plugin was already on `kit.select`,
  yet passed no `respect_override`, so a user with telescope-ui-select, fzf-lua
  or dressing installed got kit's own chooser instead of their configured
  picker. Now set on both trail pickers, which are exactly the case it is for:
  a plain list of names with no rendering the browser's theme contributes
  anything to. The browser's own panes stay kit-themed — they are the view, not
  a prompt over it.

## What the original list said


This audit produced no new items — the four from
[`ARCH_AND_CODING.md`](ARCH_AND_CODING.md) and two from
[`Zentral-Prinzipien.md`](Zentral-Prinzipien.md) cover everything it found:

- **A** — argument type checks on the published API surface (`generate`,
  `install`, `uninstall`, `setup`, `scan_full`).
- **B** — `@raises`/`@error` on the few functions that actually raise.
- **C** — `@types` files for `core/` and `bindings/`.
- **D** — READMEs for `core/` and `editor/` (the plugin's own `missing-readme`
  check already reports both, at info severity).
- **X** — a debug switch (`opts.debug`): per-stage timing, collected in `core`,
  reported from `bindings`.
- **Y** — decide between `lib.hover_select` and `kit.chooser`, and make the
  answer the same across the personal plugins.

Deliberately rejected, with reasons stated above and in the companion files:
`safe_call`/structured error types, weak-table memoisation, pre-sized tables, a
separate `ui_state` module, and the seven-stage import order.
