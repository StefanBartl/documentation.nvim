# What you get

A repository knows its own shape — which modules exist, what requires what,
what is documented and what only claims to be. None of that is written down
anywhere a person or a CI job can read, so it is rediscovered by hand every
time somebody new opens the tree.

documentation.nvim writes it down, as an artifact you can commit, open
offline and diff.

The map is generated, not rendered live. That is the whole trade: an artifact
you can commit and diff, at the price that a tab added in a later release
reaches an existing map by *regenerating* it, never by updating the plugin
alone.

This repository maps itself with the same tool and publishes the result:
**<https://stefanbartl.github.io/documentation.nvim/>**.
[docs/map/overview.md](map/overview.md) is the same tree as Markdown,
rendered straight on GitHub.

The published copy is honest about what it can answer: Hierarchy, Index,
Analysis, Notes, Quicks and Compare need no server and work fully; History,
Telemetry and Loaded are computed on demand from git and from runtime data on
the machine that ran the scan, and say so when opened elsewhere. See
[reuse.md § Linking to your own map from your README](reuse.md#linking-to-your-own-map-from-your-readme)
to do the same in a plugin that depends on this one.

It grew inside [lib.nvim](https://github.com/StefanBartl/lib.nvim) as
`lib.nvim.docmap` and was extracted once it had nothing left to do with
lib.nvim — see
[pipeline.md § Why this is its own plugin](pipeline.md#why-this-is-its-own-plugin).

## What it produces

| Artifact | What it is |
| --- | --- |
| `docs/map/index.html` | The interactive map: **Hierarchy**, **Index** (Tree / Functions / Modules), **Analysis**, **Compare**, **Features**, **Quicks**, **Notes**, **History** and **Findings** tabs. Self-contained — no CDN, no build step |
| `docs/map/overview.md` | The same tree as Markdown, so it renders on GitHub |
| `docs/map/module_map.json` | The IR, byte-deterministic. What `--check` compares and what `:DocMap diff` reads out of old commits |
| `docs/map/coverage.svg` | Optional (`opts.badge`): a doc-coverage badge, hand-rolled, no network call |
| `docs/map/overview.pdf` | Optional (`opts.pdf`): the same content as `overview.md`, via [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) |

**Every one of these is a snapshot of the version that wrote it.** The tour
of what each tab shows, and why, is [tabs.md](tabs.md); how each one is
computed is [pipeline.md](pipeline.md).
