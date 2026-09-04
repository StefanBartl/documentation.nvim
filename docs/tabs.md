# The generated page, tab by tab

What each tab of `docs/map/index.html` shows, and why it shows it that way.
[The README](../README.md) says what the page *is*; [`pipeline.md`](pipeline.md)
says how each of these is computed. This page is the tour in between.

The Analysis tab ranks the tree eight ways, seven of them over the same IR —
test coverage, documentation coverage, fan-in/fan-out, cyclomatic complexity,
structural **duplicates** (functions whose parse-tree shape is identical,
which is the one kind of drift the require graph is blind to by construction
— two modules that each grew their own `read(path)` do not require each
other), **plugins**: every lazy.nvim spec in the tree, which matters when
`documentation.nvim` is pointed at a Neovim *config* rather than a plugin —
`lua/plugins/*.lua` is mostly `return { { "author/repo", event = "…" } }`
with no function in sight, invisible to every other panel — and **tools**:
this repo's own [`lib.nvim.deps`](https://github.com/StefanBartl/lib.nvim)
manifest (`docs/install.json`/`docs/INSTALL.md`), declared only — never a
live "is this installed here" probe, since a static page has no host to
ask. The eighth, **telemetry**, is the odd one out on purpose: call counts
change between runs, so unlike the other seven it is never baked into the
page — `:DocMap serve` reads [`runtime-analysis.nvim`](https://github.com/StefanBartl/runtime-analysis.nvim)'s
own counts fresh on every open instead, the same on-demand shape the
History tab already uses for the one other thing that cannot live in a
static artifact.

The Hierarchy tab draws six graphs over the same IR — **Modules** (directory
hierarchy), **Types** (`@class`/`@alias` collaboration), **Inheritance**,
**Deps** (the require graph), **Calls** (function-level caller/callee) and
**Module Calls** (the same call graph collapsed module-to-module, edges
weighted by call count) — with direction and depth controls, semantic zoom,
right-click navigation and real browser Back/Forward. Right-click any box to
dim it (a "Hidden (N) — show all" pill clears them), shareable via the URL
the same way marks are — noise-reduction for a large tree, not a structural
re-layout. The Modules view also has a vertical zoom-style slider that hides
the top N levels of a deep tree, turning every node that used to sit at that
depth into its own parallel root — useful the moment a tree is several
directories deep before anything interesting starts.

The Deps and Module Calls views' `+ external` toggle answers *why* a
dependency is there, not just that it is: each external box's tooltip
breaks down exactly which functions were actually called and how often
(`plenary.async.run (2×)`), counted from the same call-resolution pass as
the internal call graph — no
second traversal. `opts.external_repos` turns the box into a working GitHub
link too, verified against a local checkout when you name one (`opts.tag_files`
does the same for another `docmap`-shaped project's own committed map).

The **Quicks** tab states the same tree in sentences instead of tables — *"Most
of your published API is never named in a spec — 12% — 9 of 72"* — negatives
first, five of each polarity. Every verdict carries a line saying what was
actually measured, including its blind spot, and links to the panel holding the
rows it came from; a number that sounds this confident has to be checkable, or
it breaks the same rule `calls_heuristic` and `dead_code` are off by default to
keep. A verdict appears only when it passes one of two cut points, so an empty
Quicks tab means every measure landed in the unremarkable band — a good
reading, not a broken one. Purity is deliberately *not* among them: nothing in
the IR records side effects, and the cheap approximations would be exactly the
confident guess this plugin refuses elsewhere.

The **Compare** tab holds whatever you marked with the `+` beside any function
or module. Its Matrix layout puts attributes down the side and marked objects
across, highlighting every row where they disagree — *"where do these four
differ"* has no other answer on the page. Marks travel in the URL and survive a
reload; a negative Quicks verdict offers **Mark all N** straight into it.

The **Features** tab reads a repo's own `docs/FEATURES/` folder, when it has
one — one card per `## Feature` section, its summary and whatever
`- **Key:** value` metadata the author wrote (`Module`, `Keymaps`, `Config`,
or anything else; there is no fixed vocabulary). An index over hand-written
prose, not a Markdown viewer — a `Module:` bullet that resolves to a real
node links straight into the Tree tab, the rest of the file stays exactly
where the author put it. A `- **Tab:** true` bullet promotes the rare,
especially-important feature out of the card list entirely and into its own
top-level tab, with everything after its metadata rendered through a small
Markdown subset instead of just linked out to. See
[`docs/features_format.md`](features_format.md) for the format this
tab reads, and this repository's own [`docs/FEATURES/`](FEATURES) for
a real (if deliberately small) example — including one promoted feature.
