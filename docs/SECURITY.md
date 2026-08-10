# Security

What this plugin does that could hurt you, what it refuses to do, and what it
deliberately does not defend against.

None of this is new hardening — the properties below were designed in. What was
missing was the written record, which is what this file is. Every property here
has a spec; where a property could only be observed by opening a socket, the
function implementing it is exported so it can be tested without one.

## What the plugin touches

| Surface | What it does |
|---|---|
| Filesystem, read | Walks `opts.source` and reads `.lua` files, `README.md`, `@types/`, and `opts.tests_dir`. |
| Filesystem, write | Writes only into `opts.out_dir` (default `docs/map`), plus `docs/BINDINGS.md` from `scripts/gen_map.lua` and `doc/tags` from `:DocMap helptags`. |
| State | Saved trails, in `stdpath("state")` — never in the repository. |
| Subprocesses | `git`, and `lua-language-server` only under `:DocMap full`. |
| Network, outbound | **None.** No telemetry, no CDN, no fetch. The generated page is self-contained; the coverage badge is rendered locally rather than fetched from shields.io. |
| Network, inbound | Only under `:DocMap serve`, and only on loopback — see below. |

## The local map server

`:DocMap serve` exists for one reason: a `file://` page cannot `fetch`, so the
History tab cannot ask for a commit's analysis without an origin. It is off
unless you start it.

- **Binds `127.0.0.1` only, never `0.0.0.0`** ([`serve.lua`](../lua/documentation/editor/serve.lua)).
  This is a personal tool on a personal machine; binding wider would expose the
  repository's source to the network.
- **Port 0** — the OS picks a free one, so there is no predictable port to
  find and no collision with anything else.
- **Dies with the editor.** A `VimLeavePre` autocmd stops it, so no listening
  socket outlives the session that opened it.
- **Two routes, both validated:**
  - `safe_sha(s)` accepts `^%x%x%x%x%x%x%x+$` up to 40 characters and nothing
    else. That value becomes an argument to `git`, and the only safe answer to
    "is this a sha" is a shape check that rejects everything else — including
    the `--upload-pack=…`-style arguments that make argument injection into git
    interesting. Even `HEAD` is refused: a whitelist that starts making
    exceptions stops being one.
  - `safe_static_name(name)` accepts a bare filename inside `out_dir`. Anything
    containing a path separator or a `..` segment is refused, so the route
    cannot be walked out of the served directory.

## Subprocess execution

**Every** external command goes through `vim.system` with an argv array. No
`io.popen`, no `os.execute`, no shell anywhere in the plugin — verifiable with
a grep over `lua/`.

That is what makes user-supplied revisions safe. `:DocMap diff <ref>`,
`:DocMap impact <ref>` and `:DocMap churn <range>` pass their argument straight
into an argv array, so a value like `; rm -rf ~` is handed to `git` as one
literal argument and rejected by git as a bad revision. There is no shell to
interpret it. (The server route is stricter still, because there the input
arrives over a socket rather than being typed by the person running the
editor.)

`lua-language-server` runs only under `:DocMap full`, with a timeout
(`opts.luals_timeout_ms`, default 60s), and its failure is downgraded to an
info-severity finding rather than aborting the scan.

## The generated page

`docs/map/index.html` is self-contained: no CDN, no external stylesheet, no
script from anywhere else. Everything the page renders comes from the IR
embedded in it at generation time.

Content from the scanned tree — module summaries, function signatures, README
text — is HTML-escaped before it reaches the page. That matters because the
page is *generated from source code*, and source code is attacker-controlled if
the tree is: see the next section for the limits of that.

## What this does not defend against

Stated plainly, because a security note that implies more coverage than it has
is worse than none:

- **A repository you chose to open.** `:DocMap` reads and parses a tree you
  pointed it at. If that tree is hostile, you have already run a scanner over
  hostile input, and the same is true of your language server, your linter and
  your editor. This plugin does not sandbox the trees it reads and does not
  claim to.
- **`opts.tag_files`.** Cross-project links read another project's
  `module_map.json` from a local path you configured. It is parsed as JSON, not
  executed, but the path is trusted because you wrote it.
- **`opts.external_repos`.** Never a network call and never reads anything
  outside `opts.external_repos.*.local_path` (a local `uv.fs_stat`, same
  trust boundary as `opts.tag_files` above) — the GitHub URL it builds is a
  plain string, only ever opened by the reader's own click in the generated
  page, at view time, in their own browser. `owner`/`repo`/`branch` are
  interpolated into that string unescaped; they come from your own config,
  not from anything scanned.
- **`opts.extra_checks`.** Arbitrary Lua you supply, run against the IR. That
  is the feature.
- **Anything your plugin manager does.** Installation, updates and their hooks
  are outside this plugin.
- **The state directory.** Saved trails in `stdpath("state")` are plain JSON
  with no integrity check. Corrupting them can make a trail load garbage; it
  cannot execute anything.

## Reporting

This repository carries no licence and is a personal project. If you find
something, open an issue at
<https://github.com/StefanBartl/documentation.nvim/issues>. There is no embargo
process and no security contact beyond that — say so in the issue if you would
rather not describe the detail publicly.
