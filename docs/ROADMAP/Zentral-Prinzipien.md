# Central principles — applied to documentation.nvim

An audit against `E:/repos/Notes/MyNotes/Checklists/Lua/Zentrale-Prinzipien.md`
— the ten-question mental pass, answered honestly for this plugin.

Assessed 2026-07-28. English, like the rest of `docs/`.

The checklist's own framing: *"if several points answer yes, a structural change
is usually worth it."* Here **two** answer yes, and both are recorded at the
bottom. The rest answer no, several of them because the structure this plugin
already has was chosen for exactly these reasons.

---

## lib.nvim adoption (the checklist's opening requirement)

Verified by grep, not by memory. Twelve modules in use:

```
lib.nvim.autocmd                       lib.nvim.fs.open.url.system_opener
lib.nvim.cross.uv.spawn_capture        lib.nvim.fs.read
lib.nvim.debounce                      lib.nvim.map
lib.nvim.fs.collect_recursive          lib.nvim.notify
lib.nvim.fs.is_subpath                 lib.nvim.ui.kit
lib.nvim.fs.mkdirp                     lib.nvim.usercmd
```

- **`lib.notify` instead of `vim.notify`/`print`** — holds. No direct
  `vim.notify` call anywhere in `lua/`; two prefixed instances exist
  (`[documentation]` for the commands, `[DocBrowse]` for the browser).
- **`lib.map`, `lib.usercmd`, `lib.autocmd`** — holds. No direct
  `vim.keymap.set` anywhere. Three raw `nvim_create_autocmd` calls remain, each
  for a stated reason (see §4).
- **`lib.cross`** — used for `spawn_capture`. Cross-platform otherwise holds by
  construction: no `io.popen`, no `os.execute`, no `/tmp`, no `$HOME`; paths
  normalised with `gsub("\\", "/")` at every entry point.
- **`lib.hover_select`** — **not used.** See item **Y** below.
- **`lib.lazy`** — not used as a module; the same effect is achieved with
  `__index` metatables and thunked requires. Equivalent result, no dependency.
- **`lib.memo`** — not used. Nothing here has a repeated-lookup hot path; see
  §7.

---

## 1. Bundle events, decouple logic — **no**

Four autocommands total, on four different events, in four different modules.
None duplicates another, and none of them is a shared event several modules
race on. The manifest in `bindings/autocmds.lua` states the whole surface, and
`:checkhealth` prints it — which is the transparency this question is really
asking for.

## 2. Load own logic lazily — **no, this is already the design**

Nothing loads at startup. `require("documentation")` registers no command and
installs no autocmd; `documentation/init.lua` puts `browse`, `diff`, `cli` and
`history` behind `__index` metatables; the `ACTIONS` dispatch table holds thunks
rather than module paths, so `:DocMap check` never loads the churn, diff or DOT
code; `whichkey.lua` is required from `bind()` only.

## 3. Context instead of repeated API access — **no**

The IR *is* the context object, built once per scan and threaded everywhere.
`Documentation.Bindings.Ctx` is the same idea for the command layer: `cfg`,
`handle`, `notify`, `open_map`, `find_node`, built once in `setup()`.

## 4. Autocommand groups used cleanly — **no, but worth knowing why**

Each autocmd is deletable and re-initialisable, and each is scoped to a
lifecycle its owner controls. The registry deliberately uses a **raw**
`nvim_create_augroup` rather than `lib.nvim.autocmd.group()` — the group is
per-handle so `uninstall()` can be precise, and the helper's name→id cache has
no visibility into a second handle for the same name. That reasoning is in the
code at the call site.

Reload without restart works: `registry.uninstall` and `serve.stop` are
idempotent, and `usercmd.create` defaults to `force = true`.

## 5. Event or command? — **no**

Almost everything here is a command. The only event-driven work is the watch
rescan, which is **opt-in** (`opts.watch`, default false), debounced, and
filtered by `is_subpath` before doing anything.

## 6. Treesitter necessary? — **no, genuinely required**

Not pattern-matching dressed up. `functions.lua` needs the parse tree for
function spans (`line`/`line_end` — what `impact` maps diff hunks onto),
`calls.lua` resolves `local x = require(...)` aliases before matching call
sites, `duplicates.lua` compares parse-tree *shapes*, and `complexity` counts
branch nodes. None of that is reachable with a line scan. And it does not run in
a frequent event — it runs on an explicit `:DocMap` or a debounced write.

The one place a regex *is* used instead is `deps.extract_source`, deliberately:
it runs before the parse so a file treesitter cannot parse still contributes its
dependencies. (It has a known blind spot — `pcall(require, "x")` — tracked
separately.)

## 7. Cache present and explicit? — **no**

One cache: `st.commits`, the git log, per browser session — because re-running
`git log` on every `5` keypress would make the mode feel slower than it is. It
is regenerable (close and reopen) and lives in runtime state, not on disk.

The checklist asks for caches in `stdpath("cache")`. The one thing this plugin
*does* persist — saved trails — is in `stdpath("state")`, which is correct: it
is user intent, not a recomputable cache, and losing it would lose data rather
than cost a recomputation.

## 8. Allocations in the hot path — **no**

No string concatenation in loops anywhere; every renderer uses the
`put()`-into-a-buffer + `table.concat` pattern (23 files). The hot path proper
is the scan, which allocates per file once. Closures in frequent paths: the
`CursorMoved` handler is one closure created once at bind time, not per event.

## 9. Debuggability — **yes, partly.** See item **X**

Strong: `:checkhealth documentation` prints the resolved configuration, the
artifact state, the autocmd surface and the test wiring. Control flow is
traceable, and the pure/impure split means most of it can be exercised
headlessly.

Missing: **there is no debug switch.** When a scan produces a surprising result
the options are "read the artifact" or "add a print". Every other question in
this section answers well, so this one stands out.

## 10. Runtime over startup — **no**

The only frequent-event code is the browser's `CursorMoved`, which is minimal
and deterministic: an `is_open()` check and a re-render of one pane. Startup
cost is zero by construction (§2).

---

## Kurzform, answered

| Question | Answer |
|---|---|
| When does it run? | On an explicit command; optionally on write, debounced and opt-in. |
| Must it run now? | No — nothing runs at startup. |
| Does it load more than needed? | No — lazy proxies and thunked requires throughout. |
| Does it run more often than needed? | No — one cached git log, one debounce. |
| Is work repeated? | No — the IR is built once and threaded. |
| Is the data flow clear? | Yes — scan → IR → check → render, with the IR as the stated contract. |

---

## What is actually worth doing — **both done** (2026-07-29)

See `Checklist.md` for the closures. Item Y's premise turned out to be stale:
`lib.nvim.ui.hover_select` no longer exists — `kit.chooser` absorbed it. The
real finding was that this plugin passed no `respect_override`, so a user's
configured picker was ignored for two plain name lists. Fixed.

**X — A debug switch.** The one weak answer in §9. Concretely: an
`opts.debug` (or `$DOCUMENTATION_DEBUG`) that turns on timing per pipeline stage
and a count per finding kind, routed through the existing `lib.nvim.notify`
instances so it obeys the no-notify-in-`core` rule — meaning the timing is
collected in `core` and *reported* in `bindings`. Cheap, and it turns "the scan
felt slow" into a number.

**Y — Evaluate `lib.hover_select`.** The browser uses `lib.nvim.ui.kit`'s
`chooser` for trail load/delete and the fuzzy jump. The checklist wants
`hover_select` as the consistent selection UI across all personal plugins. These
may already be the same thing, or `kit.chooser` may be the richer one — worth
ten minutes to check which, and to make the answer the same in both plugins
rather than each picking its own. Not a code change until that is settled.

Explicitly **not** doing: `lib.lazy` (the metatable proxies already achieve it
with no dependency), `lib.memo` (nothing to memoise — §7), moving trails to
`stdpath("cache")` (they are intent, not cache).
