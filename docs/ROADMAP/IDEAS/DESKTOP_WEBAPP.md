# A polished desktop/web-app version — costed, not decided

Raised 2026-08-11: "a Desktop/Webapp version, building on this concept, but
with everything refined, also with better View/UI/feature equipment."
Analysis, not a proposal — the same posture
[`PORTABILITY.md`](../PORTABILITY.md)/[`MULTILANG.md`](../MULTILANG.md)
already take, referenced from [`ROADMAP.md`](../ROADMAP.md) rather
than repeated there.

**Two different products are bundled under one idea, and they cost
completely different things.** "Desktop app" (single-user, local,
packaged, no editor open) and "web app" (hosted, reachable by more than
one person) share a UI layer but not a trust model or a distribution
story. Splitting them is the first finding, not a footnote.

---

## What already exists — more than the idea's framing assumes

`docs/ECOSYSTEM.md` §6 already answered the adjacent question for
runtime-analysis.nvim ("Neovim plugin, web app, Electron app, or a
compiled binary?") and found, measured rather than guessed: **"a rich
browser UI" was already solved twice in-house** — documentation.nvim's
own generated page (`core/render/html.lua`, self-contained HTML+JS, no
CDN, no build step) is one of the two examples that analysis cites.

Concretely, as of this session, the generated page already has:

- Six Hierarchy views, a zoom slider, hide/dim, SVG export, right-click
  navigation
- A nine-tool Analysis tab (test/doc coverage, deps, complexity,
  duplicates, plugins, tools, telemetry, loaded — the last two
  server-backed with named-snapshot pickers)
- Compare (matrix/columns/stacked layouts, URL + `localStorage`
  persistence), History (git-backed diff/impact), Index, Features, Notes
- Works cold from `file://` for everything that doesn't need a server, and
  clearly explains itself (not silently blank) for the panels that do

This is already most of what "a webapp" colloquially means: a real,
navigable, stateful single-page application. The idea's own "refined,
better View/UI" framing is asking for investment in a UI that already
exists and already works — which matters, because it means a large slice
of what "better" could mean is available **today**, with none of the
infrastructure below, by spending design/frontend effort on the current
static page directly.

## What's actually missing, split by product

### Desktop app

A packaged, distributable thing a user downloads and runs — not "open
Neovim, run `:DocMap`, then open the file it wrote."

**The real blocker is generation, not display.** The display half exists
(above). What doesn't: producing `module_map.json`/`index.html` without
already being inside a running Neovim session. This was investigated for
real this session, not assumed:

- A parser-less standalone CLI (`standalone/vim_shim.lua` +
  `standalone/docmap.lua`, plain `lua`/`luajit`, no Neovim) was built and
  verified end to end against this repo's own real IR. It works — module
  tree, require graph, most drift checks, all renderers — for everything
  that doesn't need per-function facts.
- The actual blocker for a **full-fidelity** desktop app is
  `vim.treesitter`, and as of 2026-08-11 it is a **harder** blocker than
  an earlier draft of this document claimed. That draft said a standalone
  Lua binding to `libtree-sitter` made this "buildable, not blocked",
  based on reading [`ltreesitter`](https://github.com/euclidianAce/ltreesitter)'s
  API surface. **That was wrong** — it checked whether the API *shape*
  fits, never whether the binding builds and runs. Both available
  bindings were then actually installed and exercised, and both fail on
  Windows: `ltreesitter` does not compile at all (a real upstream
  `DWORD`-to-`const char *` bug in its `_WIN32` branch, present on
  `main`), and `lua-tree-sitter` compiles only after two local packaging
  fixes and then segfaults in `tree:root_node()` — reproducibly, against
  two independently built grammars, so not an ABI-version mismatch.
  [`PORTABILITY.md`](../PORTABILITY.md)'s own "That question was answered
  empirically" section has the full detail, including the two side
  findings worth keeping (Neovim's shipped grammar loads fine through a
  third-party binding; building the grammar from source is one `gcc`
  command). Neither binding was tested on Linux/macOS — that is the
  obvious next step, not a claim that it works there.
- Packaging once generation is solved: `luastatic` links a Lua
  interpreter, the sources and any C modules into one binary — installed
  and tried this session, genuinely "the least interesting step"
  ([`PORTABILITY.md`](../PORTABILITY.md)'s own words, confirmed rather
  than just asserted). A cross-platform build matrix (Windows/Linux/macOS)
  was scoped but not built.

**Two things a desktop app needs that the current page does not:**

- **A project switcher.** Today one map is one `index.html` for one repo.
  A desktop app browsing "my dozen personal plugins" wants one shell with
  a list of projects, not a dozen browser tabs pointed at a dozen files.
  No design work has happened on this at all — it is a real, unscoped
  gap, not a small one: it touches state/URL scheme, not just a new
  screen.
- **A shell to run in.** Once generation works standalone, "desktop app"
  still needs *something* to open the HTML in with app-like chrome (a
  window, not a browser tab) — Tauri/Electron-class tooling, or simply
  "open it in the user's default browser" (already what `:DocMap open`
  does, and arguably enough — a browser tab *is* the shell most users of
  a dev tool already trust and know how to bookmark).

### Web app

Hosted, reachable by more than the person who generated it. This is the
harder half, and the current architecture has an explicit, deliberate
answer that a web app would have to overturn:

> "Bind `127.0.0.1`, never `0.0.0.0`. This is a personal tool on a
> personal machine; there is no case where the network needs it."
> — `editor/serve.lua`'s own header comment.

That is not an oversight to lift; it is the whole reason the server has
never needed authentication, per-user isolation, or a trust boundary
between "whoever can reach this port" and "whoever owns this source code".
A real web app — even a small one, even self-hosted by one team — reopens
every one of those questions from zero: who can see which repo's map, how
a snapshot (telemetry, loaded) is scoped per viewer rather than per
machine, what happens when two people's `:DocMap serve` sessions would
otherwise collide. None of this is designed. None of it is a natural
extension of the current single-user, loopback-only server — it is a
different program wearing the same HTML.

**The honest reading of "web app" that costs the least:** the same static
page, published somewhere reachable (GitHub Pages, already sketched as
idea 6.3 in [`ROADMAP.md`'s idea backlog](IDEAS.md#63-publishing-the-map-to-github-pages)),
for the panels that don't need a server at all. Everything server-backed
(History, Telemetry, Loaded) stays a local, personal-machine feature under
this reading — which is arguably already "a web app" in the sense most
people mean when they say it about a docs site, and costs a publish
workflow, not a rewrite.

## What's cheap regardless of the above

Worth separating out because it's easy to conflate with the infrastructure
questions above: real UI/UX polish on the *existing* page — typography,
information density, a genuine design pass on the Analysis panels'
tables, better empty/loading states — needs none of standalone
generation, none of packaging, none of a trust-model redesign. It is
available today, and arguably the highest-leverage single piece of "better
View/UI/feature equipment" per hour spent, precisely because it doesn't
wait on anything else in this document.

## Verdict

Not one project. Three, in decreasing order of what's already solved:

1. **UI polish on the current page** — cheap, available now, no
   dependency on anything else here.
2. **A real standalone desktop app** — the hard half (generation without
   Neovim) is partly built and partly **blocked**: the parser-less MVP
   ships and works, but the full-fidelity path is blocked on upstream
   defects in both Lua `libtree-sitter` bindings (Windows-confirmed;
   Linux/macOS untested — see above). The UI half mostly exists; a
   project switcher and a packaging pass are the remaining work *after*
   the parsing blocker is resolved or the target platform narrowed.
3. **A hosted web app** — the least developed of the three, and the one
   whose hardest question (a real multi-tenant trust model) has no answer
   sketched anywhere in this ecosystem yet. Costed here only as "genuinely
   open, not merely unbuilt" — unlike (2), there is no existing research
   to point at.

## Revisit if

(2): once the treesitter Lua-binding path is actually built (not just
scoped) and there's a real want for "run this without opening Neovim at
all" beyond the convenience the current `:DocMap`/`:DocMap serve` flow
already gives inside an editor session that's usually open anyway. (3):
if a genuine multi-person/multi-team use case shows up — nothing in this
ecosystem's current single-author, single-machine posture asks for it
today.
