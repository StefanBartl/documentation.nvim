# Work plan — the language axes and what follows from them

**Purpose: this file is the resume point.** Everything agreed in the session
of 2026-08-18 is written down here, including the parts not built, so the
work can continue from a cold start in another chat with nothing lost. It is
a *work* plan, not a design document — the reasoning behind each item lives
in the `IDEAS/` file it points at, and is not repeated.

Spans two repositories. `documentation.nvim` owns the engine and the
generated page; [`docmap-desktop`](https://github.com/StefanBartl/docmap-desktop)
owns the window in front of them. Items are marked which.

---

## Table of content

- [Where things stand](#where-things-stand)
- [Part 1 — done in this session](#part-1--done-in-this-session)
- [Part 2 — next, and why in this order](#part-2--next-and-why-in-this-order)
- [Part 3 — the standing backlog, re-rated](#part-3--the-standing-backlog-re-rated)
- [Part 4 — the plugin corpus and Neovim configs](#part-4--the-plugin-corpus-and-neovim-configs)
- [Part 5 — document hygiene](#part-5--document-hygiene)
- [Part 6 — how to verify anything here](#part-6--how-to-verify-anything-here)

---

## Where things stand

Two axes that share a word and almost nothing else:

| Axis | Meaning | Plan |
|---|---|---|
| **Multilang** | Which programming languages the engine *reads* | [`IDEAS/MULTILANG.md`](IDEAS/MULTILANG.md) Part 4 |
| **i18n** | Which interface language it *speaks* | [`IDEAS/I18N.md`](IDEAS/I18N.md) |

They touch in exactly one place — both rewrite `check.lua`'s `add()`, and
done separately the second rewrites the first. See I18N.md Part 5.

The lookup layer (keyword hover and its relatives) is a third strand,
planned in [`IDEAS/ReferenceTab.md`](IDEAS/ReferenceTab.md) § *The lookup
layer*.

---

## Part 1 — done in this session

Recorded so a reader knows what *not* to redo. Detail lives in the commits;
the verification evidence lives in `docs/FEATURES/FEATURES.md`.

**Engine (`documentation.nvim`):**

- `lang_registry.report()` and `languages` in `--capabilities` — the backend
  list, with a three-valued `grammar_loaded` (`true` / `false` / absent,
  where absent means "needs no parser" and is not a degradation).
- Keyword hover in rendered snippets. Glossary per backend, reached through
  `lang_registry.glossaries()`, keyed by file extension; strings and
  comments skipped by per-language delimiters; one base reference URL per
  language, per-entry anchors deliberately unfilled until someone opens them.
- `config.detect_source` asks the backends instead of assuming Lua. **This
  fixed a hard failure:** a JavaScript project could not be scanned at all
  (`source directory not found: <root>/lua`), despite the engine having read
  JS/TS since Phase 1.
- `opts.source` takes a list; `scan.lua` walks every root, with a synthetic
  parent node **only** when there is more than one. A mixed tree used to map
  one half and say nothing about the other.
- `scan.lua` gained `VENDOR_DIRS`, which a `src`-or-root `source` makes
  necessary.

**Desktop (`docmap-desktop`):**

- `scan_languages` — file-extension counts per project, no engine needed.
  Skips any subdirectory that is its own checkout (found by measurement:
  306 of 448 "Lua files" in this repo were copies of itself under
  `.claude/worktrees/`).
- `engine_languages` — reads the engine's backend list, joined with the
  count **on the tree-sitter grammar name**, so neither side has to know the
  other's vocabulary.
- The Engine panel's verdict is asked, not inferred: it used to read "ready"
  whenever a grammars *directory* resolved, so one grammar out of four still
  said "ready".

---

## Part 2 — next, and why in this order

### 2.1 ~~The report says what it did not look at~~ — **built 2026-08-18**

The failure this session found twice was the same shape both times: a map
that looks healthy and is silently missing half its subject. `VENDOR_DIRS`
and the multi-root walk both narrow it; neither closes it.

`ir.meta.unclaimed`/`outside`/`claimed`. The report fires only for a
language wholly absent from the map, because `outside` alone would print a
line on every run for every repository with a `scripts/`. Detail in
`FEATURES/FEATURES.md`.

### 2.2 Language legend in the page — engine

A map can now hold several languages, and nothing on screen says which node
is which.

- [x] `language` per node, schema 3 — **built 2026-08-18**, including the
      schema-tolerance check against a real schema-2 artifact.
- [x] **A legend and a filter in the Tree view** — built 2026-08-18. Drawn
      only when the map holds more than one language, so the common case pays
      nothing (verified: single-language map renders an empty, hidden bar).
- [x] The same for the **Hierarchy** views — built 2026-08-18. Dims rather
      than removes: taking boxes out of a graph re-flows every remaining one
      and can disconnect the picture, so the reader loses the shape they
      were looking at in order to ask a question about part of it.
- [ ] Doc-coverage split per language, rather than one average that is true
      of neither half.
- **Acceptance:** the mixed fixture's map distinguishes its Lua and its
  TS nodes without the reader inspecting paths.

### 2.3 Look at the window — desktop

Still not done and still the oldest debt. The sidebar language line, the
Engine panel's new language list, and the keyword card have all been
verified structurally and in a real browser DOM; **none has been seen by a
human**. Specifically worth checking: does the third line in the project
list break the row height, and does real Tab-navigation reach the keyword
spans (unverifiable here — a non-compositing pane never takes window focus,
so `focusin` never fires).

---

## Part 3 — the standing backlog, re-rated

[`IDEAS/IDEAS_IMPLEMENTATION_PLAN.md`](IDEAS/IDEAS_IMPLEMENTATION_PLAN.md)
already rates everything in `IDEAS.md` by effort and benefit. Its open
**quick wins**, in its own recommended order:

| § | Idea | Note |
|---|---|---|
| ~~1.2~~ | ~~`@example` blocks that do not parse~~ | Built. Cheap as rated, but no tree in this ecosystem uses `@example` — it has never fired on real code |
| ~~6.1~~ | ~~SARIF output for CI~~ | Built as `--sarif=<path>`. Findings carry **no** line, contrary to that entry's claim; every result points at line 1 and says so |
| ~~2.5~~ | ~~Unused requires~~ | Built as `unused-require`. 144 aliased requires here, none unused |
| ~~3.2~~ | ~~Copy-link for the current view~~ | Built |
| ~~6.3~~ | ~~Publish the map to GitHub Pages~~ | **Was already built** — `pages.yml`. Listed as open because nobody checked |
| ~~6.4~~ | ~~Mermaid export~~ | Built as `:DocMap mermaid [tree\|deps]` |
| ~~9~~ | ~~Schema versioning + a payload-contract test~~ | **Built 2026-08-18.** Its first run caught a sixth victim: `endpoints`, absent from the artifact since `core/endpoints.lua` shipped |

**§9 was built the same day it was promoted, and was worth it immediately.**
`html.lua`'s comment thread records `duplicates`, `docs`, `quicks` and
`checklist` each added to `ir` and forgotten in the page payload; this
session added `glossaries` as the fifth and only got it right by reading
that comment. The test's first run found the sixth without anyone looking:
`endpoints`, absent from `module_map.json` since `core/endpoints.lua`
shipped, invisible because the *page* encodes node tables wholesale and so
showed routes the artifact never carried.

**Both halves of §9 are now built.** `TESTS/artifact_contract_spec.lua`
covers `ir` against `to_json`; `TESTS/payload_contract_spec.lua` covers `ir`
against `html.lua`'s payload list — the half the trap actually lived in, and
the one that swallowed four of the six victims. Each was verified by
deleting a field and watching it fail, rather than by passing.

**Every quick win in that list is now closed**, one of them by discovering it
had shipped already. What is left in `IDEAS.md` is the work that was never
rated cheap: §1.1 (code blocks checked against the API), §1.3 (API-surface
change detection), §2.1/§2.2 (the panels gated on the `TAGS` refactor), §5.x
(framework conventions) and §6.2/§6.6.

**§1.7's precondition is met**, and the entry in
`IDEAS_IMPLEMENTATION_PLAN.md` has been updated to say so — see Part 4.

### Additional items from this session, not previously recorded

- [x] ~~**Stdlib hover**~~ — built 2026-08-18. One correction to the note
      this item carried: `calls_external` does **not** know which stdlib
      names a tree uses; it tracks required *modules*, and `table.concat` is
      a global. The entries were chosen from a direct count of the source
      instead (`ipairs` 405, `require` 328, `table.sort` 79, `vim.trim` 40).
- [x] ~~**A mixed-language fixture in CI.**~~ Built 2026-08-18 as
      `TESTS/fixtures/polyglot/` — a tree, not snippets: two source roots, a
      helper beside a module, a file outside every root, an extension no
      backend claims. Verified to fail rather than assumed to pass: with
      ECMA source detection disabled it reports `expected "lua/pgl + src",
      got "lua/pgl"`, which is the exact shape of the failure it exists for.
- [ ] **Per-entry reference anchors**, once someone has opened them. The
      renderer already supports them; they are unfilled on purpose.
- [x] ~~**`.jsx`**, **class methods**, **`module.exports = {…}`**~~ — all
      three closed 2026-08-18, each shape verified against a real parse
      first. Class methods are flat-named `Class.method`; the Phase-0
      owning-scope field remains required for Python and Rust.

---

## Part 4 — the plugin corpus and Neovim configs

Checked against the real trees in `E:\repos`, not assumed.

### 4.1 What the corpus actually is

**33 `.nvim` repositories, roughly 30 of them already carrying a committed
`docs/map/module_map.json`**, and one shared library (`lib.nvim`) that the
others consume 9–25 distinct modules of apiece.

**There is no feature worth building *only* for these plugins.** They are
ordinary annotated Lua trees and the existing map already serves them. What
the corpus is, is the missing prerequisite for something already in the
backlog and already deferred for its absence:

- [x] ~~**Cross-repository checks over `tag_files` (IDEAS §1.7)**~~ — both
      halves built 2026-08-18. The decision it was waiting on: "no consumer
      requires this module" **cannot** be a check, because that number is a
      floor and asserting it would raise 33 findings against `lib.nvim`
      today, nearly all wrong. It stays a report. `consumer-require-missing`
      is the direction that can be asserted — a consumer's map says in
      writing that it requires something the library does not declare.
- [x] ~~**A reverse index over `lib.nvim`**~~ — built 2026-08-18 as
      `core/consumers.lua` and `:DocMap consumers`. Against 29 sibling maps:
      107 modules required by a consumer, 108 required only by the library
      itself, 33 by nobody. The two-way version says 141 unused, wrong about
      all 108 in between.
- [ ] **A cross-repo dashboard** in `docmap-desktop`, which is the one place
      that already holds several projects at once. The workspace-level view
      no single repository can have.

### 4.2 Neovim configs — what is left after `plugins.lua` and `bindings.lua`

Already built, and not to be re-proposed: lazy.nvim spec extraction
(`core/plugins.lua`), and keymaps, user commands and autocmds
(`core/bindings.lua`). Options (`vim.opt.x = …`) were considered there and
deliberately declined.

What is genuinely missing and is meaningful *only* for a config:

- [x] ~~**Keymap conflict detection.**~~ Built 2026-08-18 as
      `binding-conflict`, covering user commands too. Its first run found a
      bug in `bindings.lua` itself: `buffer` was read through a string-only
      accessor, so every `{ buffer = true }` keymap had been recorded as
      global since the module shipped.
- [ ] **Other plugin managers.** `plugins.lua` is scoped to lazy.nvim's spec
      shape and says so; packer's `use {…}`, vim-plug's `Plug '…'` and
      mini.deps' `add()` are separate extractors, not a bent version of that
      one.
- [ ] **Lazy-load inventory** — which plugin loads on which event/ft/cmd,
      from spec fields already parsed. Answers "why is this not loaded yet",
      which is the second question a config is opened for.
- [ ] **Orphaned spec files** — a `lua/plugins/foo.lua` whose plugin nothing
      references any more.

Sequence note: keymap conflicts first. It is a check over data that already
exists, so it proves the config-shaped direction is worth extending before
any new extractor is written for it.

---

## Part 5 — document hygiene

Agreed convention, to be applied across both repos' `docs/`:

- Anything **built** moves to `docs/FEATURES/FEATURES.md` (engine) with its
  verification evidence, and is **removed** from the idea/roadmap file rather
  than left ticked. A backlog that keeps its completed items stops showing
  what is left.
- `docmap-desktop/docs/HANDOVER.md` keeps its existing convention: an item
  that is done *and pushed* is struck out entirely.
- Two files must never describe one thing. Where a plan spans both repos,
  the engine repo holds it and the desktop repo links to it.

Open pass:

- [ ] `IDEAS/IDEAS.md` — several entries are marked done inline
      (§3.4, §4.1, §8.2) rather than removed.
- [ ] `IDEAS/IDEAS_IMPLEMENTATION_PLAN.md` — re-rate now that §9's cost has
      been paid four times, and that §1.7's blocking precondition is met.
- [ ] `IDEAS/MULTILANG.md` — Phase 0's stage list still shows items this
      session closed.

---

## Part 6 — how to verify anything here

The standing rule, which produced every real finding in this session:
**measure, do not reason.** Concretely:

```
nvim --headless -l scripts/ci.lua          # 5 gates: stylua, luacheck, tests, map --check, standalone
nvim --headless -l scripts/gen_map.lua     # a docs change makes the map stale; regenerate and commit
```

`docmap-desktop`: `cargo test` in `src-tauri/` and
`node --test src/lib/*.test.js`. `cargo test` needs the placeholders CI also
creates (both are `.gitignore`d):

```
mkdir -p src-tauri/binaries src-tauri/resources/grammars
touch src-tauri/binaries/docmap-x86_64-pc-windows-msvc.exe
touch src-tauri/resources/grammars/placeholder.dll
```

Three habits worth keeping, each earned this session:

- **A real tree beats a fixture.** The language counter looked correct
  against fixtures and reported 448 Lua files in a repo holding 98.
- **Pull the code out of the artifact, not out of the source.** The keyword
  tokenizer was tested by extracting it from the *generated page* — the same
  bytes a reader gets — against twelve inputs.
- **A structural check is not a visual one.** Say which was done. Several
  things here are verified in a DOM and have still never been looked at.
