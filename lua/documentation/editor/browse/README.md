# `documentation.editor.browse`

`:DocBrowse` — the module map inside the editor.

```vim
:DocBrowse                  " read docs/map/module_map.json (~10ms)
:DocBrowse live             " install a watching handle instead (~0.65s once)
:DocBrowse lib.nvim.fs      " open centered on a module
:DocBrowse history          " open on the commit list
:DocBrowse endpoints        " open on the whole tree's route registrations
:DocBrowse telemetry        " open on the static x runtime join
:DocBrowse live lib.nvim.fs
```

```lua
require("documentation.editor.browse").open({ root = "/path/to/repo" })
```

## What this is not

**Not the HTML diagram in a terminal.** Boxes with connecting curves need
pixels — free positions, curves, continuous zoom. A terminal is a fixed cell
grid, and what comes out of that is a worse version of
[the page that already exists](../../core/render/html.lua). Nobody would prefer it.

So this is a **navigator over the same edges**, not a drawing of them: the
hierarchy is a drill-down list, and Deps/Calls are lists too.

## Why it exists anyway

Three things the editor can do that the generated page cannot:

1. **Jump to the source at the line** (`gd`). The page can at best link to
   GitHub.
2. **Fill the quickfix list** (`gq`). "Every caller of `M.read`, in the
   quickfix list" is what an editor UI is for — and the point where call
   edges stop being decorative and start saving work.
3. **Be live** (`:DocBrowse live`). The page is an artifact showing the state
   of the last `:DocMap`; a watching handle re-scans on write.

If only one of those survived, it would be (2).

## Data source

Artifact-first, and that is measured rather than assumed:

| Path | Cost |
| --- | --- |
| `scan()` over lib.nvim | **0.65 s** (283 nodes) |
| read + decode `module_map.json` | **0.01 s** (810 KB) |

Two thirds of a second of blocking editor time between keypress and window is
the difference between "opens" and "hangs", so the default reads the artifact
and the live scan is opt-in. The cost of that choice is staleness, so the
status line says so when the artifact is older than the newest source file
rather than showing wrong data silently.

`live` reuses an already-installed handle rather than installing a second one,
because `install()` treats a collision as replace — which tears down a watch
another caller may rely on *and* drops every `on_change` subscriber with it.
Reusing alone was not enough, though: `docmap.command.setup()` installs with
the plain config, which sets no `watch`, so a `:DocMap` earlier in the session
left exactly the handle this finds, and "live" meant a view that never
re-scanned on write — the mode's whole promise, broken by nothing more than
which command ran first. `registry.ensure_watch()` upgrades such a handle in
place, keeping its subscribers.

> The artifact and the in-memory IR are not the same document: `module_map.json`
> writes `nodes` as an **array** in walk order (that is what makes the file
> byte-deterministic — a JSON object's key order would not be) and carries no
> `order` key. `source.rehydrate` bridges the two so everything downstream
> reads one shape. Absent optional fields are written as `null`, so decoding
> uses `luanil` — otherwise `node.module` comes back as `vim.NIL`, which is
> *truthy*, and `types_detail == nil` (the "LuaLS never ran" signal) is never
> true.

## Modes and keys

| Key | Effect |
| --- | --- |
| `1` … `8` | Structure / Deps / Calls / Types / History / Trail / Endpoints / Telemetry |
| `j` `k` | Move; the detail pane follows |
| `<CR>` | Descend a level (Structure) or follow the edge (Deps/Calls) |
| `-` / `<BS>` | Up a level |
| `<C-o>` / `<C-i>` | Back / forward through the visit history |
| `h` / `l` | Direction: incoming / outgoing (Deps, Calls) |
| `+` / `_` | Depth ±1 (Deps) |
| `gd` | Open the source at the line, closing the browser |
| `gq` | Current list into the quickfix list |
| `gI` | Blast radius of the selected node into the quickfix list |
| `gO` | Open the generated page at this exact position |
| `gD` | The opened commit's diff in a scratch buffer (History) |
| `gs` | Send the selected route as a request via `runtime-analysis.nvim` (Endpoints) |
| `p` | Pin / unpin the entry under the cursor |
| `d` | Unpin (Trail) |
| `S` | Save this trail under a name (Trail) |
| `L` | Load a saved trail, adding to this one (Trail) |
| `X` | Forget a saved trail (Trail) |
| `f` | Filter this list in place (`-negate`, `"phrase"`; empty clears) |
| `/` | Fuzzy jump across every module and function |
| `?` | This table, in a float, for the current mode |
| `q` `<Esc>` | Close |

`?` is rendered from the same `KEYS` table `bind()` installs from — the table
above is a copy for readers, the overlay is not. A second hand-maintained list
of keys is exactly the drift this plugin exists to detect, so the spec asserts
the claim rather than leaving it to a comment: every key actually bound on the
list buffer has to appear in the panel.

Keys the current mode ignores (`+`/`_` outside Deps, `gD` outside History) are
**marked, not hidden**. "Why did `+` do nothing" is the question someone opens
the overlay to answer, and a key that has vanished from the list reads as one
that was never there. They stay *bound* in every mode too — the handlers
already gate themselves, and leaving the key unbound would let it fall through
to Vim's own meaning, where `+` moves the cursor down a line. Nothing
happening is the better wrong answer.

## Telemetry mode

The static x runtime join — ECOSYSTEM.md step 8, `docs/ROADMAP/telemetry-
documentation-bridge.md` (in the `lib.nvim` repo) for the full design. One
row per function this tree's own static analysis and a `runtime-analysis.
telemetry` namespace (`opts.title` by default, `opts.telemetry_namespace`
to override) both have an opinion about, badge-prefixed by which of four
cells it falls in: `✕` no static caller and never called, `!` called but no
static caller (a `dead-function` false positive — a callback, dynamic
dispatch, or a cross-repo consumer — telemetry proves it alive), `○` has a
static caller but nothing exercised it, blank when both agree the function
is healthy. A function with no telemetry data at all is listed too,
undecorated except a trailing note — absence of data is never rendered as
if it were evidence, in this mode or in `dead-function`'s own suppression
(the same join silences a `dead-function` finding once telemetry proves the
exact function alive, never the reverse). Soft dependency throughout:
`pcall(require, "runtime-analysis.telemetry")`, a plain message when the
plugin is absent or nothing was ever recorded for the namespace, exactly
like `gs` degrades in Endpoints mode.

The history stack is the counterpart to the browser's Back/Forward, and it
matters *more* here: without an address bar there is no other answer to "where
am I".

`history` holds the whole trail **including the current position**, with
`hindex` pointing at it — the model the HTML renderer and every browser use.
Worth stating because the alternative is tempting and does not work: recording
only *past* positions leaves `hindex` addressing the entry before the current
one, so the first `<C-o>` falls off the front of the list and the second lands
one stop too far back. Both directions are a plain bounds check now, and the
cursor row of the position being left is synced into its entry before moving,
so coming back restores the row the user was on rather than the row they
arrived at.

A key that cannot change anything does not become a stop either — `+`/`_`
outside Deps (depth is the only axis `walk_requires` reads), `h`/`l` when the
direction is already what was asked for. Otherwise the trail fills with
positions identical to their neighbours, and a `<C-o>` that visibly does
nothing reads as the history being broken rather than as the key having been a
no-op.

`gI` is the counterpart to `gq`: `gq` sends what is *on screen*, `gI` sends
what would **break**. It reports the transitive closure of `required_by`, and
it acts on whatever the detail pane is describing rather than on the centered
node — those differ the moment the cursor moves, and a figure that disagreed
with the one two panes over would be worse than no figure. On a *function*
entry the answer is its module's radius, which is the only honest one: the
require graph has no finer grain than a module.

`gO` hands the current position to the generated page. The navigator knows
mode, center, direction, depth and function; the page's whole state lives in
its URL fragment. So it is a `format()` and the existing opener, and it
answers "actually, I want to see that as a picture" without having to find the
place again.

## Filtering a list

`f` narrows whatever list is on screen, in place.

```
fs bar        rows containing "fs" AND "bar"
"open url"    a phrase, spaces and all
-spec         no row containing "spec"
-"unit test"  a negated phrase
```

**Not what `/` does**, and the two are worth keeping apart. `/` is a fuzzy
jump across every module and function in the tree: "take me to the thing I can
name". `f` answers "show me less of what I am already looking at", and that
wants a different matcher — plain case-insensitive substrings, so a query
means exactly what it says. Fuzzy matching is forgiving, and forgiveness is
wrong here: the entire point of typing `-spec` is that nothing containing
"spec" survives it.

Terms are ANDed, and there is no `OR`. That is not an omission — the reason to
narrow a list is to make it shorter, and every `OR` makes it longer. Someone
who wants a union already has `/`.

One key, not two: `f` opens prefilled with the query in effect, so editing a
filter and clearing it are the same gesture (submit an empty line). Same
reasoning that gave `p` a single toggle.

Three things worth knowing:

- **It matches the row's label** — what is on screen — and nothing else.
  Filtering on data the row does not display would make rows vanish for
  reasons the reader cannot see, which is the failure this feature exists to
  avoid rather than cause.
- **The status line always shows an active filter and its hidden count**
  (`⌕ fs -spec (4 hidden)`). A filter is the only view state that *removes
  rows*, so without that a narrowed list and a genuinely short one are
  indistinguishable. An empty result renders an explicit row saying so, never
  a blank column.
- **It belongs to the list it was typed against.** Changing the subject
  (mode, node, function) drops it; changing an *axis* — direction, depth —
  keeps it. That asymmetry is the feature: narrowing a Deps list and then
  flipping direction to see the same narrowing is the reason to narrow it.
  Carrying the query into a different module's list would instead present a
  short list as a complete one.

It travels with positions in the visit history, so `<C-o>` back onto a
narrowed list finds it narrowed the same way. It is not itself a history stop
— `<C-o>` undoes moves, and making it sometimes undo a keystroke of typing
would be two different meanings on one key.

`gq` exports what is on screen, so filtering and then `gq` is how a subset of
a call graph reaches the quickfix list.

[`filter.lua`](filter.lua) is **pure**, like `trail.lua`: the whole query
language is driven from a headless spec, and only the one key that reaches it
needs the UI.

## Trail mode

```vim
:DocBrowse trail            " open straight on the pinned positions
```

`p` pins the entry under the cursor, in any mode; `6` lists what has been
pinned; `d` unpins there. The count rides along in every other mode's status
line (`📌3`) — a trail invisible from where you are pinning is a feature with
no feedback — but only once there is something to count.

**Not the same thing as `<C-o>`/`<C-i>`**, and conflating them helps neither.
The history stack answers "where was I a moment ago": automatic, ordered by
time, truncated the moment a new move happens. A trail answers "where do I
want to be able to get back to": deliberate, ordered by when it was pinned,
and nothing but an explicit unpin removes an entry. Reading a dependency graph
produces dozens of history stops and about four places actually worth
returning to.

Three decisions worth knowing:

- **A pin is a view, not a subject.** It carries the mode and the axes
  (`dir`, `depth`, `sha`) it was taken in, and `<CR>` restores all of them.
  Half-restoring — landing on the right module in whatever mode happens to be
  current — is what makes bookmarks feel unreliable: the pin was "this
  module's incoming requires at depth 3", and arriving at its child list is
  not that place.
- **Identity is what the pin is about, not how it was being looked at.**
  `dir` and `depth` travel *on* the pin but are not part of its key, so
  pinning a module in Deps at depth 2 and again at depth 3 toggles the one
  bookmark rather than growing a near-duplicate nobody meant to create.
- **Pins are keyed by repository root**, not by browser instance, so they
  survive closing and reopening the window — and, through
  [`trail_store.lua`](trail_store.lua), Neovim itself. A bookmark with the
  lifetime of a scrollbar is not a bookmark.

A pin whose node has since vanished from the map (renamed, deleted) renders as
a non-navigable row saying so, rather than as a label for something that is no
longer there — the same rule the HTML map's History tab applies to its module
chips. External requires refuse to be pinned at all: they resolve to nothing in
the scanned tree, so there is no position to return to.

`trail.lua` is **pure** — a table of records, no window, no buffer, no `vim`
API — which is what lets the whole model be driven from a headless spec
without mounting a single float. Same split `diff.lua` and `history.lua`
already follow.

### Saved trails

The working trail persists on its own; `S` names a copy of it, `L` loads one
back and `X` forgets one. All three are Trail-mode keys: the verbs are about
the list, and the list is what mode `6` shows.

```
stdpath("state")/documentation.nvim/trails.json
```

`state`, not `data` and emphatically not the repository — a trail is
navigation state, with no more claim on the project than a jumplist has.
Committing it would put one reader's path into everyone else's checkout, and
`--check` would then have an opinion about it. Roots are absolute paths used
verbatim as keys: two checkouts of the same project are two places to have
looked around in.

Three decisions here too:

- **Loading adds; it never replaces.** Replacing would silently destroy the
  trail built this session, and a bookmark tool that can lose bookmarks stops
  being trusted. The alternative is a confirmation dialog nobody wants on a
  navigation key. Additive also composes — two saved trails can be loaded one
  after the other, which "replace" makes impossible.
- **`X` deletes a *saved* trail, never the pins on screen.** Those are what
  the reader is looking at; a key that could clear them from behind a picker
  would be the one destructive surprise in the feature.
- **[`trail_store.lua`](trail_store.lua) listens rather than being called.**
  It subscribes to `trail.on_change`, which is what keeps `trail.lua` free of
  I/O — and is more robust than saving at each call site, because a mutation
  added later cannot forget to persist. Writes are debounced (pinning six
  things is one write) with a synchronous flush on `VimLeavePre`, since the
  debounce timer is exactly what quitting does not wait for.

Hydration happens once per root, at `browse.open()`. Re-reading on every open
would discard whatever was pinned since — the newest pins, which is the worst
half to lose. A malformed or truncated file costs that root its pins and never
raises: this lives in the user's state directory, where a full disk or an
older version of this plugin can leave anything behind.

## History mode

```vim
:DocBrowse history          " open straight on the commit list
```

The one mode whose data does not come from the IR. It has two levels:

1. **The commit list** — `git log`, newest first.
2. **What one commit touched** — `<CR>` on a commit maps its diff hunks onto
   function spans and lists the functions the changed lines fall inside, each
   with its direct caller count.

`<CR>` on one of those functions leaves History for **Calls, incoming** — the
question History is asking is "who is affected by this", and Calls-in is the
mode that already answers it. `-` goes back to the commit list.

Two warnings can appear in the detail pane, and both are the reason the
analysis is trustworthy rather than merely plausible:

- *"predates the committed map"* — that revision has no `docs/map` artifact,
  so nothing could be attributed to functions and only the changed files are
  known.
- *"spans were approximated"* — the artifact at that revision has no
  `line_end`, so a function's extent was taken as reaching to the next one.
  That over-attributes into the gaps between functions rather than
  under-attributing, which is the safe direction, but it is a guess and says
  so.

Changed paths nothing could be attributed to are listed at the end as
non-navigable rows. They are why the list is shorter than the diff looks, and
hiding them would make that look like a bug.

Git runs in `init.lua`, never in `view.lua` — the analysis lands on the state
(`st.commits`, `st.impact`) and `view` renders it like any other mode. That is
what keeps the mode testable headlessly; see
[`history.lua`](../../core/history.lua) for the attribution itself.

## Layout

Three [`ui.kit.layout`](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/ui/kit/README.md) slots:

```
┌─ list ───────────────┬─ detail ─────────────────┐
│ ▸ lib.nvim.fs        │ lib.nvim.fs.read         │
│   lib.nvim.git       │                          │
│ ▸ lib.nvim.store     │ Reads a file…            │
│   …                  │ @param path string       │
│                      │ 3 callers · 1 callee     │
├──────────────────────┴──────────────────────────┤
│ lib.nvim ▸ fs ▸ read     [calls ←in]            │
└─────────────────────────────────────────────────┘
```

Each slot gets a filetype (`documentation-browse-list` / `-detail` / `-status`)
so a user's own config can highlight them.

## Structure

| File | Holds |
| --- | --- |
| `source.lua` | Where the IR comes from: artifact vs. live handle, rehydration, the staleness check |
| `view.lua` | Pure: state → list entries, detail lines, status line. No window touched, so the mode logic is testable headlessly |
| `init.lua` | Layout, state, navigation, keymaps, actions |

`view.lua` being pure is what lets
[`TESTS/docmap_browse_spec.lua`](../../../../TESTS/docmap_browse_spec.lua)
check every mode against a synthetic IR without mounting anything.

## Notes

- The entry under the cursor is read from the **window**, not from a cached
  index. The cache is kept in step by a `CursorMoved` autocmd, which is fine
  for redrawing but must not be what an action trusts: any path that moves the
  cursor without firing that autocmd would make `<CR>` act on a row the user
  is not looking at. (It did, before this was fixed.)
- `gd` on a Calls entry lands on the callee's **declaration**, not on the call
  site. An edge's `line` is where the call is written, which is in the file
  already on screen — jumping there would send every row in the list back to
  where it started.
- Closing on `gd` is deliberate: the floats cover the editor, so "jumping to" a
  file the user cannot see is not a jump.
