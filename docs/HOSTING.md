# Hosting the map

Everything this project exposes to a program that *embeds* it rather than
reads it: the capability handshake, the API routes, the one URL parameter the
page reads, and the two-way message channel between the page and whatever
frame it is in.

`docmap-desktop` is the host that exists today, and its own docs describe its
half. This file describes **this** half — the surfaces the engine and the
generated page publish, and the decisions behind them, because those are what
a second host would have to hold to.

## Table of content

- [Why there is a host surface at all](#why-there-is-a-host-surface-at-all)
- [`--capabilities`, the handshake](#--capabilities-the-handshake)
- [`--api=<route>`, one question at a time](#--apiroute-one-question-at-a-time)
- [`?theme=`, the one URL parameter](#theme-the-one-url-parameter)
- [The page talks to its host](#the-page-talks-to-its-host)
- [The host asks the page](#the-host-asks-the-page)
- [What a host must not assume](#what-a-host-must-not-assume)

---

## Why there is a host surface at all

The generated page is self-contained: no CDN, no build step, no server. Open
`docs/map/index.html` in any browser and everything structural works.

Three things do not, and each of them is why one of the surfaces below
exists.

- **Some panels need data the artifact does not carry** — the Telemetry
  join, the Loaded snapshots, the checklist, the commit list. Those come from
  `/api/*`, which needs something on the other end. Inside Neovim that is
  `:DocMap serve`; outside it, a host forwards to `--api=<route>`.
- **A host has a window, and the page is inside it.** It wants the header's
  counts for its own status bar, and the diagram for a Save dialog. Reading
  the DOM across a frame boundary is not available to it and would be the
  wrong contract anyway.
- **The theme has to be right before the first paint**, which rules out
  anything that arrives as a message.

**The rule all three follow: the page answers questions and takes no
instructions.** Nothing a host sends changes what the page does — only what
it reports back. That is what makes embedding it safe in both directions, and
it is a property to keep rather than a coincidence.

---

## `--capabilities`, the handshake

```bash
docmap --capabilities
```

Prints one JSON object and exits 0. It is what a host asks before trusting a
binary with anything.

| Field | What it says |
|---|---|
| `capabilities` | Coarse feature names this build has — `api`, `languages`, `schema`. A host that wants one thing can test for it without parsing the rest. |
| `schema` | The artifact schema this build writes. The release is rolling (`standalone-latest`), so there is no version number to report that would not be fiction; the schema is what actually decides whether two artifacts are comparable, and it is bumped deliberately. |
| `build` | Commit, commit date, and whether the tree it was built from was clean. **Present only in a bundled binary** — `scripts/package.lua` writes it at bundle time and never into the source tree, so a run from a checkout answers `null` rather than claiming a provenance it does not have. |
| `routes` | Every `/api/*` route name this build answers, read from `core/api.routes`. A route added there is advertised here without this being told. |
| `languages` | One entry per backend: `name`, `grammar`, `grammar_loaded`, `calls`. See [`LANGUAGES.md`](LANGUAGES.md). |

**`languages` is what lets a host stop guessing why a map came back thin.**
Pointed at a mostly-Python repository, an engine without the Python grammar
produces a valid, nearly empty map. A host that reads this list can say so
*before* generating, rather than presenting the empty result as a success.

**`grammar_loaded` is three-valued and must stay that way**: `true`, `false`
(wants a grammar, has none — a complete module tree and no function-level
data) and `null` (needs no parser, which is full fidelity). A host that
flattens the last two reports a healthy backend as broken.

### Why the flag sits in root-argument position

`--capabilities` is the *first* argument, where a path would go, and that is
deliberate. An older binary that has never heard of it rejects a leading `-`
immediately, before doing any work. One that arrives as an ordinary flag
after a root would be ignored by an old build — which would then **generate a
map**, writing into the caller's repository and exiting 0 with output that is
not JSON.

That is measured rather than imagined: it is what the shipped binary did the
first time it was handed `--api=telemetry`, and a host polling a panel would
have rewritten a user's `docs/map` on every fetch.

So "this engine has no capabilities" and "this engine is too old" are a
single observation, which is what a host actually needs.

---

## `--api=<route>`, one question at a time

```bash
docmap /path/to/repo --api=telemetry
docmap /path/to/repo --api=commits --snapshot=50
```

Answers one of the generated page's own `/api/*` routes and prints its JSON,
instead of generating anything. Today's routes:

| Route | Answers |
|---|---|
| `telemetry` | The telemetry join for this repository. |
| `telemetry/snapshots` | Which named telemetry snapshots exist. |
| `loaded` | The loaded-versus-declared comparison. |
| `loaded/snapshots` | Which named loaded snapshots exist. |
| `checklist` | The hand-verified ledger and what has drifted. |
| `commits` | Recent commits, for the History tab. |
| `commit/<sha>` | One commit's diff. Not in `routes` because its name carries the sha. |

**One route per invocation, deliberately.** A request is one question, and a
process that answered several would need a protocol to say which answer is
which. `stdout` carries exactly the JSON, so a caller does not have to find
where it starts.

`--snapshot=<value>` carries the single optional parameter, whatever the
chosen route makes of it — a snapshot name for `telemetry`/`loaded`, a commit
count for `commits`, unused otherwise. One flag rather than one per route,
because exactly one route reads it at a time.

**The join logic stays in Lua.** `docmap-desktop` runs a small HTTP server
that forwards `/api/*` here; its Rust side is transport only. `core/api.lua`
owns the answers and shares them with `editor/serve.lua`'s in-editor server,
so the two hosts cannot disagree.

---

## `?theme=`, the one URL parameter

```
index.html?theme=dark
index.html?theme=light
```

Three states: `light` and `dark` decide, and anything else — including no
parameter — follows the OS.

Applied in `<head>`, before any element exists, because a theme applied after
first paint is a flash of the wrong one.

**A query parameter rather than a message, for two reasons that both matter.**
A message cannot arrive early enough. And a page that executes instructions
from whatever embeds it is a different security posture from one that reads
its own URL — the same line the message channel below draws, drawn here as
well.

It is also a feature outside any host: it is a thing a person can type into a
browser.

---

## The page talks to its host

The page volunteers two messages, both `postMessage` to `window.parent`, both
tagged `source: "docmap"`. A page with no listening host is not an error and
not a special case — nothing happens.

**Where the reader is**, on every navigation:

```js
{ source: "docmap", tab: "hierarchy", atool: null, view: "calls" }
```

Coarse on purpose. `tab`, the Analysis sub-tool, and the Hierarchy view —
not scroll position, not selection. It is sent only when one of the three
changes, so a host is not woken by every interaction. This is what lets a
host put a note over a panel it knows something about, and what lets it
return the reader to the same panel after a reload.

**A request to open a file**, from the map's own right-click menu:

```js
{ source: "docmap", kind: "open-file", path: "lua/x/init.lua", line: 42 }
```

The path is repository-relative, because that is what the artifact stores.
`line` is `null` for a node with no function behind the click. **The page
does not open anything** — it cannot, and should not be able to. It says what
was asked for; a host that has an editor decides what to do about it, and a
host that has none ignores it.

---

## The host asks the page

The one inbound direction, and the one with a security posture written into
it. A message is read only if it carries `source: "docmap-host"`, and only a
fixed vocabulary is understood:

| `ask` | Reply |
|---|---|
| `"export-svg"` | `{ok: true, kind: "svg", name, data}` — or `{ok: false, reason: "no-diagram"}` when nothing is drawn. |
| `"counts"` | `{ok: true, kind: "counts", modules, namespaces, files, errors, warnings}` — what the header shows. |

Every reply carries `source: "docmap"` and `replyTo: <the message's id>`.

Four consequences, stated so a later verb has to argue against them rather
than quietly break them:

- **A malicious embedder gains nothing it did not have.** Everything
  answerable here is already rendered on the page it embedded.
- **A fixed vocabulary, not a dispatch table keyed by whatever arrived.** An
  unknown verb is answered with silence, never with an error echoing the
  input back.
- **Replies go to the asker's own origin, never `"*"`.** An `opener` that is
  not the embedder learns nothing by listening. `ev.origin` is `"null"` for a
  sandboxed or `file:` embedder and `postMessage` rejects that as a target —
  those hosts get no answer, which is the correct outcome rather than a
  broadcast.
- **`counts` cannot drift from the header beside it.** The three structural
  counts come from the artifact and the two finding counts from the same
  array the header reads, so this needs no new payload.

**There was a third question, `state`, and it was removed rather than kept.**
It answered with the same coarse context the page already volunteers, on the
reasoning that asking is cheaper than waiting. A round later nothing had ever
asked it: the one host there is reads the volunteered message, because by the
time it has a reason to care the message has already arrived. A question
nobody asks is not free — it is a branch in a published channel that every
generated artifact carries, and that every future change has to keep
answering correctly.

---

## What a host must not assume

- **That the map on disk was written by the engine now on `PATH`.** A
  generated map is a snapshot of the engine that wrote it; page-side features
  arrive by regenerating, not by updating whatever reads the map. This is the
  single fact that makes the app's behaviour predictable rather than
  mysterious — see [`USAGE.md`'s first section in
  `docmap-desktop`](https://github.com/StefanBartl/docmap-desktop/blob/main/docs/USAGE.md).
- **That an empty panel means an empty project.** Several panels are empty
  for reasons that belong to the build, not the repository — no grammar, no
  call extraction for this language, no telemetry collected. The handshake is
  what lets a host tell those apart, and a host that can tell them apart
  should say which.
- **That `build` is present.** It is absent for an engine run from a source
  checkout, and absent is a real answer.
- **That the schema will not change.** Compare `schema` rather than assuming;
  it is bumped when the artifact gains a field that changes what an older
  reader would conclude.
