-- TESTS/spec_roots_links_spec.lua -- the spec files `documentation.testing`
-- looks for are found and read through `core/safe_fs.lua`.
--
-- `testing/specs.lua` used to stat the tests directory and every `spec_roots`
-- entry, walk them with `lib.nvim.fs.collect_recursive` and open each file
-- itself, so a tests directory (or a `.lua` spec root) that is a link led it
-- to somebody else's files, whose names and `require`s then landed in the page
-- `spec_state` renders. `.docmap.json` can set `spec_state`, `tests_dir` and
-- `spec_roots`, so a repository could switch that on by itself.
--
-- Each case has a spec outside the project and a twin that stays inside, so
-- "refuse every link" cannot pass.

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("documentation.config")
  local docmap = require("documentation")
  local safe_fs = require("documentation.core.safe_fs")
  local specs = require("documentation.testing.specs")
  local testing = require("documentation.testing")

  local base = (vim.fn.tempname():gsub("\\", "/")) .. "_spec_roots_links"
  local root = base .. "/repo"
  local outside = base .. "/outside"

  H.write(root .. "/lua/t/init.lua", {
    "---@module 't'",
    "local M = {}",
    "function M.named_inside() end",
    "return M",
  })
  H.write(root .. "/TESTS_IN/a_spec.lua", { "local t = require('t')", "t.named_inside()" })
  H.write(outside .. "/tests/leak_spec.lua", { "local t = require('t')", "t.only_named_outside()" })

  local here = H.canonical(root)
  ok(H.link(outside .. "/tests", root .. "/TESTS", true), "a tests folder link out can be made")
  ok(H.link(outside .. "/tests", root .. "/specs_out", true), "a directory link out can be made")
  ok(H.link(here .. "/TESTS_IN", root .. "/specs_in", true), "a directory link inside can be made")
  -- File links need a privilege on Windows that a test account may not have.
  local file_links = vim.fn.has("win32") == 0
  if file_links then
    ok(H.link(outside .. "/tests/leak_spec.lua", root .. "/x.lua", false), "a file link out")
    ok(H.link(here .. "/TESTS_IN/a_spec.lua", root .. "/y.lua", false), "a file link inside")
    ok(
      H.link(outside .. "/tests/leak_spec.lua", root .. "/TESTS_IN/leak_spec.lua", false),
      "a spec that is a link out, in a folder that is not"
    )
  end

  ---@param problems { kind: string, message: string }[]
  local function said(problems)
    local out = {}
    for _, p in ipairs(problems) do
      out[#out + 1] = p.kind .. ": " .. p.message
    end
    return table.concat(out, "\n")
  end

  -- ------------------------------------------------------------- discover
  local found, problems = specs.discover(root, "TESTS")
  eq(#found, 0, "discover: a tests folder that is a link out of the project holds no specs")
  eq(#problems, 1, "...and that is reported, as it is not the same as having none")
  ok(
    said(problems):find("is not read", 1, true) ~= nil
      and said(problems):find("outside the project", 1, true) ~= nil,
    "...with the reason: " .. said(problems)
  )
  eq(problems[1].kind, "invalid_spec_root", "...as a spec root that cannot be used")

  found, problems = specs.discover(root, "NOPE")
  eq(#found + #problems, 0, "discover: no tests folder at all is still a normal state")

  found, problems = specs.discover(root, "TESTS_IN")
  eq(table.concat(found, ","), "TESTS_IN/a_spec.lua", "discover: a plain tests folder is read")
  eq(#problems, 0, "...with nothing to report (a spec that is a link out is just not one)")

  found, problems = specs.discover(root, "NOPE", { "specs_out" })
  eq(#found, 0, "discover: a spec root that is a link out holds no specs")
  ok(
    said(problems):find("spec root specs_out is not read", 1, true) ~= nil,
    "...and says it is not read, rather than that it does not exist: " .. said(problems)
  )

  found, problems = specs.discover(root, "NOPE", { "specs_in" })
  eq(table.concat(found, ","), "specs_in/a_spec.lua", "discover: a spec root link inside is read")
  eq(#problems, 0, "...with nothing to report")

  local _, absent = specs.discover(root, "NOPE", { "missing_dir" })
  ok(
    said(absent):find("spec root does not exist", 1, true) ~= nil,
    "discover: a listed root that is not there still says so: " .. said(absent)
  )

  if file_links then
    found, problems = specs.discover(root, "NOPE", { "x.lua" })
    eq(#found, 0, "discover: a spec root file that is a link out is not a spec")
    ok(said(problems):find("is not read", 1, true) ~= nil, "...and is reported: " .. said(problems))

    found, problems = specs.discover(root, "NOPE", { "y.lua" })
    eq(table.concat(found, ","), "y.lua", "discover: a spec root file link inside is a spec")
    eq(#problems, 0, "...with nothing to report")
  end

  -- ----------------------------------------------------------------- read
  local info = specs.read(root, "TESTS_IN/a_spec.lua")
  eq(info.unreadable, nil, "read: a plain spec is read")
  eq(table.concat(info.modules, ","), "t", "...and says what it requires")
  if file_links then
    local linked = specs.read(root, "x.lua")
    ok(linked.unreadable ~= nil, "read: a spec that is a link out is unreadable")
    eq(#linked.modules, 0, "...and nothing of it is taken")
    local text, why = specs.read_capped(root .. "/x.lua", root)
    eq(text, nil, "read_capped: a link out is not read")
    ok(
      tostring(why):find("outside the project", 1, true) ~= nil,
      "...and the reason is the link's: " .. tostring(why)
    )
    eq(specs.read(root, "y.lua").unreadable, nil, "read: a link inside is read")
  end
  eq(specs.read_capped(root .. "/lua", root), nil, "read_capped: a directory is not a file")
  local climbing, climb_why = specs.read_capped(root .. "/../outside/tests/leak_spec.lua", root)
  eq(climbing, nil, "read_capped: a path that climbs out of the project is not read")
  ok(
    tostring(climb_why):find("outside the project", 1, true) ~= nil,
    "...and says so: " .. tostring(climb_why)
  )

  local kept = specs.MAX_FILE_BYTES
  specs.MAX_FILE_BYTES = 8
  local done, capped = pcall(specs.read, root, "TESTS_IN/a_spec.lua")
  specs.MAX_FILE_BYTES = kept
  assert(done, capped)
  eq(capped.unreadable, "larger than 8 bytes", "read: a spec over the size cap is unreadable")

  -- ----------------------------------------------------------- spec_state
  local function spec_state(extra)
    local opts = config.build(
      root,
      vim.tbl_extend(
        "force",
        { source = "lua/t", lua_root = "lua", spec_state = true },
        extra or {}
      )
    )
    local ir = docmap.scan_full(opts)
    return ir.spec_state
  end

  local leaking = spec_state()
  ok(leaking ~= nil, "spec_state: computed for a tests folder that is a link out")
  eq(leaking.totals.with_specs, 0, "...it has no spec in it")
  eq(
    vim.json.encode(leaking):find("leak_spec", 1, true),
    nil,
    "...and nothing of what is behind the link is in the page's data"
  )

  local staying = spec_state({ tests_dir = "TESTS_IN" })
  eq(staying.totals.with_specs, 1, "spec_state: a plain tests folder counts")
  eq(
    table.concat(staying.nodes["lua/t"].specs, ","),
    "TESTS_IN/a_spec.lua",
    "...with its own spec, and not the link out beside it"
  )

  -- ------------------------------------------------ a loader behind a link
  -- `computed_loader_gaps` re-reads the sources the map names. One of them
  -- being replaced by a link must not make it read a file outside, and neither
  -- must the `init.lua` it looks for in a folder the scan took for a namespace
  -- because that file was a link out.
  local proj = base .. "/proj"
  local function module(name, body)
    H.write(proj .. "/lua/p/" .. name .. ".lua", {
      ("---@module 'p.%s'"):format(name),
      "local M = {}",
      body or "",
      "return M",
    })
  end
  H.write(proj .. "/lua/p/init.lua", { "---@module 'p'", "return {}" })
  module("a")
  module("linked_out")
  module("linked_in")
  H.write(proj .. "/lua/p/ns/inner.lua", { "---@module 'p.ns.inner'", "return {}" })
  H.write(proj .. "/TESTS/a_spec.lua", { "local a = require('p.a')", "a.x()" })
  local loader = { "local M = {}", "function M.load(n) return require(n) end", "return M" }
  H.write(outside .. "/loader.lua", loader)
  H.write(proj .. "/support/loader.lua", loader)
  if file_links then
    ok(
      H.link(outside .. "/loader.lua", proj .. "/lua/p/ns/init.lua", false),
      "an init.lua link out"
    )
  end
  ok(
    docmap.generate({ root = proj, source = "lua/p", title = "p", luals = false }) ~= nil,
    "a map to select against"
  )

  if file_links then
    vim.fn.delete(proj .. "/lua/p/linked_out.lua")
    vim.fn.delete(proj .. "/lua/p/linked_in.lua")
    ok(
      H.link(outside .. "/loader.lua", proj .. "/lua/p/linked_out.lua", false),
      "a source link out"
    )
    ok(
      H.link(H.canonical(proj) .. "/support/loader.lua", proj .. "/lua/p/linked_in.lua", false),
      "a source link inside"
    )

    local answer = testing.affected_specs({ root = proj, changed = { "lua/p/a.lua" } })
    ok(answer ~= nil, "affected_specs: answered")
    local loaders = {}
    for _, gap in ipairs(answer.graph.gaps) do
      if gap.kind == "dynamic_require_in_graph" then
        loaders[gap.module or gap.path] = true
      end
    end
    eq(loaders["p.linked_in"], true, "a source that is a link inside is read for computed requires")
    eq(loaders["p.linked_out"], nil, "...and one that is a link out is not")
    eq(loaders["lua/p/ns"], nil, "...nor an init.lua that is a link out, found beside its folder")
  end

  -- --------------------------------------------- specs that cannot be seen
  -- A tests folder behind a link out, or a folder in it that cannot be
  -- listed, means specs may be missing: the answer must not call itself
  -- complete, or a caller would skip a spec it never saw.
  local function mapped(dir)
    H.write(dir .. "/lua/g/init.lua", { "---@module 'g'", "return {}" })
    H.write(dir .. "/lua/g/a.lua", { "---@module 'g.a'", "local M = {}", "return M" })
    ok(
      docmap.generate({ root = dir, source = "lua/g", title = "g", luals = false }) ~= nil,
      "a map to select against"
    )
  end
  -- `verify` settles "stale" by a fresh scan: the fixtures are not repositories.
  local function select_for(dir)
    return testing.affected_specs({ root = dir, changed = { "lua/g/a.lua" }, verify = true })
  end
  ---@param answer table
  ---@param kind string
  local function gap_of(answer, kind)
    for _, gap in ipairs(answer.graph.gaps) do
      if gap.kind == kind then
        return gap
      end
    end
  end

  local gate_out = base .. "/gate_out"
  mapped(gate_out)
  H.write(outside .. "/gate_tests/g_spec.lua", { "local a = require('g.a')", "a.x()" })
  ok(
    H.link(outside .. "/gate_tests", gate_out .. "/TESTS", true),
    "a tests folder link out, mapped"
  )
  local refused = select_for(gate_out)
  ok(refused ~= nil, "affected_specs: answered for a tests folder that is a link out")
  eq(refused.complete, false, "...but not as complete: the specs behind the link were not seen")
  eq(#refused.specs, 0, "...and the one behind the link is not selected")
  local gap = gap_of(refused, "invalid_spec_root")
  ok(gap ~= nil, "...with the spec root as the gap")
  ok(
    gap and gap.message:find("is not read", 1, true) ~= nil,
    "...saying it was not read: " .. tostring(gap and gap.message)
  )

  local gate_in = base .. "/gate_in"
  mapped(gate_in)
  H.write(gate_in .. "/TESTS/a_spec.lua", { "local a = require('g.a')", "a.x()" })
  H.write(gate_in .. "/TESTS/sub/b_spec.lua", { "local a = require('g.a')", "a.y()" })
  local whole = select_for(gate_in)
  eq(whole.complete, true, "affected_specs: a readable tests folder is complete")
  eq(table.concat(whole.specs, ","), "TESTS/a_spec.lua,TESTS/sub/b_spec.lua", "...with both specs")

  -- A folder that exists but cannot be listed (no permission), as the host
  -- would answer it: the walk gets no handle.
  local function without_listing(tail, fn)
    local host = safe_fs.host
    local scandir = host.scandir
    host.scandir = function(path)
      if (path:gsub("\\", "/")):sub(-#tail) == tail then
        return nil
      end
      return scandir(path)
    end
    local ran, err = pcall(fn)
    host.scandir = scandir
    assert(ran, err)
  end

  without_listing("/TESTS/sub", function()
    local files, unlisted = safe_fs.walk_files(gate_in, gate_in .. "/TESTS")
    eq(#files, 1, "walk_files: what can be listed is still returned")
    eq(table.concat(unlisted, ","), "TESTS/sub", "...and the folder that could not be is named")

    local found_here, issues = specs.discover(gate_in, "TESTS")
    eq(table.concat(found_here, ","), "TESTS/a_spec.lua", "discover: the rest of the root is read")
    eq(#issues, 1, "...and the part that was not is reported")
    eq(issues[1].kind, "invalid_spec_root", "...as a spec root that could not be used")
    ok(
      issues[1].message:find("could not be read: TESTS/sub", 1, true) ~= nil,
      "...naming the folder: " .. tostring(issues[1].message)
    )

    local partial = select_for(gate_in)
    eq(partial.complete, false, "affected_specs: a folder that cannot be listed is not complete")
    ok(gap_of(partial, "invalid_spec_root") ~= nil, "...and the gap is there")
    eq(table.concat(partial.specs, ","), "TESTS/a_spec.lua", "...with the specs that were seen")
  end)
  local _, none = safe_fs.walk_files(gate_in, gate_in .. "/TESTS")
  eq(#none, 0, "walk_files: nothing is unlisted when every folder can be listed")

  vim.fn.delete(base, "rf")
end
