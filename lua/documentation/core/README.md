# `documentation.core`

The pipeline: **scan → check → render**. No editor, no commands, no keys.

## The contract

The IR is what holds the two halves apart:

> Renderers never touch the filesystem, and the scanner never knows what will
> be drawn.

Everything here takes a `Documentation.Opts` and produces or transforms a
`Documentation.IR`. Nothing here reads `state`, opens a window, or notifies the
user — `grep -rln notify lua/documentation/core/` returns nothing, and that is
a property to preserve, not a coincidence.

## Layers, enforced

`scripts/gen_map.lua` declares two rules against this repository's own map:

```lua
layers = {
  { from = "documentation.core", to = "documentation.editor" },
  { from = "documentation.core", to = "documentation.bindings" },
}
```

so `:DocMap check` — and therefore CI — fails if anything here ever requires
the editor or the command layer. That is the whole reason the directory exists:
the pipeline has to stay runnable with no editor around it, and nothing but a
check keeps
a boundary like that from quietly rotting.

## What is where

| Stage | Files |
|---|---|
| Walk & parse | [`scan.lua`](scan.lua), [`functions.lua`](functions.lua), [`symbols.lua`](symbols.lua) |
| Graphs | [`deps.lua`](deps.lua) (require), [`calls.lua`](calls.lua) (call sites) |
| Enrichment | [`luals.lua`](luals.lua) (`@class`/`@alias`, opt-in), [`tagfiles.lua`](tagfiles.lua) (cross-project links) |
| Derived facts | [`coverage.lua`](coverage.lua) (`fn.tested`), [`doccoverage.lua`](doccoverage.lua) (`fn.documented`), [`duplicates.lua`](duplicates.lua) |
| Check | [`check.lua`](check.lua) → `Documentation.Finding[]` |
| Analysis over an IR | [`diff.lua`](diff.lua), [`history.lua`](history.lua), [`churn.lua`](churn.lua) |
| Render | [`render/`](render/) — html, markdown, mermaid, dot, badge |
| Support | [`json.lua`](json.lua) (deterministic), [`find.lua`](find.lua), [`cli.lua`](cli.lua) |
| Types | [`@types/`](@types/init.lua) — the analysis result shapes; the IR itself is [one level up](../@types/init.lua) |

## Pure by default

`diff`, `history`, `churn`, `duplicates`, `coverage`, `doccoverage` and every
renderer are pure: an IR in, a structure or a string out. No git, no
filesystem.

That is not a stylistic preference. It is what lets `:DocMap impact` be tested
without a repository, `churn` be scored without running `git log`, and the
whole browser model be driven from a headless spec. Everything that *must*
shell out lives in [`editor/`](../editor/) or
[`bindings/`](../bindings/) — the git half of `impact` is in
`bindings/usrcmds/impact.lua`, and the pure half it calls is `history.lua`.

The scanner and `luals.lua` are the deliberate exceptions: they are the two
places that read the world.

## Determinism

`module_map.json` is byte-deterministic, and `--check` byte-compares it. That
is why [`json.lua`](json.lua) exists instead of `vim.json.encode`, whose key
order is unspecified, and why nothing here embeds a timestamp, a hostname or
anything else that would make a regeneration differ from the artifact it is
compared against.

The same rule is why git data can never enter the IR: a commit that embedded
history would invalidate its own artifact the moment it landed. See
`:DocMap churn` and the History tab for how that constraint was worked around.
