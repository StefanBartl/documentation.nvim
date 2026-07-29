# Arch & Coding rules — applied to documentation.nvim

An audit against `E:/repos/Notes/MyNotes/Checklists/Lua/Arch&Coding-Regeln.md`,
section by section, with the evidence and the gaps that are worth acting on.

Written in English like the rest of `docs/`. Assessed 2026-07-28.

Verdict up front: the tree already follows most of this, in several places more
strictly than the rules ask. **Four items are worth doing** and are collected at
the bottom; everything else is either satisfied or does not apply to a plugin of
this shape, and the reason is recorded so it does not get re-litigated.

---

## 1. Safety & error handling

| Rule | State | Evidence |
|---|---|---|
| Prefer `pcall` | **holds** | 17 files use it. Every external boundary is wrapped: `vim.json.decode`, `vim.treesitter.get_string_parser`, `nvim_buf_set_name`, `require` of optional modules, the LuaLS subprocess. |
| Type guards before API access | **mostly** | `safe_sha`/`safe_static_name` type-check; `browse.open` asserts `opts.root`. See gap **A**. |
| Explicit returns, no silent failures | **holds** | `write()` returns `ok, err`; `luals.run` returns `doc, err`; the CLI returns an exit code. A failed LuaLS enrichment becomes an info-severity *finding* rather than a swallowed error — the strongest example in the tree. |
| No `notify()` in low-level code | **holds, verified** | `grep -rln notify lua/documentation/core/` returns **nothing**. Notification lives in `editor/` and `bindings/` only. This is exactly the rule, and it is enforced structurally rather than by habit. |
| Standardised error wrapping (`safe_call`) | **not adopted** | Deliberate — see the note below. |
| Structured error types | **not adopted** | Deliberate — see the note below. |
| `@error` / `@raises` tags | **gap** | See gap **B**. |
| Private functions stay local | **holds** | Module-level `local function` throughout; the public surface is the returned `M`. Two narrow exports exist *because* they are security properties that must be testable (`safe_sha`, `safe_static_name`) and both say so in their doc comment. |

**On `safe_call` and structured error types.** Not adopted, and this is a
decision rather than an omission. The plugin already has a *domain* error
channel that is richer than either: `Documentation.Finding[]`, with `severity`,
`check`, `node` and `message`. Everything a user needs to act on arrives through
it, gets tallied, and lands in the quickfix list. Adding a second, parallel
error representation for the handful of internal boundaries — all of which are
already `pcall`-wrapped and turn into findings — would mean two ways to express
"something went wrong" in one codebase. Revisit only if a caller ever needs to
*branch* on an error kind; nothing does today.

## 2. Modularisation

| Rule | State | Evidence |
|---|---|---|
| One module, one responsibility | **holds** | `scan` / `check` / `render/*` / `diff` / `history` / `churn` are each one job. The 732-line `command.lua` was the one violation and was split into `bindings/usrcmds/` (one file per action) on 2026-07-28. |
| Prefer pure functions | **holds, strongly** | `diff.lua`, `history.lua`, `churn.lua`, `duplicates.lua`, `browse/trail.lua`, `browse/view.lua` and every renderer are pure — IR in, structure or string out. The purity is load-bearing: it is what lets the whole browser model be driven from a headless spec. |
| Local over global functions | **holds** | luacheck runs clean over 58 files with no global writes. |
| Design patterns where useful | **holds** | Registry (`editor/registry.lua`), observer (`handle.on_change`), lazy proxy (`__index` metatables in `init.lua`), dispatch table (`ACTIONS`). |
| Tools via a registry | **holds** | `editor/registry.lua`, keyed by normalised root. |
| No global state | **mostly** | Two module-level singletons: `browse.state` and `serve.current`. Both are deliberate and documented — two browsers on screen would fight over the same keys, and two servers would fight over lifecycle. Explicit state is threaded everywhere else. |

## 3. Buffer & window management

| Rule | State |
|---|---|
| Assign first, then check | **holds** — the `slot()`/`group.slots` pattern, with `is_valid()` before use. |
| `nvim_*_is_valid()` guards | **holds** — `M.is_open()` checks `state.slots.list:is_valid()`; `dot.lua` checks `nvim_buf_is_valid` before deleting. |
| Uniform UI methods | **holds** — delegated to `lib.nvim.ui.kit` (`layout.mount`, `viewer`, `chooser`) rather than hand-rolled. |
| State via a `ui_state` module | **adapted** — the state table is `browse`'s own; a separate module would split it from the only code that reads it. |
| `cleanup_all()` | **holds** — `M.close()` is idempotent, unsubscribes and closes the group; `registry.uninstall` and `serve.stop` are the equivalents for their surfaces. |

## 4. Methods, metatables, data models

Metatables are used where they earn it and nowhere else: the lazy-require
proxies in `init.lua`, the callable `config(root)` form, the `CLEAR` sentinel in
`browse`. No `UndoStack`-style OO layer, because nothing here has that shape —
the IR is data, and the functions over it are pure.

## 5. Documentation & annotations

| Rule | State | Evidence |
|---|---|---|
| Every file starts with `@module` | **holds, verified** | Checked across every tracked `.lua` under `lua/` — **zero** files missing it. |
| `@param` / `@return` per function | **holds** | And *machine-checked*: this plugin's own `doc-coverage` finding runs against its own tree — currently 216/272 published functions fully documented (79%). |
| Consistent English naming | **holds** | snake_case throughout, English throughout. |
| Explicit typing | **holds, strongly** | `@types/init.lua` types every option and every IR node field, with the default stated in the field text. |
| `@see` module links | **partial** | Cross-references are written as prose and Markdown links in headers rather than as `@see` tags. Equivalent information, different notation. Not worth a mass edit. |
| A `@types` file per level | **partial** | Two exist: `documentation/@types/` and `editor/browse/@types/`. See gap **C**. |
| README per module | **partial** | Four: root, `config/`, `bindings/usrcmds/`, `editor/browse/`. `core/` and `editor/` have none; the `missing-readme` check reports these as *info*, which is the right severity. See gap **D**. |
| German README + English vimdoc | **N/A** | That rule is scoped to `nvim/config` modules. This is a published plugin: English throughout is required by the other checklist, and `doc/documentation.txt` exists. |

## 6. Testability & readability

| Rule | State |
|---|---|
| Small, focused (SRP) | **holds** after the `usrcmds` split. |
| Clarity over brevity | **holds** — the comment density here is unusually high and explains *why*, not *what*. |
| Testability by design | **holds** — the pure/impure split is the whole architecture. `history`, `diff` and `churn` are testable without git; `trail` and `view` without a window. |
| Snapshot/restore | **holds** — `browse.snapshot()` + the `SNAP_KEYS` history stack. |
| Separate test entry | **holds** — `TESTS/run.lua`, headless, four gates behind `scripts/ci.lua`. |

## 7. Error handling & validation (security)

Covered by §1 and by [`docs/SECURITY.md`](../SECURITY.md), which is the audit
record for the server, the subprocess rule (`vim.system` argv only — no
`io.popen`, no `os.execute`, no shell anywhere in `lua/`, verified by grep) and
the escaping in the generated page.

## 8. Performance & memory

| Rule | State | Evidence |
|---|---|---|
| Debounced writes | **holds** | `lib.nvim.debounce` on the watch autocmd (`opts.watch_ms`, default 500). |
| Async instead of blocking | **partial, deliberate** | The scan is synchronous. It has to be: `--check` must be deterministic and the CLI exits on its result. The one genuinely slow path (`lua-language-server`) is opt-in *and* timeout-bounded. |
| `table.concat` over `..` in loops | **holds, verified** | 23 files use `table.concat`; the `put()`-into-a-buffer pattern is used in every renderer and in `to_json`. No `s = s .. x` in a loop anywhere. |
| Local aliases | **holds** | Requires are hoisted to file-local names at the top of each module. |
| Weak tables / memoisation | **not used** | Correct for this shape: the IR is built once per scan and handed over. There is no repeated-lookup hot path to memoise, and a weak cache over a structure that is replaced wholesale each rescan would add a failure mode for no gain. |
| Explicit `collectgarbage()` | **not used** | Right call. The IR's lifetime is the handle's; forcing a collection would be guessing at the allocator. |
| Pre-sized tables | **not used** | The scan's sizes are not known in advance. Would be measurable only on trees far larger than any this targets. |

## 9–11. Caching, weak tables, special cases

Not applicable as written — see the weak-table note above. The one caching
decision that *was* made is recorded instead: `browse` caches the commit list
per session (`st.commits`), because re-running `git log` on every `5` keypress
would make the mode feel slower than it is.

---

## What is actually worth doing — **all four done** (2026-07-29)

See `Checklist.md` for what each closure actually looked like. Kept as written
below, because the reasoning for *why* each was worth doing is the record.

**A — Argument type checks at the published boundary.** The rule asks for a
check on every argument. Applying that literally to ~270 functions would bury
the code in asserts that only ever fire during development, when LuaLS already
catches the same mistakes from the annotations. The defensible subset is the
*published* surface — `generate`, `install`, `uninstall`, `setup`, `scan_full`
— where a caller outside this repo can pass anything. `browse.open` already
asserts `opts.root`; the others do not. Small, and it makes the failure message
name the caller's mistake instead of erroring three frames deep.

**B — `@raises` / `@error` on the functions that actually raise.** Few do:
`write_artifacts` calls `error()` on a failed write, `browse.open` asserts. Most
return `ok, err` instead, which is the better shape and needs no tag. Worth
tagging the handful that raise, so the annotation says which is which.

**C — A `@types` file for `core/` and `bindings/`.** Both currently borrow
`documentation/@types/init.lua`. That is not wrong — the types are genuinely
shared — but `Documentation.Bindings.Ctx` and
`Documentation.Bindings.AutocmdInfo` are declared inline in their modules today,
which is inconsistent with how every other type in the tree is declared. Move
them into per-level `@types` files.

**D — READMEs for `core/` and `editor/`.** The plugin's own `missing-readme`
check reports both, at info severity. `core/` is the more valuable of the two:
it is the pipeline, and its README should state the IR contract and the
pure/impure split that the layer rule enforces.

Explicitly **not** doing: `safe_call`/structured error types (§1), weak-table
memoisation (§8), pre-sized tables (§8), a separate `ui_state` module (§3).
Each has its reason above.
