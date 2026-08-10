# Generating a map for your own plugin

Nothing in `documentation.nvim` knows about any particular repository's
layout. `opts.root` / `opts.source` point it at any tree whose files carry
`---@module`; everything else — module prefix, directory layout, types
directory name, output directory — is an option with a default.

Two ways in, depending on whether you want it in the editor or in CI.

## In the editor

Nothing beyond the plugin spec:

```lua
{
  "StefanBartl/documentation.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  cmd = { "DocMap", "DocBrowse" },
  opts = {
    source = "lua/myplugin",
    title = "myplugin.nvim",
    repo_url = "https://github.com/me/my-plugin",
  },
}
```

With no `root` set, `:DocMap`/`:DocBrowse` resolve one **per invocation** from
the current buffer's file (up to the nearest `.git`, see
|documentation-root|) — right when you maintain several repositories side by
side, and wrong when you want one fixed target. Set `root` explicitly for the
latter, which is what the CLI path below does — a headless run has no buffer
to resolve from in the first place.

If you want the commands under different names (because another plugin in the
same config also calls `setup()`), set `command_name` and
`browse_command_name`. Leaving both at their defaults is a silent overwrite,
not an error: `usercmd.create` defaults to `force = true`.

Mapping a Lua project that is **not** a Neovim plugin works the same way and
needs nothing extra — `nvim --headless -l` is being used as a Lua interpreter
that happens to ship a parser. The one real precondition is `---@module` on
your files. See [PORTABILITY.md](PORTABILITY.md), which also costs out what
dropping the Neovim dependency entirely would take.

## In CI and in a pre-commit hook

Copy two files and edit five lines.

### 1. `scripts/gen_map.lua`

Copy [`scripts/gen_map.lua`](../scripts/gen_map.lua) verbatim, then change only
the options table at the bottom:

```lua
local opts = require("documentation.config").build(root, {
  source = "lua/myplugin",
  title = "myplugin.nvim",
  out_dir = "docs/map",
  repo_url = "https://github.com/me/my-plugin",
  branch = "main",
})

local code = require("documentation.core.cli").run(opts, _G.arg or {})
vim.cmd("cq " .. code)
```

Everything above it is generic: it resolves `cwd`, puts the repository and
`lib.nvim` on the runtimepath, and hands off to `documentation.core.cli` — the same
`--check`/`--full` CLI this repository uses on itself, extracted into
[`cli.lua`](../lua/documentation/core/cli.lua) for exactly this reason. It returns
an exit code rather than calling `cq` itself, so it stays a plain function a
test can assert on.

The runtimepath block matters more than it looks. A headless `nvim -l` run has
no plugin manager, so neither `documentation` nor `lib.nvim` is reachable by
default. The copied script resolves `lib.nvim` from `$LIB_NVIM_DIR`, then
`.deps/lib.nvim`, then a sibling checkout — and `documentation.nvim` itself the
same way if it is not already on your rtp.

```bash
nvim --headless -l scripts/gen_map.lua                    # regenerate
nvim --headless -l scripts/gen_map.lua --check            # stale or drift -> exit 1
nvim --headless -l scripts/gen_map.lua --check --lenient  # fail on staleness only
nvim --headless -l scripts/gen_map.lua --full             # + LuaLS enrichment
```

### 2. `scripts/hooks/pre-commit`

Copy [`scripts/hooks/pre-commit`](../scripts/hooks/pre-commit) verbatim and
edit only the three variables at its top:

```sh
SOURCE_DIR="lua/"
OUT_DIR="docs/map/"
GEN_SCRIPT="scripts/gen_map.lua"
```

Install it once per clone — hooks are not versioned by git itself:

```bash
git config core.hooksPath scripts/hooks
```

It only *checks*: it never regenerates and never stages. A hook that writes
into the commit it is validating produces diffs the author did not intend and
misbehaves under `--amend` and rebase. Bypass a single commit with
`git commit --no-verify`.

`core.hooksPath` rather than a versioned runner like `lefthook`, deliberately:
adopting this should cost your plugin one copied file, not a new dependency.

### 3. CI

`--check` *is* the whole check:

```yaml
map:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: actions/checkout@v4
      with:
        repository: StefanBartl/lib.nvim
        path: .deps/lib.nvim
    - uses: actions/checkout@v4
      with:
        repository: StefanBartl/documentation.nvim
        path: .deps/documentation.nvim
    - uses: rhysd/action-setup-vim@v1
      with: { neovim: true, version: stable }
    - run: nvim --headless -l scripts/gen_map.lua --check
```

Worth having even with the hook installed: the hook is opt-in per clone, so
without a CI job the committed map goes stale on `main` with nothing noticing.
That is not hypothetical — it is why this job exists here.

## Repository-specific drift checks

The generic checks make no assumptions about your conventions. Anything that
does goes in `opts.extra_checks`, a list of
`fun(ir: Documentation.IR, opts: Documentation.Opts): Documentation.Finding[]`:

```lua
---@param root string
---@return Documentation.Check
local function my_check(root)
  return function(ir, _opts)
    local findings = {}
    -- …
    findings[#findings + 1] = {
      severity = "error",     -- "error" | "warn" | "info"
      check = "my-check",     -- stable id, shown in the map and the CLI output
      node = "lua/myplugin",  -- an IR node id, or nil
      message = "…",
    }
    return findings
  end
end
```

Only `error` severity fails `--check` (unless `--lenient`). Choose it for
things that are *false*, not for things that are untidy: a check that is red
before anyone touches anything gets switched off the same day.

## Cross-project links (`opts.tag_files`)

Doxygen's `TAGFILES` equivalent. A tree of small plugins that all depend on
`lib.nvim` and each generate their own map is the normal case, and every one of
those maps otherwise draws `lib.nvim.fs`, `lib.nvim.ui.kit` and friends as
nameless inert grey boxes in the Deps view's `+ external` toggle.

```lua
require("documentation").generate({
  ...,
  tag_files = { ["lib.nvim"] = "/path/to/lib.nvim/docs/map" },
})
```

Every `requires_external` module matching the prefix — whole-segment matching,
so `lib.nvim.fs` but never `lib.nvimx` — is looked up in that directory's
`module_map.json`. What resolves gets a solid, accent-coloured box that opens
the other project's page at that node. What does not is left exactly as before:
silently inert, never an error.

Local paths only, deliberately: the tag file is read synchronously during
`scan_full()`, and a network fetch would turn a deterministic `--check` into
one that depends on network availability and timing.

## GitHub links for third-party deps (`opts.external_repos`)

`tag_files` above only helps when the external module is *another
`docmap`-shaped project*. The common case — a third-party plugin
(`plenary.nvim`, ...) with no `docmap` artifact to resolve against — gets a
GitHub link instead, into the same `ir.tag_links` table:

```lua
require("documentation").generate({
  ...,
  external_repos = {
    plenary = "nvim-lua/plenary.nvim",
    ["lib.nvim"] = { repo = "StefanBartl/lib.nvim", local_path = "/path/to/lib.nvim" },
  },
})
```

The link is a guess (`<lua_root>/<module, dots as slashes>.lua`) unless
`local_path` names a real local checkout, in which case both the flat and
`init.lua`-directory shape are checked against it — see
[`docs/PIPELINE.md`](PIPELINE.md#external-callplugin-visibility-optsexternal_repos)
for why a flat-only guess is wrong more often than you'd expect, and why a
`local_path` whose location differs between where you regenerate and where
`--check` runs breaks reproducibility. Each external box's tooltip also
shows exactly which functions of that module were actually called and how
often, independent of whether a link resolved at all.

## Linking to your own map from your README

Once `docs/map/` is committed, point your own README at it — one line under
whatever "development" or "internals" section you already have:

```markdown
This plugin's own module map: [docs/map/overview.md](docs/map/overview.md)
```

Link `overview.md`, not `index.html`: GitHub renders Markdown inline in the
repo view, so `overview.md` is useful the moment it is committed. `index.html`
is real HTML — GitHub shows it as source, not rendered — so it only pays off
once you actually publish it somewhere a browser can load it directly (locally
via `:DocMap open`, or `scripts/publish_map.sh` to Pages, see
[FINISH_PLAN.md](ROADMAP/FINISH_PLAN.md)). Nothing stops you linking both; just
know which one works today and which one is a promise for later.

## What the tree has to look like

One requirement: files carry `---@module`. That is what the scanner reads —
each file's leading comment block, everything before the first non-comment
line, and it stops there. It does not parse Lua.

Function-level data (`node.functions`, the call graph, complexity) comes from
`vim.treesitter` instead, and needs no annotation at all beyond the doc
comments you already write.

Everything past that one requirement is opt-in, and each tag buys a specific
thing: `@param` unlocks the three structural checks and the coverage number,
`@internal` makes that number describe your API rather than your helpers,
`@see` gets cross-references with a check behind them. The full contract —
which tag feeds which part of the pipeline, plus a minimum-viable set to adopt
first — is in [ANNOTATION_TAGS.md](ANNOTATION_TAGS.md).

Structure is derived, not declared:

| Node kind | What it is |
|---|---|
| `module` | A directory containing `init.lua` |
| `namespace` | A directory without `init.lua`, grouping others |
| `file` | A non-`init.lua` Lua file |

A `@types/` directory (name configurable via `opts.types_dir`) is an
**attribute** of its module, not a sibling node.

For the reasoning behind all of the above, see [PIPELINE.md](PIPELINE.md).
