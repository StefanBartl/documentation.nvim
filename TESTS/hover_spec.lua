-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/hover_spec.lua — the hover.nvim contribution.
--
-- The property that carries this integration is not "does it find the
-- module": it is **does it admit when the answer is old**. The map is a
-- snapshot that nothing regenerates on its own, and a preview from a stale
-- map does not look stale — it looks current, which is strictly worse than
-- looking absent. The staleness case below is therefore the one worth
-- breaking the build over.
--
-- It also has a shape that is easy to get wrong in a way nothing reports:
-- `node.path` names either a file or the *directory* of a module with an
-- `init.lua` in it, and statting the directory answers with a mtime that does
-- not move when a file inside it is edited. An edited module would then look
-- current forever. That is covered separately from the file case.

return function(H)
  local hover = require("documentation.hover")

  -- ---------------------------------------------------------- dotted name --
  H.eq(
    hover.dotted_at('local n = require("lib.nvim.notify")', 25),
    "lib.nvim.notify",
    "inside a require"
  )
  H.eq(hover.dotted_at("see a.b.c here", 8), "a.b.c", "bare in prose")
  H.eq(hover.dotted_at("just-a-word here", 3), nil, "no dot is not a module name")
  H.eq(hover.dotted_at("", 0), nil, "an empty line")
  H.eq(hover.dotted_at("a.b", 99), nil, "a column past the end")

  -- ------------------------------------------------------------- the float --
  local root = vim.fn.tempname()
  vim.fn.mkdir(root .. "/docs/map", "p")
  vim.fn.mkdir(root .. "/lua/pkg/dirmod", "p")
  vim.fn.writefile({ "-- file module" }, root .. "/lua/pkg/filemod.lua")
  vim.fn.writefile({ "-- dir module" }, root .. "/lua/pkg/dirmod/init.lua")

  local map = {
    nodes = {
      {
        module = "pkg.filemod",
        summary = "A module that lives in one file.",
        path = "lua/pkg/filemod.lua",
        functions = { {}, {} },
        requires = { {} },
        required_by = {},
      },
      {
        module = "pkg.dirmod",
        summary = "A module that lives in a directory.",
        path = "lua/pkg/dirmod",
        functions = {},
        requires = {},
        required_by = { {}, {}, {} },
      },
    },
  }
  vim.fn.writefile({ vim.json.encode(map) }, root .. "/docs/map/module_map.json")

  -- The map is written *after* the sources, so both are current for now.
  local artifact = root .. "/docs/map/module_map.json"
  local now = os.time()
  vim.uv.fs_utime(root .. "/lua/pkg/filemod.lua", now - 100, now - 100)
  vim.uv.fs_utime(root .. "/lua/pkg/dirmod/init.lua", now - 100, now - 100)
  vim.uv.fs_utime(artifact, now, now)

  local captured = {}
  local real_registry = package.loaded["hover.registry"]
  package.loaded["hover.registry"] = {
    register = function(name, contribution)
      captured.name = name
      captured.contribution = contribution
    end,
    position_at = function() end,
  }

  hover._reset()
  H.ok(hover.setup(), "setup registers")
  H.eq(captured.name, "documentation.nvim", "under this plugin's name")
  H.ok(type(captured.contribution.positions) == "table", "as a position preview")

  local answer = captured.contribution.positions[1]
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, root .. "/probe.lua")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'local a = require("pkg.filemod")',
    'local b = require("pkg.dirmod")',
    'local c = require("pkg.absent")',
    "local d = 1",
  })

  local file_mod = answer(buf, 1, 22)
  H.ok(type(file_mod) == "table", "a mapped module answers")
  H.eq(file_mod.title, "pkg.filemod", "titled with the module name")
  local file_body = table.concat(file_mod.lines, "\n")
  H.ok(file_body:find("lives in one file", 1, true) ~= nil, "carrying its summary")
  H.ok(file_body:find("2 functions", 1, true) ~= nil, "and its counts")

  H.ok(type(answer(buf, 2, 22)) == "table", "a directory module answers too")
  H.eq(answer(buf, 3, 22), nil, "a module the map does not know is declined")
  H.eq(answer(buf, 4, 7), nil, "a name with no dot is declined")

  -- ------------------------------------------------------------ staleness --
  -- The whole reason this integration is allowed to exist: an answer from a
  -- map older than the code has to say so.
  local fresh = table.concat(answer(buf, 1, 22).lines, "\n")
  H.ok(
    fresh:find("newer than the map", 1, true) == nil,
    "a current map says nothing about staleness"
  )

  hover._reset() -- drops the parsed-map cache
  vim.uv.fs_utime(root .. "/lua/pkg/filemod.lua", now + 100, now + 100)
  package.loaded["hover.registry"] = {
    register = function(_, contribution)
      captured.contribution = contribution
    end,
    position_at = function() end,
  }
  hover.setup()
  local stale = table.concat(captured.contribution.positions[1](buf, 1, 22).lines, "\n")
  H.ok(
    stale:find("newer than the map", 1, true) ~= nil,
    "an edited file module is reported as stale"
  )

  -- The directory case, which the obvious implementation gets wrong: a
  -- directory's mtime does not move when a file inside it is edited, so this
  -- has to stat `init.lua` rather than the directory.
  hover._reset()
  vim.uv.fs_utime(root .. "/lua/pkg/dirmod/init.lua", now + 100, now + 100)
  package.loaded["hover.registry"] = {
    register = function(_, contribution)
      captured.contribution = contribution
    end,
    position_at = function() end,
  }
  hover.setup()
  local stale_dir = table.concat(captured.contribution.positions[1](buf, 2, 22).lines, "\n")
  H.ok(
    stale_dir:find("newer than the map", 1, true) ~= nil,
    "an edited directory module is reported as stale"
  )

  -- ------------------------------------------------------- the find cache --
  -- The walk up to `docs/map/module_map.json` is cached, misses included,
  -- and the miss is the case that matters: in a repository with no generated
  -- map every position ask used to pay the full climb again. Measured
  -- 2026-09-03, cursor on a dotted name, 2000 repetitions: 97.3 us per ask
  -- before, 2.9 us after.
  --
  -- Counted rather than timed. A timing assertion on a filesystem walk is a
  -- flake waiting for a slow runner; the number of `fs_stat` calls is the
  -- thing the cache actually changes, and it is exact.
  local stats = 0
  local real_stat = vim.uv.fs_stat
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.uv.fs_stat = function(...)
    stats = stats + 1
    return real_stat(...)
  end

  local nomap = vim.fn.tempname() .. "/a/b/c/d"
  vim.fn.mkdir(nomap, "p")
  local nobuf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(nobuf, nomap .. "/probe.lua")
  vim.api.nvim_buf_set_lines(nobuf, 0, -1, false, { 'local a = require("pkg.filemod")' })

  local ask = captured.contribution.positions[1]

  stats = 0
  ask(nobuf, 1, 22)
  local first_miss = stats
  H.ok(first_miss > 1, "a miss walks the tree once")

  stats = 0
  ask(nobuf, 1, 22)
  H.eq(stats, 0, "and never again for the same directory")

  hover._reset()
  hover.setup()
  stats = 0
  captured.contribution.positions[1](nobuf, 1, 22)
  H.ok(stats > 1, "_reset() forgets it, which is how a new map is picked up")

  -- The hit is cached as well, so the climb is paid once there too. Not zero
  -- afterwards: `load_map` still stats the artifact for its mtime and the
  -- module's own source for the staleness check, which is the point of both.
  stats = 0
  captured.contribution.positions[1](buf, 1, 22)
  local first_hit = stats
  stats = 0
  captured.contribution.positions[1](buf, 1, 22)
  H.ok(stats < first_hit, "a hit skips the climb the second time")

  vim.uv.fs_stat = real_stat
  vim.api.nvim_buf_delete(nobuf, { force = true })
  vim.fn.delete(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(nomap))), "rf")

  -- ------------------------------------------------------------- out_dir --
  -- `out_dir` is configurable and the walk used to hardcode `docs/map`, so
  -- anyone who moved the artifact got no module hover at all -- silently,
  -- which is the worst shape a missing feature has.
  --
  -- The second property is the one that keeps that fix from costing anything:
  -- asking a level where it keeps its map is *not* free (the project registry
  -- normalises a root through `uv.fs_realpath`), so it happens in a second
  -- pass that runs only where the default found nothing. A project that never
  -- moved its artifact must therefore never be asked at all.
  local moved = vim.fn.tempname()
  vim.fn.mkdir(moved .. "/doc/gen", "p")
  vim.fn.mkdir(moved .. "/lua/pkg", "p")
  vim.fn.writefile({ "-- moved module" }, moved .. "/lua/pkg/movedmod.lua")
  vim.fn.writefile({ vim.json.encode({ out_dir = "doc/gen" }) }, moved .. "/.docmap.json")
  vim.fn.writefile({
    vim.json.encode({
      nodes = {
        {
          module = "pkg.movedmod",
          summary = "A module in a project that moved its map.",
          path = "lua/pkg/movedmod.lua",
          functions = {},
          requires = {},
          required_by = {},
        },
      },
    }),
  }, moved .. "/doc/gen/module_map.json")
  local moved_now = os.time()
  vim.uv.fs_utime(moved .. "/lua/pkg/movedmod.lua", moved_now - 100, moved_now - 100)
  vim.uv.fs_utime(moved .. "/doc/gen/module_map.json", moved_now, moved_now)

  local movedbuf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(movedbuf, moved .. "/lua/pkg/probe.lua")
  vim.api.nvim_buf_set_lines(movedbuf, 0, -1, false, { 'local a = require("pkg.movedmod")' })

  hover._reset()
  hover.setup()
  local moved_answer = captured.contribution.positions[1](movedbuf, 1, 22)
  H.ok(type(moved_answer) == "table", "a project that states out_dir is found")
  H.eq(moved_answer.title, "pkg.movedmod", "out of the map it actually writes")

  -- And the default case never asks. Counted at the probe rather than at
  -- `config.file.load`: the load only happens where a `.docmap.json` exists,
  -- so counting *it* would pass even if every level were being asked --
  -- measured, by sabotaging the two passes into one and watching this
  -- assertion stay green.
  local probes = 0
  local real_stat2 = vim.uv.fs_stat
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.uv.fs_stat = function(path, ...)
    if type(path) == "string" and path:sub(-12) == ".docmap.json" then
      probes = probes + 1
    end
    return real_stat2(path, ...)
  end

  hover._reset()
  hover.setup()
  H.ok(
    type(captured.contribution.positions[1](buf, 1, 22)) == "table",
    "the default location still answers"
  )
  H.eq(probes, 0, "and a project that never moved its map is never asked where it is")

  vim.uv.fs_stat = real_stat2
  vim.api.nvim_buf_delete(movedbuf, { force = true })
  vim.fn.delete(moved, "rf")

  -- ---------------------------------------------------------- degradation --
  vim.api.nvim_buf_delete(buf, { force = true })
  vim.fn.delete(root, "rf")

  package.loaded["hover.registry"] = nil
  local real_preload = package.preload["hover.registry"]
  package.preload["hover.registry"] = function()
    error("module 'hover.registry' not found")
  end
  hover._reset()
  H.ok(not (hover.setup()), "without hover.nvim, setup declines quietly")
  package.preload["hover.registry"] = real_preload

  package.loaded["hover.registry"] = { register = function() end }
  hover._reset()
  H.ok(not (hover.setup()), "an older hover.nvim without positions is declined")

  hover._reset()
  package.loaded["hover.registry"] = real_registry
end
