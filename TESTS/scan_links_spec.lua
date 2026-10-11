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
-- Links that stay inside the project are followed; that is asserted too,
-- because "refuse every link" would pass the leak checks and break a
-- repository that links one of its own folders into another. The standalone
-- build always followed a directory link, the editor host used to skip it. A
-- directory is entered through a link at most once per scan, because every
-- path of links would otherwise be a walk of its own.

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

  -- The targets of the links meant to stay inside are spelled the way the
  -- engine spells the root (see `H.canonical`).
  local here = H.canonical(root)
  ok(H.link(here .. "/lua/q", root .. "/lua/p/inside", true), "a link inside the project")
  ok(H.link(outside .. "/lua", root .. "/lua/p/leaving", true), "a link out of the project")
  ok(H.link(here .. "/lua/p", root .. "/lua/p/loop", true), "a link back up the tree")
  ok(H.link(outside, root .. "/rootlink", true), "a link out of the project, at its root")
  ok(H.link(here .. "/tools", root .. "/toolslink", true), "a second name for a folder")
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
    "a directory link that stays in the project is entered, and its module is read"
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
  H.link(here .. "/cyc/c2", root .. "/cyc/c1/to_c2", true)
  H.link(here .. "/cyc/c1", root .. "/cyc/c2/to_c1", true)
  local cyc = scan.scan(build({ source = "cyc" }))
  ok(
    #cyc.order >= 3 and #cyc.order < 20,
    "links at each other: the walk ends (" .. #cyc.order .. ")"
  )
  ok(cyc.nodes["cyc/c1"] ~= nil and cyc.nodes["cyc/c2"] ~= nil, "...with both real folders in it")

  -- A folder that many links lead to is entered through a link once, not once
  -- per path of links: `width` links per level over `levels` levels are
  -- width^levels paths, and `dirs` folders that link to each other are
  -- `dirs`! of them. The sizes are small on purpose, so that going back to
  -- the walk of every path is red in seconds rather than a hang. Which link
  -- to a folder is the one entered follows from the sorted order of the
  -- entries, so it is the same on every run.
  local fan = base .. "/fanout"
  local levels, width = 6, 3
  for i = 0, levels do
    vim.fn.mkdir(fan .. "/lua/f" .. i, "p")
  end
  module_file(fan .. "/lua/f" .. levels .. "/init.lua", "deep", "DEEP.")
  local fan_here = H.canonical(fan)
  for i = 0, levels - 1 do
    for k = 1, width do
      local link = fan .. "/lua/f" .. i .. "/l" .. k
      ok(H.link(fan_here .. "/lua/f" .. (i + 1), link, true), "a link to the next level: " .. link)
    end
  end
  ok(H.link(fan_here .. "/lua/f0", fan .. "/lua/start", true), "a link to the first level")
  local fanned = scan.scan(config.build(fan, { source = "lua", lua_root = "lua" }))
  ok(
    #fanned.order < 4 * levels + 10,
    "links to the next level from every level: the walk is not exponential ("
      .. #fanned.order
      .. ")"
  )
  ok(
    fanned.nodes["lua/f0"] ~= nil and fanned.nodes["lua/f" .. levels] ~= nil,
    "...with the first and the deepest real folder in it"
  )
  ok(fanned.nodes["lua/f0/l1"] ~= nil, "...a folder is entered through the first link to it")
  eq(fanned.nodes["lua/f0/l2"], nil, "...and not through the second")

  local full = base .. "/fullgraph"
  local dirs = 6
  for i = 1, dirs do
    module_file(full .. "/lua/d" .. i .. "/init.lua", "d" .. i, "D" .. i .. ".")
  end
  local full_here = H.canonical(full)
  for i = 1, dirs do
    for j = 1, dirs do
      if i ~= j then
        local link = full .. "/lua/d" .. i .. "/l" .. j
        ok(H.link(full_here .. "/lua/d" .. j, link, true), "a link to the other folder: " .. link)
      end
    end
  end
  local graph = scan.scan(config.build(full, { source = "lua", lua_root = "lua" }))
  ok(
    #graph.order <= 4 * dirs,
    "every folder linking to every other: the walk is not factorial (" .. #graph.order .. ")"
  )
  for i = 1, dirs do
    ok(graph.nodes["lua/d" .. i] ~= nil, "...and the real folder d" .. i .. " is in the map")
  end

  -- A link to every level of one deep folder: each leads to the levels below
  -- it, which are entered through that link as well and so count once, not
  -- once per link above them.
  local deep = base .. "/deepchain"
  local nest = 30
  local nested = deep .. "/lua/c"
  module_file(nested .. "/init.lua", "c", "C.")
  vim.fn.mkdir(deep .. "/lua/links", "p")
  local deep_here = H.canonical(deep)
  for i = 1, nest do
    nested = nested .. "/x"
    vim.fn.mkdir(nested, "p")
    local link = deep .. "/lua/links/l" .. i
    ok(H.link(deep_here .. nested:sub(#deep + 1), link, true), "a link to level " .. i)
  end
  local chain = scan.scan(config.build(deep, { source = "lua", lua_root = "lua" }))
  ok(
    #chain.order < 3 * nest + 10,
    "a link to every level of a deep folder: the walk is not quadratic (" .. #chain.order .. ")"
  )
  ok(chain.nodes["lua/c" .. ("/x"):rep(nest)] ~= nil, "...with the deepest real folder in it")

  -- The traversal that counts what lies outside the source roots. A link from
  -- there that leads into a source root is the source tree under another name,
  -- and its files are in the map already; counting them would change
  -- `meta.outside`, and with it the bytes of a committed map, for nothing. A
  -- link to some other folder outside the roots is counted once, like the
  -- folder itself, and so is a chain of links that fans out.
  local outer = base .. "/outer"
  module_file(outer .. "/lua/p/init.lua", "p", "P.")
  H.write(outer .. "/tools/app.js", { "// app", "function a() {}" })
  H.write(outer .. "/third/js/lib.js", { "// lib", "function b() {}" })
  H.write(outer .. "/gen/g" .. levels .. "/deep.js", { "// deep", "function c() {}" })
  local outer_here = H.canonical(outer)
  ok(H.link(outer_here .. "/lua", outer .. "/tools/libs", true), "a link to a source root")
  ok(H.link(outer_here .. "/lua/p", outer .. "/tools/part", true), "a link to a folder in one")
  ok(
    H.link(outer_here .. "/third/js", outer .. "/tools/vendored", true),
    "a link to another folder"
  )
  for i = 0, levels - 1 do
    vim.fn.mkdir(outer .. "/gen/g" .. i, "p")
    for k = 1, width do
      ok(
        H.link(outer_here .. "/gen/g" .. (i + 1), outer .. "/gen/g" .. i .. "/l" .. k, true),
        "a link to the next level outside the roots"
      )
    end
  end
  local counted = scan.scan(config.build(outer, { source = "lua", lua_root = "lua" })).meta.outside
  eq(counted and counted.lua, nil, "a link to a source root is not counted as outside it")
  eq(counted and counted.js, 3, "a folder reached by two names, or by many links, is counted once")
  counted = scan.scan(config.build(outer, { source = "lua/p", lua_root = "lua" })).meta.outside
  eq(counted and counted.lua, nil, "...nor is a link to a folder above a source root")

  -- Where the file system folds case (macOS, Windows) a link may spell a
  -- folder in another case than the folder does, and both spellings lead to
  -- it. Every spelling is a path of its own to a walk that tells folders apart
  -- by where they are, so the scan asks the file system whether it folds case
  -- (`safe_fs.folds_case`) and compares by lower case if it does. Linux does
  -- not fold: this runs on the real host with a wrapper that does, as the
  -- Windows rules run on a fake in `safe_fs_spec`. The links are named so that
  -- they sort before the real folder, after it, and one on each side.
  local uv = vim.uv or vim.loop
  ---`path` spelled as it is on disk, where a component differs from it in case only.
  ---@param path string
  ---@return string
  local function as_on_disk(path)
    if path:sub(1, 1) ~= "/" then
      path = uv.cwd() .. "/" .. path -- a root written relative to the working directory
    end
    local at = ""
    for part in path:gmatch("[^/]+") do
      if not uv.fs_lstat(at .. "/" .. part) then
        local handle, name = uv.fs_scandir(at == "" and "/" or at), nil
        while handle do
          name = uv.fs_scandir_next(handle)
          if not name or name:lower() == part:lower() then
            break
          end
        end
        part = name or part
      end
      at = at .. "/" .. part
    end
    return at
  end
  ---Run `fn` on a host that folds case, and put the real one back whatever happens.
  ---@param fn fun()
  local function on_case_folding_host(fn)
    if safe_fs.windows then
      return fn() -- folds case already
    end
    local saved = safe_fs.host
    local folding = vim.tbl_extend("force", {}, saved)
    for _, call in ipairs({ "lstat", "stat", "readlink", "scandir" }) do
      folding[call] = function(path)
        return saved[call](as_on_disk(path))
      end
    end
    safe_fs.host = folding
    safe_fs.forget()
    local ran, err = pcall(fn)
    safe_fs.host = saved
    safe_fs.forget()
    if not ran then
      error(err, 0)
    end
  end

  -- Each level has the real folder `s/p` and two links to it, `names[1]`
  -- written as `s/p` and `names[2]` as `S/p`; `s/p` holds the next level. A
  -- walk meets the entries of a folder in order, or from the last one, so the
  -- names that sort before `s` or after it decide which spelling it enters
  -- first.
  ---@param dir string
  ---@param under string Folder of the first level, below `dir`.
  ---@param count integer Levels
  ---@param names string[]
  ---@param relative boolean? Targets written relative to the link, so that the spelling of the way adds up from level to level. Not possible with a junction.
  ---@return string deepest The real folder of the last level.
  local function spelled_twice(dir, under, count, names, relative)
    vim.fn.mkdir(dir .. "/" .. under, "p")
    local canonical = H.canonical(dir) .. "/" .. under
    local at = dir .. "/" .. under
    for _ = 1, count do
      vim.fn.mkdir(at .. "/s/p", "p")
      local target = relative and "" or (canonical .. "/")
      ok(H.link(target .. "s/p", at .. "/" .. names[1], true), "a link spelled as the folder is")
      ok(H.link(target .. "S/p", at .. "/" .. names[2], true), "a link spelled in another case")
      at, canonical = at .. "/s/p", canonical .. "/s/p"
    end
    return at
  end

  for _, names in ipairs({ { "a", "b" }, { "t", "u" }, { "a", "u" }, { "t", "a" } }) do
    local label = names[1] .. "/" .. names[2]
    local folded = base .. "/casefold_" .. names[1] .. names[2]
    module_file(folded .. "/lua/p/init.lua", "p", "P.")
    spelled_twice(folded, "lua/d0", levels, names)
    local deepest = spelled_twice(folded, "gen/d0", levels, names)
    H.write(deepest .. "/deep.js", { "// deep", "function d() {}" })
    on_case_folding_host(function()
      eq(safe_fs.folds_case(folded), true, "the wrapper is a file system that folds case")
      local spelled = scan.scan(config.build(folded, { source = "lua", lua_root = "lua" }))
      ok(
        #spelled.order < 4 * levels + 10,
        "links to one folder in two cases ("
          .. label
          .. "): the walk is not exponential ("
          .. #spelled.order
          .. ")"
      )
      ok(
        spelled.nodes["lua/d0" .. ("/s/p"):rep(levels)] ~= nil,
        "...with the deepest real folder in it"
      )
      eq(
        spelled.meta.outside and spelled.meta.outside.js,
        1,
        "links to one folder in two cases ("
          .. label
          .. ") outside the roots: its file is counted once"
      )
    end)
  end

  -- The standalone `docmap .` is given the root `.`, which has no letter to
  -- write in another case and, without a `realpath`, stays as it is. The disk
  -- is asked through a name in it.
  local dotted = base .. "/casefold_ab"
  local starting = uv.cwd()
  on_case_folding_host(function()
    ok(uv.chdir(dotted), "the working directory is the project")
    local opts = config.build(dotted, { source = "lua", lua_root = "lua" })
    opts.root = "."
    local ran, result = pcall(scan.scan, opts)
    uv.chdir(starting)
    if not ran then
      error(result, 0)
    end
    ok(
      #result.order < 4 * levels + 10,
      "links to one folder in two cases, from the root `.`: the walk is not exponential ("
        .. #result.order
        .. ")"
    )
    eq(
      result.meta.outside and result.meta.outside.js,
      1,
      "...and outside the roots its file is counted once"
    )
  end)

  -- A spelling the scan cannot see through (here the case of a disk that
  -- folds it, with the scan told that it does not: the same holds for Unicode
  -- case, normal forms and short Windows names) makes a folder as many
  -- folders as there are paths of links to it, twice as many with every level.
  -- The number of folders the walks enter through links is bounded all the
  -- same: past `scan.MAX_LINKED_DIRS` no further link is followed, and that is
  -- said once. The limit is lowered here to keep the fixtures small; each walk
  -- has a project of its own.
  local limit = 3
  local twin_levels = 5
  ok(scan.MAX_LINKED_DIRS >= 10000, "the limit is far above what a real tree holds")
  local twinned = { main = base .. "/linkcap_main", outer = base .. "/linkcap_outer" }
  module_file(twinned.main .. "/lua/p/init.lua", "p", "P.")
  module_file(twinned.outer .. "/lua/p/init.lua", "p", "P.")
  if not safe_fs.windows then
    spelled_twice(twinned.main, "lua/d0", twin_levels, { "a", "b" }, true)
    local deepest = spelled_twice(twinned.outer, "gen/d0", twin_levels, { "a", "b" }, true)
    H.write(deepest .. "/deep.js", { "// deep", "function d() {}" })
  end

  ---Scan `dir` on the folding host, at most `cap` folders entered through links.
  ---@param dir string
  ---@param cap integer
  ---@param blind boolean? The scan is not told that the disk folds case.
  ---@return Documentation.IR ir
  ---@return { path: string, why: string }[] noted Links left alone.
  local function scan_capped(dir, cap, blind)
    local result, noted
    on_case_folding_host(function()
      local saved_limit, saved_folds = scan.MAX_LINKED_DIRS, safe_fs.folds_case
      scan.MAX_LINKED_DIRS = cap
      if blind then
        safe_fs.folds_case = function()
          return false
        end
      end
      local ran, got = pcall(scan.scan, config.build(dir, { source = "lua", lua_root = "lua" }))
      scan.MAX_LINKED_DIRS, safe_fs.folds_case = saved_limit, saved_folds
      if not ran then
        error(got, 0)
      end
      result, noted = got, safe_fs.skipped
    end)
    return result, noted
  end

  local default_limit = scan.MAX_LINKED_DIRS
  ---@param scanned Documentation.IR
  ---@return integer
  local function js_files(scanned)
    return scanned.meta.outside and scanned.meta.outside.js or 0
  end
  if not safe_fs.windows then
    local merged = scan_capped(twinned.main, default_limit)
    local free, free_noted = scan_capped(twinned.main, default_limit, true)
    local held, held_noted = scan_capped(twinned.main, limit, true)
    ok(
      #free.order > 2 * #merged.order,
      "without the limit the twins multiply (" .. #free.order .. " against " .. #merged.order .. ")"
    )
    eq(#free_noted, 0, "nothing is said while the limit is not met")
    ok(
      #held.order <= #merged.order + limit,
      "past the limit no link is followed (" .. #held.order .. " of " .. #free.order .. ")"
    )
    eq(#held_noted, 1, "...and that is said once")
    eq(held_noted[1] and held_noted[1].why, "many", "...as a limit, not as a link that leaves")
    ok(
      held.nodes["lua/d0" .. ("/s/p"):rep(twin_levels)] ~= nil,
      "...with the real folders in the map"
    )

    local free_js = js_files(scan_capped(twinned.outer, default_limit, true))
    local held_js = js_files(scan_capped(twinned.outer, limit, true))
    ok(free_js > limit + 1, "outside the roots the twins multiply too (" .. free_js .. ")")
    ok(
      held_js >= 1 and held_js <= limit + 1,
      "...and are counted up to the limit (" .. held_js .. ")"
    )
  end

  -- Everything below a folder entered through a link counts with it: a link
  -- to a folder with many folders in it (reached only through the link, as one
  -- into `vendor` is) is not a way past the limit.
  local wide = base .. "/linkcap_wide"
  module_file(wide .. "/lua/p/init.lua", "p", "P.")
  for i = 1, 6 do
    H.write(wide .. "/vendor/big/s" .. i .. "/f.js", { "// f", "function f() {}" })
  end
  vim.fn.mkdir(wide .. "/tools", "p")
  ok(H.link(H.canonical(wide) .. "/vendor/big", wide .. "/tools/big", true), "a link into vendor")
  eq(js_files(scan_capped(wide, default_limit)), 6, "a link into a folder that is skipped by name")
  ok(
    js_files(scan_capped(wide, limit)) <= limit,
    "...is followed up to the limit, folders below it too"
  )

  -- A file system that tells `Up` from `up` has two folders there, and each is
  -- read, also when a link leads to one of them or to the folder around them.
  -- Where it does not they are one folder with both files in it: the counts
  -- are the same on every host.
  ---@param dir string
  ---@return integer? js Files of that language outside the source roots.
  local function js_outside(dir)
    local outer_ir = scan.scan(config.build(dir, { source = "lua", lua_root = "lua" }))
    return outer_ir.meta.outside and outer_ir.meta.outside.js
  end

  local sens = base .. "/casesens"
  module_file(sens .. "/lua/p/init.lua", "p", "P.")
  H.write(sens .. "/gen/Up/x.js", { "// x", "function x() {}" })
  H.write(sens .. "/gen/up/y.js", { "// y", "function y() {}" })
  eq(js_outside(sens), 2, "folders that differ in case alone are both read")
  vim.fn.mkdir(sens .. "/tools", "p")
  ok(H.link(H.canonical(sens) .. "/gen", sens .. "/tools/g", true), "a link to the folder around")
  eq(js_outside(sens), 2, "...and still are when a link leads to the folder around them")

  local sens_up = base .. "/casesens_up"
  module_file(sens_up .. "/lua/p/init.lua", "p", "P.")
  H.write(sens_up .. "/gen/b/y.js", { "// y", "function y() {}" })
  H.write(sens_up .. "/gen/B/x.js", { "// x", "function x() {}" })
  vim.fn.mkdir(sens_up .. "/gen/M", "p")
  ok(H.link(H.canonical(sens_up) .. "/gen/B", sens_up .. "/gen/M/l", true), "a link to one of them")
  eq(js_outside(sens_up), 2, "...and when a link leads to only one of them")

  -- The same in the map: a folder entered through a link keeps all it has,
  -- the folders that differ in case alone among it.
  local twins = base .. "/casetwins"
  module_file(twins .. "/lua/tw/Up/init.lua", "tw_up_cap", "CAP.")
  module_file(twins .. "/lua/tw/up/init.lua", "tw_up_low", "LOW.")
  if not safe_fs.folds_case(twins) then
    ok(
      H.link(H.canonical(twins) .. "/lua/tw", twins .. "/lua/a", true),
      "a link to a folder of both"
    )
    local twin_ir = scan.scan(config.build(twins, { source = "lua", lua_root = "lua" }))
    for _, id in ipairs({ "lua/tw/Up", "lua/tw/up", "lua/a/Up", "lua/a/up" }) do
      ok(twin_ir.nodes[id] ~= nil, id .. " is in the map")
    end
  end

  -- A link to a file in the place of one the walk looks for in every folder
  -- (`init.lua`, `README.md`, `@types/`): it is the only thing between that
  -- file and the map, so what it leads to is read if it stays in the project
  -- and none of it is if it leaves. A project of its own, and none of its
  -- folders is called `out`, which the walk leaves out by default.
  local mroot = base .. "/modlink"
  local mhere = H.canonical(mroot)
  module_file(mroot .. "/lua/real/init.lua", "real", "REAL-INIT-SUMMARY.")
  H.write(mroot .. "/lua/real/README.md", { "# real" })
  H.write(mroot .. "/lua/real/@types/shape.lua", { "---@class RealShape" })
  module_file(outside .. "/mod_init.lua", "leaked_init", "OUTSIDE-INIT-SUMMARY.")
  H.write(outside .. "/README.md", { "# OUTSIDE-README" })
  H.write(outside .. "/types/leaked.lua", { "---@class LeakedType" })
  vim.fn.mkdir(mroot .. "/lua/lk", "p")
  vim.fn.mkdir(mroot .. "/lua/inn", "p")
  if H.link(outside .. "/mod_init.lua", mroot .. "/lua/lk/init.lua", false) then
    ok(H.link(outside .. "/README.md", mroot .. "/lua/lk/README.md", false), "a README.md link out")
    ok(
      H.link(outside .. "/types", mroot .. "/lua/lk/@types", true),
      "a link out as the types folder"
    )
    ok(
      H.link(mhere .. "/lua/real/init.lua", mroot .. "/lua/inn/init.lua", false),
      "an init.lua link in"
    )
    ok(
      H.link(mhere .. "/lua/real/README.md", mroot .. "/lua/inn/README.md", false),
      "a README.md link in"
    )
    ok(
      H.link(mhere .. "/lua/real/@types", mroot .. "/lua/inn/@types", true),
      "a types folder link in"
    )
    local mod = scan.scan(config.build(mroot, { source = "lua", lua_root = "lua" }))
    local leaked = vim.json.encode(mod)
    eq(
      leaked:find("OUTSIDE-INIT-SUMMARY", 1, true),
      nil,
      "init.lua that is a link out: its summary is not read"
    )
    eq(leaked:find("leaked_init", 1, true), nil, "...nor its module name")
    eq(leaked:find("leaked.lua", 1, true), nil, "...nor the types folder that is a link out")
    local lk, inn = mod.nodes["lua/lk"], mod.nodes["lua/inn"]
    eq(lk.kind, "namespace", "init.lua that is a link out: the folder has no module file")
    eq(lk.module, nil, "...so no module name")
    eq(lk.readme, nil, "README.md that is a link out is not offered")
    eq(#lk.types, 0, "a types folder that is a link out has no members")
    eq(inn.module, "real", "init.lua that is a link in: still read")
    ok(inn.summary:find("REAL-INIT-SUMMARY", 1, true), "...with its summary: " .. inn.summary)
    eq(inn.readme, "lua/inn/README.md", "README.md that is a link in is offered")
    eq(#inn.types, 1, "a types folder that is a link in has its members")
  else
    ok(vim.fn.has("win32") == 1, "a file link could not be made on a platform that should allow it")
  end

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
      H.link(H.canonical(base .. "/cfg_in") .. "/real.json", base .. "/cfg_in/.docmap.json", false),
      "inside file link"
    )
    local inside = config.build(base .. "/cfg_in", { source = "lua", lua_root = "lua" })
    eq(inside.title, "FROM-LINKED-FILE", ".docmap.json that is a link inside: still read")
  else
    ok(vim.fn.has("win32") == 1, "a file link could not be made on a platform that should allow it")
  end

  vim.fn.delete(base, "rf")
end
