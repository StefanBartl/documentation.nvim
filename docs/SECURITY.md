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
| Filesystem, read | Walks `opts.source` and reads `.lua` files, `README.md`, `@types/`, and `opts.tests_dir`. A link in the tree is followed only if it stays inside the project — see [Links](#links-junctions-and-the-output-directory). |
| Filesystem, write | Writes only into `opts.out_dir` (default `docs/map`), plus `docs/BINDINGS.md` from `scripts/gen_map.lua` and `doc/tags` from `:DocMap helptags`. **Never through a link**: nothing between the project root and `out_dir` may be one. |
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

## Links, junctions and the output directory

A repository is somebody else's input, and it can contain a symlink — on
Windows also a junction — anywhere. `core/safe_out_dir.lua` refuses `..` and
absolute paths in `out_dir`, but that is a check of a *string*; a link makes a
clean string lead anywhere. [`core/safe_fs.lua`](../lua/documentation/core/safe_fs.lua)
is the check of the thing itself, with one rule for writing and one for
reading.

**Writing.** Before the first byte is written, every component from the
project root to the output directory is asked with `lstat` (the standalone
build asks `cmd.exe` on Windows, where `lfs` cannot), and so is each file
about to be written. If any of them is a link the run stops with a message
naming it, and writes nothing:

```
docmap: refusing to write the map: docs/map is a link (a symlink or a junction),
so the map would be written wherever it leads. Replace it with a plain directory.
```

This holds however `out_dir` got its value — the default, a flag, the host's
options, or a `.docmap.json` in the repository — because the string is
relative to the root, so the links on the way are the repository's. A link that
stays inside the project is refused as well. It covers `module_map.json`,
`index.html`, `overview.md`, `coverage.svg` and `overview.pdf`. `--out-dir` has
never been able to name a place outside the project (`..`, an absolute path and
a drive letter are refused for it as for any other source), so there is no such
destination for this check to leave alone.

**Reading.** The source walk, the source roots, `.docmap.json` and the
committed map that `--check` reads back follow a link only if, resolved one
step at a time without opening anything on the way, it stays inside the
project. One that leaves it is not followed; the run says so on stderr:

```
3 links not followed:
  lua/p/escape -> /home/me/private: it leads outside the project
```

A source root that is such a link, or reaches outside with `..`, is refused with
the reason rather than reported as missing. Links that stay inside the project
work as they did, and a link back up the tree is walked once, not for ever.
`--check` reads the committed map through the same rule and refuses, rather than
reporting "stale", when it cannot: a map that cannot be read is not an old one.

**On Windows**, a link target is judged as a string before it is looked at.
Anything but a plain drive path — `\\host\share`, `\\?\UNC\…`,
`\\?\GLOBALROOT\…`, `\??\…`, a device or a volume path — is never opened, so
a link to a share cannot make the machine contact that host. The standalone
build recognises a link by asking `cmd.exe` (`dir /a:l`, once per directory the
walk enters) because `lfs.symlinkattributes` is `lfs.attributes` there. Only
the labels `<JUNCTION>`, `<SYMLINKD>` and `<SYMLINK>` count; cloud-sync
placeholders (OneDrive's files on demand) are reparse points too and stay
ordinary files. The one thing it cannot do is match a link whose name has
non-ASCII characters against the console's code page, so in a directory that
holds such a link every non-ASCII name is treated as a link as well. When
`cmd.exe` does not answer, nothing in that directory is followed, and the run
says so.

**Not covered yet:** these still open fixed names under the root directly and
follow whatever is there — the `docs/FEATURES` and checklist folders, the files
`core/check.lua` and `core/docs.lua` resolve README links to, `opts.tests_dir`
(`lib.nvim.fs.collect_recursive`), `opts.tag_files` and `opts.external_repos`.
They are the same class and belong behind the same module.

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
  claim to. It does refuse to write or read *through a link* where that lets a
  repository reach outside itself — the section above says exactly where, and
  where it does not yet.
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
