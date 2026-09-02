---@module 'documentation.config.DEFAULTS'
--- The plugin-side defaults, as data.
---
--- Split out of `build()` so "what does this plugin default to" is answerable
--- by reading one table rather than by reading a function and mentally
--- executing it. Nothing here is derived, conditional or computed — that is
--- the whole point of the split, and the reason three fields are deliberately
--- **absent**:
---
---   `root`    there is no default repository. Every entry point supplies it
---             (a lazy spec's `opts.root`, `install()`, or the cwd), and a
---             table that invented one would be stating a guess as a default.
---   `source`  derived from `root` by `config.detect_source`.
---   `title`   derived from `root`'s basename.
---
--- A user's `opts` is merged over this by `documentation.config.build`; see
--- there for the merge rule.

--- Not annotated `Documentation.Opts`: that class requires `root`, and this is
--- deliberately a partial table. Typing it as the full class would either need
--- a fake `root` or a `---@diagnostic disable`, and both are worse than an
--- honest partial.
---@type table<string, any>
local DEFAULTS = {
  lua_root = "lua",
  types_dir = "@types",
  out_dir = "docs/map",
  branch = "main",
  tests_dir = "TESTS",
  command_name = "DocMap",
  browse_command_name = "DocBrowse",
  progress_style = "auto",
  -- Register a position preview with hover.nvim, so resting the cursor on a
  -- dotted module name says what that module is -- read out of the map this
  -- plugin writes, with no scan at runtime. A no-op without hover.nvim.
  hover = true,
  -- Ceiling for a `git log` over the repository's full history, in ms —
  -- `:DocMap churn`, the checklist's history pass and the MCP tool all bound
  -- themselves by it. Two minutes is generous for most repositories and tight
  -- for a very old or very large one, which is the whole reason it is a key
  -- and not a constant repeated three times.
  git_log_timeout_ms = 120000,
  -- How long a telemetry read stays cached, in ms. The number it shows is a
  -- snapshot of a file another process appends to all day: no TTL makes it
  -- live, and a longer one only makes it wrong for longer. Shorten it while
  -- watching a namespace fill up.
  telemetry_ttl_ms = 2000,
}

return DEFAULTS
