---@meta
---@module 'documentation.editor.@types'
--- Types for `documentation.editor.generate_all` — the only file in this
--- directory (outside `browse/`, which keeps its own `@types/`) with real
--- classes worth factoring out.

---One entry in the `projects` list `M.run` accepts.
---@class Documentation.GenerateAll.Project
---@field root string Absolute path to the project's repository root.
---@field title string? Passed through to `generate()`'s own `opts.title`.

---One entry in the `results` list `M.run`'s `on_done` receives, in the
---same order `projects` was given.
---@class Documentation.GenerateAll.Result
---@field project Documentation.GenerateAll.Project
---@field ok boolean
---@field err string? Set when `ok` is false — subprocess stderr, or its
---exit code when stderr was empty.

---@class Documentation.GenerateAll.Opts
---@field on_progress fun(index: integer, total: integer, project: Documentation.GenerateAll.Project)? Called just before each project starts.
---@field on_done fun(results: Documentation.GenerateAll.Result[])? Called once, after every project has finished.
---@field luals? boolean LuaLS enrichment for every project in this run -- forwarded verbatim to each subprocess's own `generate()` call. Default true (unset means true), matching this module's own behavior before this option existed; `:DocMapAll`'s own default flips this per-call (see `bindings/usrcmds/generate_all.lua`), not this module.

return {}
