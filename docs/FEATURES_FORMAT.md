# The `docs/FEATURES/` format: what the Features tab reads, and why

A field guide for **documenting your own plugin's features** so
`documentation.nvim` has something to build its Features tab from. Written
the same way [`ANNOTATION_TAGS.md`](ANNOTATION_TAGS.md) documents `@module`/
`@param`/etc.: what the parser reads, what you get in return, and what
happens if you leave a piece out.

Everything below is verified against the source at the time of writing —
[`core/features.lua`](../lua/documentation/core/features.lua)'s `M.resolve`
is the one function that decides what is understood.

---

## Why this exists, and why it looks like this

Before writing this, three of the user's own plugins already had a
`docs/FEATURES/`-shaped folder — `lib.nvim`, `markdown.nvim`,
`color_my_ascii.nvim` — and all three had independently invented a
**different** shape: essay-style problem/solution write-ups, compact
per-sub-feature metadata blocks, and full per-feature user manuals,
respectively. None of the three matches what a machine can reliably parse
line-by-line without a real Markdown/CommonMark parser, and none of the
three needed one — a human reads all three fine.

This format is deliberately closest to the **middle** one
(`markdown.nvim`'s), because it is the one shape that is both human-writable
prose *and* mechanically recognizable with the same "a cheap reliable
reading beats a general one" discipline `core/deps.lua`'s require-extraction
and `lib.nvim.deps.spec`'s fenced-block parsing already use elsewhere in
this codebase. Nothing here requires YAML, JSON, or a schema — a
`docs/FEATURES/` folder that predates this document and merely happens to
use `##` headings and `- **Key:** value` bullets already qualifies.

---

## The shape

```
docs/FEATURES/
  README.md          -- optional: the folder's own intro, shown once at
                         the top of the Features tab. Never itself a theme.
  UI.md               -- one file per theme, name is your own choice
  PERFORMANCE.md
  SECURITY.md
```

`docs/features/` (lowercase) is also recognized, `docs/FEATURES/` (matching
`docs/BINDINGS.md`'s own uppercase convention) is preferred when a repo
somehow ships both — same JSON-preferred-over-Markdown precedent
`lib.nvim.deps.spec`'s `SPEC_FILES` order sets. Neither existing is not an
error: `ir.features` is simply `nil`, and the tab says so — the same
"a missing thing is a real answer, not a broken one" posture `ir.tools`
already takes toward a repo with no `lib.nvim.deps` manifest.

A repo picks its own theme names and its own number of files — one
`FEATURES.md` for a small plugin, a dozen theme files for a large one.
Nothing here prescribes a taxonomy; `docs/FEATURES/README.md` is where a
repo states its own.

---

## Inside a theme file

```markdown
# UI

Everything that draws something on screen.

## Status line marker

Shows the current mode in the status line, updated on every mode change.

- **Module:** `ui/statusline.lua` (`render`, `on_mode_changed`)
- **Config:** `opts.statusline.enabled` (default `true`)

## Cache eviction indicator

A feature does not have to be a visible action — a background cache that
evicts entries on a TTL counts too, and this one has nothing to bind a key
to.
```

- **A leading `# Title` plus prose before the first `##`** becomes the
  file's own intro, shown once above its features in the tab. Optional —
  a file that opens directly on a `##` has no intro, which is a real state,
  not a parse failure.
- **Each `## <name>`** is one feature. `name` is free text — it is what
  the tab's index shows, so write it the way a reader would look for it,
  not as a code identifier.
- **The first run of prose lines after the heading** is the feature's
  summary — one or a few sentences, no format requirement. A feature can be
  *only* this: the "cache eviction indicator" example above has no metadata
  bullets at all, and is still a complete, valid entry.
- **A contiguous run of `- **Key:** value` bullets**, immediately following
  the summary, is parsed into ordered key/value metadata. "Contiguous"
  matters: a blank line ends the run, so prose written *after* a metadata
  block (an example, a caveat) is never mistaken for more metadata.

### The metadata bullets

**There is no fixed vocabulary, and validating one was deliberately not
built.** `lib.nvim.deps.spec` enforces `bin`/`why`/`pkg` because that format
feeds an installer — a missing field there is a real defect. A feature
write-up feeds a reader, and `markdown.nvim`'s own real
`docs/FEATURES/headings.md` already uses `Module`, `Keymaps`, `Config`, *and*
one-off keys like `Scope-aware` in the same file — a whitelist would have
rejected working documentation that predates this parser. Any
`- **Label:** text` line is captured as `{key = "Label", value = "text"}`,
in the order written, duplicates and all.

That said, three keys are worth using consistently, because the Features
tab treats them specially when present:

| Key | What the tab does with it |
|---|---|
| `Module` | If the value contains (or is) a path this repo's own scan recognizes, the row links straight to that node in the Tree tab — the same resolution `:DocMap why`'s module-name matching already does, not a new one. |
| `Keymaps` / `Usercmds` / `Autocmds` | Rendered as-is; not cross-resolved against `docs/BINDINGS.md`'s own rows (which have no per-row anchors to resolve *to* — see "What this deliberately does not do" below). Write these as a normal Markdown link to `../BINDINGS.md#keymaps`/`#user-commands`/`#autocommands` yourself if you want a click-through; the tab only renders the link, it does not invent one. |
| `Config` | Rendered as-is. No cross-check against `config/DEFAULTS.lua` — that would mean parsing Lua defaults generically across every consuming plugin's own shape, a real feature and not this one. |

---

## What this deliberately does not do

- **No full Markdown rendering.** The Features tab is an index — theme,
  feature name, summary, metadata — the same shape the Plugins and Tools
  Analysis panels already are, not a prose viewer. Anything written in a
  theme file *after* the metadata bullets (a longer example, a
  troubleshooting section) stays in the file; the tab links out to it
  (`srcUrl`-resolved the same way every other source link on the page is)
  rather than re-rendering it. A plugin that already writes full
  `color_my_ascii.nvim`-style manual pages loses nothing — the tab still
  extracts name/summary/metadata from the top of each `##` section and
  links to the rest.
- **No per-row anchors into `docs/BINDINGS.md`.** GitHub-flavored Markdown
  does not anchor individual table rows, only headings — `docs/BINDINGS.md`
  as generated by `bindings/docs.lua` has exactly three anchors
  (`#user-commands`, `#keymaps`, `#autocommands`), not one per command. A
  `Keymaps:` bullet can link to the whole section; resolving to one row
  would need `docs/BINDINGS.md` to grow per-row ids, a change to a
  different, already-stable generator this feature does not touch.
- **No hover-icon "which feature uses this function" affordance.** The
  roadmap item this format ships for names this explicitly as a
  **separate, speculative follow-up**, gated on a position-to-feature
  index that does not exist yet ("beim Hovern über eine Funktion/Table [...]
  ein Icon zeigen, welche Feature(s) diesen Code-Teil gerade einsetzen").
  Building it here would have answered a question nobody asked yet at the
  cost of the question that was: an index that exists at all.
