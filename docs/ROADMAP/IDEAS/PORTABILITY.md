# Outside Neovim

Two questions that look like one: **can this map a Lua project that is not a
Neovim plugin** (yes, today, from the terminal) and **could it run without
Neovim installed at all** (not without one specific dependency, and this
document is the cost estimate).

The other axis — supporting languages other than Lua — is costed separately
in [`MULTILANG.md`](MULTILANG.md).

Measured against the tree at the time of writing: 33 files, 14 059 lines
excluding `@types/`, 221 `vim.*` call sites.

---

## What works today

Nothing in the pipeline knows about any particular repository. `opts.root` and
`opts.source` point it at any tree; every other assumption — module prefix,
directory layout, types directory, output directory — is an option with a
default. `nvim --headless -l` is a Lua interpreter that happens to ship a
parser, a filesystem library and a JSON codec, and `scripts/gen_map.lua` uses
it as exactly that. See [`REUSE.md`](../REUSE.md) for the two files to copy.

The real precondition is not Neovim, it is **`---@module` on your files**.
Without those the scan produces an empty tree, and nothing else in the
pipeline has anything to work on.

Verified against [`lib.nvim`](https://github.com/StefanBartl/lib.nvim) — a
different repository, run from the terminal, no editor session:

```
nodes=271  functions=838  findings=90  duplicate groups=27
```

So "can I use this for my Lua project" is already answered. What follows is
the other question.

---

## What a Neovim-free port would cost

### The shape of the dependency

Of the 221 `vim.*` call sites, the largest group is the one that does not need
porting at all:

| | Sites | What happens to it |
|---|---:|---|
| **Editor-only** — `vim.api`, `vim.bo`, `vim.cmd`, `vim.ui`, `vim.health`, quickfix | 83 | **Deleted, not ported.** A CLI has no buffers. |
| **Stdlib helpers** — `vim.trim`, `split`, `tbl_*`, `list_extend`, `deepcopy`, `fs.dirname` | 52 | Five lines of Lua each. |
| **Filesystem / process** — `vim.uv`, `vim.system`, `vim.fs.dir`, `vim.fn.getcwd` | 38 | `luv` is the same library as a standalone LuaRocks package; `vim.uv` → `luv` is close to a rename. `vim.system` → `io.popen` or luv's spawn. |
| **JSON** — `vim.json.decode`/`encode`, `vim.NIL` | 23 | The deterministic *encoder* is already this repo's own ([`json.lua`](../lua/documentation/core/json.lua)) — only a decoder is missing. |
| **Treesitter** | 25 | The blocker. See below. |

The 83 editor-only sites are the number worth reading twice: they are not a
porting cost, they are a deletion. `editor/` — `browse/`, `command.lua`,
`registry.lua`, `serve.lua`, `health.lua` — comes to **4 873 of 14 059 lines (35 %)** and
simply do not come along.

### How much is already portable

**Ten files have zero `vim.*` today**: `editor/browse/filter.lua`,
`editor/browse/trail.lua`, `core/churn.lua`, `core/doccoverage.lua`,
`core/duplicates.lua`, `core/history.lua`, and four of the five renderers.
`core/render/html.lua` — 3 347 lines, the largest file in the tree — has
exactly one.

That is not luck. It is the same purity rule the specs are built on: data in,
a structure out, no window and no filesystem. It was adopted so the model
could be driven headlessly, and portability is a side effect of it.

The rest of the pipeline is thin on `vim.*` too — `scan.lua` 3, `deps.lua` 2,
`init.lua` 2, `tagfiles.lua` 1, `config.lua` 3, `coverage.lua` 3,
`check.lua` 5.

### The blocker is exactly one thing

`vim.treesitter`, 25 sites across six files: `functions.lua`, `calls.lua`,
`symbols.lua`, `coverage.lua`, `deps.lua`, `health.lua`.

Without a parser you lose everything that is **per function**: the function
list, call edges, module symbols, cyclomatic complexity, the structural
shapes duplicate detection groups by, and test coverage.

What survives is more than it sounds, because `deps.extract_source` is
**pattern matching over lines, not a parse** — treesitter is used there only
to classify a require as deferred or load-time. So a parser-less build still
produces:

- the module tree, headers, summaries and READMEs;
- the whole require graph, and with it `require-cycle`, `layer-violation` and
  `require-not-declared` (minus the deferred/load-time distinction, which
  would make the cycle check noisier);
- `missing-module-tag`, `module-path-mismatch`, `missing-readme`,
  `dead-readme-link`, `unreferenced-module`;
- the Markdown, DOT and Mermaid renderers.

Getting the parser back means the tree-sitter C library, a Lua binding, the
Lua grammar, and a shim for the Neovim API shape this code is written against
(`query.parse`, `iter_captures`, `get_node_text`, `get_string_parser`).
Standalone bindings exist; **how well any of them fits this code has not been
checked, and that is the first thing to verify before starting.** Everything
else in this document is arithmetic, that part is research.

### Summary

Roughly 113 of the 221 sites are mechanical, 83 are deleted rather than
ported, and 25 are the actual project. The core pipeline is already close to
editor-free; it hangs on a single dependency, and that dependency is the
scanner.

---

## The three-step version: split, bundle, link

The obvious plan is "separate the editor half, make a binary, bundle
tree-sitter". Each step is real, but they are not equally cheap and the third
one is not what it first looks like. Measured with `tree-sitter` CLI 0.26.9 and
this repository's own queries.

### Step 1 — the split, and enforcing it — **done**

It was already 35% done by accident of the purity rule. What was missing was
anything that *stopped* it re-merging: nothing prevented `scan.lua` from
requiring `browse/`.

The plugin already shipped the mechanism — `opts.layers` and the
`layer-violation` check — but it could not express this boundary against the
flat tree. The editor half was five separate module paths (`browse.*`,
`command`, `registry`, `serve`, `health`), not one prefix, and a rule from
`documentation` down to the browser would have flagged `browse/init.lua`
requiring `browse/view.lua`.

`documentation.core.*` / `documentation.editor.*` makes it one line, now
declared in `scripts/gen_map.lua`:

```lua
layers = { { from = "documentation.core", to = "documentation.editor",
             why = "the pipeline has to stay runnable without an editor" } }
```

The tool now checks its own split in its own CI, and the boundary cannot rot.
That was the whole argument for the rename — not tidiness, enforceability.
Declaring the rule found one real violation immediately: `tagfiles.lua`
reached into `command.lua` for `find_node`, a lookup that touches nothing but
the IR. It is `core/find.lua` now.

One-directional on purpose. The editor half reaching into the core is the
point of the core existing; only the other direction costs anything.
`init.lua` sits outside the rule and reaches both, which is what a facade is
for.

### Step 2 — a binary — **done 2026-08-11, and it was not the least interesting step**

`luastatic` links a Lua interpreter, your `.lua` sources and any C libraries
into one executable.

**It works. `docmap.exe`, 1.5 MB, alone in an otherwise empty directory,
with no Lua interpreter, no LuaRocks tree and no Neovim anywhere — and no
`LUA_PATH`/`LUA_CPATH` set — generates a complete map.**

This section previously called it "the least interesting step". That was
wrong, and the correction is the useful part, because all three obstacles
are invisible until you actually run it:

- **`luastatic` derives module names from file *paths*.** Pass
  `E:/repo/standalone/vim_shim.lua` and the bundled module is called
  `E.repos.documentation.nvim.standalone.vim_shim`, so the binary dies at
  its first `require`. It therefore needs a **staging layout** whose
  relative paths spell the require names: `documentation/`, `lib/nvim/`,
  `standalone/`, `dkjson.lua`. What makes `init.lua` work is one line in
  its injected searcher — `lua_bundle[name] or lua_bundle[name..".init"]`
  — so `documentation/init.lua` does satisfy `require("documentation")`.
- **On Windows it shells out to `nm` without quoting.** Any library path
  containing a space fails, and the message names a nonexistent file
  (`nm: 'C:\Program': No such file`). `C:\Program Files (x86)\Lua\5.4\src\liblua.a`
  is exactly such a path. Copy the library somewhere without spaces.
- **Its C-compiler probe fails on Windows** ("C compiler not found") even
  with `CC` set to an absolute `gcc.exe`. It still writes the generated
  `.c`, so the workaround is to compile that yourself — which is a
  one-line `gcc` invocation and works first try.

**C modules need a static library, not the `.dll`/`.so` LuaRocks
installs.** `lfs` is a single C file, so `gcc -c` plus `ar rcs` is the
whole story. This is also why the binary above is the **parser-less**
build: it degrades exactly as designed, and confirmed by measurement —
with `DOCMAP_TS_DIR` pointing at real grammars it still reports the
parser-less result, because `lua_tree_sitter` was never linked in. A
full-fidelity binary additionally needs `lua_tree_sitter` **and**
`libtree-sitter` as static libraries, and a grammar per language.

**The load-bearing input is the file list, and it must be measured rather
than grepped.** [`scripts/bundle_manifest.lua`](../../../scripts/bundle_manifest.lua)
runs the real standalone pipeline and reads `package.loaded` afterwards:
45 Lua files, 2 C modules for this repository. A grep over `require`
lines is wrong in both directions — it would bundle the editor-only
`lib.nvim` modules the standalone build never loads, and it would miss
`core/lang/js`, `ts` and `tsx`, which are reached through
`core/lang_registry` and named at no call site. That second failure would
not even be a build error: it would be a binary that silently produces no
function-level data for JS/TS files.

### The full-fidelity binary works too (2026-08-11)

**`docmap.exe` (1.7 MB) plus one grammar shared library (146 KB), with no
Lua, no LuaRocks tree and no Neovim, produces a map byte-identical to
`nvim --headless -l scripts/gen_map.lua`.** Verified the only way that
means anything: let the binary write into `docs/map` exactly as
`gen_map.lua` does, then `git diff` against the committed artifacts —
empty.

What it needed beyond the parser-less build:

- **One static library for the binding *and* its vendored tree-sitter.**
  `lua-tree-sitter`'s 15 C sources plus `tree-sitter/lib/src/lib.c` (which
  `#include`s the rest of libtree-sitter) compile into a single
  `lua_tree_sitter.a`. The include path needs `tree-sitter/lib/src` — the
  same omission this document already records as one of the published
  rock's two packaging defects.
- **The grammar stays an external shared library**, and that is not a
  shortcut: `Language.load(path, lang)` resolves the grammar by `dlopen`
  at runtime, so there is nothing for a static link to attach to. Ship the
  binary alongside a directory of grammars and point `$DOCMAP_TS_DIR` at
  it. Loading a grammar built independently into a process whose
  libtree-sitter is statically linked works — a grammar depends only on
  `tree_sitter/parser.h` and hands back a struct pointer.

**And one more `luastatic` defect, this one squarely a bug.** It derives a
bundled C module's name from its `luaopen_<name>` symbol and then rewrites
**every** underscore to a dot, so `lua_tree_sitter` is registered as
`lua.tree.sitter`. `lfs` survives only because it has no underscore. The
binary therefore fell through to the LuaRocks `.dll` on `$LUA_CPATH` — a
shared library built against `lua54.dll`, which cannot load into a
statically linked host — and silently degraded to the parser-less result
with a perfectly good binding compiled in. `standalone/treesitter.lua` now
tries both names, which is a three-line fix in this repository rather than
surgery on luastatic's generated C.

**That bug also produced the one real usability finding.** Degrading
silently is right for the product, and awful to debug: the binary reported
the parser-less result and nothing said why. `DOCMAP_TS_DEBUG=1` now
prints the reason to stderr, and it is what located the defect above in
one run.

**A trap in the verification method, worth recording because it looked
like a fidelity gap.** Comparing the binary's output against the committed
map showed a 1,023-byte difference — an extra prose entry for
`docs/map/overview.md`. Not a defect: the docs scanner excludes its own
`out_dir`, so a run writing to `.deps/binfull` counts `docs/map/` as
documentation while a run writing to `docs/map` does not. Two runs are
only comparable when their `out_dir` matches.

**The build itself is now a script, for the same reason the manifest is.**
[`scripts/package.lua`](../../../scripts/package.lua) does manifest →
staging → `luastatic` → compile → verify, and encodes all four workarounds
above so they never have to be rediscovered. It runs under PUC Lua rather
than Neovim, deliberately: `luastatic` is a PUC-Lua program and a C
toolchain is required anyway, so demanding Neovim for a script whose whole
output is a Neovim-free artifact would be gratuitous.

```
LUA_INCDIR=… LUA_LIBA=…/liblua.a DOCMAP_STATIC_LIBS=…/libs CC=gcc \
  lua scripts/package.lua --out=build
```

Writing it turned up two more defects, both of the same family as the ones
already listed — silent until run:

- **The same unquoted-command bug, in this script.** `cmd.exe` strips the
  first and last quote of a command line, so a quoted interpreter path
  under `C:\Program Files (x86)\…` arrives broken and reports
  `'C:\Program' is not recognized`. It needs an *extra* pair of quotes
  around the whole line. Exactly what `luastatic`'s `nm` call gets wrong,
  reproduced by accident one file later.
- **A silent catch-all in the path mapping**, which is the one worth
  keeping. The manifest yields repo-relative paths when run from the
  repository and absolute ones when run from a build directory; the
  mapping matched only the former and fell through to the basename for
  everything else. Every module was registered flat — `calls`, `check`,
  `init` — the build reported success, and the binary died at its first
  `require`. The mapping now returns nil rather than guessing, and the
  `verify` step exists precisely because a binary that links is not a
  binary that runs. That step is what caught it.

**And the manifest must be built in the configuration you intend to
ship**, which is a further instance of the same hazard. The closure is not
one fixed list: `core/functions.lua`'s `scan_file` returns early when no
parser is available, so `core/plugins.lua` and `core/symbols.lua` — both
required below that point — never load. Measured: **43 files parser-less
against 45 with a grammar reachable.** Packaging a full-fidelity binary
from a parser-less manifest would drop those two and produce, again, not
a build error but a binary that silently extracts no plugin specs and no
module-scope symbols. The script warns on stderr when it is producing the
parser-less closure rather than leaving that to be noticed later.

### Step 3 — tree-sitter, and why the CLI is the wrong unit to bundle

The CLI does work, and `tree-sitter query` returns exactly the shape this code
reads from `iter_captures`: capture name, start and end `(row, col)`, and the
matched text. Verified against this repository's real complexity query.

It has two problems, one of degree and one of kind.

**Degree — process startup dominates, so batching is mandatory.** Measured:

| | Time |
|---|---:|
| First run (grammar compiled on demand) | 0.698 s |
| Warm, one file | 0.081 s |
| One invocation over 35 files | **0.229 s** |
| Per-file loop over the same 35 files | 2.482 s |
| One invocation over lib.nvim's 367 files | **0.592 s** |

Per-file is 10× worse than batched, so any design that parses a file at a time
— which is what `scan()` does today — is off the table. Even batched, this
repository issues **8 distinct queries**, so a full scan is ~8 invocations:
roughly 4.7 s over lib.nvim against 0.65 s for the entire in-process scan
today. Around 7×, for the query half alone.

Note also that the CLI compiles a grammar from source on first use, which
means a C toolchain on the *user's* machine — a heavier dependency than the
thing it was supposed to remove.

**Kind — queries are only half of what this code does.** There are 12 query
call sites, and **27 tree-navigation call sites** across `functions.lua`,
`calls.lua`, `symbols.lua` and `deps.lua`: `:child()`, `:child_count()`,
`:parent()`, `:type()`, `:range()`. `tree-sitter query` cannot serve any of
them. `shape_of` — the fingerprint duplicate detection is built on — walks
every node in a subtree, and `is_top_level` walks the parent chain. Recovering
those from `tree-sitter parse`'s S-expression output means writing a tree API
over parsed text, which is a component, not a shim.

**So: bundle the library, not the CLI.** The CLI is a Rust wrapper around
`libtree-sitter`, which is C — and `tree-sitter-lua`'s `src/parser.c` is
generated C. Both link into a `luastatic` binary natively, and you cannot link
a Rust executable into a C one anyway; bundling the CLI would mean embedding it
as a resource and exec'ing it at runtime. Linking the library gives one
artifact, no subprocess, no per-invocation cost, no C toolchain on the user's
machine, and — the part that decides it — **the full node API, so the 27
navigation sites survive**.

What that leaves is a Lua binding whose surface matches what this code calls.
That is the one genuinely unresolved question, and it is sharper than
"does a binding exist": does one exist shaped like `query.parse` /
`iter_captures` / `get_node_text` / `:child` / `:parent`, or does a shim have
to be written over it? Answer that before anything else in this document is
worth starting.

### That question was answered empirically (2026-08-11), and the answer is "not on Windows"

**The API-shape question turned out to be the easy half, and answering only
it produced a wrong conclusion.** An earlier pass this same session read
[`ltreesitter`](https://github.com/euclidianAce/ltreesitter)'s C source,
confirmed its method surface lines up almost exactly with what `core/*.lua`
calls (one real gap — no `node:parent()`, closable with a ~30-line
pure-Lua parent-index shim), and concluded a full-fidelity standalone
build was "buildable, not blocked". **That conclusion was wrong**, because
checking an API's *shape* is not checking that it *builds and runs*. Both
available Lua bindings to `libtree-sitter` were then actually installed
and exercised. Both fail on Windows, in different ways:

| Binding | Result | Detail |
|---|---|---|
| [`ltreesitter`](https://github.com/euclidianAce/ltreesitter) | **Does not compile** | `csrc/dynamiclib.c`'s `_WIN32` branch does `*out_error = GetLastError()` — assigning a `DWORD` to a `const char *`. Present on `main`, not only the 0.3.0 release, so this has effectively never built on Windows. |
| [`lua-tree-sitter`](https://github.com/xcb-xwii/lua-tree-sitter) | **Compiles (after two local fixes), then segfaults** | Its published `.src.rock` ships an incomplete vendored tree-sitter (the bundled ICU `unicode/*.h` are missing — building from a `--recurse-submodules` checkout fixes that), and its rockspec omits `tree-sitter/lib/src` from `incdirs` (a one-line fix). With both applied it builds and installs cleanly — and then `tree:root_node()` segfaults. |

**The segfault is grammar-independent**, which is worth recording because
it rules out the obvious first suspect: it reproduces identically against
Neovim's own shipped `parser/lua.dll` *and* against `tree-sitter-lua`
compiled from source locally. Both report ABI version 15; the vendored
`libtree-sitter` declares `TREE_SITTER_LANGUAGE_VERSION 15` with a minimum
of 13, so the versions genuinely match. The node metatable is registered
correctly (`LTS_setup_node` runs in `luaopen_lua_tree_sitter`). The
remaining likely cause is a struct-by-value ABI problem in the mingw
build — `ts_tree_root_node` returns a 32-byte `TSNode` by value, which
`LTS_push_node` then takes by value — but that was **not** proven, and is
recorded as a hypothesis, not a finding.

**Two useful side findings from the same pass:**

- Neovim's own shipped grammar `.dll` loads fine through a third-party
  binding (`Language.load(path, "lua")` succeeds, reports ABI 15). Not
  usable for this purpose regardless — a build whose whole premise is
  "runs without Neovim" cannot depend on Neovim's parser being installed —
  but it does confirm grammar loading itself is not the hard part.
- **Building the grammar from source is trivial**, contrary to any worry
  that it needs the `tree-sitter` CLI or a Node toolchain: one
  `gcc -O2 -shared -o lua_grammar.dll src/parser.c src/scanner.c -Isrc`
  against a plain `tree-sitter-lua` checkout, worked first try. The
  generated `parser.c` needs only `tree_sitter/parser.h`, which the
  grammar repo vendors itself.

**Status: the real-parsing standalone path is blocked on Windows**, on
upstream defects in both bindings rather than on anything in this
repository. Nothing here says it is blocked on Linux/macOS — neither
binding was tested there, and `lua-tree-sitter`'s two packaging bugs
above are Windows-neutral (they would bite any platform) while its
segfault may well be Windows-specific. Testing that is the obvious next
step if this is picked up again.

### That next step was taken (2026-08-11): **it works on Linux**

Run under WSL/Arch on the same machine the Windows failures above were
recorded on — so the two results differ by platform and nothing else.
`lua-tree-sitter`, built against the system LuaJIT.

**Both documented packaging fixes were necessary and sufficient**, which
independently confirms the diagnosis above rather than merely repeating
it: a `--recurse-submodules` clone supplies the ICU `unicode/*.h` the
published rock omits, and adding `tree-sitter/lib/src` to the include
path fixes the second. With both applied, `libtree-sitter` and the
binding compile clean.

**`tree:root_node()` returns normally** and prints a complete, correct
S-expression. **The Windows segfault is therefore platform-specific**,
which supports the mingw struct-by-value hypothesis recorded above
(`ts_tree_root_node` returning a 32-byte `TSNode` by value) — still not
*proven*, but no longer competing with "the binding is simply broken".

The whole pipeline was exercised, not just the crashing call:
`Language.load` → `Parser.new`/`set_language` → `parse_string` →
`root_node` → `Query.new` → `Query.Cursor.new` → `next_capture` → byte
offsets → source text. A two-function fixture returned exactly its two
expected captures with correct names, node types and positions.

**Two findings that change the shim estimate, both in the good direction:**

- **`node:parent()` exists on this binding.** The ~30-line parent-index
  shim costed above was for `ltreesitter`'s gap; `lua-tree-sitter` has
  `parent`, `next_sibling`, `prev_sibling`, `next_named_sibling`,
  `prev_named_sibling` natively. That shim is not needed.
- **No LuaRocks, and no root, were required.** Plain `gcc` against
  `pkg-config --cflags --libs luajit`. That matters for the packaging
  story: it is the same shape a `luastatic` link would take.

**What a shim does still have to cover** — all API *shape*, none of it a
capability gap, and all of it composable from methods that exist:

| Neovim API this code calls | `lua-tree-sitter` equivalent |
|---|---|
| `node:range()` → 4 numbers | compose from `start_point`/`end_point` (or `start_byte`/`end_byte`) |
| `node:start_point()` → `row, col` | returns a `Point` object, not a tuple |
| `query:iter_captures()` generator | `Query.Cursor.new(q, node)` + imperative `cursor:next_capture()` |
| `vim.treesitter.get_node_text` | `src:sub(node:start_byte() + 1, node:end_byte())` |

Node methods confirmed present and used by this repository's 27
navigation call sites: `child`, `child_count`, `parent`, `type`,
`named_child`, `named_child_count`, `start_byte`, `end_byte`,
`start_point`, `end_point`, plus `is_named`/`is_missing`/`has_error`.

**Revised status: the full-fidelity standalone path is viable on Linux
and blocked on Windows.** Not blocked as such. macOS remains untested,
but the failure mode that blocked Windows is a mingw hypothesis, so
macOS is more likely to resemble Linux than Windows.

Reproduction lives in `~/ts-test` inside the WSL instance (both repos
cloned, both artifacts built) if this is picked up again.

### And then it did not reproduce on Windows either (2026-08-11, later the same day)

The planned next experiment was to rebuild the binding with MSVC instead
of mingw, to test the struct-by-value hypothesis. **That experiment was
never needed: re-running the failing call against the same mingw-built
artifact passed.** Not a rebuild, not a newer version — the same file.
`lua_tree_sitter.dll` carries a build timestamp of 03:16 that day, while
the failure above was committed at 08:47 and 09:16, so the binary predates
its own bug report by hours and has not been touched since.

Everything Phase 0 verified under WSL now also passes natively on Windows,
against **a grammar built from source in this session** — `gcc -O2 -shared
-o lua_grammar.dll src/parser.c src/scanner.c -Isrc` against a plain
`tree-sitter-lua` checkout — with **no Neovim involved anywhere**, which is
the configuration the standalone premise actually requires. The earlier
successful `Language.load` of Neovim's own shipped `parser/lua.dll` was
explicitly discounted above for that reason; it is kept here only as a
control, and both now pass identically:

```
require lua_tree_sitter            ok
Language.load                      ok  ABI 15
Parser:parse_string                ok
Tree:root_node                     ok  chunk
Node:parent                        ok
query -> captures -> source text   ok  got [alpha beta gamma gamma]
Cursor:set_byte_range              ok  1 capture(s), expected 1
```

**Why the original run failed could not be reconstructed, and nothing here
should be read as having fixed it.** Three candidate explanations were
checked and none holds: the binding statically links `libtree-sitter`
(its only imports are `KERNEL32`, `msvcrt` and `lua54.dll`, and there is
no `libtree-sitter.dll` anywhere on `PATH`), so a stray-DLL mix-up is
ruled out; there is exactly one `lua54.dll` on the machine, sitting beside
the interpreter that loads it, so the "two Lua runtimes in one process"
failure mode is ruled out too; and both sides of the struct-by-value call
come from the same mingw build, so the two compilers cannot disagree
across it. The honest summary is *does not reproduce*, with the cause of
the original observation unexplained — most likely something about how
that particular run was invoked, which was not written down at the time.

**That is exactly why this is now a script and not a paragraph.**
[`standalone/check_treesitter.lua`](../../../standalone/check_treesitter.lua)
runs the whole pipeline against a fixture whose expected captures are
stated before anything executes, so a pass means "produced this exact
answer" rather than "did not crash", and exits non-zero naming the stage
that failed. It is deliberately not wired into `TESTS/run.lua`: it needs a
`lua-tree-sitter` rock and a compiled grammar, and CI should not grow a
dependency on either. Run it on a machine you are asking the question
about:

```
lua standalone/check_treesitter.lua /path/to/lua_grammar.dll lua
```

**Revised status again: the full-fidelity standalone path is not currently
blocked on any tested platform.** Windows and Linux both pass. The MSVC
experiment stays on the shelf rather than being struck out — if the crash
returns, it is still the cheapest next probe, and the script above is now
what would catch the regression instead of a hand-run session nobody kept.

**macOS is out of scope, by decision rather than by omission
(2026-08-11).** It is not a target for this project; earlier notes above
that call it "untested" should be read as "not going to be tested", so
that it stops reappearing as an open question in every status pass.

### Step 3 is done: the standalone build is byte-identical to Neovim (2026-08-11)

[`standalone/treesitter.lua`](../../../standalone/treesitter.lua) replaces
`vim_shim.lua`'s inert parser stub with a real `vim.treesitter` backed by
`lua-tree-sitter`. **No `core/*.lua` file changed to accommodate it** —
that was the whole premise of the split enforced in Step 1, and this is
the first time it has actually been tested rather than asserted.

The acceptance test is not a judgement call: generate this repository's own
map both ways and compare bytes.

| Artifact | Result |
|---|---|
| `module_map.json` | **identical** (953,400 bytes) |
| `index.html` | **identical** (1,504,097 bytes) |
| `overview.md` | **identical** (13,433 bytes) |

```
nvim --headless -l scripts/gen_map.lua
DOCMAP_TS_DIR=/path/to/grammars lua standalone/docmap.lua . \
  --source=lua/documentation --repo-url=… --branch=main
```

**Four API gaps had to be bridged, and three of them are exactly the kind
that reading documentation gets wrong** — each was measured against a real
parser first: `capture:index()` is 0-based while Neovim's `query.captures`
is a 1-based array; `match:captures_to_table()` returns a flat array of
`Capture` objects rather than Neovim's capture-id → node-array mapping;
`node:range()` and `node:field()` do not exist and are composed from
`start_point`/`end_point` and `field_name_for_child`. A fifth,
`node:iter_children()`, was found the honest way — by running the real
generator and watching it stop in `core/plugins.lua`.

**Two latent determinism bugs in the *plugin itself* surfaced from this**,
both the same root cause and neither visible from inside Neovim: LuaJIT
renders an integral float as `100`, PUC Lua 5.3+ as `100.0`, and both
leaked into the byte-compared artifact — once through `core/json.lua`
encoding values, once through `core/quicks.lua` building pre-formatted
`detail` strings with `%s`. Fixed in both places. Under LuaJIT the output
is unchanged, verified by regenerating and confirming no value-formatting
byte moved. This is the artifact `--check` compares and a pre-commit hook
fails on, so "the same tree scanned by a different Lua reads as stale" was
a real defect waiting for its first non-Neovim run.

**The fallback is intact and was tested, not assumed:** with no binding
installed, or a binding but no reachable grammar, the build degrades to
the parser-less MVP and exits 0 rather than failing. A machine without the
rock still gets a working, smaller build.

### The determinism defect now has a gate (2026-08-11)

Finding a defect that four green gates could not see is an argument about
the gates, not just about the defect. Every one of them runs inside
Neovim, so none could express the bug at all.

A fifth gate, `scripts/ci.lua`'s `standalone`, runs the build under a Lua
that is **not** LuaJIT and asserts the artifact carries no host-dependent
number formatting. It uses the **parser-less** build on purpose: that
needs only `lfs` and `dkjson`, both ordinary rocks, while the
full-fidelity path needs `lua-tree-sitter`, whose published rock has the
two packaging defects recorded above. Gating `main` on that would be a
check that goes red without anyone touching anything — the same advice
this project gives adopters in [`REUSE.md`](../../REUSE.md#repository-specific-drift-checks).
Full byte-parity against a Neovim run therefore stays a local gate, run
the way this session ran it.

**The gate was verified by breaking it**, not by watching it pass:
reverting one of the two `core/quicks.lua` fixes turns it red with the
offending string quoted, and restoring the fix turns it green. A gate
that has never failed is a gate nobody has tested.

`TESTS/host_lua_determinism_spec.lua` locks the same invariant as a unit
test. It is honest about its own limit: under LuaJIT those assertions
pass whether or not the fix is present, because LuaJIT never had the bug.
It is a specification lock for the next reader, and the `standalone` gate
is the thing that actually catches a regression.

**What is not blocked:** the parser-less MVP (`standalone/vim_shim.lua` +
`standalone/docmap.lua`) works today, verified end to end against this
repository's own tree — module tree, require graph, and every check and
renderer that does not need per-function facts, byte-identical to a real
`nvim --headless` run apart from the function-level data it honestly
reports as absent.

### The inputs now exist as durable artifacts, and one new trap (2026-08-11)

Everything above proved the full-fidelity binary *can* be built. What was
actually installed afterwards was the **parser-less** one, and the grammar
it had been proven against was not kept — so the proof was real and the
working setup was not. This section records the durable version, plus the
one failure the earlier runs did not hit.

**The trap: build the binding against tree-sitter's `master` and it does
not compile.** `lua-tree-sitter` calls `ts_language_version` and
`ts_parser_timeout_micros`, both **removed** upstream after the version it
pins. A plain `git clone` of tree-sitter gets `master` and fails with two
`implicit declaration` errors that read like a broken binding rather than a
version mismatch. The submodule pin is the answer and is worth reading
rather than working around:

```bash
git -C lua-tree-sitter ls-tree HEAD tree-sitter   # -> 726dcd1… = 0.25.4
git -C tree-sitter fetch --depth 1 origin 726dcd1e872149d95de581589fc408fb8ea9cb0b
git -C tree-sitter checkout FETCH_HEAD
```

**Four grammars, not one.** The earlier run proved the mechanism with Lua
alone; `core/lang/{js,ts,tsx}` are dead weight in a binary that can only
parse Lua. Each is still one `gcc` call against a plain checkout — no
tree-sitter CLI, no Node:

```bash
gcc -O2 -shared -o <lang>.dll src/parser.c src/scanner.c -Isrc
```

from `tree-sitter-grammars/tree-sitter-lua`,
`tree-sitter/tree-sitter-javascript`, and `tree-sitter/tree-sitter-typescript`
(whose `typescript/` and `tsx/` are separate grammars in one repository).
**Mixed ABI is fine and worth stating**, because it looks like it should not
be: Lua and JavaScript build to ABI 15, TypeScript and TSX to ABI 14, and
the one statically linked libtree-sitter loads all four.

**Verify a grammar rather than trusting that it compiled.** A grammar that
links cleanly can still be the wrong one for its file name, and the failure
downstream is silent missing data.
[`standalone/check_treesitter.lua`](../../../standalone/check_treesitter.lua)
answers this for Lua; for the others the equivalent check is load, parse a
snippet of that language, and assert the root type with no `ERROR` node in
the tree — all four pass.

**And that grammar check is not enough on its own, which is the sharper
lesson.** All four grammars passed it while the binary still could not scan
a TypeScript file at all — the manifest hazard below, one level deeper than
the version already recorded. Running the binary over a real JS/TS/TSX
corpus is what caught it: 11 files copied out of `mdview.nvim`'s client and
one `.tsx` from a Next.js project, which after the fix yields **48
functions — 37 from `.ts`, 10 from `.js`, 1 from `.tsx`** with real names
(`parseSourcepos`, `installHistory`, `Navbar`). A per-grammar load test
proves the grammar; only a real scan proves the pipeline.

### The manifest closure has a second axis: what was scanned (2026-08-11)

Already recorded above: the bundle manifest must be measured with a parser
available, because `core/plugins.lua` and `core/symbols.lua` load only
below `scan_file`'s early return. **That is one of two independent axes,
and the second cost a shipped-and-verified binary its first contact with a
TypeScript project.**

`core/lang/ecma` requires `core/endpoints` while scanning a `.js`/`.ts`/
`.tsx` file. This repository is pure Lua, so a manifest measured here —
with every grammar present, byte-identical output, all gates green — still
has no `core/endpoints` in it. The binary was correct for every input it
had been tested against and died with a `module not found` traceback on the
first `.tsx` file.

Measured in this repository: **43 files parser-less, 45 with a grammar
reachable, 46 once a JS/TS/TSX corpus is scanned as well.**

The fix is in [`scripts/bundle_manifest.lua`](../../../scripts/bundle_manifest.lua)
rather than in an instruction to whoever builds: it now probes twice, the
repository and then a generated three-language fixture, and `package.loaded`
accumulating across both makes the union automatic. Generated rather than
checked in on purpose — a fixture under `TESTS/` would be picked up by
`coverage.lua`'s scan of that directory and start moving this repository's
own `fn.tested` numbers, which is a real artifact change to pay for a build
detail.

**The general rule, now that both axes are known:** the closure is a
property of one *run*, so the manifest is only as complete as the corpus
and configuration it was measured under. A binary meant to scan languages
the measuring repository does not contain needs them represented somewhere
in the probe.

**Layout as installed** (paths are this machine's; nothing in the code
assumes them — the binary takes `$DOCMAP_TS_DIR`, and the app's
"Grammars…" button points at the same directory):

| Path | Holds |
|---|---|
| `C:\tools\docmap.exe` | the full-fidelity binary, 1.74 MB |
| `C:\tools\docmap-grammars\` | `lua.dll`, `javascript.dll`, `typescript.dll`, `tsx.dll` |
| `C:\tools\docmap-libs\` | `lfs.a`, `lua_tree_sitter.a` — kept so an engine rebuild does not re-clone three repositories |

**Re-verified, and it is a reproduction rather than a new result**: the
*packaged binary* — not the script under PUC Lua with the LuaRocks
`.dll` — reports `Module map is up to date` against this repository's
committed artifacts, which is `--check`'s byte comparison of all three.
The distinction matters because everything the packaging step adds
(luastatic's name rewriting, the single-archive link, the static
libtree-sitter) sits between the verified source path and the shipped
artifact.

One method note, recorded because it cost two false diagnoses: the docs
scanner reads **every** `.md` in the tree, so writing a comparison map into
`build/cmp/` inside the repository changes the input and the diff reports a
difference that is the measurement's own doing. Compare with `--check` and
the real `out_dir`, or generate outside the tree.

### Step 4 — the binary answers `/api/*`, not just `--check` (2026-08-11)

Everything above proves the *scan* half is portable: same source, same
`module_map.json`, on any host. The generated page also fetches four
`/api/*` routes at runtime — `telemetry`, `telemetry/snapshots`, `loaded`,
`loaded/snapshots` — and until now only `editor/serve.lua` inside Neovim
could answer them. `docmap-desktop` (a Tauri desktop app hosting maps for
several projects, [github.com/StefanBartl/docmap-desktop](https://github.com/StefanBartl/docmap-desktop))
needed the same answers from a process with no editor at all.

The answers moved to `core/api.lua`, reachable from the standalone build the
same way `core/scan.lua` already was — a plain Lua module with no socket
and no editor dependency. `editor/serve.lua` kept its socket, its security
checks and its response encoding, and stopped computing the bodies itself;
`standalone/docmap.lua` gained `--api=<route> [--snapshot=NAME]`, printing
one route's JSON and exiting. One route per invocation, deliberately: a
request is one question, and a process answering several would need a
protocol to say which answer is which.

**This needed one more piece of portable state than the scan half does.**
`runtime-analysis.nvim`'s telemetry store resolves its cache root from
`vim.fn.stdpath("cache")` at module load time, so `standalone/vim_shim.lua`
gained a real implementation — verified against a real `nvim --headless` on
this platform rather than read off documentation, since a shim that
resolves a *different* directory than the running editor would silently
report "no telemetry data" for data sitting on disk. On Windows `cache` is
`$TEMP/nvim`, not the intuitive `%LOCALAPPDATA%`.

**A version check turned out to be load-bearing, not optional.** An engine
built before `--api=` existed does not decline the flag — every
unrecognised `--flag` after the root falls through to `core/cli.run` as an
ordinary argv entry, so the old binary treated `--api=telemetry` as an
argument, *regenerated the map*, and exited 0 with output that was not
JSON. It overwrote this repository's own committed map the first time it
was tried. `--capabilities`, recognised in the *root*-argument position
(the one spot an older binary rejects immediately, before doing any work,
independent of whether it recognises the flag), is what a caller checks
first — verified non-destructive against the previously shipped binary.

Same "closure is a property of one *run*" rule as the manifest section
above, extended to a third probe: a scan run never loads `core/api`,
`core/artifact` or `core/loaded_diff`, so `scripts/bundle_manifest.lua` now
runs the `--api=` mode too, or a binary built from the first two probes
alone would die with `module not found` on its first Telemetry request from
a real host.

### Step 5 — the full toolchain exists on Windows too, found rather than assumed (2026-08-12)

The blocker for shipping any of the above was never the code — it was that
`C:\tools\docmap.exe` predated `--api=` entirely, and rebuilding it needed a
PUC Lua 5.4 toolchain nobody had confirmed was on this machine. It was:
`C:\Program Files (x86)\Lua\5.4\src\lua.exe` (5.4.8), `gcc` via mingw64, and
LuaRocks already installed, just not configured to see that interpreter.
`luafilesystem`, `dkjson` and `luastatic` installed clean once pointed at
it — the packaging story for the parser-less half was never actually
blocked, only unconfigured.

**`lua-tree-sitter` needed the same two fixes already diagnosed on Linux
(the section above, 2026-08-11) — and, measured rather than assumed, they
were exactly enough on Windows too.** A `--recurse-submodules` clone
supplies the vendored ICU headers the published rock omits; adding
`tree-sitter/lib/src` to the rockspec's `incdirs` fixes the second. `luarocks
make` against the patched rockspec from that clone built and installed
clean, and `standalone/check_treesitter.lua` against a real
`lua_grammar.dll` passed every stage — the same fixture, the same
pass/fail shape the Linux run already established.

**The rebuilt binary is byte-identical to the committed map** (`--check`
with matching `--repo-url`/`--branch`) and has real function-level data —
213/462 functions found by name, versus 0 for a parser-less build — so this
is not a downgrade from the binary it replaced, it is the same fidelity
plus a working `--api=`. `--capabilities`, `checklist`, `commits` and
`commit/<sha>` were each verified against this repository's own real
data (its own commit history, its own checklist ledger), not a fixture.

**Telemetry specifically stayed a documented "no data," not a lie or a
crash** — see `ensure_soft`'s own doc comment in `standalone/docmap.lua`
for the full trace: `runtime-analysis.telemetry` needs
`lib.nvim.autocmd`, which needs `lib.lua.lazy`, a `lib.*` sub-namespace
`bundle_manifest.lua`'s `bucket()` does not recognise (`^lib%.nvim` only).
Reading that data from a compiled standalone binary is therefore still
open — a real, scoped follow-up, not solved today — while everything that
does not depend on `runtime-analysis.nvim` now works end to end.

**A side effect worth recording on its own:** `scripts/ci.lua`'s
`standalone` gate had been *skipped* on this machine for the entire rest
of this work — "no PUC Lua on PATH with lfs + dkjson" — meaning every
commit in Steps 3 and 4 above went in without that gate ever actually
running here. With `lua5.4.exe` now placed on `PATH` (a copy in
`C:\tools`, since the real install lives somewhere `luarocks`/`gcc` cannot
write a same-named binary into) and the rocks installed, it runs for real
and passes, including the non-host-dependent-number-formatting check that
gate exists for.

### Step 6 — the packaging script itself has three POSIX-path bugs, found by building on Linux (2026-08-12)

Everything above proved the *pipeline* (tree-sitter, the binding, the
Windows toolchain). This step proved something narrower and previously
untested: does `scripts/package.lua` itself run correctly on a non-Windows
host? It had never been run under anything but PUC Lua on Windows before
today. Under WSL/Arch — the same instance Step 3's Linux verification used
— it failed three times, each time on a real, previously-latent bug rather
than a environment problem, and each time in the same shape: a check meant
to recognise "this path is already absolute" that only recognised the
Windows spelling of absolute.

**`mkdirp`'s leading `/` disappears inside `gmatch("[^/]+")`.** A POSIX
absolute path's first character is a separator to that pattern, not
content, so `mkdirp("/tmp/x")` built `tmp`, then `tmp/x` — real
directories, just relative ones, created under whatever the current
directory happened to be rather than under `/`. Silent on Windows for as
long as this script has existed, because every path there carries a drive
letter and the loop's *first* match is never empty. Surfaced as
`package: cannot write /tmp/docmap-build/stage/documentation/init.lua` —
misleading on its face, since the write failed only because the directory
silently existed at the wrong path, not because writing failed outright.

**The manifest-to-staged-path mapping had the same blind spot for a rock
installed outside the tree.** `dkjson` reached via a plain
`LUA_PATH=/tmp/?.lua` entry (this environment's stand-in for a real
LuaRocks install) is reported by `bundle_manifest.lua` as an absolute
POSIX path. The code that decides whether a manifest path is already
absolute checked only `f:match("^%a:")` — true for `C:\...`, false for
`/tmp/...` — so the POSIX path was treated as repo-relative and prefixed
with the repo root a second time, producing `scripts/..//tmp/dkjson.lua`
and a read failure. On Windows this never had a chance to trigger: a
LuaRocks-installed rock's path always carries a drive letter there too.

**`stage_abs` had the identical check** for the *output* directory
(`--out=`), which would have double-prefixed an absolute `--out=/tmp/...`
value with `cwd` the same way, one step later in the build. Found by
inspection once the pattern was recognised the second time, fixed before
it could fail a third time separately.

**All three fixed by extending each check from "starts with a drive
letter" to "starts with a drive letter, or starts with `/`"** — see the
three sites in `scripts/package.lua`. None of the fixes changes Windows
behaviour: a Windows path never starts with `/`, so the added branch is
simply never taken there. `git blame` will show these as old code — they
are as old as the script itself, latent since Step 2, waiting for the
first `--out=<absolute POSIX path>` this repository had never actually
tried.

**A fourth issue was environment, not a bug**: `copy()`'s plain
`io.open`/`io.write` does not carry an executable bit through, and gcc's
own `+x` on the file it produced did not survive being read back from a
Windows drive mounted into WSL (`/mnt/e`, DrvFs) — the copy landed as
`rw-r--r--` and the verify run failed with `Permission denied` until a
manual `chmod +x`. A real GitHub Actions `ubuntu-22.04` runner has no such
mount in the path — the whole runner is native Linux filesystem — so this
would not reproduce there. Fixed anyway, cheaply: an explicit
`chmod +x` on the copied binary, skipped on Windows, a no-op on a
filesystem that already tracked the bit correctly.

**With all four applied, the full-fidelity engine was built entirely
under WSL/Arch, end to end, from a clean checkout of this repository**:
PUC Lua 5.4.8 from `lua.org` source (`make linux`; Arch's own `lua54`
package ships no static `.a`), `lua-tree-sitter` and `lfs` compiled to
static archives with plain `gcc` (no LuaRocks needed at all — the
rockspec's own `sources` list is the accurate file list, used directly),
all four grammars via `tree-sitter build` (the same CLI `.github/workflows/ci.yml`'s
own `tests` job already uses for JS/TS/TSX — simpler than a manual `gcc`
invocation and needs no separate libtree-sitter, since a grammar's `.so`
depends only on `tree_sitter/parser.h`), `dkjson` fetched as the single
pure-Lua file it is.

**The result matched the Windows one exactly**: `213/462 functions found
by name in TESTS` — the identical count Step 5 reported for the Windows
build, not merely a similar one. And `--check` against this repository's
own committed `docs/map` reported **`Module map is up to date`** — byte
identical, built by a different compiler on a different OS from a
different Lua source tree, which is the strongest evidence this pipeline
does not have a hidden Windows-only assumption left in it anywhere that
matters to the output.

**This closes the remaining precondition for Task 7's real CI staging**
(`docs/HANDOVER.md` in `docmap-desktop`, "Bundling der Engine"): the
recipe that would need to run inside a `ubuntu-22.04` GitHub Actions
runner is now proven, not assumed — every command above ran in a fresh
shell with nothing pre-installed but what a plain distro image and a
`curl`/`git clone` would already give a CI job.

### Step 7 — `--api=telemetry` against real data, finished this time (2026-08-12)

Step 5 recorded the trace and stopped: `bucket()` widened would fix the
*transitive* half of `runtime-analysis.telemetry`'s chain
(`lib.nvim.autocmd` -> `lib.lua.lazy`), and named that as a follow-up
rather than guessing at the rest. Doing that follow-up found it was only
half the fix.

**`bucket()`'s `^lib%.` branch (added) does exactly what it says — makes
`lib.lua.lazy`/`lib.lua.yaml` visible to the packager.** `staged_name()`
needed a matching branch too (`lib/lua/...`, a sibling of the already-handled
`lib/nvim/...` under the same `lib.nvim` checkout), or a manifest that
correctly *measured* the dependency still had nowhere to *stage* it — the
same "recognised but not placed" gap the whole `staged_name()` function
exists to prevent for its other three cases. Verified via `strings
build/docmap.exe`: 19 hits for the module's own identifiers before either
fix, none of them the module's actual source, only this tree's own doc
comments *mentioning* `runtime-analysis.telemetry` by name — the tell.

**And even with both of those fixed, `--api=telemetry` still answered
`"no data"` — because `bucket()` never recognised `runtime-analysis.*`
itself.** `^documentation`, `^lib%.`, `dkjson`: three buckets, and
`runtime-analysis.telemetry`/`runtime-analysis.loaded` matched none of
them. Measured (`package.loaded` sees them, real requires resolve them at
build time) but never bucketed, so never staged, so `pcall(require,
"runtime-analysis.telemetry")` inside the *compiled* binary failed exactly
the way `telemetry_join.lua`'s own soft-dependency handling is designed to
absorb silently — indistinguishable from "not installed" without probing
the binary directly. A fourth bucket, `runtime_analysis`, plus the matching
`staged_name()` branch for the `runtime-analysis.nvim` checkout's own
`lua/runtime-analysis/...` tree, closed it.

**Verified against this machine's own real, previously-recorded 63 KB of
telemetry** (`documentation.nvim`'s own self-instrumentation,
`$TEMP/nvim/runtime-analysis.nvim/cache/telemetry/documentation.nvim.json`):
rebuilt with the sibling-checkout heuristic already in `ensure_soft`
finding `../runtime-analysis.nvim` with no env var needed locally, then

```
docmap.exe <root> --api=telemetry
```

against `documentation.nvim`'s own tree now answers `"available":true`
with real per-function call counts, where every build before this one —
including the one Step 5 called done — answered `"available":false,
"reason":"no data"` against the same real data sitting on the same disk.
`--check` and the function-count parity (213/462) both re-confirmed
unchanged, so this closed a real gap without moving anything else.

## Why this is not scheduled

Because the first question is already answered, and it is the one people
actually ask. `nvim --headless` is a dependency that CI installs in one step
and most Lua developers already have. A parser-less build would trade the
function-level half of the map — which is most of what makes the map worth
generating — for removing a dependency that costs almost nothing.

The case would change if the goal were a LuaRocks package usable from a
non-Neovim toolchain, or if a Lua binding to `libtree-sitter` turned out to
match the API surface this code is written against.

**As of 2026-08-11 the second condition is met on Linux.** The API surface
matches, and `lua-tree-sitter` builds and runs correctly there — the
Windows failure recorded above is platform-specific, not a property of the
binding. See the section above for the verified pipeline and the exact
(small, purely shape-level) shim that remains.

That removes the *technical* reason this was not scheduled. The
*motivational* one above still stands on its own terms — `nvim --headless`
is a cheap dependency for someone who already uses Neovim — but it no
longer applies to the case that actually motivates this work:
[`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md)'s Finding 2, that
reaching people who do **not** use Neovim is the point, and for them the
dependency is not cheap but total.

**Step 1 is worth doing on its own merits, though**, and does not depend on any
of the rest: the split already exists, and making it enforceable costs a rename
plus one `layers` rule. Everything after it is optional.

Recorded so the estimate does not get made from scratch again.
