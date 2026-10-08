-- TESTS/scan_links_spec.lua — the scanner does not follow a link out of the
-- project.
--
-- The **real** scanner (`documentation.core.scan`) over a real tree with real
-- links: symlinks, or directory junctions on Windows (`H.link`). A link out of
-- the project is a way for a repository to make the engine read somebody
-- else's files and print what it finds into a map -- or, on Windows, to make
-- the machine contact another host just by listing a directory. The tree has
-- one of each kind of thing that matters, and the assertions look at what is
-- in the IR and, as importantly, at what is not.
--
-- Links that stay inside the project are followed, as they were before; that
-- is asserted too, because "refuse every link" would pass the leak checks
-- and break a repository that links one of its own folders into another.

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("documentation.config")
  local scan = require("documentation.core.scan")
  local safe_fs = require("documentation.core.safe_fs")

  local base = (vim.fn.tempname():gsub("\\", "/")) .. "_scan_links"
  local root = base .. "/repo"
  local outside = base .. "/outside"

  local function module_file(path, name, summary)
    H.write(path, { "---@module '" .. name .. "'", "--- " .. summary, "local M = {}", "return M" })
  end

  module_file(root .. "/lua/p/init.lua", "p", "P-SUMMARY.")
  module_file(root .. "/lua/q/init.lua", "q", "Q-SUMMARY.")
  module_file(outside .. "/lua/init.lua", "leaked", "OUTSIDE-SUMMARY.")
  module_file(outside .. "/secret.lua", "secret", "SECRET-SUMMARY.")
  H.write(outside .. "/lib/app.js", { "// outside", "function f() {}" })
  H.write(root .. "/tools/app.js", { "// inside", "function g() {}" })

  ok(H.link(root .. "/lua/q", root .. "/lua/p/inside", true), "a link inside the project")
  ok(H.link(outside .. "/lua", root .. "/lua/p/leaving", true), "a link out of the project")
  ok(H.link(root .. "/lua/p", root .. "/lua/p/loop", true), "a link back up the tree")
  ok(H.link(outside, root .. "/rootlink", true), "a link out of the project, at its root")
  ok(H.link(root .. "/tools", root .. "/toolslink", true), "a second name for a folder")
  local made_file = H.link(outside .. "/secret.lua", root .. "/lua/p/secret.lua", false)

  local function build(extra)
    return config.build(root, vim.tbl_extend("force", { lua_root = "lua" }, extra or {}))
  end

  local ir = scan.scan(build({ source = "lua" }))
  local ids = {}
  for _, id in ipairs(ir.order) do
    ids[id] = ir.nodes[id]
  end

  ok(ids["lua/p"] ~= nil, "the plain module is in the map")
  ok(ids["lua/q"] ~= nil, "...and its plain sibling")
  ok(
    ids["lua/p/inside"] ~= nil and ids["lua/p/inside"].module == "q",
    "a link that stays in the project is followed, as it always was"
  )
  eq(ids["lua/p/leaving"], nil, "a link out of the project is not in the map")
  eq(ids["lua/p/loop"], nil, "a link back up the tree is not walked again")

  local encoded = vim.json.encode(ir)
  ok(encoded:find("Q-SUMMARY", 1, true) ~= nil, "what a followed link leads to is read")
  eq(encoded:find("OUTSIDE-SUMMARY", 1, true), nil, "nothing of the folder behind the link is read")
  eq(encoded:find("SECRET-SUMMARY", 1, true), nil, "nothing of a file behind a link is read")
  eq(encoded:find("leaked", 1, true), nil, "...nor its module name")

  -- What the CLI reports: every link left alone, with a reason.
  local skipped = {}
  for _, s in ipairs(safe_fs.skipped) do
    skipped[s.path] = s.why
  end
  eq(skipped["lua/p/leaving"], "leaves", "the link out is reported, with its reason")
  eq(skipped["rootlink"], "leaves", "...as is the one at the root of the project")
  if made_file then
    eq(skipped["lua/p/secret.lua"], "leaves", "...and a file link out")
  else
    ok(vim.fn.has("win32") == 1, "a file link could not be made on a platform that should allow it")
  end
  eq(skipped["lua/p/inside"], nil, "a link that stays in the project is not reported")

  -- The second traversal, which counts files outside every source root, must
  -- not go through the link at the root either; and a folder reached by two
  -- names is read once.
  local outside_js = ir.meta.outside and ir.meta.outside.js or 0
  eq(outside_js, 1, "the folder behind the root link is not counted; `tools` is, once")

  -- A fresh scan starts a fresh report.
  local clean_root = base .. "/clean"
  module_file(clean_root .. "/lua/c/init.lua", "c", "C-SUMMARY.")
  scan.scan(config.build(clean_root, { source = "lua", lua_root = "lua" }))
  eq(
    #safe_fs.skipped,
    0,
    "a scan with nothing to leave alone reports nothing, not the last one's list"
  )

  -- Two links at each other terminate, and every directory still appears.
  module_file(root .. "/cyc/c1/init.lua", "c1", "C1.")
  module_file(root .. "/cyc/c2/init.lua", "c2", "C2.")
  H.link(root .. "/cyc/c2", root .. "/cyc/c1/to_c2", true)
  H.link(root .. "/cyc/c1", root .. "/cyc/c2/to_c1", true)
  local cyc = scan.scan(build({ source = "cyc" }))
  ok(
    #cyc.order >= 3 and #cyc.order < 20,
    "links at each other: the walk ends (" .. #cyc.order .. ")"
  )
  ok(cyc.nodes["cyc/c1"] ~= nil and cyc.nodes["cyc/c2"] ~= nil, "...with both real folders in it")

  -- A source root that is itself such a link is refused with the reason,
  -- not reported as missing.
  local linked_root_ok = H.link(outside .. "/lua", root .. "/srclink", true)
  ok(linked_root_ok, "a source root that is a link can be made here")
  local scanned, err = pcall(scan.scan, build({ source = "srclink" }))
  eq(scanned, false, "a source root that leaves the project is not scanned")
  ok(tostring(err):find("is not read", 1, true), "...and says so: " .. tostring(err))
  ok(tostring(err):find("outside the project", 1, true), "...and why: " .. tostring(err))
  scanned, err = pcall(scan.scan, build({ source = "../outside/lua" }))
  eq(scanned, false, "a source root that climbs out with `..` is not scanned either")
  ok(tostring(err):find("is not read", 1, true), "...with the same message: " .. tostring(err))

  scanned, err = pcall(scan.scan, build({ source = "not_there" }))
  eq(scanned, false, "a source root that is not there fails, as before")
  ok(
    tostring(err):find("source directory not found", 1, true),
    "...with the message it always had: " .. tostring(err)
  )

  -- `.docmap.json` is the first file of a repository that is read, and the
  -- repository chooses what it is: a link to a file elsewhere (or, on Windows,
  -- on another machine) would be opened like any other, and its keys would
  -- steer the run.
  H.write(outside .. "/evil.json", { '{ "title": "LEAKED-TITLE", "out_dir": "leaked/map" }' })
  module_file(base .. "/cfg_out/lua/c/init.lua", "c", "C.")
  local escaping = H.link(outside .. "/evil.json", base .. "/cfg_out/.docmap.json", false)
  if escaping then
    local warned = {}
    local built = config.build(base .. "/cfg_out", { source = "lua", lua_root = "lua" }, {
      warn = function(message)
        warned[#warned + 1] = message
      end,
    })
    ok(built.title ~= "LEAKED-TITLE", ".docmap.json that is a link out: its title is not applied")
    eq(built.out_dir, "docs/map", ".docmap.json that is a link out: ...nor its out_dir")
    ok(
      table.concat(warned, "\n"):find("not read", 1, true) ~= nil,
      ".docmap.json that is a link out: ...and it is said: " .. table.concat(warned, " | ")
    )

    -- The same file, linked to from inside the project, is read.
    H.write(base .. "/cfg_in/real.json", { '{ "title": "FROM-LINKED-FILE" }' })
    module_file(base .. "/cfg_in/lua/c/init.lua", "c", "C.")
    ok(
      H.link(base .. "/cfg_in/real.json", base .. "/cfg_in/.docmap.json", false),
      "inside file link"
    )
    local inside = config.build(base .. "/cfg_in", { source = "lua", lua_root = "lua" })
    eq(inside.title, "FROM-LINKED-FILE", ".docmap.json that is a link inside: still read")
  else
    ok(vim.fn.has("win32") == 1, "a file link could not be made on a platform that should allow it")
  end

  vim.fn.delete(base, "rf")
end
