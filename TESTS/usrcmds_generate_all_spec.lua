-- TESTS/usrcmds_generate_all_spec.lua — bindings.usrcmds.generate_all and
-- the opts.generate_all wiring in bindings.usrcmds itself.
--
-- The subprocess mechanism (documentation.editor.generate_all.run() —
-- real headless Neovim per project) already has its own thorough,
-- real-subprocess coverage in generate_all_spec.lua. What THIS layer adds
-- is thin glue: reading opts.generate_all, deciding whether :DocMapAll
-- gets registered at all, and (for autoload) which projects are actually
-- missing a map. Stubbing documentation.generate_all.run rather than
-- spawning real subprocesses again tests exactly that glue, not something
-- already proven elsewhere.

return function(H)
  local eq, ok = H.eq, H.ok

  local repo_root = (debug.getinfo(1, "S").source:sub(2):match("(.*)[/\\]TESTS[/\\]")) or "."
  local usrcmds_generate_all = require("documentation.bindings.usrcmds.generate_all")
  local docmap = require("documentation")

  ---A minimal fake ctx/notify — `generate_all.lua`'s `M.run` only ever
  ---reads `ctx.generate_all` and `ctx.notify`, never `ctx.cfg`/`ctx.handle`.
  ---@return table ctx
  ---@return table calls  {info=string[], warn=string[], error=string[]}
  local function fake_ctx(generate_all_cfg)
    local calls = { info = {}, warn = {}, error = {} }
    return {
      generate_all = generate_all_cfg,
      notify = {
        info = function(msg)
          calls.info[#calls.info + 1] = msg
        end,
        warn = function(msg)
          calls.warn[#calls.warn + 1] = msg
        end,
        error = function(msg)
          calls.error[#calls.error + 1] = msg
        end,
      },
    },
      calls
  end

  -- ------------------------------------------------- no config -> warns
  do
    local ctx, calls = fake_ctx(nil)
    usrcmds_generate_all.run(ctx)
    eq(#calls.warn, 1, "M.run: no opts.generate_all at all -- one warning, no crash")
    eq(#calls.info, 0, "M.run: ...and nothing claiming to generate")
  end

  do
    local ctx, calls = fake_ctx({ projects = {} })
    usrcmds_generate_all.run(ctx)
    eq(#calls.warn, 1, "M.run: opts.generate_all.projects = {} -- same as absent, not a crash")
  end

  -- --------------------------------------------- configured -> delegates
  -- Stubs documentation.generate_all.run (the real subprocess orchestrator,
  -- already covered by generate_all_spec.lua) to check THIS layer calls it
  -- with the right projects and wires on_progress/on_done to notify/progress
  -- correctly -- without spawning a real subprocess a second time.
  do
    local original_run = docmap.generate_all.run
    local received_projects, received_opts

    docmap.generate_all.run = function(projects, opts)
      received_projects, received_opts = projects, opts
      -- Simulate completion synchronously, one progress tick then done.
      if opts.on_progress then
        opts.on_progress(1, #projects, projects[1])
      end
      if opts.on_done then
        opts.on_done({ { project = projects[1], ok = true } })
      end
    end

    local projects = { { root = "/fake/one", title = "one" } }
    local ctx, calls = fake_ctx({ projects = projects })
    usrcmds_generate_all.run(ctx)

    eq(received_projects, projects, "M.run: forwards opts.generate_all.projects verbatim")
    ok(type(received_opts.on_progress) == "function", "M.run: wires on_progress")
    ok(type(received_opts.on_done) == "function", "M.run: wires on_done")
    ok(#calls.info >= 1, "M.run: notifies at least once (starting + finished)")
    eq(#calls.error, 0, "M.run: no error notification when every project succeeded")

    docmap.generate_all.run = original_run
  end

  do
    local original_run = docmap.generate_all.run
    docmap.generate_all.run = function(projects, opts)
      if opts.on_done then
        opts.on_done({ { project = projects[1], ok = false, err = "boom" } })
      end
    end

    local ctx, calls = fake_ctx({ projects = { { root = "/fake/one", title = "one" } } })
    usrcmds_generate_all.run(ctx)
    eq(#calls.error, 1, "M.run: a failed project reports via notify.error")
    ok(
      calls.error[1]:find("boom", 1, true) ~= nil,
      "M.run: the error message carries the real failure reason"
    )

    docmap.generate_all.run = original_run
  end

  -- --------------------------------------------------------- autoload
  -- Real filesystem: one project with an existing module_map.json (must be
  -- skipped), one without (must be generated).
  do
    local has_map = repo_root .. "/.deps/generate-all-autoload-has-map"
    local missing_map = repo_root .. "/.deps/generate-all-autoload-missing-map"
    os.execute(('rm -rf "%s" "%s"'):format(has_map, missing_map))
    vim.fn.mkdir(has_map .. "/docs/map", "p")
    vim.fn.mkdir(missing_map, "p")
    local fd = assert(io.open(has_map .. "/docs/map/module_map.json", "w"))
    fd:write("{}")
    fd:close()

    local original_run = docmap.generate_all.run
    local received_projects
    docmap.generate_all.run = function(projects, opts)
      received_projects = projects
      if opts.on_done then
        opts.on_done({})
      end
    end

    local calls = { info = {}, warn = {}, error = {} }
    local fake_notify = {
      info = function(msg)
        calls.info[#calls.info + 1] = msg
      end,
      warn = function(msg)
        calls.warn[#calls.warn + 1] = msg
      end,
      error = function(msg)
        calls.error[#calls.error + 1] = msg
      end,
    }

    usrcmds_generate_all.autoload({
      projects = {
        { root = has_map, title = "has_map" },
        { root = missing_map, title = "missing_map" },
      },
    }, fake_notify)

    ok(received_projects ~= nil, "autoload: generate_all.run was called (something was missing)")
    eq(#received_projects, 1, "autoload: only the project without a map is included")
    eq(received_projects[1].title, "missing_map", "autoload: ...specifically the missing one")

    docmap.generate_all.run = original_run
    os.execute(('rm -rf "%s" "%s"'):format(has_map, missing_map))
  end

  do
    -- Every project already has a map: generate_all.run must not be called
    -- at all -- not called-with-empty-list, genuinely not called.
    local has_map = repo_root .. "/.deps/generate-all-autoload-all-present"
    os.execute(('rm -rf "%s"'):format(has_map))
    vim.fn.mkdir(has_map .. "/docs/map", "p")
    local fd = assert(io.open(has_map .. "/docs/map/module_map.json", "w"))
    fd:write("{}")
    fd:close()

    local original_run = docmap.generate_all.run
    local was_called = false
    docmap.generate_all.run = function()
      was_called = true
    end

    usrcmds_generate_all.autoload({
      projects = { { root = has_map, title = "has_map" } },
    }, { info = function() end, warn = function() end, error = function() end })

    eq(was_called, false, "autoload: nothing missing -- generate_all.run is never called")

    docmap.generate_all.run = original_run
    os.execute(('rm -rf "%s"'):format(has_map))
  end

  -- --------------------------------------------- :DocMapAll registration
  -- Only registered when opts.generate_all.projects is actually configured
  -- and non-empty -- confirmed by calling usrcmds.setup() with each shape
  -- and checking the command's existence, not its behavior (already covered
  -- above).
  do
    local usrcmds = require("documentation.bindings.usrcmds")
    local fixture = repo_root .. "/.deps/generate-all-cmdreg-fixture"
    os.execute(('rm -rf "%s"'):format(fixture))
    vim.fn.mkdir(fixture .. "/lua", "p")

    usrcmds.setup({ root = fixture, command_name = "DocMapGenAllSpecNone" })
    eq(
      vim.fn.exists(":DocMapGenAllSpecNoneAll"),
      0,
      ":DocMapAll-shaped alias is NOT registered without opts.generate_all"
    )

    usrcmds.setup({
      root = fixture,
      command_name = "DocMapGenAllSpecSome",
      generate_all = { projects = { { root = fixture, title = "fixture" } } },
    })
    eq(
      vim.fn.exists(":DocMapGenAllSpecSomeAll"),
      2,
      ":DocMapAll-shaped alias IS registered when opts.generate_all.projects is non-empty"
    )

    os.execute(('rm -rf "%s"'):format(fixture))
  end
end
