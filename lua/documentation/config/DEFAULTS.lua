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
}

return DEFAULTS
