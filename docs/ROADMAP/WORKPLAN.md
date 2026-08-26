# Work plan — the language axes and what follows from them

> **A record, not a queue.** Since 2026-08-20 the open items of all three
> repositories live in **one** plan:
> [`docmap-desktop/docs/PLAN.md`](https://github.com/StefanBartl/docmap-desktop/blob/main/docs/PLAN.md). This document keeps what does not
> belong there — the derivation, including the parts that turned out to be
> wrong assumptions. The checkboxes are removed so that it does not look like
> a second queue.

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
the verification evidence lives in `docs/FEATURE_LOG.md`.

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
`docs/FEATURE_LOG.md`.

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
- [x] ~~Doc-coverage split per language, rather than one average that is true
      of neither half.~~ — built 2026-08-20 as `doccoverage.by_language`,
      and it found a defect on its first real run: against a mixed Lua/Zig
      tree the breakdown said `zig 0/2` for a file whose documented function
      was documented. The measure demanded `@param` lines from a language
      that has none, so every Zig function had scored undocumented since Zig
      shipped — hidden by exactly the tree-wide average this item asked to
      split. Fixed with the `param_docs` contract field; `false` on nine
      backends, absent means true, so an unknown language keeps the strict
      rule.
- **Acceptance:** the mixed fixture's map distinguishes its Lua and its
  TS nodes without the reader inspecting paths.

### 2.3 ~~Look at the window~~ — partly closed 2026-08-19

Screenshots arrived, and they were worth more than every structural check
before them: the menu bar, the feedback dialog and two real maps in the
window. Three things only a human could have reported came out of them —
a promoted feature tab pushing the permanent tabs onto a second row, the
Features tab rendering raw Markdown, and a dark theme that stopped at the
sidebar because the map is a different origin.

**Still not seen:** the keyword card's Tab-navigation. Unverifiable from
here for the same reason as before — a non-compositing pane never takes
window focus, so `focusin` never fires — and unchanged since the note
that first said so.

The project list that this worried about no longer exists: `docmap-desktop`
replaced it with a picker, so "does the third line break the row height"
is moot rather than answered.

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
- [x] ~~**Marker comments in the Notes tab**~~ — built 2026-08-19,
      `core/markers.lua`. Reported by an author whose tree is full of
      `-- TODO:` and whose Notes tab said `Todo 0`: those sections read
      LuaCATS annotations and were never counting comments. Keyword set is
      `todo-comments.nvim`'s, alias for alias. Comment boundaries come from
      the grammar, not from a pattern — the text-scanning first version
      reported three to-dos that live inside string literals in this
      repository's own renderer. Schema 4.
- [x] ~~**Marker comments for the languages added after Lua and ECMA.**~~
      Closed 2026-08-19 by `TESTS/backend_contract_spec.lua`, which fails a
      registered backend that declares no comment syntax — and fails it
      naming the consequence, since the default (skip rather than guess) is
      right and silent. Checked by emptying the Lua backend's tokens: two
      specs go red.
- [x] ~~**Markers in `check.lua` and Quicks**~~ — decided and built
      2026-08-20: **Quicks yes, `check.lua` no.** The argument the entry was
      waiting for is the line between a measurement and a claim. Every
      `check.lua` finding is something this tool found by comparing
      documentation to reality; a `FIX` marker contradicts nothing — it is
      the author stating a fact about their own code. Gating on one would
      render a claim like a measurement, and would fail the repository that
      wrote its defect down while passing the one that kept quiet.

      `recorded-defects`, weight 55, `tab: notes`, `bad = 1`, `FIX` family
      only (`TODO`/`HACK`/`PERF` are scheduled work and stay in the tab).
      Its `basis` says whose claim the number is and that nothing fails
      because of it — asserted in `TESTS/quicks_spec.lua`, because that
      sentence *is* the feature. See `docs/FEATURE_LOG.md`.
- **Per-entry reference anchors**, once someone has opened them. The
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
- **A cross-repo dashboard** in `docmap-desktop`, which is the one place
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
- **Other plugin managers.** `plugins.lua` is scoped to lazy.nvim's spec
      shape and says so; packer's `use {…}`, vim-plug's `Plug '…'` and
      mini.deps' `add()` are separate extractors, not a bent version of that
      one.
- **Lazy-load inventory** — which plugin loads on which event/ft/cmd,
      from spec fields already parsed. Answers "why is this not loaded yet",
      which is the second question a config is opened for.
- **Orphaned spec files** — a `lua/plugins/foo.lua` whose plugin nothing
      references any more.

Sequence note: keymap conflicts first. It is a check over data that already
exists, so it proves the config-shaped direction is worth extending before
any new extractor is written for it.

---

## Part 4b — shipped 2026-08-19, after this file was last rewritten

Recorded here rather than folded into the parts above, because those are
organised by the plan they came from and none of these did.

- [x] **Marker comments** — `-- TODO:`, `// FIXME:`, `-- PERF:` in the
      Notes tab, `todo-comments.nvim`'s keyword set alias for alias.
      Comment boundaries come from the grammar, not from a pattern: the
      text-scanning first version reported three to-dos that live inside
      string literals in this repository's own renderer. Schema 4.
- [x] **`?theme=`** — the page takes its theme from the URL, read in
      `<head>` before first paint. Built because an embedding host cannot
      reach across an origin boundary, which is why choosing dark in
      `docmap-desktop` left a white page inside a dark window.
- [x] **An inbound channel, questions only** — `export-svg` and `state`.
      No instructions: a host that wants the page somewhere navigates the
      frame's URL. Unknown verbs get silence; replies go to the asker's
      origin, never `"*"`.
- [x] **Eight tabs and a second level** — Index owns Tree/Functions/
      Modules, Features owns the promoted ones. `state.tab` unchanged, so
      every shared link still lands where it did.
- [x] **The engine says which build it is** — `--capabilities` reports the
      artifact schema and, in a bundled binary, the commit it was built
      from and whether that tree was clean. A version number would have
      been fiction: the only tag is `standalone-latest`.
- [x] **Branding** — a topbar naming the tool, and `· documentation.nvim`
      in the browser title of every map except this repository's own.

---

## Part 4c — config analysis, shipped 2026-08-21

Part 4 named three remaining config-shaped items. Two are settled, and
**the measurement changed both of them** — recorded here because the
correction is the useful part, not the feature.

- [x] **Lazy-load inventory** — its own analysis tool: which plugin loads on
      which event / ft / cmd / keys, and what sits at startup. Measured
      against a real config first, and the entry that came back was
      mislabelled: 7 of 52 specs were `lazy = true` with no trigger of any
      kind. Read as written, that says "loads later"; what it means is
      "never loads". Three load states, then, not two.
- [ ] **Orphaned spec files — decided 2026-08-21: not built.** A `no`
      is a result. The single real candidate in the one config available was
      a **false positive** — the file registers through a helper — and the
      remaining candidates declare nothing only because their contents are
      deliberately commented out. "Names no plugin" therefore does not
      separate a dead file from a parked one, and a panel that reports
      parked files as rot is worse than no panel. Reopen only with a corpus
      that can show the criterion holding.
- [x] **`opts.plugins.wrappers`** — not on the list, and the largest of the
      three. Chasing that false positive: `core/plugins.lua` read only a
      file's own `return { … }`, so a config registering through
      `plugins.add({ … })` contributed **nothing**, silently. Measured:
      **52 specs, against 85 once the one wrapper was declared** — the
      missing 33 in a single 906-line file, 63 % of that config invisible,
      with every panel over `n.plugins` quietly answering about the half
      that happened to use a table literal. Declared, never detected, as
      `bindings.wrappers` already was. The module header's claim that
      "every sampled file uses the direct form" was true when written and
      is corrected in place rather than deleted.

- [x] **Other plugin managers — and they were not M.** Rated a day's work as
      three separate extractors; measured first, they are none. packer's
      `use`, vim-plug's `Plug` and mini.deps' `add` all register through a
      call taking a table or a string, which the wrapper walk already
      handled. What was genuinely missing was two small things: a *string*
      argument (`use "a/b"`, and with it packer.nvim itself, which its own
      config always lists that way), and three key spellings — `requires`,
      `depends`, `source`. The trigger keys are spelled identically across
      managers and needed nothing. Declaration per manager, one line each,
      in REUSE.md.

      vim-plug in its Lua call form only. `Plug 'a/b'` in a `.vim` file is
      VimScript; that config is out of reach here rather than half-read, and
      saying so is cheaper than a second parser.

- [x] **The Reference tab — decided 2026-08-21: not built.** Step 6 of
      `ReferenceTab.md` asked honestly whether the panels still earn a tab
      once the in-place lookups exist. Counted over this repository's 791
      snippets: 64 of the Lua glossary's 76 entries are reachable by
      hovering something already on screen, 18,807 decorations emitted. A
      tab would index answers the reader already meets at the point of the
      question.

      The count paid for itself anyway: the stdlib glossary was keyed by
      dotted name, and Lua is written with colons — **1004 colon calls
      against 6 dotted ones** for the same eleven functions, i.e. the most
      common stdlib call shape in the language was invisible to the feature
      built to explain stdlib calls. A declared `syntax.method_namespace`
      fixed it, +934 decorations, verified by running the page's own
      tokenizer over the generated artifact.

**Part 4's config-shaped work is complete.** The estimate that was wrong
twice in one file — M for the extractors, S for the orphan check — was wrong
in the same direction both times: it described the feature instead of the
gap. The gap is only visible by running the thing against real code.

---

## Part 5 — document hygiene

> **Escalated 2026-08-19 from hygiene to a rebuild.** The items below are
> corrections — idea files that still list built things. The request that
> came back from the installed app is larger and it is right: a great deal
> has shipped that the docs and the README cover thinly or not at all, and
> the fixes made today were patches. They repaired what had become false,
> not what was never written.
>
> Do it as a rewrite with an inventory first — what exists, what is
> documented, then close the gap. `docs/FEATURES/` is the nearest thing to
> that inventory and is itself incomplete.
>
> One thing it has to say that nothing anywhere says today: **a generated
> map is a snapshot of the engine that wrote it.** Page-side features
> arrive by regenerating, not by updating whatever is reading the map.
> That was found the hard way — a fixed feature looked broken in an
> installed app because the map on disk predated the fix.
>
> Tracked jointly with `docmap-desktop`'s `docs/WORKPLAN.md` §10.7, since
> it is one job across two repositories.
>
> **This repository's half done 2026-08-20**, by the same method: inventory
> from the code first. What it found, in the order it hurt:
>
> - **`docs/PIPELINE.md` — "the document to read before changing anything",
>   2158 lines — did not mention multi-language support once.** Its eleven
>   matches for "language" were all `lua-language-server` or Compiler
>   Explorer. It opened with "an annotated Lua tree" and described a scan
>   stage that hardcodes `init.lua`, which stopped being true at the first
>   backend. `REUSE.md`, `WORKFLOW.md` and `MCP.md` mention languages zero
>   times each. **The folder described a nine-months-younger tool.**
> - **No per-language reference existed anywhere.** The only record was
>   `IDEAS/MULTILANG.md` — a *decision log*, in a folder named for things
>   not yet built. Now [`docs/LANGUAGES.md`](../LANGUAGES.md): the
>   twenty-three backends tabulated from `lang_registry.report()`, the
>   contract field by field, grammar resolution and the three-state
>   handshake, every `DOCMAP_<LANG>_PARSER`, and what adding one costs.
> - **The folder had no index.** Thirty-odd files; the README's table listed
>   eighteen. Now [`docs/README.md`](../README.md), grouped by the question
>   a reader arrives with.
> - **Two counts in prose disagreed with the code**, and tabulating the
>   registry is what caught both: `param_docs = false` is **nine**
>   languages, not eight — Ruby was called "a different case" and then
>   dropped from the total — and there are **four** directory-owns-a-module
>   conventions, not three; Rust's `mod.rs` was missing from the README's
>   sentence and knew it was the fourth in its own header. Neither affected
>   a number the tool reports, both were fixed at the source.
>
> **The lesson, worth more than the fixes:** a count written in a document
> is a claim, a count derived from the code is a fact — and the docs that
> were most wrong were the ones nobody suspected, because they had been
> *edited* recently without being *re-inventoried*.

Agreed convention, to be applied across both repos' `docs/`:

- Anything **built** moves to `docs/FEATURE_LOG.md` (engine) with its
  verification evidence, and is **removed** from the idea/roadmap file rather
  than left ticked. A backlog that keeps its completed items stops showing
  what is left.
- `docmap-desktop/docs/HANDOVER.md` keeps its existing convention: an item
  that is done *and pushed* is struck out entirely.
- Two files must never describe one thing. Where a plan spans both repos,
  the engine repo holds it and the desktop repo links to it.

Open pass:

- `IDEAS/IDEAS.md` — several entries are marked done inline
      (§3.4, §4.1, §8.2) rather than removed.
- `IDEAS/IDEAS_IMPLEMENTATION_PLAN.md` — re-rate now that §9's cost has
      been paid four times, and that §1.7's blocking precondition is met.
- `IDEAS/MULTILANG.md` — Phase 0's stage list still shows items this
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
