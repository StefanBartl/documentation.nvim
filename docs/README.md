# `docs/`

The index this folder went without for too long. Thirty-odd files, and until
now the only way to find the right one was the table at the bottom of the
[README](../README.md) — which lists eighteen of them.

Start with the [README](../README.md) if you have not: it is the tour. This
page is the map of the documentation itself, grouped by the question you
arrived with.

---

## Using it

| Document | Answers |
|---|---|
| [`COMMANDS.md`](COMMANDS.md) | `:DocMap` and `:DocBrowse`, subcommand by subcommand — all twenty-one actions, what each writes, and why the read-only browser is a separate command rather than `:DocMap browse`. |
| [`WORKFLOW.md`](WORKFLOW.md) | Day to day: which panel answers which question, how to read the Telemetry join's badges correctly, Trail vs filter vs fuzzy jump. The one document about *combining* features rather than describing them. |
| [`BINDINGS.md`](BINDINGS.md) | Every key, user command and autocommand this plugin installs. **Generated** from the tables that drive the plugin — do not edit by hand. |
| [`CALL_HIERARCHY.md`](CALL_HIERARCHY.md) | Incoming/outgoing calls in Neovim's native LSP UI, alongside LuaLS (which has none): setup, keymaps, and how to tell an unattached client from a function with no callers. |
| [`EXAMPLES/`](EXAMPLES/README.md) | Runnable snippets for the parts of the API easier to read as code than as prose. |

## Pointing it at your own code

| Document | Answers |
|---|---|
| [`REUSE.md`](REUSE.md) | Generating a map for your own repository — editor, CI and pre-commit hook, cross-project links, and what the tree has to look like. |
| [`LANGUAGES.md`](LANGUAGES.md) | **Twenty-three backends**: what each one reads, the `Documentation.LangBackend` contract field by field, how grammars are resolved, what a missing one costs, and how to add the twenty-fourth. |
| [`ANNOTATION_TAGS.md`](ANNOTATION_TAGS.md) | Annotating your own plugin: what each LuaCATS tag buys you here, the minimum viable set, and which custom tags would be worth adding. |
| [`FRAMEWORK_CONVENTIONS.md`](FRAMEWORK_CONVENTIONS.md) | The layer *above* language support — recognizing an ecosystem's structural convention (lazy.nvim specs today; Next.js-style file routing and React hooks costed as the web case). |
| [`FEATURES_FORMAT.md`](FEATURES_FORMAT.md) | The `docs/FEATURES/` shape the Features tab reads, and what happens when you leave a piece out. |
| [`CHECKLIST_FORMAT.md`](CHECKLIST_FORMAT.md) | The hand-verified ledger: a syntax for facts a scanner cannot decide, watched for staleness by their citation rather than re-derived. |
| [`HOSTING.md`](HOSTING.md) | **Embedding the map in your own program**: the `--capabilities` handshake, the `--api=<route>` answers, `?theme=`, and the two-way message channel between the page and its frame — including why the page answers questions and takes no instructions. |
| [`MCP.md`](MCP.md) | The MCP server: exposing the module tree, require graph, call graph and drift findings to a coding agent as tools. |
| [`SECURITY.md`](SECURITY.md) | What this plugin does that could hurt you, what it refuses to do, and what it deliberately does not defend against. |

## How it works

| Document | Answers |
|---|---|
| [`PIPELINE.md`](PIPELINE.md) | **The document to read before changing anything.** Every stage, every design decision, and the measurement behind each one. |
| [`DEVELOPMENT.md`](DEVELOPMENT.md) | Running the specs, the linters and the map locally. |
| [`ANNOTATIONS.md`](ANNOTATIONS.md) | The inventory — which LuaCATS tags this tree actually uses, counted. |

## What shipped, what is open, what was turned down

| Document | Answers |
|---|---|
| [`docs/FEATURE_LOG.md`](FEATURE_LOG.md) | The decision record: what shipped, which commit, and why it was built that way. |
| [`FEATURES/`](FEATURES/README.md) | This plugin's own `docs/FEATURES/` catalog — the user-facing half, and the Features tab's first real test. Deliberately a representative sample, not full coverage. |
| **[`docmap-desktop/docs/PLAN.md`](https://github.com/StefanBartl/docmap-desktop/blob/main/docs/PLAN.md)** | **The queue — and it is not in this repository.** Since 2026-08-20 there is one plan for all three (`documentation.nvim`, `docmap-desktop`, `runtime-analysis.nvim`), because the same task used to appear in five places in three different states. Quick wins, medium, large. |
| [`CHECKLIST/architecture.md`](CHECKLIST/architecture.md) | This tree's own hand-verified facts, each cited and dated. |

## Generated, not written

| Path | What |
|---|---|
| [`map/`](map/overview.md) | This repository's own map — [`index.html`](map/index.html), [`overview.md`](map/overview.md), `module_map.json`. Regenerate with `:DocMap` or `scripts/gen_map.lua`; a docs change makes it stale. |
| [`BINDINGS.md`](BINDINGS.md) | Listed above, repeated here because editing it by hand is the mistake it is easiest to make. |
