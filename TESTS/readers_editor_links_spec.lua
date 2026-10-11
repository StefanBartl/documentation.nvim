-- TESTS/readers_editor_links_spec.lua — the editor's own readers of the
-- committed map do not go through a link, or a `..`, that leaves the project.
--
-- `readers_links_spec.lua` covers the engine's readers; `core/artifact.load`
-- refuses a map behind such a link. Three readers in the editor open the same
-- `<root>/<out_dir>/module_map.json` by hand and used not to: the browser
-- (`editor/browse/source.lua`, the read and the staleness check), the
-- hover.nvim contribution (`hover.lua`) and `:checkhealth documentation`.
-- Each is given a project whose map is behind a link that leaves it and a twin
-- whose link stays inside, so "refuse every link" cannot pass; a recorder
-- shows that the path through the link is not even looked at (on Windows a
-- link to `\\host\share` makes the editor contact that host), and the
-- Windows rules are driven through the injectable `safe_fs` host.

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("documentation.config")
  local safe_fs = require("documentation.core.safe_fs")
  local source = require("documentation.editor.browse.source")
  local hover = require("documentation.hover")
  local uv = vim.uv

  local base = (vim.fn.tempname():gsub("\\", "/")) .. "_readers_editor_links"
  local outside = base .. "/outside"
  local now = os.time()

  local function map_json(summary)
    return vim.json.encode({
      root = "lua/x",
      nodes = {
        {
          id = "lua/x",
          module = "pkg.filemod",
          summary = summary,
          path = "lua/x/a.lua",
          functions = {},
          requires = {},
          required_by = {},
        },
      },
    })
  end

  ---Set a file's modification time (seconds since the epoch).
  local function touch(path, at)
    uv.fs_utime(path, at, at)
  end

  H.write(outside .. "/map/module_map.json", { map_json("OUTSIDE") })
  touch(outside .. "/map/module_map.json", now)
  H.write(outside .. "/newer.lua", { "return 'newer'" })
  touch(outside .. "/newer.lua", now + 100)
  H.write(outside .. "/cfg.json", { vim.json.encode({ out_dir = "gen" }) })
  -- Where `out_dir = "../outside_x"` would lead from any project below `base`.
  H.write(base .. "/outside_x/module_map.json", { map_json("ESCAPED") })

  ---A project: one source file older than `now`, and a real map in `real_map/`
  ---for a link to lead to. Returned in the spelling the engine uses for a root.
  local function project(name)
    local root = base .. "/" .. name
    H.write(root .. "/lua/x/a.lua", { "return {}" })
    touch(root .. "/lua/x/a.lua", now - 100)
    H.write(root .. "/real_map/module_map.json", { map_json("INSIDE") })
    touch(root .. "/real_map/module_map.json", now)
    return H.canonical(root)
  end

  ---`<root>/docs/map` as a link to `target`.
  local function map_link(root, target)
    vim.fn.mkdir(root .. "/docs", "p")
    return (H.link(target, root .. "/docs/map", true))
  end

  ---`<root>/docs/map` as a plain directory holding a map dated `now`.
  local function plain_map(root, dir)
    local path = root .. "/" .. (dir or "docs/map") .. "/module_map.json"
    H.write(path, { map_json("PLAIN") })
    touch(path, now)
  end

  local function opts_for(root)
    return config.build(root, { source = "lua/x", lua_root = "lua" })
  end

  ---Every path the editor statted or opened while `fn` ran.
  local function recording(fn)
    local seen = {}
    local real_stat, real_open = uv.fs_stat, io.open
    uv.fs_stat = function(path, ...)
      seen[#seen + 1] = path
      return real_stat(path, ...)
    end
    rawset(io, "open", function(path, ...)
      seen[#seen + 1] = path
      return real_open(path, ...)
    end)
    local ran, failure = pcall(fn)
    uv.fs_stat = real_stat
    rawset(io, "open", real_open)
    if not ran then
      error(failure, 0)
    end
    return seen
  end

  ---@param seen string[]
  ---@param needle string
  ---@return boolean
  local function touched(seen, needle)
    for _, path in ipairs(seen) do
      if path:find(needle, 1, true) then
        return true
      end
    end
    return false
  end

  local seen ---@type string[]
  local link_out, link_in = project("link_out"), project("link_in")
  local made = map_link(link_out, outside .. "/map")
  made = map_link(link_in, link_in .. "/real_map") and made
  ok(made, "the directory links can be made here")

  -- --------------------------------------------- browse: load_artifact
  local ir, err = source.load_artifact({ root = link_out })
  eq(ir, nil, "load_artifact: a map behind a link out of the project is not read")
  ok(tostring(err):find("not read", 1, true) ~= nil, "...and it says why: " .. tostring(err))
  ok(tostring(err):find("OUTSIDE", 1, true) == nil, "...nothing of it leaks into the message")

  local inside = source.load_artifact({ root = link_in })
  ok(inside ~= nil, "load_artifact: one behind a link that stays inside is read")
  eq(inside.nodes["lua/x"].summary, "INSIDE", "...and it is the map the link leads to")

  local _, handle, hint = source.acquire({ root = link_out })
  eq(handle, nil, "acquire: no handle for a refused map")
  ok(
    tostring(hint):find("not read", 1, true) ~= nil,
    "...the browser's status line gets the reason"
  )

  local none_ir, none_err = source.load_artifact({ root = project("no_map") })
  eq(none_ir, nil, "load_artifact: no map at all is still no map")
  ok(tostring(none_err):find("run :DocMap first", 1, true) ~= nil, "...and says to run :DocMap")

  -- `out_dir` is the repository's text (`.docmap.json`). A value the writers
  -- refuse is refused here too -- including one `safe_fs` alone would resolve
  -- to a place inside the project.
  local plain = project("plain")
  plain_map(plain)
  ok(source.load_artifact({ root = plain }) ~= nil, "load_artifact: a plain map is read")
  for _, out_dir in ipairs({ "docs/../docs/map", "../outside_x" }) do
    local refused, refusal = source.load_artifact({ root = plain, out_dir = out_dir })
    eq(refused, nil, "load_artifact: out_dir " .. out_dir .. " is not used")
    ok(
      tostring(refusal):find("not a safe relative path", 1, true) ~= nil,
      "...and it says so: " .. tostring(refusal)
    )
  end

  -- ---------------------------------------------------- browse: stale
  eq(source.stale(opts_for(link_out)), true, "stale: a map behind a link out is not a fresh one")
  eq(
    source.stale(opts_for(link_in)),
    false,
    "stale: one behind a link inside is judged by its mtime"
  )

  local newer_plain = project("stale_plain")
  plain_map(newer_plain)
  H.write(newer_plain .. "/lua/x/b.lua", { "return {}" })
  touch(newer_plain .. "/lua/x/b.lua", now + 100)
  eq(source.stale(opts_for(newer_plain)), true, "stale: a source file newer than the map is seen")

  local file_out, file_in = project("stale_file_out"), project("stale_file_in")
  plain_map(file_out)
  plain_map(file_in)
  H.write(file_in .. "/lib/newer.lua", { "return 'newer'" })
  touch(file_in .. "/lib/newer.lua", now + 100)
  local file_links = H.link(outside .. "/newer.lua", file_out .. "/lua/x/ext.lua", false)
  file_links = H.link(file_in .. "/lib/newer.lua", file_in .. "/lua/x/ext.lua", false)
    and file_links
  if file_links then
    eq(
      source.stale(opts_for(file_out)),
      false,
      "stale: a file link out of the project is neither statted nor counted"
    )
    eq(
      source.stale(opts_for(file_in)),
      true,
      "stale: a file link that stays inside is the file it leads to"
    )
  end

  -- A long-lived editor asks again: a directory that was plain when something
  -- last looked at it and is a link now must not be answered for from what was
  -- seen then.
  local swapped = project("stale_swapped")
  plain_map(swapped)
  local swapped_opts = opts_for(swapped)
  eq(source.stale(swapped_opts), false, "stale: a plain map, source older, is fresh")
  safe_fs.stat(swapped, swapped .. "/docs/map/module_map.json")
  vim.fn.delete(swapped .. "/docs/map", "rf")
  if H.link(outside .. "/map", swapped .. "/docs/map", true) then
    seen = recording(function()
      eq(source.stale(swapped_opts), true, "stale: ...and not once docs/map is a link out")
    end)
    ok(
      not touched(seen, swapped .. "/docs/map"),
      "stale: ...and nothing is statted through it: " .. table.concat(seen, ", ")
    )
  end

  -- ----------------------------------------------------------- hover
  ---Ask the hover.nvim contribution about a dotted name in a file of `root`:
  ---`fn(ask)` gets a function that returns the float, or nil.
  local function with_hover(root, fn)
    local real_registry = package.loaded["hover.registry"]
    local captured
    package.loaded["hover.registry"] = {
      register = function(_, contribution)
        captured = contribution
      end,
      position_at = function() end,
    }
    hover._reset()
    local buf = vim.api.nvim_create_buf(false, true)
    local ran, answer = pcall(function()
      hover.setup()
      vim.api.nvim_buf_set_name(buf, root .. "/lua/x/probe.lua")
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'local a = require("pkg.filemod")' })
      return fn(function()
        return captured.positions[1](buf, 1, 22)
      end)
    end)
    vim.api.nvim_buf_delete(buf, { force = true })
    hover._reset()
    package.loaded["hover.registry"] = real_registry
    if not ran then
      error(answer, 0)
    end
    return answer
  end

  ---What the contribution answers on the first ask.
  local function hover_at(root)
    return with_hover(root, function(ask)
      return ask()
    end)
  end

  eq(hover_at(link_out), nil, "hover: a map behind a link out of the project answers nothing")
  local float = hover_at(link_in)
  ok(float ~= nil, "hover: one behind a link that stays inside answers")
  eq(float.title, "pkg.filemod", "...with the module it was asked about")
  ok(
    table.concat(float.lines, "\n"):find("INSIDE", 1, true) ~= nil,
    "...out of the map it leads to"
  )

  local rec_out = project("hover_rec")
  made = map_link(rec_out, outside .. "/map")
  ok(made, "hover: the link can be made")
  seen = recording(function()
    eq(hover_at(rec_out), nil, "hover: ...also while recording")
  end)
  ok(
    not touched(seen, rec_out .. "/docs/map"),
    "hover: nothing is statted or opened through the link: " .. table.concat(seen, ", ")
  )

  -- `out_dir` stated by the repository's `.docmap.json`.
  local function with_out_dir(name, out_dir, map_dir)
    local root = project(name)
    H.write(root .. "/.docmap.json", { vim.json.encode({ out_dir = out_dir }) })
    if map_dir then
      plain_map(root, map_dir)
    end
    return root
  end
  local stated = with_out_dir("hover_stated", "doc/gen", "doc/gen")
  local stated_float = hover_at(stated)
  ok(stated_float ~= nil, "hover: an out_dir the repository states is still found")
  ok(table.concat(stated_float.lines, "\n"):find("PLAIN", 1, true) ~= nil, "...in the map it names")
  eq(
    hover_at(with_out_dir("hover_dots", "doc/../doc/gen", "doc/gen")),
    nil,
    "hover: an out_dir the writers refuse is not believed, even where it stays inside"
  )
  eq(
    hover_at(with_out_dir("hover_escape", "../outside_x")),
    nil,
    "hover: an out_dir that leaves the project finds no map"
  )

  -- ...and the same value out of a project the editor has installed.
  local function with_registry(root, out_dir, fn)
    local real = package.loaded["documentation.editor.registry"]
    package.loaded["documentation.editor.registry"] = {
      get = function(dir)
        return dir == root and { cfg = { out_dir = out_dir } } or nil
      end,
    }
    local ran, failure = pcall(fn)
    package.loaded["documentation.editor.registry"] = real
    if not ran then
      error(failure, 0)
    end
  end
  local installed = project("hover_installed")
  plain_map(installed, "doc/gen")
  with_registry(installed, "doc/gen", function()
    ok(hover_at(installed) ~= nil, "hover: an installed project's out_dir is found")
  end)
  with_registry(installed, "doc/../doc/gen", function()
    eq(hover_at(installed), nil, "hover: ...and one the writers refuse is not believed")
  end)

  -- The file that states it is the repository's too.
  local cfg_link = project("hover_cfg_link")
  local cfg_made = H.link(outside .. "/cfg.json", cfg_link .. "/.docmap.json", false)
  local cfg_plain = with_out_dir("hover_cfg_plain", "doc/gen", "doc/gen")
  seen = recording(function()
    hover_at(cfg_plain)
  end)
  ok(touched(seen, cfg_plain .. "/.docmap.json"), "hover: a plain .docmap.json is looked at")
  if cfg_made then
    seen = recording(function()
      eq(hover_at(cfg_link), nil, "hover: a .docmap.json that is a link out names no map")
    end)
    ok(
      not touched(seen, cfg_link .. "/.docmap.json"),
      "hover: ...and is not statted either: " .. table.concat(seen, ", ")
    )
  end

  -- Asked again after the directory became a link: the answer is not the one
  -- the first ask found.
  local swap = project("hover_swap")
  plain_map(swap)
  touch(swap .. "/docs/map/module_map.json", now - 50)
  with_hover(swap, function(ask)
    ok(ask() ~= nil, "hover: a plain map answers")
    vim.fn.delete(swap .. "/docs/map", "rf")
    if H.link(outside .. "/map", swap .. "/docs/map", true) then
      seen = recording(function()
        eq(ask(), nil, "hover: ...and no longer once docs/map is a link out")
      end)
      ok(
        not touched(seen, swap .. "/docs/map"),
        "hover: ...and nothing is statted through it: " .. table.concat(seen, ", ")
      )
    end
  end)

  -- The source file the staleness note compares against comes from the map.
  local src_out, src_in = project("hover_src_out"), project("hover_src_in")
  plain_map(src_out)
  plain_map(src_in)
  H.write(src_in .. "/lib/newer.lua", { "return 'newer'" })
  touch(src_in .. "/lib/newer.lua", now + 100)
  vim.fn.delete(src_out .. "/lua/x/a.lua")
  vim.fn.delete(src_in .. "/lua/x/a.lua")
  local src_links = H.link(outside .. "/newer.lua", src_out .. "/lua/x/a.lua", false)
  src_links = H.link(src_in .. "/lib/newer.lua", src_in .. "/lua/x/a.lua", false) and src_links
  if src_links then
    local out_body = table.concat(hover_at(src_out).lines, "\n")
    ok(
      out_body:find("newer than the map", 1, true) == nil,
      "hover: a source file that is a link out is not compared"
    )
    local in_body = table.concat(hover_at(src_in).lines, "\n")
    ok(
      in_body:find("newer than the map", 1, true) ~= nil,
      "hover: ...one that stays inside is, and is newer"
    )
  end

  -- ---------------------------------------------------------- health
  ---What `:checkhealth documentation` reports for `root`, as { kind, message }.
  local function health_of(root)
    local report = {}
    local function sink(kind)
      return function(message)
        report[#report + 1] = { kind = kind, message = message }
      end
    end
    local saved = {
      health = rawget(vim, "health"),
      module = package.loaded["documentation.editor.health"],
      deps = package.loaded["lib.nvim.deps.health"],
      cwd = vim.fn.getcwd(),
    }
    vim.health = {
      start = sink("start"),
      ok = sink("ok"),
      warn = sink("warn"),
      error = sink("error"),
      info = sink("info"),
    }
    package.loaded["documentation.editor.health"] = nil
    package.loaded["lib.nvim.deps.health"] = { report_for = function() end }
    local ran, failure = pcall(function()
      vim.fn.chdir(root)
      require("documentation.editor.health").check()
    end)
    vim.fn.chdir(saved.cwd)
    vim.health = saved.health
    package.loaded["documentation.editor.health"] = saved.module
    package.loaded["lib.nvim.deps.health"] = saved.deps
    if not ran then
      error(failure, 0)
    end
    return report
  end

  ---@param report { kind: string, message: string }[]
  ---@param kind string
  ---@param needle string
  ---@return boolean
  local function reported(report, kind, needle)
    for _, line in ipairs(report) do
      if line.kind == kind and line.message:find(needle, 1, true) then
        return true
      end
    end
    return false
  end

  local plain_report = health_of(plain)
  ok(reported(plain_report, "ok", "1 nodes"), "health: a plain map is read")
  ok(
    reported(plain_report, "ok", "newer than every source file"),
    "health: ...and is newer than the one source file"
  )

  local out_report = health_of(link_out)
  ok(reported(out_report, "warn", "not read"), "health: a map behind a link out is a warning")
  ok(not reported(out_report, "ok", "nodes"), "health: ...and is not counted")
  ok(
    reported(health_of(link_in), "ok", "1 nodes"),
    "health: one behind a link that stays inside is read"
  )

  for _, case in ipairs({
    { name = "health_dots", out_dir = "doc/../doc/gen", map_dir = "doc/gen" },
    { name = "health_escape", out_dir = "../outside_x" },
  }) do
    local report = health_of(with_out_dir(case.name, case.out_dir, case.map_dir))
    ok(
      reported(report, "warn", "not a safe relative path"),
      "health: out_dir " .. case.out_dir .. " is a warning"
    )
    ok(not reported(report, "ok", "nodes"), "health: ...and no map is read from it")
  end

  if file_links then
    local stale_out = health_of(file_out)
    ok(
      reported(stale_out, "ok", "newer than every source file"),
      "health: a source file that is a link out is not compared"
    )
    ok(
      reported(health_of(file_in), "warn", "older than the newest source file"),
      "health: ...one that stays inside is, and the map is older"
    )
  end

  -- ------------------------------------------- the Windows rules
  ---Run `fn` with the Windows path rules and a host on which `<root>/docs/map`
  ---is a link whose target is spelled `target`; everything else is the real
  ---disk. Returns the paths `lstat` and `stat` were asked about.
  local function windows_map_link(root, target, fn)
    local saved_host, saved_windows = safe_fs.host, safe_fs.windows
    local wanted = (root .. "/docs/map"):lower()
    local lstats, stats = {}, {}
    safe_fs.host = setmetatable({
      lstat = function(path)
        lstats[#lstats + 1] = path
        if path:lower() == wanted then
          return { type = "link" }
        end
        return saved_host.lstat(path)
      end,
      readlink = function(path)
        if path:lower() == wanted then
          return target
        end
        return saved_host.readlink(path)
      end,
      stat = function(path)
        stats[#stats + 1] = path
        return saved_host.stat(path)
      end,
    }, { __index = saved_host })
    safe_fs.windows = true
    safe_fs.forget()
    local ran, failure = pcall(fn)
    safe_fs.host, safe_fs.windows = saved_host, saved_windows
    safe_fs.forget()
    safe_fs.clear_skipped()
    if not ran then
      error(failure, 0)
    end
    return lstats, stats
  end

  local unc = "\\\\attacker\\share\\m"
  local win = project("windows")
  local lstats, stats = windows_map_link(win, unc, function()
    local refused, refusal = source.load_artifact({ root = win })
    eq(refused, nil, "windows: a map behind a link to another machine is not read")
    ok(
      tostring(refusal):find("another machine", 1, true) ~= nil,
      "windows: ...and it says why: " .. tostring(refusal)
    )
    eq(hover_at(win), nil, "windows: hover answers nothing for it")
    ok(
      reported(health_of(win), "warn", "another machine"),
      "windows: :checkhealth warns about it, with the reason"
    )
  end)
  ok(touched(lstats, win .. "/docs/map"), "windows: the readers asked safe_fs about the link")
  ok(not touched(stats, win .. "/docs/map"), "windows: ...and nothing was statted through it")

  windows_map_link(win, "..\\real_map", function()
    local relative = source.load_artifact({ root = win })
    ok(relative ~= nil, "windows: a link whose target stays inside is read")
    eq(relative.nodes["lua/x"].summary, "INSIDE", "windows: ...and it is the map it leads to")
    ok(hover_at(win) ~= nil, "windows: hover answers for it")
    ok(reported(health_of(win), "ok", "1 nodes"), "windows: :checkhealth reads it")
  end)

  vim.fn.delete(base, "rf")
end
