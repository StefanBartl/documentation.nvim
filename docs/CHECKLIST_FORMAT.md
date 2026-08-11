# Checklist format

A **ledger of hand-verified facts**, not a set of automated checks. The
distinction is the whole feature.

Drift checks (`:DocMap check`) re-derive a verdict from the tree on every run.
A checklist item does not: it records something a person decided once by
reading the code, and what gets watched afterwards is the **citation**. If the
cited file has been committed to since the item was last verified,
`:DocMap checklist` flags it "re-read this" — rather than continuing to display
a verdict that may quietly have stopped being true.

The output is not pass/fail. It is *what needs attention*.

## Why not just write more checks

This came out of reading a real corpus rather than from designing one.
`docs/ROADMAP/RULES/` in this author's nvim-config is 33 per-plugin reports
plus 9 thematic syntheses, each guideline cited to a real `file:line`. Its
`keybindings-count.md` asks "does `<leader>xy` support `2<leader>xy`" *per
keymap* — and no scanner can decide that, because it needs to know whether
count-semantics make sense for that particular action. A person answered it
once, reading the code.

That is the honest shape of most real checklist content: recorded facts, not
re-derivable rules.

## Where it lives

| Candidate | Resolution order |
|---|---|
| `docs/CHECKLIST/` | first — one `.md` per theme, like `docs/FEATURES/` |
| `docs/checklist/` | |
| `docs/CHECKLIST.md` | the degenerate single-file case |
| `docs/checklist.md` | |

First match wins. Files inside a folder are read in sorted order, so two runs
over an unchanged tree produce identical bytes — the artifact is byte-compared
by `--check`.

## The syntax

```markdown
## Keybindings

- [x] `<leader>xy` supports count where it should
      <!-- @ref lua/plugins/dap/keymaps.lua:32 -->
      <!-- @verified 2026-08-08 -->

- [ ] Picker inputs support autocompletion
      <!-- @ref lua/plugins/foo/usrcmds.lua:14 -->
```

`- [x]` / `- [ ]` is the syntax every roadmap file in this ecosystem already
uses. The metadata rides in HTML comments: invisible in a rendered preview,
trivially parseable line by line, no CommonMark parser involved.

| Tag | Meaning |
|---|---|
| `@ref path` or `@ref path:line` | Repo-relative file the verdict was read off. The line is optional and is where a flagged item jumps to. |
| `@verified YYYY-MM-DD` | When a person last checked it. |
| anything else | Kept and carried through, not dropped. |

**Accepted without complaint**, because a corpus written by hand across dozens
of files will contain all of it: `*` as the bullet marker, uppercase `[X]`,
items that wrap across several indented lines, a blank line between the item
and its comments, and comments that wrap across lines themselves.

## `@verified` is a date, not a commit hash

A hash would be exact — staleness becomes a clean "any commits since this
one". But nobody hand-writes a hash, so requiring one forces a command to
check an item off, which reopens a decision this feature deliberately settled
the other way: hand-editing, as the `RULES/` corpus was actually produced.

The cost is one real imprecision: **a commit made on the verification day
itself does not mark the item stale.** Same-day ordering is unknowable from a
date alone, and of the two possible errors, "misses a same-day edit" is far
less damaging than "flags every item the moment it is verified" — which would
make the ledger cry wolf and get ignored.

## The four states

`:DocMap checklist` shows the first two by default; `:DocMap checklist all`
shows everything.

| State | Meaning |
|---|---|
| **stale** | The cited file has commits newer than `@verified`. Go re-read it. |
| **unverified** | Cited, but no `@verified` date to compare against. |
| **uncited** | No `@ref` at all — a fact about the project rather than about a line of code. It can never go stale, and that is a real state, not a defect. |
| **current** | The cited file has not moved since verification. |

A flagged item jumps to the **cited source line**, not to the checklist line.
The point of a stale flag is to send you to the code you need to re-read; the
`- [ ]` line is where you go to *record* the answer, which is the second step.

## Why staleness is not in the generated map

The ledger itself bakes into `module_map.json` happily — it is parsed Markdown.
The staleness verdict cannot, and this is a hard constraint rather than a
preference:

> git data cannot enter the committed artifact, because `--check` byte-compares
> generated output against committed output, so a map carrying history has no
> fixed point.
> — `core/churn.lua`, which hit the same wall first

So `core/checklist.lua` is pure and never runs git. `status()` takes a
`path -> commit dates` table that somebody else produced, which is also what
lets every staleness case be tested with no repository, no commits and no clock
involved.

## Try it

```
:DocMap checklist        " stale and unverified only
:DocMap checklist all    " everything, including what is still current
```

This repository keeps its own ledger in
[`docs/CHECKLIST/architecture.md`](CHECKLIST/architecture.md) — eight facts
about layering, coexistence with other tooling, and the protocol surfaces,
each cited and dated.
