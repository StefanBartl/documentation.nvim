---@module 'documentation.editor.generate_all'
--- `M.run(projects, opts)` — full-fidelity `generate()` for a *list* of
--- projects, one real headless Neovim subprocess per project, chained
--- sequentially and never blocking the calling session.
---
--- **Why this exists, found rather than designed in from the start.** A
--- personal config's own `:DocMapAll` used to call `documentation.
--- generate({root=…, luals=true})` in a plain in-process loop across a
--- couple dozen plugins, reasoning that `generate()`'s own internal LuaLS
--- wait (`vim.wait`, which drains the event loop) made the whole call
--- "event-loop-friendly". That covers only the wait *around* the LuaLS
--- subprocess — the scan and render on either side of it are plain
--- synchronous Lua with no yield point at all, and across many whole
--- repositories that froze the calling Neovim session entirely, file
--- explorer included, for the length of the run. Reported exactly that
--- way by someone using the feature, not predicted.
---
--- **Why a subprocess rather than fixing the yield points.** Making
--- `core/scan.lua`'s own walk yield periodically would help the one
--- session running it, at the cost of a real, invasive change to code
--- that has no reason today to know it might be interrupted mid-scan.
--- `vim.system()` sidesteps the question instead: a whole extra Neovim
--- process does the CPU-bound work, so nothing in the *caller's* process
--- can ever be blocked by it, independent of how any given version of
--- the scan pipeline happens to be written.
---
--- **Why this lives in `editor/`, not `core/`.** `vim.system()`, a
--- second headless Neovim process, `nvim` needing to resolve on `PATH` —
--- none of that has anything to do with `core`'s own rule ("the pipeline
--- runs with no editor around it"). This module *is* the editor-side
--- orchestration around several independent `core`-driven scans, one per
--- project, each running inside its own throwaway Neovim.
---
--- **Why no usercmd is registered here.** Unlike `:DocMap`, which is
--- bound to one project resolved from the current buffer
--- (`bindings/usrcmds/init.lua`'s `buffer_root`), "all of my projects" is
--- inherently something only the calling config can know — documentation.
--- nvim has no notion of "your personal plugin list". A consumer's own
--- usercmd (a five-line wrapper) supplies that list and decides how to
--- show progress; this module supplies the orchestration underneath it.
---
--- **Notification-free by design**, matching `core`'s own rule one layer
--- up: this never calls `vim.notify`, `print`, or anything UI-shaped —
--- only the two optional callbacks below. A caller that wants a
--- statusline indicator, a quickfix summary, or nothing at all decides
--- that itself; this module has no opinion.

local M = {}

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

---Build the `-c` argument for one project's headless `generate()` call.
---
---An inline `-c "lua …"` string rather than a bundled script file: the
---whole call is three lines, and inlining it means this feature needs no
---companion file shipped alongside the plugin, found via some
---`debug.getinfo` self-location trick, for a consuming config's `nvim
-----headless` to `luafile`. `%q` is Lua's own quoting for exactly this —
---a string literal safe against quotes, backslashes and newlines in a
---path — so no manual escaping is needed for `root`/`title` however odd
---a path this runs against.
---
---`vim.cmd(...)` rather than `os.exit(...)`: `generate()` runs inside a
---*real* headless Neovim (not a `-l` bare-Lua runner, see `M.run`'s own
---reasoning for why that matters), and quit commands are the normal way
---to end such a session; `os.exit` would skip Neovim's own teardown.
---
---**The branch between `qa!` and `cquit!` is not decoration — found by
---running the failure path for real, not assumed.** The first version
---always called `qa!`, reasoning that the `pcall` around `generate()`
---already turned a scan failure into a caught, reported error rather
---than an uncaught one. True, and irrelevant: `qa!` exits `0`
---unconditionally, so `generate_one`'s own `res.code ~= 0` check —
---the only way a failure is supposed to reach `on_done`'s `ok = false`
---— never fired. A deliberately broken project (a root with no `lua/`
---to scan) reported `ok = true` with the real error sitting unread in
---`stderr`. `:cquit!` (`:cq`) is Vim's own "quit and tell the calling
---process this failed" — a real non-zero exit, still through Neovim's
---normal quit path rather than `os.exit`'s abrupt one.
---@param project Documentation.GenerateAll.Project
---@return string
local function headless_lua_arg(project)
  return (
    "lua local ok, err = pcall(require('documentation').generate, "
    .. "{root=%q, title=%s, luals=true}); "
    .. "if ok then vim.cmd('qa!') else io.stderr:write(tostring(err)); vim.cmd('cquit!') end"
  ):format(project.root, project.title and ("%q"):format(project.title) or "nil")
end

---Spawn one project's headless generation.
---@param project Documentation.GenerateAll.Project
---@param on_done fun(result: Documentation.GenerateAll.Result)
local function generate_one(project, on_done)
  vim.system(
    { "nvim", "--headless", "-c", headless_lua_arg(project), "-c", "qa!" },
    { text = true },
    function(res)
      if res.code ~= 0 then
        on_done({
          project = project,
          ok = false,
          err = (res.stderr and res.stderr ~= "" and res.stderr) or ("exit code " .. res.code),
        })
        return
      end
      on_done({ project = project, ok = true })
    end
  )
end

---Generate every project in `projects`, one real headless Neovim process
---at a time, chained so exactly one is ever running.
---
---Sequential rather than parallel, for the same reason `:MyReposUpdate`-
---shaped batch operations across this ecosystem all are: each run is a
---real CPU-bound process (documentation.nvim's own LuaLS enrichment pass
---included), and running several at once would not finish sooner while
---making the machine genuinely unusable rather than just busy.
---
---One project failing (a scan error, a LuaLS timeout, a non-zero exit)
---does not abort the rest — every project in `projects` gets attempted,
---and `results` (passed to `on_done`) says which ones failed and why.
---
---Returns immediately; `on_done` is the only place completion is
---observable, matching `vim.system()`'s own async shape one layer up.
---@param projects Documentation.GenerateAll.Project[]
---@param opts Documentation.GenerateAll.Opts?
function M.run(projects, opts)
  opts = opts or {}
  local total = #projects
  ---@type Documentation.GenerateAll.Result[]
  local results = {}
  local index = 1

  local function run_next()
    local project = projects[index]
    if not project then
      if opts.on_done then
        opts.on_done(results)
      end
      return
    end

    if opts.on_progress then
      opts.on_progress(index, total, project)
    end

    generate_one(project, function(result)
      results[#results + 1] = result
      index = index + 1
      run_next()
    end)
  end

  run_next()
end

return M
