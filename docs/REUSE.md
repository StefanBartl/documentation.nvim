# Generating a map for your own plugin

Nothing in `documentation.nvim` knows about any particular repository's
layout, and — since twenty-three language backends — nothing in it assumes
the tree is Lua either. `opts.root` / `opts.source` point it at any tree a
backend claims; everything else — module prefix, directory layout, types
directory name, output directory — is an option with a default.

The examples below are Lua because this is a Neovim plugin documenting
itself. Nothing in the setup changes for another language: point `source` at
the directory, and `lang_registry` picks the backend per file. Which
languages, and what each one needs, is [`LANGUAGES.md`](LANGUAGES.md).

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

Mapping a project that is **not** a Neovim plugin works the same way and
needs nothing extra — `nvim --headless -l` is being used as a Lua interpreter
that happens to ship parsers. The only precondition is a grammar for the
language on the runtimepath, which for anything Neovim ships is already true.
Dropping the Neovim dependency entirely has been costed out separately.

## Before either: `.docmap.json`

Most of what a repository wants to say about itself is a fact about the
*tree* — where its sources are, what its layers are, which checks its team
decided are noise — and every host below reads it from one file at the
repository root:

```json
{
  "$schema": "https://raw.githubusercontent.com/StefanBartl/documentation.nvim/main/docs/docmap.schema.json",
  "source": "lua/myplugin",
  "title": "myplugin.nvim",
  "repo_url": "https://github.com/me/my-plugin",
  "layers": [
    { "from": "myplugin.core", "to": "myplugin.ui", "why": "the pipeline stays runnable headless" }
  ]
}
```

Put it there first, and the two recipes below get shorter rather than
longer: the copied `gen_map.lua` needs no options table at all, and the
GitHub Action needs no inputs. It is also the only way a `layers` rule
reaches the standalone binary or `docmap-desktop`, neither of which has an
options table to be given one in.

The file is **data, never code**: it is read out of a repository that CI
just cloned or that somebody added to a desktop app by pointing at a
directory, and executing it would make "look at this project's map" a
code-execution primitive on any tree. `extra_checks` is a list of Lua
functions and therefore stays a host-side option — which is the one thing
the recipes below still exist for.

A repository states facts about itself and not about the session reading
it. `command_name`, `keys`, `watch`, `diagnostics` and `telemetry` are
refused with a warning naming them; the full split, and the reason for each
group, is in
[`lua/documentation/config/file.lua`](../lua/documentation/config/file.lua).

## In CI and in a pre-commit hook

Copy two files and edit five lines — or fewer, with a `.docmap.json` in
place.

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

### Narrowing what gets read

Two options say what a repository's map should *not* contain, and both are
plain `opts` fields as well as flags, so the editor, CI and a host all set
them the same way.

```bash
nvim --headless -l scripts/gen_map.lua --exclude=src/generated --exclude=third_party
nvim --headless -l scripts/gen_map.lua --languages=lua,go
```

**`exclude` is a path, not a pattern.** Repository-relative, matched as a
path or a path prefix: `src/generated` excludes that directory and
everything under it, and does *not* match `src/generated_by_hand`. There is
no glob dialect on purpose — `VENDOR_DIRS` already covers "this directory
name wherever it appears" (`node_modules`, `target`, `dist`, `build`, `.venv`
and a dozen more, always, with no configuration), which is what a wildcard
would mostly be asked for. The shape that was missing is the other one:
*this path, in this repository.* A path answers it exactly.

Repeatable rather than comma-separated, because a directory can contain a
comma and a backend name cannot.

**`languages` is an allow list over the backends**, by their registered names
— see [`LANGUAGES.md`](LANGUAGES.md) for the twenty-three. Omitting it, or
passing an empty list, reads all of them; that is the reading that cannot
lose data, since an empty selection nearly always means the caller had
nothing to say. It also narrows **source detection**, not only the walk: a
switched-off backend must not get to name the directory the scan starts in,
or a repository restricted to Lua would be walked from a JavaScript `src/`
and come back empty.

An unknown name is honoured rather than dropped, so `--languages=golang`
reads nothing and says so on stderr. The alternative — ignoring what it
cannot recognise — makes a typo behave like no filter at all, which is the
opposite of what was asked for.

**Neither option is a substitute for `source`.** `source` says where to
start; these two say what to leave out once there.

### Pointing it at a Neovim *config*

Two options exist only for this case, and both are **declared rather than
detected** — a helper that takes its argument in the expected order is
declarable, one that reorders or builds it is not, and guessing which is
which is how a scanner starts inventing things.

```lua
opts = {
  plugins  = { wrappers = { ["plugins.add"] = true } },
  bindings = { wrappers = { map = "keymap", ["usercmd.create"] = "usercmd" } },
}
```

**`plugins.wrappers` is worth checking even if you think you do not need
it.** `core/plugins.lua` reads a file's own top-level `return { … }`, which
is what most spec files are. A config that registers through its own helper
contributes **nothing** — and that is a silent zero, not an error. Measured
against one real config: 52 specs found, 85 once its single wrapper was
declared, with the missing 33 sitting in one 906-line file.

If the Plugins or Lazy-loading panels look thinner than your config is, this
is the first thing to check.

#### Other plugin managers

packer, vim-plug and mini.deps need **no extractor of their own** — this was
expected to need three, and measuring first said otherwise. All three
register through a call taking a table or a string, which is exactly what a
declared wrapper walks:

```lua
plugins = { wrappers = { use = true } }   -- packer:    use { … } / use "a/b"
plugins = { wrappers = { Plug = true } }  -- vim-plug:  Plug("a/b") from Lua
plugins = { wrappers = { add = true } }   -- mini.deps: add({ … }) / add("a/b")
```

packer's `requires`, mini.deps' `depends` and its `source` are read as the
`dependencies` and repo they are. The trigger keys (`event`, `ft`, `cmd`,
`keys`) are spelled the same across managers, so they needed nothing.

**vim-plug only in its Lua call form.** `Plug 'a/b'` in a `.vim` file is
VimScript, and this reads Lua; a config that keeps its plugin list in
VimScript is out of reach here, not partially in it.

A string argument has to *look* like a repo (`owner/name`) to count, so
declaring `add` does not turn every `add("some message")` in the file into a
plugin.

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

**The short way: a GitHub Action, and nothing to copy.**

```yaml
map:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: StefanBartl/documentation.nvim@main
      with:
        source: lua/myplugin
        repo-url: https://github.com/me/my-plugin
```

That is the whole job. The action checks out the engine and `lib.nvim` into
the runner's temp directory — never into your workspace, where the walk would
map them — installs Neovim, and runs the same `--check` gate.

**Pass `repo-url` (and `branch`, if it is not `main`) even though they look
cosmetic.** They end up *inside* the committed artifact, so a local run that
sets them and a CI run that does not compare two different files, and the
check fails on a difference nobody made.

**It installs Neovim rather than downloading the standalone binary**, and
that is the one design decision in it. `--check` compares byte for byte
against a map your own `:DocMap` wrote inside Neovim; the parser-less
standalone build produces a different one — a complete module tree with no
function-level data — so a check running it would call every repository
stale, forever.

**Where the action stops, and where it no longer does.** It has no `layers`
input and never will: both halves of the old reasoning — that a layer rule
is a claim about one tree's own architecture, and that it fits no YAML input
without inventing a configuration language — were right about inputs and
wrong about the conclusion. The answer to "this does not fit on a command
line" is a file, so `layers` goes in `.docmap.json` and the action reads it
like every other host.

`extra_checks` is the one that genuinely stops here, because it is code and
that file is data. A repository that wants its own checks has outgrown three
lines of YAML and should copy `scripts/gen_map.lua` as described above.

Pin `@v1` rather than `@main` once you care about reproducibility. The action
runs whichever engine ref it was resolved from, deliberately: **a generated
map is a snapshot of the engine that wrote it**, so the engine that checks it
has to be the engine that would write it.

### The long way, by hand

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
once you publish it somewhere a browser loads it directly.

**Both of this project's own repositories now do publish it**, via
`.github/workflows/pages.yml` (copy it; it uploads `docs/map/` as committed
and needs no build step). Once yours does too, link the published URL rather
than the file — that is the version a reader can actually click:

```markdown
This plugin's own module map: https://<user>.github.io/<repo>/
```

Worth knowing before you publish: the Tree, Hierarchy, Analysis, Index, Notes
and Compare tabs work fully with no server. History, Telemetry and Loaded are
computed on demand from git and from runtime data on the machine that ran the
scan — a published copy says so plainly instead of reporting a network error.
And the map embeds source snippets and signatures, so publishing it publishes
those; on a public repository that changes nothing, on a private one it would
be a leak.

## What the tree has to look like

**In Lua, one requirement: files carry `---@module`.** That is what the
scanner reads — each file's leading comment block, everything before the
first non-comment line, and it stops there. It does not parse the language.

**In every other language, no requirement at all.** Lua is the one backend
that sets `module_tag = true`, because a Lua module's canonical name cannot
be recovered from its path; everywhere else the path *is* the identity, so
`missing-module-tag` never fires and there is nothing to add to your files
before mapping them. See [`LANGUAGES.md`](LANGUAGES.md).

Function-level data (`node.functions`, the call graph, complexity) comes from
`vim.treesitter` instead, and needs no annotation at all beyond the doc
comments you already write.

Everything past that is opt-in, and each tag buys a specific thing: `@param`
unlocks the three structural checks and the coverage number, `@internal`
makes that number describe your API rather than your helpers, `@see` gets
cross-references with a check behind them. The full contract — which tag
feeds which part of the pipeline, plus a minimum-viable set to adopt first —
is in [ANNOTATION_TAGS.md](ANNOTATION_TAGS.md), written for LuaCATS; the
equivalent per language is whatever that language's own doc convention
already spells, which each backend reads without configuration.

Structure is derived, not declared:

| Node kind | What it is |
|---|---|
| `module` | A directory containing the language's module file — `init.lua`, `index.ts`, `__init__.py`, `mod.rs` |
| `namespace` | A directory without one, grouping others |
| `file` | Any other source file a backend claims |

A `@types/` directory (name configurable via `opts.types_dir`) is an
**attribute** of its module, not a sibling node.

For the reasoning behind all of the above, see [PIPELINE.md](PIPELINE.md).
