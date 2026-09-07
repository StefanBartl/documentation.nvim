# Contributing to documentation.nvim

Thank you for your interest! Bugs, ideas and questions are welcome in the
[issue tracker](https://github.com/StefanBartl/documentation.nvim/issues); pull
requests very welcome.

**Read [`pipeline.md`](pipeline.md) first.** It carries every stage of the
generator, every design decision and the measurement behind each one. Most
changes that look obvious from the outside are already answered there.

The toolchain — where the headless runners look for `lib.nvim`, and the five
things CI runs — is [`DEVELOPMENT.md`](DEVELOPMENT.md).

## Ground rules

- Lua only, idiomatic Neovim Lua. 2-space indentation.
- **The IR must stay byte-deterministic on unchanged input.** No timestamps,
  sorted-key JSON, stable iteration order. `--check` is a byte comparison, and it
  is only a usable staleness test as long as this holds. A change that makes two
  runs of the same tree differ is a bug, however cosmetic the difference looks.
- **The map is a snapshot of the version that wrote it.** A new tab or panel
  reaches an existing map by regeneration, never by the plugin alone. Do not add
  code that reads an old `module_map.json` and pretends it has the new fields.
- **A backend answers five questions and nothing else** — which files it claims,
  where its sources live, what documents a file, what documents a declaration,
  and what makes a declaration public. Anything a backend needs beyond that is a
  sign the contract is wrong, not that this backend is special.
- **Evidence strength is part of the answer.** Go's visibility is enforced by the
  compiler; Lua's `@internal` is an authoring claim. Where a check depends on
  which of the two it got, say so in the finding rather than flattening them.
- The MCP tools are **read-only**, and none of them writes `@verified`. That is
  load-bearing, not incidental — see [`mcp.md`](mcp.md).
- Commands are registered through `lib.nvim.bindings.usercmd.composer`.
- Descriptive commit messages.

## Project layout

| Path | Contains |
| --- | --- |
| `lua/documentation/core/` | The pipeline: scan, parse, build the IR, render the artifacts |
| `lua/documentation/core/lang/` | One backend per language, all behind `Documentation.LangBackend` |
| `lua/documentation/editor/` | `:DocBrowse` — the in-editor view over the same map |
| `lua/documentation/bindings/` | The `:DocMap` and `:DocBrowse` route trees |
| `lua/documentation/config/` | `Documentation.Opts`, `.docmap.json` precedence, check grading |
| `lua/documentation/mcp/` | The MCP server: nine read-only tools over stdio |
| `lua/documentation/integrations/` | Soft-dependency bridges (nvzone/menu) |
| `scripts/` | The headless runners, including `gen_map.lua` and `ci.sh` |
| `action.yml` | The GitHub Action, at the repository root so adopting it copies nothing |
| `docs/` | Everything the README links to |
| `TESTS/` | The spec suite |

## Adding a language backend

[`languages.md`](languages.md) has the contract field by field and the parity
matrix. In short:

1. Implement `Documentation.LangBackend` under `lua/documentation/core/lang/`.
   Answer the five questions; do not reach outside them.
2. Declare which Treesitter grammar it wants, and what it falls back to when the
   grammar is absent. A missing grammar costs precision, never the map.
3. Be explicit about the visibility rule and how strong the evidence is.
4. Add fixtures under `TESTS/` and a row to the parity matrix in
   [`languages.md`](languages.md) — measured, not asserted.

## Adding a drift check

1. Implement it so it returns findings, never writes.
2. Grade it (error / warning / info) and justify the grade in
   [`pipeline.md § Drift checks`](pipeline.md#drift-checks). A check that fires on
   correct code is worse than no check: `dead-function` had to survive the fact
   that a library is *made of* functions with no internal caller, and that
   reasoning is written down for exactly this reason.
3. Make it switchable through `opts.checks`.

## Tests

`scripts/ci.sh` runs everything CI runs.
[GitHub Actions](../.github/workflows/ci.yml) runs it on every push and PR to
`main`, including the `--check` staleness test against this repository's own
committed map.

## Workflow

1. Fork the repository.
2. Branch as `feature/<name>`.
3. Make the change, add fixtures or a spec, regenerate this repository's own map,
   update the affected pages under `docs/`.
4. Open a PR with a clear description of what changed and why.
