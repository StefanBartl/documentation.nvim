# Security

What this plugin does that could hurt you, what it refuses to do, and what it
deliberately does not defend against.

None of this is new hardening — the properties below were designed in. What was
missing was the written record, which is what this file is. Every property here
has a spec; where a property could only be observed by opening a socket, the
function implementing it is exported so it can be tested without one (the
link rule of the static route, `serve.static_answer`, is). The exceptions are
the stderr report of the links a run did not follow
(`report_skipped_links` in `core/cli.lua`), which no spec pins, and the race
below, which cannot be tested without flaking.

## What the plugin touches

| Surface | What it does |
|---|---|
| Filesystem, read | Walks `opts.source` and reads `.lua` files, `README.md`, `@types/`, and `opts.tests_dir`. A link in the tree is followed only if it stays inside the project — see [Links](#links-junctions-and-the-output-directory). |
| Filesystem, write | Writes into `opts.out_dir` (default `docs/map`), the `--sarif=<path>` report, `:DocMap annotate --write/--sidecar` (the source file or `<file>.annot.lua`), `docs/BINDINGS.md` from `scripts/gen_map.lua`, and `doc/tags` from `:DocMap helptags`. **Never through a link, in a tree that is not changed while the run goes on**: nothing between the project root and `out_dir` may be one, and neither may the report, the annotated file or `docs/BINDINGS.md`. The check and the write are separate steps, see [the limit](#links-junctions-and-the-output-directory). |
| State | Saved trails, in `stdpath("state")` — never in the repository. |
| Subprocesses | `git`, and `lua-language-server` under `:DocMap full` or when your own config sets `luals`; `pandoc` with a PDF engine (through pdfport.nvim) when your own config sets `pdf`. A `.docmap.json` in the repository can set neither. The standalone build runs its commands through `io.popen`, on Windows that is `cmd.exe /c` (see Subprocess execution), and also starts `cmd.exe` (`dir /a:l`) to tell links from directories. |
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
    cannot be walked out of the served directory. The file is then read through
    [`safe_fs`](../lua/documentation/core/safe_fs.lua): a file, or a `docs/map`,
    that is a link leaving the project is answered 404
    (`not served: <name>, it leads outside the project`, the target is not
    named). Links that stay inside the project keep working.

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

The command line (`docmap`, `scripts/gen_map.lua`) prints that one line on
stderr, after the run's list of links not followed, and exits with **2**: the
code `--check` has for a refusal to read, and not 1, which says the map is
stale or the tree has drift. An `out_dir` that is not a safe relative path is
refused the same way. Called from Lua, `write_artifacts` and `generate` raise
the same message as an error.

This holds however `out_dir` got its value — the default, a flag, the host's
options, or a `.docmap.json` in the repository — because the string is
relative to the root, so the links on the way are the repository's. A link that
stays inside the project is refused as well. It covers `module_map.json`,
`index.html`, `overview.md`, `coverage.svg` and `overview.pdf`, and the other
writes of the engine follow the same rule:

- `--sarif=<path>` refuses a report that has a link on its path
  (`docmap: refusing to write <path>: <name> is a link, ...`). A relative path
  is checked name by name below the directory the run started in; an absolute
  path below the project root is checked below the root, and elsewhere only the
  report file's own name is. A `..` after a name is refused, and so is `C:file`
  on Windows. A refusal, like a failed write, does not change the exit code.
- `:DocMap annotate --write` and `--sidecar` refuse a source file, a
  `<file>.annot.lua` or a directory on the way that is a link, also one that
  stays inside the project. The command reports it per file, with the link
  named, and leaves the tree as it was.
- `scripts/gen_map.lua` does not write `docs/BINDINGS.md` if it is a link (or
  has one on the way), says so on stderr and goes on; its exit code is
  unchanged.

`out_dir` itself has to be a safe relative path (`core/safe_out_dir.lua`).
`write_artifacts` has always refused `..`, an absolute path and a drive letter in
it. Two other places did not: before `e472c5c`, `--check` read the committed map
from an `out_dir` nobody had vetted, and `write_pdf_artifact` wrote
`overview.pdf` to one; both vet it now. So "`--out-dir` outside the project" was
never possible for the map, but it was for those two.

**The limit: a tree that changes while the run goes on.** The guard is an
`lstat` of the chain followed by an `open` by path, two separate steps, and the
kernel resolves the path again at the second. A process that can rename
entries inside the project while `docmap` runs — swapping `docs/map` between a
directory and a link to somewhere else, over and over — can win that window and
redirect the write. The window runs from the check to the last file written,
which can be long (`index.html` is large). Path-based Lua cannot close it
(there is no portable `O_NOFOLLOW` and no open relative to a directory handle,
and a check after the write could only detect it), so the guard is for static
trees: a checkout somebody else handed you, not a tree an attacker modifies
concurrently. What can be overwritten that way is only the fixed artifact names,
with generated content,
and only where you could write yourself. The same limit applies to every other
write and read above. Checkout content alone cannot do this; it takes a second
process with write access to the tree.

**Reading.** The source walk, the source roots, `.docmap.json`, the prose
corpus (every `.md` under the root), the tests directory, the Features and
Checklist folders, the targets of README links and the committed map follow a
link only if, resolved one step at a time without opening anything on the way,
it stays inside the project. The committed map is read by `--check`, the app's
`--api=` routes, the static files of `:DocMap serve`, `:DocBrowse` (the map and
its staleness check), the hover.nvim contribution and `:checkhealth
documentation`; the editor-side readers vet `out_dir` with `core/safe_out_dir`
as the writers do. The same holds for the other files a repository can name:
the install manifest (`docs/install.json`, `docs/INSTALL.md`, the `install_dir`
key; read with a 1 MiB bound, so a device cannot exhaust memory), the spec roots
behind `spec_state` and `affected_specs` (`tests_dir`, `spec_roots`, the spec
files and the sources re-read for computed requires), and the probes of source
detection. One that leaves the project is not followed; the run says so on
stderr:

```
3 links not followed:
  lua/p/escape -> /home/me/private: it leads outside the project
```

An absolute target is matched against the project path as given and, where the
host can say, as the system resolves it. A target that spells the same place
another way — a Windows 8.3 short name (`RUNNER~1` for `runneradmin`), `/var` for
`/private/var` — counts as leaving the project: the check never asks the file
system about a path it has not placed inside the project first. A README link
target is not judged when it has a URL scheme (`mailto:`, `tel:`, `https://`),
nor when it passes through a link that leaves the project (it is not looked at
and not reported dead). A `..` past the root stops at the root and an absolute
target is read below the README's directory; both are judged there, and a name
Windows cannot hold (`C:/x`) is dead on both platforms.

A source root that is such a link, or reaches outside with `..`, is refused with
the reason rather than reported as missing. `--check` reads the committed map
through the same rule and refuses, rather than reporting "stale", when it
cannot: a map that cannot be read is not an old one. A refusal exits with code 2
(an `out_dir` that is not a safe relative path, or a link on the way that leaves
the project); 1 stays "stale or error-severity drift", and `--lenient` never
turns a refusal into a pass. In the editor, a `docs/map` that links outside the
project is not read by `:DocBrowse` (`map at <path> is not read: <why>`), shows
a warning in `:checkhealth`, and finds nothing in hover; a setup that kept its
maps out of the tree behind such a link has to move them. Links that stay inside
the project work. The standalone build has no `realpath`, so for a relative
root (`docmap .`, `docmap ../repo`) it joins the working directory and the root
by string to recognise an *absolute* link target that points into the project;
it answers nothing, and so the target counts as leaving, when a `..` follows a
name of the root (`hop/../proj`), because a link there makes the string wrong.

**Directory links.** A directory link that stays inside the project is entered
(the standalone build always did; the editor host used to skip them). A
directory is entered through a link at most once per scan, so a folder that
many links lead to, or links that lead to each other, are not walked once per
path of links; real directories are always walked, and which link to a folder
is the one entered follows from the sorted entries. `meta.outside` does not
count a link from outside the source roots that leads into one, and a folder
reached by several names is counted once. As a backstop for spellings of one
folder that string comparison cannot see (Unicode case, NFC/NFD, Windows 8.3
names), a scan enters at most `scan.MAX_LINKED_DIRS` (10000) folders through
links, both walks together. Past that no further link is followed, the scan
carries on with the real tree, and the link list on stderr gets one entry,
`so many folders are reached through links that no further link is followed`.
Source detection (`config.build`, which also runs on every `:DocMap`
completion) enters a probed name that is a link staying inside the project, but
never a link found below it, so a directory of links back up the tree cannot
stall it; sources reachable only through such a link are no evidence of a
language, while the scan itself still enters the directory once.

**Case.** Two spellings of one folder are the same folder when the file system
folds case: always on Windows, elsewhere the scan asks the disk once
(`safe_fs.folds_case`: the root spelled with a letter of its name in the other
case must lead to the same directory), so `Up` and `up` stay two folders on a
case-sensitive disk. The standalone build's `stat` answers the type only, so
there an existing other spelling counts as folding.

**On Windows**, a link target is judged as a string before it is looked at.
Anything but a plain drive path — `\\host\share`, `\\?\UNC\…`,
`\\?\GLOBALROOT\…`, `\??\…`, a device or a volume path — is never opened, so
a link to a share cannot make the machine contact that host. The standalone
build recognises a link by asking `cmd.exe` (`dir /a:l` for every directory the
walk enters) because `lfs.symlinkattributes` is `lfs.attributes` there. The
directories below one are listed ahead in batches: one `cmd.exe` enters many of
them by relative path (`pushd`), prints where it stands, lists it and prints a
mark that carries a per-run random value. A listing counts only when the printed
location is the expected one and its mark arrived, so a link target that prints
a forged mark or location cannot move one directory's links into another's; a
name with `% ( ) ^ & ! "`, a non-ASCII byte, a leading blank or a trailing blank
or dot is never put on such a command line, and whatever a batch does not
answer is listed on its own as before. `dir /s` is not used: it walks into
junctions, a junction back up the tree included. A line
is a link by its shape (`<label> name [target]`); the label is the language's
and decides nothing, so a translated one (`<JONCTION>`) is a link too and only
the three English ones are kept as information. Cloud-sync placeholders
(OneDrive's files on demand) are reparse points too and stay ordinary, because a
placeholder file prints no `<label>` and a placeholder folder no ` [`. The price
is that a placeholder *folder* whose name holds ` [` (`Project [2024]`) is
read as a link and not followed. The census fails closed:

- In a directory whose listing holds at least one link, an entry whose name has
  a non-ASCII byte, a `?` or a `~` followed by a digit (an 8.3 alias) is
  answered as a link and not followed, because the console may print such a
  name as `?` or a look-alike letter and `dir` prints long names only. A
  directory without a link is not affected, so German file names next to one
  link are reported as skipped links.
- Names the listing cannot tell apart are links with no target: ` evil` and
  `evil`, names that differ in case only, names holding ` [` that two lines read
  alike. With more than 32 links that themselves hold ` [` in one directory
  (crafted listings only), every name holding ` [` there reads as a link.
  This holds as well when only one of the pair is a link: a real directory
  `evil` beside a link ` evil` (or the other way round) gives one line that
  both names read, so both are links with no target. The real directory is not
  walked, and the run lists it among the links not followed (`a link on the way
  cannot be read`) rather than dropping it silently. The same goes for names
  that agree up to their first ` [`: a real `a` beside a link `a [b` (listed
  `a [b [target]`), or a real `a [b` beside a link `a`.
- A root on a network or device path (`//host/share`, `//?/C:`, `\\?\…`, or a
  relative one while the process stands on a share) is refused: `cmd.exe`
  cannot start there, so nothing under it is followed and one warning says so
  on stderr. No process is started.
- When `cmd.exe` does not answer, nothing in that directory is followed, and the
  run says so.

Translated labels are tested only on listings written from memory; the Windows
CI job is English, and no real localized `cmd.exe` has run.

**Not covered by this, and not the same problem:** `opts.tag_files`,
`opts.external_repos` and `opts.consumers` name paths *outside* the project on
purpose (a sibling checkout), and a `.docmap.json` in the repository is allowed
to set all three. The engine therefore stats and reads a path the repository
chose, link or not. That wants a rule about who may name a path outside the
root, not a link check; it is an open task, see the vault. `luals` and
`luals_timeout_ms` are **not** repository keys, and neither is `pdf`: a
`.docmap.json` that sets them is ignored with a warning (they belong to whoever
opens the repository), so a checkout cannot start `lua-language-server`, or
`pandoc` on its own Markdown, on the person scanning it.

## Subprocess execution

**Every** external command goes through `vim.system` with an argv array. No
`io.popen`, no `os.execute`, no shell anywhere in the plugin — verifiable with
a grep over `lua/`. (The standalone build under `standalone/` has no editor to
call `vim.system` on and uses `io.popen`: for `git`, for `uname` and, on
Windows, for the `cmd.exe` link listing, whose argument is a fixed string — the
directory is entered with `chdir`, never put on the command line. Its
`vim.fn.system` shim also goes through `io.popen`, which on Windows means
`cmd.exe /c`: every argument is quoted by `standalone/shell_quote.lua`, which
refuses an argument it cannot quote safely instead of passing it on, and the
whole line gets the one extra pair of quotes `cmd /c` strips.)

That is what makes user-supplied revisions safe. `:DocMap diff <ref>`,
`:DocMap impact <ref>` and `:DocMap churn <range>` pass their argument straight
into an argv array, so a value like `; rm -rf ~` is handed to `git` as one
literal argument and rejected by git as a bad revision. There is no shell to
interpret it. (The server route is stricter still, because there the input
arrives over a socket rather than being typed by the person running the
editor.)

`lua-language-server` runs under `:DocMap full`, and also whenever `opts.luals`
is on in your own config (a repository's `.docmap.json` cannot set it), with a timeout
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
