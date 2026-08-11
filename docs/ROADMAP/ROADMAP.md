# documentation.nvim — open items

What's actually still open, after a full pass through this project's roadmap
history. Everything shipped is recorded in [`FEATURES.md`](FEATURES.md)
instead — commit hashes and design decisions live there, not here. This file
only holds things with no decision yet, or a decision to *not* build something
(a documented rejection is as much a result as a shipped feature, and worth
keeping so the question doesn't get re-litigated from scratch).

Carried over from `lib.nvim`'s `docs/ROADMAP/docmap_roadmap.md`, which in turn
consolidated `docmodule.md`/`docmodule_NEXT.md` (moved in from the nvim-config
repo, 2026-07-28), `module_map.md`, and
`docmap_hierarchy_and_integrations.md`. All of those are fully superseded by
what actually got built; the original, much longer process narrative is in
lib.nvim's git history if it is ever needed.

> **Names in this file predate the extraction.** Where it says `docmap`,
> `:LibMap` or `lib.nvim.docmap`, read `documentation`, `:DocMap` and
> `documentation.*` — the module moved out into its own plugin on 2026-07-28
> (O2 below, now shipped). Entries are left as written rather than
> search-and-replaced, because several of them are *decisions* whose wording
> is the record.

## Genuinely open

