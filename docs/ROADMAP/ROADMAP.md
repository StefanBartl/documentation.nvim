# documentation.nvim — the outlook

**What this plugin is, in one sentence:** a tool that checks a tree's
documentation against the tree itself — and the map is the visible
by-product, not the purpose.

The purpose is the other half: a generated map is a pretty artifact; a map
that *fails* when documentation and reality drift apart is a test. Every
direction below is measured against that.

> **The queue lives elsewhere.** What gets built next — here *and* in
> `docmap-desktop` and `runtime-analysis.nvim` — has been in **one** plan
> since 2026-08-20:
> [`docmap-desktop/docs/PLAN.md`](https://github.com/StefanBartl/docmap-desktop/blob/main/docs/PLAN.md).
>
> What was built and why is in
> [`FEATURES.md`](../FEATURES/FEATURES.md). The derivation, including costs
> and counter-arguments, lives in [`IDEAS/`](IDEAS/) — this document is
> neither of those.

## The four big directions

**Being able to read more languages.** Twenty-three backends behind one
contract, so that a mixed repository yields *one* map instead of several.
What each of them reads is in [`LANGUAGES.md`](../LANGUAGES.md); what each of
them cost is in [`IDEAS/MULTILANG.md`](IDEAS/MULTILANG.md). Fifteen more are
**available, not planned** — named, costed and ordered by price in the same
file.

**Call edges outside Lua, Go and the ECMA family.** The single largest gap in
the tool: five backends out of twenty-three deliver call edges, eighteen
deliver `{}` — which leaves the calls views, `:DocMap why`, the call
hierarchy and `dead-function`'s call stage empty for those languages.
**Nothing about these languages makes that impossible**; it is unbuilt, not
blocked. Go was deliberately the first, as a pattern — and the lesson from it
is the instruction for the rest: *first ask what a scope is in this language,
then write the query.* A Go package is a directory, and a per-file resolver
loses nearly half of a real call graph to that (`aws/smithy-go`: 397 out of
883 edges).

**Speaking, not just reading.** The languages this tool *speaks* — a
different axis from the one above, despite the shared word. Findings have
carried parameters instead of finished English sentences since I18N-0; the
generated page is the remaining ~85% of the work. See
[`IDEAS/I18N.md`](IDEAS/I18N.md).

**Running without Neovim.** "A Lua map from the terminal" has worked for a
long time. Dropping the Neovim dependency entirely is costed separately in
[`IDEAS/PORTABILITY.md`](IDEAS/PORTABILITY.md) — and the standalone build has
lately proved its worth above all as a *test bench*: it reads the artifact as
an ordinary file and therefore sees things no check over the source tree
sees.

## The one open finding worth knowing about

**The `standalone` gate skips itself silently** and still counts towards "5/5
green". It needs PUC Lua on the `PATH` with `lfs` and `dkjson`; if one of
those is missing it prints *skipped*. Locally, green therefore means **"four
gates and a shrug"** — and exactly behind that, three real defects made it
into a release.

**Two halves are fixed.** `TESTS/shim_contract_spec.lua` has caught what is
*statically* visible since 2026-08-20 — every `vim.*` path and every method
name that `core/` calls, against what the shim implements. And the closing
line no longer lies: it used to say "All 5 gates passed" while one of them
had printed *skipped* forty lines earlier. It now says
**"4 gates passed, 1 skipped: standalone"** plus the sentence that explains
the rest: *a skipped gate checked nothing.*

The skip itself stays a skip — a machine with Neovim and nothing else is the
common local case, and making it red is exactly how a gate gets switched off.
What changes is the precision: "no PUC Lua on PATH" and "a PUC Lua that
cannot load the rocks" are different problems with different solutions, and
the message now names the interpreter, the missing rock and the install line.

**On the author's machine the old message was simply wrong:** `lua5.4` is on
the PATH there, and a second `lua` sits beside it that is merely missing
`dkjson`. "No PUC Lua on PATH" has therefore been sending the reader in the
wrong direction all along.

What remains open: a shim function that **exists and behaves differently** is
invisible to a static contract.
