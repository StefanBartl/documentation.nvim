> **Active development.** This repository is in its development phase — breaking changes are to be expected at any time. Pin a commit or tag if you depend on it.

# documentation.nvim

```
     _                                        _        _   _
  __| | ___   ___ _   _ _ __ ___   ___ _ __ | |_ __ _| |_(_) ___  _ __
 / _` |/ _ \ / __| | | | '_ ` _ \ / _ \ '_ \| __/ _` | __| |/ _ \| '_ \
| (_| | (_) | (__| |_| | | | | | |  __/ | | | || (_| | |_| | (_) | | | |
 \__,_|\___/ \___|\__,_|_| |_| |_|\___|_| |_|\__\__,_|\__|_|\___/|_| |_|
                                                                  .nvim
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-active%20development-blue)
[![CI](https://github.com/StefanBartl/documentation.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/StefanBartl/documentation.nvim/actions/workflows/ci.yml)

> **know your project**

> Pairs with [**lib.nvim**](https://github.com/StefanBartl/lib.nvim) — the
> utility library this grew out of and still builds on. If you are mapping a
> tree, you are probably about to want its `fs`, `ui.kit` and `usercmd` modules
> too; this plugin uses exactly those.
>
> Two companions complete the triangle:
> [`runtime-analysis.nvim`](https://github.com/StefanBartl/runtime-analysis.nvim)
> extends this plugin with live call-count telemetry from inside a running
> Neovim session — install it and the Telemetry/Loaded tabs below stop
> saying "no data".
> [`docmap-desktop`](https://github.com/StefanBartl/docmap-desktop) is the
> third leg, the same map read entirely outside Neovim, for anyone not
> sitting in the editor.

Point it at a repository and it produces a **module map**: an interactive
HTML page, a Markdown overview, a deterministic JSON artifact, and a set of
drift checks that fail CI when the documentation and the code stop agreeing.

It reads **twenty-three languages** — Lua, JavaScript, TypeScript, TSX,
Python, Ruby, PHP, C#, Go, Rust, Kotlin, Swift, Dart, Scala, Haskell,
Elixir, Erlang, OCaml, Zig, Java, C, C++ and assembly — through one backend
contract, so a tree that mixes them
comes out as one map rather than several. See
[Languages](#languages).

```vim
:DocMap          " regenerate the artifacts
:DocMap check    " verify without writing — findings go to the quickfix list
:DocMap open     " open the generated page in the browser
:DocBrowse       " navigate the same map inside the editor
```

Grew inside [`lib.nvim`](https://github.com/StefanBartl/lib.nvim) as
`lib.nvim.docmap` and was extracted once it had nothing left to do with
lib.nvim. See [docs/PIPELINE.md § Why this is its own
plugin](docs/PIPELINE.md#why-this-is-its-own-plugin).

## Table of Contents

- [What it produces](#what-it-produces)
- [Languages](#languages)
- [Installation](#installation)
- [Configuration](#configuration)
- [Commands](#commands)
- [Health](#health)
- [Headless / CI](#headless--ci)
- [Live handle instead of files](#live-handle-instead-of-files)
- [MCP server — the map as tools for a coding agent](#mcp-server--the-map-as-tools-for-a-coding-agent)
- [Desktop app — browsing maps without Neovim](#desktop-app--browsing-maps-without-neovim)
- [Drift checks](#drift-checks)
- [Documentation](#documentation)

## What it produces

| Artifact | What it is |
|---|---|
| `docs/map/index.html` | The interactive map: **Hierarchy**, **Index** (Tree / Functions / Modules), **Analysis**, **Compare**, **Features**, **Quicks**, **Notes**, **History** and **Findings** tabs. Self-contained — no CDN, no build step. |
| `docs/map/overview.md` | The same tree as Markdown, so it renders on GitHub. |
| `docs/map/module_map.json` | The IR, byte-deterministic. What `--check` compares and what `:DocMap diff` reads out of old commits. |
| `docs/map/coverage.svg` | Optional (`opts.badge`): a doc-coverage badge, hand-rolled, no network call. |
| `docs/map/overview.pdf` | Optional (`opts.pdf`): the same content as `overview.md`, via [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) (optional dependency). |

**Every one of these is a snapshot of the version that wrote it.** The page
is generated, not rendered live, so a tab or a panel that arrived in a
later release of this plugin reaches an existing map by *regenerating* it —
never by updating the plugin alone. That is the price of an artifact you
can commit, open offline and diff, and it is worth stating once rather than
being discovered.

This repository maps itself with the same tool, and publishes the result:
**<https://stefanbartl.github.io/documentation.nvim/>**. [docs/map/overview.md](docs/map/overview.md)
is the same tree as Markdown, rendered straight on GitHub.

The published copy is honest about what it can answer: Hierarchy, Index,
Analysis, Notes, Quicks and Compare need no server and work fully; History,
Telemetry and Loaded are computed on demand from git and from runtime data on
the machine that ran the scan, and say so when opened there. See
[docs/REUSE.md § Linking to your own map from your README](docs/REUSE.md#linking-to-your-own-map-from-your-readme)
to do the same in a plugin that depends on this one.

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
[`docs/FEATURES_FORMAT.md`](docs/FEATURES_FORMAT.md) for the format this
tab reads, and this repository's own [`docs/FEATURES/`](docs/FEATURES) for
a real (if deliberately small) example — including one promoted feature.

## Languages

Twenty-three backends behind one contract, so a repository that mixes them
produces one map rather than several. A backend answers the same five questions —
which files it claims, where its sources live, what documents a file, what
documents a declaration, and what makes a declaration public — and the map
does not care which language answered.

| Language | Extensions | What documents a declaration | What makes it public |
|---|---|---|---|
| **Lua** | `.lua` | LuaCATS `---` block, `@param`/`@return`/`@see` | anything without `@internal` |
| **JavaScript** | `.js`, `.jsx` | JSDoc `/** … */` | anything without `@internal`/`@private` |
| **TypeScript** | `.ts`, `.mts`, `.cts` | JSDoc | same |
| **TSX** | `.tsx` | JSDoc | same |
| **Python** | `.py`, `.pyi` | a docstring — the first *statement*, in reST, Google or NumPy style | not a leading `_`, unless `__all__` says otherwise |
| **C#** | `.cs` | XML doc comments — `/// <summary>`, `<param name="x">` | `public`; an unmarked class member is private, an unmarked interface member is public |
| **Go** | `.go` | the plain comment block above it — godoc has no tags at all | **capitalisation**, enforced by the compiler |
| **Rust** | `.rs` | `///` above the declaration; rustdoc has no tags either | `pub`; `pub(crate)` and `pub(super)` are restricted, not published |
| **PHP** | `.php` | PHPDoc `/** @param int $x … */` | not `private` and not `protected` — an unmarked method is **public** |
| **Ruby** | `.rb` | the comment block above it — RDoc prose, with YARD tags read where present | `private`/`protected`, which are **positional statements** rather than modifiers |
| **Kotlin** | `.kt`, `.kts` | KDoc `/** @param x … */`, plus `@property` | not `private`/`protected`/`internal` — an unmarked declaration is **public** |
| **Swift** | `.swift` | `///` Markdown, where a parameter is a **bullet**: `- Parameter x:` | `open`/`public`; an unmarked declaration is `internal`, meaning module-only |
| **Dart** | `.dart` | `///` Markdown prose; dartdoc has no per-parameter form | **a leading `_`**, which the compiler enforces rather than merely suggests |
| **Scala** | `.scala`, `.sc` | Scaladoc `/** @param x … */`, plus `@tparam` | not `private`/`protected` — there is no `public` keyword to ask for |
| **Haskell** | `.hs`, `.lhs` | Haddock `-- |` above the type signature | **the module's export list**, stated once in the header rather than per declaration |
| **Elixir** | `.ex`, `.exs` | `@doc` — a module attribute the compiler stores, not a comment | `def` vs `defp`; `@doc false` is public-but-undocumented |
| **Erlang** | `.erl`, `.hrl` | EDoc `%% @doc` above the spec or the function | `-export([f/2])` — an export list that names an **arity**, not just a name |
| **OCaml** | `.ml`, `.mli` | ocamldoc `(** @param x … *)`, usually *below* the declaration | the sibling **`.mli` file** — an export list that lives in another file |
| **Zig** | `.zig` | `///` above the declaration | `pub` |
| **Java** | `.java` | Javadoc, with `@param`/`@return`/`@throws`/`@deprecated` parsed | `public` |
| **C** | `.c`, `.h` | any comment directly above it, Doxygen or not | not `static` |
| **C++** | `.cc`, `.cpp`, `.cxx`, `.hpp`, `.hh`, `.hxx` | same | not `static`, and not under `private:`/`protected:` |
| **Assembly** | `.s`, `.asm`, `.nasm`, `.inc` | the comment above the label, or trailing it | `.globl` / `global` / `PUBLIC` |

**The fourth column is worth reading as a spectrum**, because it is the one
place these languages genuinely disagree rather than merely differing in
syntax. Go is at one end: visibility is capitalisation, the compiler enforces
it, and nobody can be wrong about it. Zig, Java, C#, C, C++ and assembly
state it in a keyword, so the backend reads a fact. Lua and the ECMA family have no such keyword
at the granularity this map needs, so they read an authoring convention —
`@internal` — which is a claim the author made rather than one the compiler
enforces. Both are honest; they are not the same strength of evidence, and
a reader comparing two projects should know which they are looking at.

C++'s access specifier is *positional* — everything after `private:` is
private until the next one, `class` starts private and `struct` starts
public — so it is tracked while walking rather than read off the member,
because there is nothing on the member node to read.

**What documents a *file*** differs the same way and is worth knowing,
because it is what fills the map's summaries: Lua's `---@module` block,
Zig's `//!`, a Javadoc block above `package`, a Doxygen-style header in C
and C++ (deliberately strict, so a license banner never becomes a file
summary), and in assembly the top comment block — with the same banner
filter, reached by content because assembly has no punctuation to reach it
by.

**Three shapes of documentation convention now exist here, and it is worth
knowing which one you are reading.** LuaCATS, JSDoc, Javadoc and Doxygen are
*tag* formats. Python's docstrings are *prose with sections*. C#'s XML doc
comments are *markup* — the only one that names a parameter by attribute
rather than by position, and the only one this tool parses with patterns
rather than a real parser, because a doc comment is a fragment and an XML
parser would reject most real ones as malformed.

**Python is the one language here whose documentation is not a comment.**
A docstring is a string literal the interpreter keeps, so it is found by
*position* — the first statement — rather than by adjacency, and a "TODO"
inside one is prose the author published rather than a marker. Its style
forks three ways (reST, Google, NumPy) and is detected per docstring, since
one repository routinely mixes them.

**Only Lua has a module tag.** Everywhere else the file's path *is* its
identity, because that is how those languages resolve imports — so
`check.lua` never reports a missing `@module` for a language that has no
such concept. Lua's `init.lua`, the ECMA family's `index.{js,ts,tsx}`,
Python's `__init__.py` and Rust's `mod.rs` are the four
directory-owns-a-module conventions. Everywhere else a directory is a
namespace and every file is its own module.

**Call edges are five backends of twenty-three**, not all of them: `lua`,
`js`, `ts`, `tsx` and — since 2026-08-20 — `go`. Everywhere else the Calls
and Module Calls views, `:DocMap why`, the call-hierarchy integration and
`dead-function`'s call tier are empty. Nothing in those languages makes it
impossible; it is unbuilt, and `--capabilities` reports which backends
produce call sites so a host can say *why* a panel is empty rather than
implying the project has no calls.

Go was done first as the pattern, and it moved the hard part somewhere
unexpected: the query was easy, the **scope** was not. A Go package is a
directory, so a bare `double(n)` may name a function in a sibling *file* —
397 of 883 call edges in `aws/smithy-go`. Lua and the ECMA family happen to
make file and scope the same thing, which is why four backends of call
extraction had taught nothing about it.

### Grammars, and the one backend that needs none

Twenty-two of the twenty-three parse with a tree-sitter grammar. Without the grammar
they still produce a complete module tree — correctly, and saying so — but
no function-level data. `scripts/build_engine_release.sh` builds all twenty-three grammar files
— OCaml needs two, since `.ml` and `.mli` are different languages to the
parser — into a release; inside Neovim they come from the runtimepath.

**Assembly is the exception, by design rather than by omission.** GAS, NASM
and the ARM/MASM families are a fork rather than dialects, and a grammar is
written against exactly one side of it — a NASM file read by an x86-GAS
grammar is not a degraded parse, it is a confident wrong one. Everything
that backend needs is line-directed in all of those syntaxes, because
assembly is line-oriented by construction. So the capability handshake
reports three states, not two: a grammar loaded, a grammar wanted and
missing, and **no grammar needed** — which is full fidelity, not a
degradation, and a host that collapsed the last two would report a healthy
backend as broken.

### Adding one

The seam is `core/lang_registry.lua` plus the `Documentation.LangBackend`
contract, and `TESTS/backend_contract_spec.lua` fails a backend that
forgets any part of it — including the one whose absence is silent, comment
syntax, which it proves by *finding a marker* rather than by checking the
field is set.

Measured costs, so a tenth language is an estimate rather than a guess:
roughly 230–430 lines of backend, 120–200 of spec, one grammar, and half a
day — most of it spent deciding the contract answers rather than writing
extraction. The per-language record covers each one, including the three
designs that a scan of somebody
else's repository changed and a fixture would not have.

## Installation

Requires Neovim 0.10+ (`vim.uv`, `vim.treesitter`) and
[`lib.nvim`](https://github.com/StefanBartl/lib.nvim).

<details open>
<summary><b>lazy.nvim</b></summary>

```lua
{
  "StefanBartl/documentation.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  cmd = { "DocMap", "DocBrowse" },
  opts = {},
}
```
</details>

<details>
<summary><b>vim.pack</b> (Neovim 0.12+, built in)</summary>

```lua
vim.pack.add({
  { src = "https://github.com/StefanBartl/lib.nvim" },
  { src = "https://github.com/StefanBartl/documentation.nvim" },
})

-- No lazy-loading layer here, so do it by hand: create the commands on first
-- use rather than at startup. `setup()` scans the tree, which is not something
-- to pay for in every session that never opens a map.
for _, name in ipairs({ "DocMap", "DocBrowse" }) do
  vim.api.nvim_create_user_command(name, function(a)
    vim.api.nvim_del_user_command("DocMap")
    vim.api.nvim_del_user_command("DocBrowse")
    require("documentation").setup({})
    vim.cmd(("%s %s"):format(name, a.args))
  end, { nargs = "*" })
end
```
</details>

<details>
<summary><b>mini.deps</b></summary>

```lua
local add, later = MiniDeps.add, MiniDeps.later
add({
  source = "StefanBartl/documentation.nvim",
  depends = { "StefanBartl/lib.nvim" },
})
later(function()
  require("documentation").setup({})
end)
```
</details>

<details>
<summary><b>packer.nvim</b></summary>

```lua
use({
  "StefanBartl/documentation.nvim",
  requires = { "StefanBartl/lib.nvim" },
  cmd = { "DocMap", "DocBrowse" },
  config = function()
    require("documentation").setup({})
  end,
})
```
</details>

<details>
<summary><b>paq-nvim</b> / manual <code>rtp</code></summary>

```lua
require("paq")({
  "StefanBartl/lib.nvim",
  "StefanBartl/documentation.nvim",
})

-- paq does no lazy-loading and runs no config hooks:
require("documentation").setup({})
```
</details>

`opts = {}` (or a bare `setup({})`) is enough: with no `root`, the commands
resolve one **per invocation** from the file behind the current buffer — up to
the nearest `.git` — and `documentation.config` derives `source` from it
(`lua/<name>` when `lua/` holds exactly one candidate directory, `lua`
otherwise). Open a file in a sibling checkout and the next `:DocMap` maps that
checkout; both commands name the repository they acted on in their report. Set
`root` explicitly to pin every invocation to one tree instead, which is what a
plugin generating its own map wants.

Whichever manager you use, load it **lazily on the two commands**. `setup()`
scans the tree, and a session that never opens a map should not pay for one.

Nothing registers a command until `setup()` runs — `require("documentation")`
alone never touches the user's editor, so a plugin can embed the pipeline
without also taking the commands.

## Configuration

Every option is a plain field on `Documentation.Opts`; the full list with
per-field documentation is in
[`lua/documentation/@types/init.lua`](lua/documentation/@types/init.lua).

```lua
{
  "StefanBartl/documentation.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  cmd = { "DocMap", "DocBrowse" },
  opts = {
    root = "/path/to/my-plugin",       -- default: resolved per invocation
                                       -- from the current buffer's repository
    root_markers = { ".git" },         -- how that resolution finds it
    source = "lua/myplugin",           -- default: auto-detected under lua/
    title = "myplugin.nvim",           -- default: the root directory's name
    out_dir = "docs/map",
    repo_url = "https://github.com/me/my-plugin",
    branch = "main",

    luals = false,        -- opt-in LuaLS enrichment: @class/@alias detail,
                          -- type and inheritance edges. Costs seconds.
    badge = false,        -- also write coverage.svg
    pdf = false,           -- also write overview.pdf (needs pdfport.nvim,
                           -- optional dependency; async, reported separately)
    tests_dir = "TESTS",  -- auto-derived `fn.tested`
    dead_code = false,    -- widen `dead-function` to published functions too
    calls_heuristic = false,           -- guessed call edges, drawn dashed
    layers = {},          -- module-prefix layering rules
    tag_files = {},       -- cross-project links, Doxygen TAGFILES-style
    external_repos = {},  -- GitHub links for third-party deps (module-prefix
                           -- -> "owner/repo", verified against a local
                           -- checkout when you name one)
    extra_checks = {},    -- your own drift checks

    -- Ceiling for a `git log` over the full history: `churn`, the
    -- checklist's history pass and the MCP tool all bound by it. Two minutes
    -- is generous for most repositories and tight for a very old one.
    git_log_timeout_ms = 120000,
    -- How long a telemetry read stays cached. The number it shows is a
    -- snapshot of a file another process appends to all day: no TTL makes it
    -- live, a longer one only makes it wrong for longer.
    telemetry_ttl_ms = 2000,
    -- Detail carried per documentation reference. Both bound the size of a
    -- byte-deterministic artifact that is already large.
    context_max = 120,
    refs_per_entity = 20,

    command_name = "DocMap",
    browse_command_name = "DocBrowse",

    which_key = true,     -- register :DocBrowse's keys with which-key when
                          -- it is installed; a no-op when it is not
    menu = true,           -- <RightMouse> context menu mirroring :DocBrowse's
                            -- keys (nvzone/menu, soft dependency); a no-op
                            -- when it is not installed
    keys = {},            -- rebind or disable :DocBrowse's keys, by action

    telemetry = true,      -- self-instrument this tree with runtime-
                            -- analysis.telemetry when it is installed; a
                            -- no-op when it is not. Set false to opt out.
    telemetry_namespace = nil,  -- default: opts.title -- the namespace both
                                -- this and :DocBrowse's telemetry mode use

    checks = {},          -- switch a check off, or re-grade it
    theme = "system",     -- theme baked into the generated page
    serve_port = 0,       -- 0 lets the OS pick; set it for a stable URL

    features_dir = nil,   -- default: docs/FEATURES, then docs/features
    checklist_dir = nil,  -- default: docs/CHECKLIST[.md], then lowercase
    install_dir = "docs", -- where install.json / INSTALL.md live

    browse = {},          -- :DocBrowse's layout, theme and opening list
    diagram = {},         -- how :DocMap dot / mermaid draw
  },
}
```

### `.docmap.json` — options the repository states about itself

Most of the table above is a fact about the *tree*, not about your session,
and until now a Lua table was the only place to put one. That left the other
three hosts — the standalone binary, the GitHub Action, `docmap-desktop` —
able to pass only the handful of options that fit on a command line.

A `.docmap.json` at the repository root is read by every one of them:

```json
{
  "$schema": "https://raw.githubusercontent.com/StefanBartl/documentation.nvim/main/docs/docmap.schema.json",
  "source": ["lua", "src"],
  "exclude": ["src/generated"],
  "repo_url": "https://github.com/me/my-plugin",
  "layers": [
    { "from": "myplugin.core", "to": "myplugin.ui", "why": "the pipeline stays runnable headless" }
  ],
  "checks": { "undocumented-param": false, "missing-module-tag": "warn" }
}
```

Precedence, loosest first: the defaults, what `config.build` derives from the
root, **this file**, the host's explicit `opts` table, then CLI flags. So a
Neovim spec still wins over the file, and `--exclude=` still wins over both.

A repository may state facts about itself and not about the session reading
it: `command_name`, `keys`, `watch`, `diagnostics`, `telemetry` and their
neighbours are refused with a warning naming them, because a checkout you
cloned must not be able to rebind your keys or start a watcher. The file is
**data, never code** for the same reason — `extra_checks` is a list of Lua
functions and stays a host-side option. The full split is in
[`lua/documentation/config/file.lua`](lua/documentation/config/file.lua).

### Switching a check off, or re-grading it

`opts.checks` is keyed by the check code a finding carries — the same string
the quickfix list, the SARIF report and the page's Findings tab all show.

```lua
checks = {
  ["undocumented-param"] = false,   -- off entirely
  ["missing-module-tag"] = "warn",  -- keep it, stop failing CI on it
  ["dead-function"] = "info",
}
```

`false` drops every finding of that check; a severity string re-grades it.
Anything unlisted keeps the severity it is raised with, and the policy
applies to `extra_checks` results too, since those carry a code like any
other. A code that names nothing is reported rather than ignored.

This is what makes gradual adoption workable: `missing-module-tag` is an
`error`, so a repository annotating its tree file by file used to have a red
`--check` from the first commit until the last one.

### Rebinding the browser's keys

`opts.keys` is keyed by *action*, not by the default left-hand side, so a
rebinding survives a change of defaults. A string or a list replaces an
action's keys; `false` turns it off.

```lua
keys = {
  quickfix = "gQ",              -- one replacement key
  filter   = { "F", "<C-f>" },  -- several
  pin      = false,             -- off entirely
}
```

Every binding is buffer-local to the browser window, so a replacement only has
to be free *inside* `:DocBrowse` — not in your global keymap. A disabled action
still appears in the `?` cheatsheet, marked `(disabled)`, because "where did
`p` go" deserves an answer. An unknown action name is reported rather than
ignored.

The action names are the `id` fields of the `KEYS` table in
[`lua/documentation/editor/browse/init.lua`](lua/documentation/editor/browse/init.lua),
enumerated as `Documentation.Browse.KeyAction` in
[`lua/documentation/editor/browse/@types/init.lua`](lua/documentation/editor/browse/@types/init.lua):
`move`, `enter`, `up`, `back`, `forward`, `dir_in`, `dir_out`, `depth_inc`,
`depth_dec`, `goto_source`, `quickfix`, `impact`, `open_page`, `commit_diff`,
`pin`, `unpin`, `trail_save`, `trail_load`, `trail_delete`, `filter`, `search`,
`help`, `close`.

The mode-switch keys `1`…`6` are deliberately not rebindable: they are
positional (`3` means "the third list") and are generated from the mode list,
so renumbering them individually would desynchronise them from what the status
line shows.

## Commands

Full reference: [docs/COMMANDS.md](docs/COMMANDS.md).

```vim
:DocMap                          " regenerate
:DocMap check                    " verify without writing -> quickfix
:DocMap annotate                 " preview a ---@module header for every undocumented file
:DocMap annotate --write         " …and write it in place
:DocMap full                     " regenerate WITH LuaLS enrichment
:DocMap open                     " open the HTML in the system browser
:DocMap graph deps               " …opened on the dependency graph
:DocMap graph calls my.module    " …on one module's call graph
:DocMap why my.a my.b            " shortest require path between two -> quickfix
:DocMap pick                     " fuzzy-find any module or function -> jump to its line
:DocMap dot deps                 " the require graph as Graphviz DOT, in a buffer
:DocMap diff HEAD~5              " what changed about the tree's shape
:DocMap impact                   " …and where the changed lines radiate to
:DocMap churn                    " churn x complexity, hottest first -> quickfix
:DocMap churn HEAD~200..         " …over one range instead of all history
:DocMap plugins                  " every lazy.nvim spec in the tree -> quickfix
:DocMap bindings                 " every recognized keymap/user command/autocmd -> quickfix
:DocMap endpoints                " every recognized call-based route registration -> quickfix
:DocMap tools                    " this repo's own lib.nvim.deps manifest -> quickfix
:DocMap checklist                " hand-verified ledger entries that are stale or unverified -> quickfix
:DocMap checklist all            " …including entries that are already current
:DocMap serve                    " local map server (enables the History tab)
:DocMap helptags                 " regenerate this plugin's own doc/tags
:DocMap all                      " every opts.generate_all.projects, fast scan, one subprocess each (needs opts.generate_all)
:DocMap all full                 " …with LuaLS enrichment for every project
:DocMapAll                       " standalone alias for :DocMap all
:DocMapAllFull                   " standalone alias for :DocMap all full

:DocBrowse                       " navigate the map inside the editor
:DocBrowse live                  " …re-scanning on every write
:DocBrowse my.module             " …opened on one module
:DocBrowse history               " …opened on the commit list
:DocBrowse trail                 " …opened on the pinned positions
```

Inside `:DocBrowse`, `?` shows the keys for the current mode. It renders from
the same table the browser installs its keys from, so it cannot drift from
them; keys the current mode ignores are marked rather than hidden.

`p` pins the entry under the cursor and `6` lists what has been pinned — a
**trail**, deliberately separate from `<C-o>`/`<C-i>`. The history stack
answers "where was I a moment ago"; a trail answers "where do I want to get
back to". A pin restores the whole view it was taken in, not just its subject.

Trails persist across Neovim restarts, in
`stdpath("state")/documentation.nvim/trails.json` — navigation state, never the
repository. `S` saves the current trail under a name, `L` loads one back
(adding to what is already pinned, never replacing it) and `X` forgets one.

`f` narrows the list on screen in place — `fs bar` for both terms, `"open url"`
for a phrase, `-spec` to exclude. Deliberately not `/`, which fuzzy-jumps
across the whole tree: this matches plain substrings, so `-spec` means nothing
containing "spec" survives. The status line always shows an active filter and
its hidden count, and `gq` exports what is on screen.

## Health

```vim
:checkhealth documentation
```

Checks the dependencies and the treesitter Lua parser, and then the part worth
running it for: the configuration a `:DocMap` issued right now would act on —
the resolved root, the auto-detected `source`, how many `.lua` files are
actually under it, and whether the committed map has fallen behind the sources.

With no `root` set, `:DocMap` resolves one from the current buffer, so "it
mapped the wrong repository" and "it says my tree has one module" are the same
mistake seen from two angles. The command's report names the repository it
acted on; this check shows the same answer before anything is written.

## Headless / CI

```bash
nvim --headless -l scripts/gen_map.lua                    # regenerate
nvim --headless -l scripts/gen_map.lua --check            # stale or drift -> exit 1
nvim --headless -l scripts/gen_map.lua --check --lenient  # fail on staleness only
nvim --headless -l scripts/gen_map.lua --full             # + LuaLS enrichment
```

`--check` regenerates in memory and compares byte for byte; it writes nothing.
Output is deterministic across runs on unchanged input — no timestamp in the
IR, sorted-key JSON — which is the whole reason a byte comparison is a usable
staleness test.

Every gate CI runs, in one command:

```bash
scripts/ci.sh
```

### In someone else's repository

On GitHub, adopting the check copies nothing — `action.yml` lives at this
repository's root:

```yaml
- uses: StefanBartl/documentation.nvim@main
  with:
    source: lua/myplugin
```

`source` is optional; without it the source root is detected the same way
`:DocMap` detects it.

`exclude` and `languages` are there too, one path per line and one
comma-separated list respectively — the same two flags the standalone CLI
takes.

The Action still exposes no `layers` input, and does not need one: layer
rules go in the repository's own `.docmap.json` (see
[Configuration](#configuration)), which every host reads, including this one.
`extra_checks` is the one that genuinely stops here, because it is Lua code
and that file is data. A repository that wants its own checks copies two
files and edits five lines instead: [docs/REUSE.md](docs/REUSE.md).

## Live handle instead of files

`generate()` is one-shot. `install()` is the other half — a live
`Documentation.Handle` another plugin's code reaches for directly, instead of
parsing `module_map.json` off disk:

```lua
local handle = require("documentation").install({
  root = vim.fn.getcwd(),
  source = "lua/myplugin",
  watch = true,          -- rescan on BufWritePost under source/**.lua, debounced
  callhierarchy = true,  -- native in/outgoing-calls LSP support, alongside LuaLS
  diagnostics = true,    -- drift findings as vim.diagnostic, not only :DocMap check
})

handle.ir()                                -- current IR, in memory
handle.requires("lua/myplugin/fs")         -- require edges out
handle.callers("lua/myplugin/fs#M.read")   -- call edges in
handle.on_change(function(ir, findings) end)
handle.uninstall()
```

`callhierarchy = true` attaches a second, narrow LSP client alongside
whatever real language server is already there — off by default, costs no
new scan, answers only `textDocument/prepareCallHierarchy`/`callHierarchy/
incomingCalls`/`outgoingCalls` and a caller/callee count on hover. Built
because LuaLS itself has no call-hierarchy support at all (verified against
its source, and its own two-years-open feature request); Neovim's own
`vim.lsp.buf.incoming_calls()`/`hover()` already merge results from every
attached client, no new keybinding needed.

`diagnostics = true` publishes the same drift findings `:DocMap check`
already computes as native `vim.diagnostic` entries — a wavy underline and
sign-column mark while reading, not a separate list to open. No new LSP
client needed here at all, unlike `callhierarchy`: `vim.diagnostic.set()`
works directly on any already-open buffer. File-level granularity, the
same the quickfix list already has (`Documentation.Finding` carries no
line number); `info`-severity findings map to `vim.diagnostic.severity.HINT`
and are shown, where the quickfix list drops them.

`godbolt = true` (**experimental**, `generate()`-time, not `install()`) adds
a "⚙ Compiler Explorer ↗" link next to every module and function in the
generated page — a real `luac -l -l -p` bytecode disassembly, verified
against Compiler Explorer's own API and compiler source (`lua` is a real
language there, with five real interpreter versions), not a workaround.
Built entirely client-side from each function's already-serialized
`fn.snippet`, no new IR field; a module's own link concatenates its
functions' snippets, an approximation of the file rather than a
byte-perfect one, which is why this ships marked experimental.

## MCP server — the map as tools for a coding agent

The same `Documentation.Handle`, reachable from outside Neovim by an agent
that speaks [MCP](https://modelcontextprotocol.io):

```
nvim --headless -l scripts/mcp_server.lua
```

An MCP client spawns that as a subprocess and talks JSON-RPC over its
stdin/stdout — nothing listens on a port and nothing authenticates, because
with stdio the client *is* the parent process. Nine tools: `docmap_modules`,
`docmap_node`, `docmap_requires`, `docmap_required_by`, `docmap_callers`,
`docmap_callees`, `docmap_findings`, `docmap_rescan`, `docmap_checklist`. Each
is a projection of a handle method — the agent asks "what calls this
function" instead of grepping for the name and guessing which hits are real.
`docmap_checklist` is read-only in a way that is load-bearing rather than
incidental: no tool in this catalogue writes `@verified`, so an agent cannot
mark its own work as verified.

Client configuration, the tool table, and the five decisions worth knowing
about (why file watching is off, why no tool returns a raw IR node, why a
failing tool is a *result* rather than a transport error, why there is no
verify tool) are in [docs/MCP.md](docs/MCP.md).

## Desktop app — browsing maps without Neovim

[`docmap-desktop`](https://github.com/StefanBartl/docmap-desktop) is a small
Tauri app that hosts generated maps for several projects side by side, for
anyone reading them who is not sitting in Neovim. It runs this plugin's
standalone binary as a subprocess and serves the page over a real `http://127.0.0.1` origin,
so the Telemetry and Loaded panels below work the same way they do in the
editor — real data when [`runtime-analysis.nvim`](https://github.com/StefanBartl/runtime-analysis.nvim)
has collected any, an honest "no host" message otherwise, never a blank
panel.

## Drift checks

The rendered map is the visible half; the checks are the half that catches
bugs. `missing-module-tag` and `module-path-mismatch` are errors;
`missing-summary`, `dead-readme-link`, `sibling-reference-missing`,
`dead-see-target`, `type-vs-class`, `doc-references-missing`,
`test-references-missing`, `require-cycle`, `require-not-declared`,
`tag-require-missing` and `layer-violation` are warnings; `missing-readme`,
`unreferenced-module`, `orphaned-class-alias`, `tag-file-unavailable`,
`undocumented-param`, `param-name-mismatch`, `file-holds-many-modules` and
`dead-function` are informational.

The last pair is the cross-repository one and needs `opts.tag_files` set —
another checkout's `docs/map` directory, per module prefix. With it,
`tag-require-missing` reports a `require` into that project which its own
generated map no longer declares, and `tag-file-unavailable` says so when
that map could not be read rather than reporting a clean bill it did not
earn. That second one is the common case: every plugin in this ecosystem
but this one gitignores `docs/map/`, so these checks are for a working copy
with sibling checkouts, not for CI. Each one's reasoning — especially `dead-function`'s, which has
to survive the fact that a library is *made of* functions with no internal
caller — is in [docs/PIPELINE.md § Drift checks](docs/PIPELINE.md#drift-checks).

Repository-specific checks go in `opts.extra_checks`.

## Documentation

**Start at [docs/README.md](docs/README.md)** — the folder's own index,
grouped by the question you arrived with. The table below is the short list.

| Document | Covers |
|---|---|
| [docs/PIPELINE.md](docs/PIPELINE.md) | Every stage, every design decision, and the measurement behind each one. |
| [docs/LANGUAGES.md](docs/LANGUAGES.md) | The twenty-three backends as a reference: what each reads, the `Documentation.LangBackend` contract field by field, grammar resolution, what a missing grammar costs, and how to add the twenty-fourth. |
| [docs/COMMANDS.md](docs/COMMANDS.md) | `:DocMap` and `:DocBrowse`, subcommand by subcommand. |
| [docs/WORKFLOW.md](docs/WORKFLOW.md) | Using it day to day: which panel answers which question, reading the Telemetry join's badges correctly, Trail vs filter vs fuzzy jump. |
| [docs/REUSE.md](docs/REUSE.md) | Generating a map for your own plugin — including the GitHub Action, which is the version that requires copying nothing. |
| [docs/CHECKLIST_FORMAT.md](docs/CHECKLIST_FORMAT.md) | The hand-verified ledger: a syntax for facts a scanner cannot decide, watched for staleness by their citation rather than re-derived. |
| [docs/CALL_HIERARCHY.md](docs/CALL_HIERARCHY.md) | Incoming/outgoing calls in Neovim, alongside LuaLS (which has none): setup, keymaps, and how to tell an unattached client from a function with no callers. |
| [docs/HOSTING.md](docs/HOSTING.md) | Embedding the map in your own program: the `--capabilities` handshake, the `--api=<route>` answers, `?theme=`, and the page's two-way message channel. |
| [docs/MCP.md](docs/MCP.md) | The MCP server: exposing the module tree, require graph, call graph and drift findings to a coding agent as tools. |
| [docs/FRAMEWORK_CONVENTIONS.md](docs/FRAMEWORK_CONVENTIONS.md) | The layer above language support — recognizing one ecosystem's structural convention (lazy.nvim specs today; Next.js-style file routing and React hooks costed as the web-ecosystem case). |
| [docs/FEATURES/ECOSYSTEM.md](docs/ECOSYSTEM.md) | **Architectural concept**, agreed, nothing implemented: where docs cross-references, API-endpoint inventory, hover previews and an API request runner each belong — and why the runtime half is its own plugin (`runtime-analysis.nvim`), a Neovim plugin rather than a binary, meeting this one in the editor rather than in the committed artifact. |
| [docs/ANNOTATION_TAGS.md](docs/ANNOTATION_TAGS.md) | **Annotating your own plugin**: what each tag buys you here, the minimum viable set, and which custom tags would be worth adding. |
| [docs/ANNOTATIONS.md](docs/ANNOTATIONS.md) | The inventory — which LuaCATS tags this tree actually uses, counted. |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Running the specs, the linters and the map locally. |
| [lua/documentation/editor/browse/README.md](lua/documentation/editor/browse/README.md) | The editor-side browser in detail. |
| `:help documentation.nvim` | The same, in Vim help format. |

## License

MIT — see [LICENSE](LICENSE).
