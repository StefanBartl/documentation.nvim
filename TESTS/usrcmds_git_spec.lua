-- TESTS/usrcmds_git_spec.lua — the `:DocMap` subcommands that shell out to
-- `git`: `churn`, `diff`, `impact`, `checklist`.
--
-- Real subprocesses against a real, disposable fixture repository —
-- `git init`, real commits, pinned dates — the same posture `api_spec.lua`
-- and `mcp_spec.lua`'s own `docmap_checklist` block already take and state
-- why: a test that stubs `vim.system` would prove the wiring reads the stub
-- correctly and nothing about whether the real command, the real `--`
-- pathspec exclusion or the real async callback chain actually works.
--
-- What this closes: `core/churn.lua`'s ranking, `core/diff.lua`'s compare/
-- render and `core/checklist.lua`'s status verdicts already have thorough
-- literal-data coverage in docmap_spec.lua/checklist_spec.lua. Nothing at
-- all exercised the command layer one level up — the git invocation itself,
-- its error/timeout/empty-result branches, and the notify/quickfix
-- formatting — despite each of those having real, previously untested
-- branching logic.
--
-- Each `M.run` is asynchronous (`vim.system` with a callback, not `:wait()`
-- — see `bindings/progress.lua`'s header for why), so every case below
-- pumps the loop with `vim.wait` until the fake `notify` records a call —
-- every branch in all four commands ends in exactly one `ctx.notify.info`
-- or `ctx.notify.warn`, which makes that the one reliable completion signal.

return function(H)
  local eq, ok = H.eq, H.ok
  local docmap = require("documentation")

  ---@param gr string
  ---@param args string[]
  ---@param env table<string, string>?
  local function git(gr, args, env)
    local cmd = { "git", "-c", "user.name=docmap-spec", "-c", "user.email=docmap-spec@test" }
    vim.list_extend(cmd, args)
    local opts = { cwd = gr, text = true }
    if env then
      opts.env = env
    end
    return vim.system(cmd, opts):wait()
  end

  ---@param gr string
  ---@param date string ISO date, used for both author and committer date so
  ---"is this stale" is a fact about the fixture, not about today.
  local function commit(gr, date)
    local add = git(gr, { "add", "-A" })
    ok(add.code == 0, "git fixture: add: " .. tostring(add.stderr))
    local c = git(
      gr,
      { "commit", "-m", "c" },
      { GIT_AUTHOR_DATE = date, GIT_COMMITTER_DATE = date }
    )
    ok(c.code == 0, "git fixture: commit: " .. tostring(c.stderr))
  end

  ---@param root string
  ---@param rel string
  ---@param lines string[]
  local function dwrite(root, rel, lines)
    local abs = root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "git fixture: must be writable")
    fd:write(table.concat(lines, "\n"))
    fd:close()
    return abs
  end

  ---@return string? sha
  local function head_sha(gr)
    local r = git(gr, { "rev-parse", "HEAD" })
    if r.code ~= 0 then
      return nil
    end
    return vim.trim(r.stdout or "")
  end

  ---@param handle Documentation.Handle
  ---@return Documentation.Bindings.Ctx ctx
  ---@return table calls {info=string[], warn=string[]}
  local function fake_ctx(handle)
    local calls = { info = {}, warn = {} }
    return {
      cfg = handle.cfg,
      handle = handle,
      command_name = "DocMap",
      notify = {
        info = function(msg)
          calls.info[#calls.info + 1] = msg
        end,
        warn = function(msg)
          calls.warn[#calls.warn + 1] = msg
        end,
      },
      find_node = function(ir2, name, lua_root)
        return require("documentation.core.find").node(ir2, name, lua_root)
      end,
      open_map = function()
        return true
      end,
    },
      calls
  end

  ---Pumps the loop until the fake ctx's notify fired at least once, or the
  ---timeout elapses -- every branch of every command tested here ends in
  ---exactly one info/warn call.
  ---@param calls table
  ---@param timeout integer?
  local function wait_for_notify(calls, timeout)
    return vim.wait(timeout or 15000, function()
      return #calls.info + #calls.warn > 0
    end, 20)
  end

  local function clear_qf()
    vim.fn.setqflist({}, "r")
  end

  local function qf()
    return vim.fn.getqflist({ items = 0, title = 0 })
  end

  -- Skip the whole file, gracefully, on a machine with no `git` — every
  -- command's own real degrade path (a plain `M.run` against a non-repo
  -- root) is not what is under test here; the fixture itself needs git.
  local probe_root = H.tmpfile("_usrcmds_git_probe")
  vim.fn.mkdir(probe_root, "p")
  local have_git = git(probe_root, { "init", "-q" }).code == 0
  if not have_git then
    ok(true, "usrcmds git commands: git unavailable on this machine, spec skipped")
    return
  end

  -- ================================================================ churn
  do
    local churn = require("documentation.bindings.usrcmds.churn")

    local gr = H.tmpfile("_usrcmds_churn")
    vim.fn.mkdir(gr, "p")
    ok(git(gr, { "init", "-q" }).code == 0, "churn fixture: git init")

    dwrite(gr, "lua/demo/a/init.lua", {
      "---@module 'demo.a'",
      "--- A.",
      "local M = {}",
      "---Go.",
      "function M.go() end",
      "return M",
    })
    commit(gr, "2024-01-01T00:00:00")

    dwrite(gr, "lua/demo/a/init.lua", {
      "---@module 'demo.a'",
      "--- A, edited.",
      "local M = {}",
      "---Go.",
      "function M.go() end",
      "---Stop.",
      "function M.stop() end",
      "return M",
    })
    commit(gr, "2024-02-01T00:00:00")

    local handle = docmap.install({ root = gr, source = "lua/demo", lua_root = "lua" })

    do
      -- An empty range (HEAD..HEAD) is a real, deterministic way to force
      -- "zero commits examined" without needing an empty repository.
      clear_qf()
      local ctx, calls = fake_ctx(handle)
      churn.run(ctx, "HEAD..HEAD")
      ok(wait_for_notify(calls), "churn: HEAD..HEAD settles")
      eq(#calls.info, 1, "churn: zero commits in range is one info message, not a warning")
      ok(calls.info[1]:find("No commits", 1, true) ~= nil, "churn: ...saying so")
      eq(#qf().items, 0, "churn: ...and no quickfix list")
    end

    do
      clear_qf()
      local ctx, calls = fake_ctx(handle)
      churn.run(ctx, "")
      ok(wait_for_notify(calls), "churn: full history settles")
      eq(#calls.info, 1, "churn: two real commits touching a scanned module is one info message")
      ok(
        calls.info[1]:find("demo.a", 1, true) ~= nil,
        "churn: the only touched module is named as hottest"
      )
      local q = qf()
      eq(#q.items, 1, "churn: one quickfix row for the one ranked module")
      ok(
        q.items[1].text:find("a", 1, true) ~= nil,
        "churn: the row points at the module's own source"
      )
    end

    do
      -- A bad range: git itself rejects it, so this is the real non-zero-exit
      -- branch, not a simulated one.
      clear_qf()
      local ctx, calls = fake_ctx(handle)
      churn.run(ctx, "not-a-real-ref..HEAD")
      ok(wait_for_notify(calls), "churn: a bad range settles")
      eq(#calls.warn, 1, "churn: an invalid rev-range warns, not crashes")
      ok(calls.warn[1]:find("git log failed", 1, true) ~= nil, "churn: ...naming git's own failure")
    end

    docmap.uninstall(handle)
  end

  -- ================================================================= diff
  do
    local diff_cmd = require("documentation.bindings.usrcmds.diff")

    local gr = H.tmpfile("_usrcmds_diff")
    vim.fn.mkdir(gr, "p")
    ok(git(gr, { "init", "-q" }).code == 0, "diff fixture: git init")

    dwrite(gr, "lua/demo/a/init.lua", {
      "---@module 'demo.a'",
      "--- A.",
      "local M = {}",
      "---Go.",
      "function M.go() end",
      "return M",
    })
    commit(gr, "2024-01-01T00:00:00")

    -- A real committed artifact at this point in history: one module, one
    -- function.
    docmap.generate({ root = gr, source = "lua/demo", lua_root = "lua" })
    commit(gr, "2024-01-02T00:00:00")
    local old_sha = head_sha(gr)
    ok(old_sha ~= nil, "diff fixture: captured the map's own commit")

    -- Now the tree moves on: a second function, uncommitted -- the live IR
    -- diff.lua compares the old artifact against is `ctx.handle.ir()`, which
    -- reflects the working tree, not HEAD.
    dwrite(gr, "lua/demo/a/init.lua", {
      "---@module 'demo.a'",
      "--- A, edited.",
      "local M = {}",
      "---Go.",
      "function M.go() end",
      "---Stop.",
      "function M.stop() end",
      "return M",
    })

    local handle = docmap.install({ root = gr, source = "lua/demo", lua_root = "lua" })

    do
      local ctx, calls = fake_ctx(handle)
      diff_cmd.run(ctx, "not-a-real-ref")
      ok(wait_for_notify(calls, 15000), "diff: a bad ref settles")
      eq(#calls.warn, 1, "diff: an unreadable ref warns")
      ok(calls.warn[1]:find("Cannot read", 1, true) ~= nil, "diff: ...naming the read failure")
    end

    do
      local ctx, calls = fake_ctx(handle)
      ---@cast old_sha string
      diff_cmd.run(ctx, old_sha)
      ok(wait_for_notify(calls, 15000), "diff: a real ref settles")
      eq(#calls.info, 1, "diff: comparing against the real committed map is one info message")
      ok(calls.info[1]:find("1 function", 1, true) ~= nil, "diff: the new function is counted")

      local found
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(b) and vim.bo[b].filetype == "markdown" then
          local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
          if table.concat(lines, "\n"):find("M.stop", 1, true) then
            found = b
          end
        end
      end
      ok(found ~= nil, "diff: the rendered buffer names the added function")
    end

    docmap.uninstall(handle)
  end

  -- =============================================================== impact
  do
    local impact_cmd = require("documentation.bindings.usrcmds.impact")

    local gr = H.tmpfile("_usrcmds_impact")
    vim.fn.mkdir(gr, "p")
    ok(git(gr, { "init", "-q" }).code == 0, "impact fixture: git init")

    dwrite(gr, "lua/demo/a/init.lua", {
      "---@module 'demo.a'",
      "--- A.",
      "local M = {}",
      "---Go.",
      "function M.go() end",
      "return M",
    })
    commit(gr, "2024-01-01T00:00:00")

    local handle = docmap.install({ root = gr, source = "lua/demo", lua_root = "lua" })

    do
      -- No uncommitted changes yet: HEAD to working tree is empty.
      local ctx, calls = fake_ctx(handle)
      impact_cmd.run(ctx, "HEAD")
      ok(wait_for_notify(calls, 15000), "impact: no changes settles")
      eq(#calls.info, 1, "impact: nothing changed since HEAD is one info message")
      ok(calls.info[1]:find("Nothing changed", 1, true) ~= nil, "impact: ...saying so")
    end

    do
      local ctx, calls = fake_ctx(handle)
      impact_cmd.run(ctx, "not-a-real-ref")
      ok(wait_for_notify(calls, 15000), "impact: a bad ref settles")
      eq(#calls.warn, 1, "impact: an invalid ref warns")
      ok(calls.warn[1]:find("Cannot diff", 1, true) ~= nil, "impact: ...naming the diff failure")
    end

    do
      -- A real, uncommitted addition, then a rescan so the live IR the
      -- command reads actually reflects it.
      dwrite(gr, "lua/demo/a/init.lua", {
        "---@module 'demo.a'",
        "--- A, edited.",
        "local M = {}",
        "---Go.",
        "function M.go() end",
        "---Stop.",
        "function M.stop() end",
        "return M",
      })
      handle.rescan()

      clear_qf()
      local ctx, calls = fake_ctx(handle)
      impact_cmd.run(ctx, "HEAD")
      ok(wait_for_notify(calls, 15000), "impact: a real uncommitted change settles")
      eq(#calls.info, 1, "impact: a touched function is one info message")
      ok(
        calls.info[1]:find("function(s) touched", 1, true) ~= nil,
        "impact: ...naming what was touched"
      )
      ok(#qf().items > 0, "impact: and a quickfix row for it")
    end

    docmap.uninstall(handle)
  end

  -- ============================================================ checklist
  do
    local checklist_cmd = require("documentation.bindings.usrcmds.checklist")

    local gr = H.tmpfile("_usrcmds_checklist")
    vim.fn.mkdir(gr, "p")
    ok(git(gr, { "init", "-q" }).code == 0, "checklist fixture: git init")

    dwrite(gr, "lua/demo/a.lua", { "---@module 'demo.a'", "-- a" })
    commit(gr, "2019-06-01T00:00:00")

    dwrite(gr, "docs/CHECKLIST/x.md", {
      "## S",
      "- [x] cited and later stale",
      "      <!-- @ref lua/demo/a.lua -->",
      "      <!-- @verified 2020-01-01 -->",
      "- [ ] never verified",
      "      <!-- @ref lua/demo/a.lua -->",
      "- [ ] cites nothing",
    })
    commit(gr, "2020-01-01T00:00:00")

    -- Touches lua/demo/a.lua again, after the @verified date above: the one
    -- commit that must make the first item stale.
    dwrite(gr, "lua/demo/a.lua", { "---@module 'demo.a'", "-- a, edited" })
    commit(gr, "2025-01-01T00:00:00")

    local handle = docmap.install({ root = gr, source = "lua/demo", lua_root = "lua" })

    do
      clear_qf()
      local ctx, calls = fake_ctx(handle)
      checklist_cmd.run(ctx, "")
      ok(wait_for_notify(calls, 15000), "checklist: default filter settles")
      eq(#calls.info, 1, "checklist: one summary message")
      ok(calls.info[1]:find("1 stale", 1, true) ~= nil, "checklist: the stale item is counted")
      ok(
        calls.info[1]:find("1 unverified", 1, true) ~= nil,
        "checklist: the unverified item is counted"
      )
      local q = qf()
      eq(#q.items, 2, "checklist: bare form lists only stale+unverified, not the uncited item")

      local stale_row
      for _, item in ipairs(q.items) do
        if item.text:find("^STALE") then
          stale_row = item
        end
      end
      ok(stale_row ~= nil, "checklist: a STALE row exists")
      eq(stale_row.type, "E", "checklist: stale is an Error-severity row")
      local stale_name = vim.api.nvim_buf_get_name(stale_row.bufnr)
      ok(
        stale_name:find("lua/demo/a.lua", 1, true) ~= nil
          or stale_name:find("lua\\demo\\a.lua", 1, true) ~= nil,
        "checklist: a cited item's quickfix target is the CITED source, not the ledger line"
      )
    end

    do
      clear_qf()
      local ctx, calls = fake_ctx(handle)
      checklist_cmd.run(ctx, "all")
      ok(wait_for_notify(calls, 15000), "checklist: 'all' filter settles")
      local q = qf()
      eq(#q.items, 3, "checklist: 'all' lists every item, including the uncited one")

      local uncited_row
      for _, item in ipairs(q.items) do
        if item.text:find("^UNCITED") then
          uncited_row = item
        end
      end
      ok(uncited_row ~= nil, "checklist: an UNCITED row exists under 'all'")
      eq(uncited_row.type, "W", "checklist: uncited is a Warning-severity row, not an Error")
      ok(
        vim.api.nvim_buf_get_name(uncited_row.bufnr):find("x.md", 1, true) ~= nil,
        "checklist: an item with no @ref falls back to the ledger file itself"
      )
    end

    docmap.uninstall(handle)
  end
end
