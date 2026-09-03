# hover.nvim integration

Rest the cursor on a dotted module name and
[hover.nvim](https://github.com/StefanBartl/hover.nvim) says what that module
is — read out of `docs/map/module_map.json`, the artifact this plugin already
writes.

```
local n = require("lib.nvim.notify")
                   └──── hover ────┘

┌ lib.nvim.notify ──────────────────────────────────────┐
│ Allows per-module prefix configuration while           │
│ mirroring vim.notify semantics.                        │
│                                                        │
│ 1 function  ·  requires 1  ·  required by 33           │
└────────────────────────────────────────────────────────┘
```

No scan at runtime, no Treesitter, no LSP. One read of a file that is already
on disk, parsed once per session and re-parsed when the artifact changes.

## Why a *position* preview and not a source

hover.nvim takes three kinds of contribution. A **source** hands back a target
string for it to classify; a **position** hands back finished content for a
cursor position that points at nothing.

This is the second kind, and the choice matters. A source would have to return
the module's source *path*, and hover.nvim would then preview its first twenty
lines — the module header if you are lucky, a license block if you are not.
The summary is what is worth showing, and it exists only in the map.

## The stale-map problem, and what is done about it

**The artifact is a snapshot.** Nothing regenerates it when the code changes,
and in at least one repository in this ecosystem it is not even tracked by
git. A preview from a stale map is the dangerous case precisely because it
does not *look* stale — it looks current, which is strictly worse than looking
absent.

So the float compares the artifact's mtime against the module's own source and
says so when the source is newer:

```
┌ lib.nvim.safe_api ────────────────────────────────────┐
│ Validated, pcall-wrapped `vim.api` accessors.          │
│                                                        │
│ 18 functions  ·  requires 0  ·  required by 0          │
│                                                        │
│ ! the source is newer than the map -- regenerate it    │
└────────────────────────────────────────────────────────┘
```

One `fs_stat` on a file the map already names. It turns a silent wrong answer
into a visible old one.

**There is a subtlety in that check worth knowing**, because the obvious
implementation gets it wrong silently: `path` in the map names either a file
(`lua/x/y.lua`) or the *directory* of a module with an `init.lua` in it.
Statting the directory answers with a mtime that does not move when a file
inside it is edited — so an edited module would look current forever. The
check stats `path`, `path.lua` and `path/init.lua` and takes the newest file
among them.

## Scope

The map is found by walking up from the buffer's own directory. So the answer
is about **the repository the buffer belongs to**, not about wherever Neovim
happens to be. A file open from another project gets that project's map, or
none.

**A moved artifact is found too**, which it was not before 2026-09-03: the walk
hardcoded `docs/map` while `out_dir` is configurable everywhere else, so anyone
who moved it got no module hover at all — silently, which is the worst shape a
missing feature has. Two places may state one, and both are read: a project the
editor has installed carries its built config, and a repository states itself in
`.docmap.json`.

It happens in **two passes**, and the order is a measurement rather than a
preference. The first probes `docs/map` at every level, which answers for every
project that never moved anything. Only where that whole walk found nothing
does the second ask each level where it says its map is — because asking is not
free: the project registry normalises a root through `uv.fs_realpath`, a
filesystem call and a slow one on Windows. Asking at every level of the first
pass turned a 112 µs cold walk into 763 µs. A project that never moved its
artifact is therefore never asked, which the spec pins by counting the probes.

Within the second pass a stated `out_dir` **replaces** the default rather than
being tried alongside it: a project that moved its artifact may still have the
old `docs/map` lying around, and answering out of that would be a preview from
a file the project has stopped writing.

**That walk is cached per directory, misses included**, and the miss is the
one that mattered. A repository with no generated map answered nothing while
paying the whole climb on every ask — up to 24 levels, one `fs_stat` each.
Measured on 2026-09-03 against the registered callback, 2000 repetitions:

| Where | Per ask, before | After |
| --- | --- | --- |
| a repository with no map, five levels deep | 97.3 µs | **2.9 µs** |
| the same at its root | 50.9 µs | 2.7 µs |
| a repository **with** a map | 117.1 µs | 40.2 µs |

The climb was 98 % of the ask against 1.6 µs for the dotted-name test, so this
is not a fast path made faster — it is the only slow one removed. The hit is
cached too, which is why the third row moves as well.

The cost is one narrow kind of staleness: a map that **appears** where there
was none — generated during the session, or arriving with a branch — is not
noticed until `documentation.hover._reset()` or a restart. A map that is
*regenerated* is unaffected, because the cached answer is the path and the
parse is keyed on its mtime.

A name with no dot is never looked up: a bare identifier is not a module name,
and answering for one would mean a map lookup for every word.

## You are no longer alone on this token

insights.nvim registers a position preview for a dotted name too, and answers
a different question about it: this plugin says **what the module is**, that
one says **who imports it**. Both are right, and the cursor is in one place.

hover.nvim steps between them — `<M-n>`, or `:Hover next` — so the second
answer is a page rather than a casualty. Before that existed (hover.nvim
`ac0a372`), `position_at` returned the *first* answer and the other plugin was
invisible, decided by load order. Nothing here changed for it: the contract is
still "answer or decline", and declining is what puts the next plugin on
screen.

## Soft in both directions

- **Without hover.nvim**, `setup()` looks for `hover.registry`, does not find
  it, and returns. Nothing registered, nothing errors.
- **Without a generated map**, nothing answers — the position preview declines
  and hover.nvim carries on as if this plugin were not installed.
- **With an older hover.nvim** that has a registry but not `positions`, the
  integration declines rather than registering something that would be
  silently ignored.

## Turning it off

```lua
require("documentation").setup({ hover = false })
```

Or from hover.nvim's side, which silences every registered position preview:

```vim
:Hover positions off
```
