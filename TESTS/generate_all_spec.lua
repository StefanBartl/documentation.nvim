-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/generate_all_spec.lua — documentation.editor.generate_all
--
-- Real subprocesses, not mocked: `vim.system()` spawning `nvim --headless`
-- is the entire point of this module (see its own header for why), so a
-- test that stubs `vim.system` would prove nothing about the one property
-- that matters — that a real headless Neovim, started fresh, can `require`
-- this plugin and write a real map. Two headless subprocess spawns, one
-- succeeding and one deliberately failing; both bounded by `vim.wait`
-- rather than left to hang the suite if something regresses.

return function(H)
  local eq, ok = H.eq, H.ok

  local ga = require("documentation.editor.generate_all")
  local repo_root = (debug.getinfo(1, "S").source:sub(2):match("(.*)[/\\]TESTS[/\\]")) or "."

  -- ------------------------------------------------------- a real project
  local fixture = repo_root .. "/.deps/generate-all-fixture"
  os.execute(('rm -rf "%s"'):format(fixture))
  vim.fn.mkdir(fixture .. "/lua/gaspec", "p")
  local fd = assert(io.open(fixture .. "/lua/gaspec/init.lua", "w"))
  fd:write(
    "---@module 'gaspec'\n--- A fixture module for generate_all_spec.\nlocal M = {}\n\n---Adds.\n---@param a number\n---@param b number\n---@return number\nfunction M.add(a, b)\n  return a + b\nend\n\nreturn M\n"
  )
  fd:close()

  do
    local done, results = false, nil
    local progress_calls = {}

    ga.run({ { root = fixture, title = "gaspec" } }, {
      on_progress = function(index, total, project)
        progress_calls[#progress_calls + 1] = { index = index, total = total, root = project.root }
      end,
      on_done = function(r)
        done = true
        results = r
      end,
    })

    -- A real headless Neovim, real LuaLS-free generate() (luals defaults
    -- true in the module, but no LuaLS binary needing to be found this
    -- fixture only needs the base scan) — generously bounded rather than
    -- tuned tight, since CI hardware varies and this spec's own value is
    -- in proving completion happens at all, not in timing it.
    vim.wait(20000, function()
      return done
    end, 100)

    ok(done, "generate_all: on_done fires for a single real project")
    ok(type(results) == "table" and #results == 1, "generate_all: one result per project")
    if results and results[1] then
      ok(
        results[1].ok == true,
        "generate_all: a real, valid project succeeds — " .. tostring(results[1].err)
      )
    end

    eq(#progress_calls, 1, "generate_all: on_progress fires once, before the one project")
    if progress_calls[1] then
      eq(progress_calls[1].index, 1, "generate_all: on_progress reports 1-based index")
      eq(progress_calls[1].total, 1, "generate_all: on_progress reports the total")
    end

    -- The actual point of the feature: a real map, written by a subprocess
    -- this test's own process never blocked on except via vim.wait's poll.
    local map_path = fixture .. "/docs/map/module_map.json"
    ok(
      (vim.uv or vim.loop).fs_stat(map_path) ~= nil,
      "generate_all: the subprocess wrote a real module_map.json"
    )
    if (vim.uv or vim.loop).fs_stat(map_path) then
      local mf = assert(io.open(map_path, "r"))
      local body = mf:read("*a")
      mf:close()
      ok(
        body:find('"gaspec"', 1, true) ~= nil,
        "generate_all: the written map names the real module it scanned"
      )
      ok(
        body:find("M.add", 1, true) ~= nil,
        "generate_all: the written map found the real function"
      )
    end
  end

  -- --------------------------------------------------- a project that fails
  -- A root with no `lua/` to scan — generate() raises, the subprocess exits
  -- non-zero, and that has to surface as ok=false with a real message
  -- rather than being swallowed.
  do
    local broken = repo_root .. "/.deps/generate-all-fixture-broken"
    os.execute(('rm -rf "%s"'):format(broken))
    vim.fn.mkdir(broken, "p")

    local done, results = false, nil
    ga.run({ { root = broken, title = "broken" } }, {
      on_done = function(r)
        done = true
        results = r
      end,
    })
    vim.wait(20000, function()
      return done
    end, 100)

    ok(done, "generate_all: on_done fires even when the project fails")
    ok(
      results and results[1] and results[1].ok == false,
      "generate_all: a project with nothing to scan reports ok=false"
    )
    ok(
      results and results[1] and type(results[1].err) == "string" and #results[1].err > 0,
      "generate_all: the failure carries a real, non-empty message"
    )
  end

  -- ------------------------------------------------- multiple, sequential
  -- One good project and one broken one in the same list, run twice each
  -- across two lists to see both orders. Not a timing assertion (real
  -- subprocess spawn time varies too much to bound tightly) -- just that
  -- every project in a list actually runs and reports back, in the order
  -- given, whether or not an earlier one failed.
  local broken = repo_root .. "/.deps/generate-all-fixture-broken"
  do
    local progress_order, done, results = {}, false, nil
    ga.run({
      { root = fixture, title = "gaspec" },
      { root = broken, title = "broken" },
    }, {
      on_progress = function(index, _, project)
        progress_order[#progress_order + 1] = { index = index, title = project.title }
      end,
      on_done = function(r)
        done, results = true, r
      end,
    })
    vim.wait(30000, function()
      return done
    end, 100)

    ok(done, "generate_all: on_done fires once both projects finish")
    eq(#results, 2, "generate_all: one result per project, in order")
    if results[1] and results[2] then
      eq(results[1].project.title, "gaspec", "generate_all: result 1 is the first project given")
      ok(results[1].ok == true, "generate_all: result 1 (the valid project) succeeded")
      eq(results[2].project.title, "broken", "generate_all: result 2 is the second project given")
      ok(
        results[2].ok == false,
        "generate_all: result 2 (the broken project) failed, not aborted the batch"
      )
    end
    eq(
      #progress_order,
      2,
      "generate_all: on_progress fires once per project, not aborted after the failure"
    )
    if progress_order[1] and progress_order[2] then
      eq(progress_order[1].index, 1, "generate_all: progress index 1 for the first project")
      eq(
        progress_order[2].index,
        2,
        "generate_all: progress index 2 for the second, run after the first finished"
      )
    end
  end

  -- --------------------------------------------------- opts.luals = false
  -- The fast path (`:DocMapAll`'s own default, 2026-08-15) — same fixture,
  -- explicit `luals = false` threaded down to `DOCMAP_GEN_LUALS=0` in the
  -- subprocess env. Proves the wiring reaches the subprocess and a real
  -- map still comes out the other end; not a claim about LuaLS itself
  -- being skipped internally (`generate_one_headless.lua`'s own env-var
  -- read already covers that in isolation).
  vim.fn.mkdir(fixture .. "/lua/gaspec", "p")
  local fd2 = assert(io.open(fixture .. "/lua/gaspec/init.lua", "w"))
  fd2:write(
    "---@module 'gaspec'\n--- A fixture module for generate_all_spec.\nlocal M = {}\n\n---Adds.\n---@param a number\n---@param b number\n---@return number\nfunction M.add(a, b)\n  return a + b\nend\n\nreturn M\n"
  )
  fd2:close()

  do
    local done, results = false, nil
    ga.run({ { root = fixture, title = "gaspec" } }, {
      luals = false,
      on_done = function(r)
        done, results = true, r
      end,
    })
    vim.wait(20000, function()
      return done
    end, 100)

    ok(done, "generate_all: opts.luals=false still fires on_done")
    ok(
      results and results[1] and results[1].ok == true,
      "generate_all: opts.luals=false still succeeds -- "
        .. tostring(results and results[1] and results[1].err)
    )
  end

  os.execute(('rm -rf "%s" "%s"'):format(fixture, broken))
end
