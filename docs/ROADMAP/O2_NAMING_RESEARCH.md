# O2 prep — naming survey + related-plugin feature research (2026-07-28)

> **Historical record, not an open item.** This was prep work for the O2
> extraction (moving this module out of `lib.nvim` into its own repo) —
> not a decision to revisit, just work already done so it is not repeated
> if a similar naming exercise ever comes up again, for this plugin or
> another. The extraction happened; the name landed on `documentation.nvim`.
> Moved out of [`ROADMAP.md`](../ROADMAP/ROADMAP.md) on 2026-08-10, which is for
> genuinely open items and documented rejections — neither applies here.

## Names checked against GitHub

| Name | Status |
|---|---|
| `dooku.nvim` | **Taken** — [Zeioth/dooku.nvim](https://github.com/Zeioth/dooku.nvim), same problem space |
| `docgen.nvim` | **Taken, twice** — [jamestrew/docgen.nvim](https://github.com/jamestrew/docgen.nvim), [dhananjaylatkar/docgen.nvim](https://github.com/dhananjaylatkar/docgen.nvim) |
| `cartographer.nvim` | **Taken, twice** — [Iron-E/nvim-cartographer](https://github.com/Iron-E/nvim-cartographer) (keymap DSL), [hkupty/cartographer.nvim](https://github.com/hkupty/cartographer.nvim) (archived 2021) |
| `wayfinder.nvim` | **Taken** — [error311/wayfinder.nvim](https://github.com/error311/wayfinder.nvim), and close enough in concept to `:LibBrowse` to risk real confusion even if it weren't |
| `doxygen.nvim` | Not confirmed formally trademarked, but avoid anyway — reusing a distinct, well-known project's exact name for something unrelated reads as a claimed affiliation that doesn't exist |
| `docmap.nvim` | Open. Matches the existing code/command names (`docmap`, `:LibMap`, `:LibBrowse`) — safest choice, no re-branding for anyone already using it via lib.nvim |
| `docgraph.nvim` | Open. States what it is (doc + require/call/type/inheritance graphs) with no metaphor |
| `luagraph.nvim` | Open. Leads with the static-analysis/graph angle over the doc-site angle |
| `codeatlas.nvim` | Open. "Atlas" (a book of maps) extends the metaphor to match the Doxygen-parity breadth better than "map" alone |
| `structura.nvim` | Open. Drops the map metaphor entirely — neutral, more "serious tool" reading |

Re-check before actually registering — availability changes. (Moot now:
the repo shipped as `documentation.nvim`, not any of the above.)

## Related-plugin feature survey

Two of four repos found while researching names turned out relevant, two
didn't:

**Not relevant** — [hkupty/cartographer.nvim](https://github.com/hkupty/cartographer.nvim)
(archived project/file/regex/TODO finder, author recommends telescope.nvim
instead; nothing about analysis or graphs) and
[Iron-E/nvim-cartographer](https://github.com/Iron-E/nvim-cartographer) (a
keymap-definition DSL, unrelated to documentation entirely — a name
collision only, not a feature one).

**[dooku.nvim](https://github.com/Zeioth/dooku.nvim)** — same problem space,
opposite architecture: a thin wrapper shelling out to *external*
per-language doc generators (Doxygen/Typedoc/JSDoc/Rustdoc/Godoc/LDoc/Yard)
and opening the HTML result. docmap's own-treesitter-analysis, zero-external-
tool-dependency approach is a deliberate, worth-keeping difference, not a
gap. Its generate-on-write option is the "regenerate on save" idea already
rejected in `ROADMAP.md`'s own "Deliberately not building" table
(unintended diffs); `:DookuOpen` is already `:LibMap open`. Nothing here
worth adopting.

**[wayfinder.nvim](https://github.com/error311/wayfinder.nvim)** — closest
relative of `:LibBrowse`, genuine candidates if `:LibBrowse` gets revisited
(none currently scheduled, listed roughly cheapest/most-valuable first):
1. ~~**`?` key-hint overlay** and **`:checkhealth docmap`**~~ — both
   shipped. They were correctly ranked cheapest-first: together they cost
   one afternoon.
2. ~~**Trail**~~ — shipped. `p` pins the entry under the cursor in any
   mode, `6` lists them, `d` unpins. One `p` rather than wayfinder's
   `p`/`a`/`A`: pressing it on something already pinned has exactly one
   sensible meaning, and a second key would only make the first worse.
3. ~~**Saved Trails**~~ — shipped. Read as one feature or two; it was built
   as both, since auto-persisting the working trail and naming copies of it
   are the same serialization of the same table. `S` saves, `L` loads
   additively, `X` forgets.
4. ~~**Local list filter**~~ — shipped as `f`, in every mode rather than
   only Deps/Calls: it narrows `st.entries`, which every mode has, so
   restricting it would have been extra code to do less.

Already covered, no gap: wayfinder's quickfix export (`x`) is already
`:LibBrowse`'s `gq`.
