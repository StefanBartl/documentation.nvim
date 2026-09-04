# Configuration

Every option `setup()` takes, the `.docmap.json` a repository states about
itself, and the two tables people most often reach for -- `checks` and `keys`.

Every option is a plain field on `Documentation.Opts`; the full list with
per-field documentation is in
[`lua/documentation/@types/init.lua`](../lua/documentation/@types/init.lua).

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
[`lua/documentation/config/file.lua`](../lua/documentation/config/file.lua).

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
[`lua/documentation/editor/browse/init.lua`](../lua/documentation/editor/browse/init.lua),
enumerated as `Documentation.Browse.KeyAction` in
[`lua/documentation/editor/browse/@types/init.lua`](../lua/documentation/editor/browse/@types/init.lua):
`move`, `enter`, `up`, `back`, `forward`, `dir_in`, `dir_out`, `depth_inc`,
`depth_dec`, `goto_source`, `quickfix`, `impact`, `open_page`, `commit_diff`,
`pin`, `unpin`, `trail_save`, `trail_load`, `trail_delete`, `filter`, `search`,
`help`, `close`.

The mode-switch keys `1`…`6` are deliberately not rebindable: they are
positional (`3` means "the third list") and are generated from the mode list,
so renumbering them individually would desynchronise them from what the status
line shows.
