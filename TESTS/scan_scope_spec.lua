-- TESTS/scan_scope_spec.lua — `opts.exclude` and `opts.languages`.
--
-- The two things a *caller* says about a repository it did not write: which
-- paths are not its code, and which languages it wants read. Both are
-- policy, so both are wrong in the same direction if they fail quietly —
-- an exclude that does not exclude writes somebody's vendored tree into
-- their map, and a language filter that leaks into the next scan produces a
-- map missing every file of a language nobody switched off.
--
-- Fixtures on disk rather than strings: both options are about the *walk*,
-- and a walk needs directories. Same shape as `binding_conflict_spec.lua`.

return function(H)
  local eq, ok = H.eq, H.ok

  local registry = require("documentation.core.lang_registry")
  local scan = require("documentation.core.scan")
  local config = require("documentation.config")

  local root = (vim.fn.tempname():gsub("\\", "/"))
  local n = 0

  ---Build a tree and scan it.
  ---@param files table<string, string> Repo-relative path to contents.
  ---@param overrides table? Merged into `config.build`'s overrides.
  ---@return Documentation.IR
  ---@return Documentation.Opts
  local function scanned(files, overrides)
    n = n + 1
    local abs = ("%s/case%d"):format(root, n)
    for rel, body in pairs(files) do
      local path = abs .. "/" .. rel
      vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
      local fd = io.open(path, "w")
      if fd then
        fd:write(body)
        fd:close()
      end
    end
    local opts = config.build(abs, overrides)
    return scan.scan(opts), opts
  end

  ---Every node id in the IR, sorted.
  ---@param ir Documentation.IR
  ---@return string[]
  local function ids(ir)
    local out = {}
    for id in pairs(ir.nodes) do
      out[#out + 1] = id
    end
    table.sort(out)
    return out
  end

  ---@param ir Documentation.IR
  ---@param id string
  ---@return boolean
  local function has(ir, id)
    return ir.nodes[id] ~= nil
  end

  local LUA = "---@module 'x'\n--- A module.\nlocal M = {}\nreturn M\n"
  local JS = "/**\n * @module x\n * A module.\n */\nmodule.exports = {};\n"

  -- ---------------------------------------------------------------------
  -- `opts.exclude`: a path, and everything under it.
  -- ---------------------------------------------------------------------
  do
    local ir = scanned({
      ["lua/app/init.lua"] = LUA,
      ["lua/app/keep.lua"] = LUA,
      ["lua/app/generated/a.lua"] = LUA,
      ["lua/app/generated/deep/b.lua"] = LUA,
    }, { source = "lua/app", exclude = { "lua/app/generated" } })

    ok(has(ir, "lua/app/keep.lua"), "a file outside the excluded path is still scanned")
    ok(not has(ir, "lua/app/generated"), "the excluded directory is not a node")
    ok(not has(ir, "lua/app/generated/a.lua"), "nor is a file inside it")
    ok(not has(ir, "lua/app/generated/deep/b.lua"), "nor one nested below it")
  end

  -- **The separator is required.** This is the difference between excluding
  -- what was named and excluding whatever starts with the same letters, and
  -- it is the bug a `string.find(rel, entry, 1, true)` implementation has.
  do
    local ir = scanned({
      ["lua/app/init.lua"] = LUA,
      ["lua/app/gen/a.lua"] = LUA,
      ["lua/app/generated/b.lua"] = LUA,
    }, { source = "lua/app", exclude = { "lua/app/gen" } })

    ok(not has(ir, "lua/app/gen/a.lua"), "`lua/app/gen` excludes `lua/app/gen`")
    ok(has(ir, "lua/app/generated/b.lua"), "and does not exclude `lua/app/generated`")
  end

  -- A single file, not only a directory.
  do
    local ir = scanned({
      ["lua/app/init.lua"] = LUA,
      ["lua/app/keep.lua"] = LUA,
      ["lua/app/drop.lua"] = LUA,
    }, { source = "lua/app", exclude = { "lua/app/drop.lua" } })

    ok(has(ir, "lua/app/keep.lua"))
    ok(not has(ir, "lua/app/drop.lua"), "one named file is excludable too")
  end

  -- **An excluded file is not an unclaimed one.** The count feeds the
  -- report line "N files of a language this map contains none of", and a
  -- file the reader declared out of scope must not come back as a complaint
  -- about their repository.
  do
    local ir = scanned({
      ["lua/app/init.lua"] = LUA,
      ["lua/app/vendorish/thing.rb"] = "# nothing\n",
    }, { source = "lua/app", exclude = { "lua/app/vendorish" } })

    eq((ir.meta.unclaimed or {}).rb, nil, "an excluded extension is not counted as unreadable")
  end

  -- No exclude is the same tree as before the option existed.
  do
    local files = {
      ["lua/app/init.lua"] = LUA,
      ["lua/app/keep.lua"] = LUA,
    }
    local with = scanned(files, { source = "lua/app", exclude = {} })
    local without = scanned(files, { source = "lua/app" })
    eq(#ids(with), #ids(without), "an empty exclude list changes nothing")
  end

  -- ---------------------------------------------------------------------
  -- `opts.languages`: an allow list over the backends.
  -- ---------------------------------------------------------------------
  do
    local ir = scanned({
      ["src/mod.lua"] = LUA,
      ["src/mod.js"] = JS,
    }, { source = "src", languages = { "lua" } })

    ok(has(ir, "src/mod.lua"), "the named language is read")
    ok(not has(ir, "src/mod.js"), "every other backend is invisible to this scan")
  end

  -- **`nil` and `{}` both mean all of them**, which is the reading that
  -- cannot lose data: an empty selection is a caller with nothing to say,
  -- and taking it as "read nothing" produces an empty map that looks like a
  -- broken repository.
  do
    local files = { ["src/mod.lua"] = LUA, ["src/mod.js"] = JS }
    local empty = scanned(files, { source = "src", languages = {} })
    ok(has(empty, "src/mod.lua") and has(empty, "src/mod.js"), "`{}` reads everything")
  end

  -- **An unknown name reads nothing rather than everything.** Dropping it
  -- would make a typo behave like an empty list, which is the opposite of
  -- what was asked; `lang_registry.unknown` is how a caller says so.
  do
    eq(#registry.unknown({ "golang", "lua" }), 1, "one of the two is not a backend")
    eq(registry.unknown({ "golang", "lua" })[1], "golang")
    eq(#registry.unknown({ "lua", "go" }), 0, "and both of these are")
    eq(#registry.unknown(nil), 0, "nil is not an error")

    local ir = scanned({ ["src/mod.lua"] = LUA }, { source = "src", languages = { "golang" } })
    ok(not has(ir, "src/mod.lua"), "a misspelled filter is honoured, not ignored")
  end

  -- ---------------------------------------------------------------------
  -- The reset discipline, which is the half that fails silently.
  --
  -- **Reset at the start of a scan, not cleared at the end**, and the
  -- difference is deliberate: `check.lua` runs *after* `scan()` and asks
  -- the registry the same question the walk did. Clearing the filter when
  -- the walk finished would make the checks disagree with the map they are
  -- checking -- `missing-module-tag` firing for a language the scan was
  -- told to ignore. So the filter outlives its scan and the *next* scan is
  -- what restores it, exactly as `snippet.MAX_LINES` and
  -- `bindings.WRAPPERS` already work.
  --
  -- `:DocBrowse` bouncing between two repositories in one session is the
  -- case that makes it matter: without the reset, the first repository's
  -- filter narrows the second one's map and nothing anywhere says why.
  -- ---------------------------------------------------------------------
  do
    scanned({ ["src/mod.lua"] = LUA }, { source = "src", languages = { "lua" } })
    ok(registry.ENABLED ~= nil, "the filter outlives its own scan, so check.lua agrees with it")
  end

  do
    -- Deliberately in this order: a narrow scan, then a scan that says
    -- nothing. The second must see everything.
    scanned({ ["src/a.lua"] = LUA }, { source = "src", languages = { "lua" } })
    local ir = scanned({ ["src/mod.lua"] = LUA, ["src/mod.js"] = JS }, { source = "src" })
    ok(
      has(ir, "src/mod.js"),
      "a later scan with no filter reads every language, not the previous scan's subset"
    )
  end

  -- ---------------------------------------------------------------------
  -- The filter reaches source *detection*, not only the walk.
  --
  -- Detection is the walk's input: a switched-off backend that still got to
  -- name the starting directory would send the walk somewhere it is not
  -- allowed to read anything, and the map would come back empty with
  -- nothing to explain it.
  -- ---------------------------------------------------------------------
  do
    local abs = ("%s/detect"):format(root)
    for rel, body in pairs({ ["lua/app/init.lua"] = LUA, ["src/index.js"] = JS }) do
      local path = abs .. "/" .. rel
      vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
      local fd = io.open(path, "w")
      if fd then
        fd:write(body)
        fd:close()
      end
    end

    local both = config.detect_source(abs)
    ok(#both >= 2, "unfiltered detection finds both roots, found " .. #both)

    local lua_only = config.detect_source(abs, { "lua" })
    eq(#lua_only, 1, "restricted to Lua, only the Lua root is offered")
    eq(lua_only[1], "lua/app")

    eq(registry.ENABLED, nil, "detect_source restores the filter it borrowed")
  end

  -- ---------------------------------------------------------------------
  -- `report()` is the capability handshake and must not shrink.
  --
  -- A host asks it "what can this build read". If a per-project filter
  -- changed that answer, the host would conclude the binary cannot read a
  -- language it can read perfectly well.
  -- ---------------------------------------------------------------------
  do
    local before = #registry.report()
    registry.set_enabled({ "lua" })
    eq(#registry.report(), before, "the handshake answers for the build, not for one scan")
    eq(#registry.all(), 1, "while the scan-facing list does narrow")
    ok(#registry.all(true) > 1, "and `all(true)` still answers for the build")
    registry.set_enabled(nil)
    eq(#registry.all(), before, "cleared again")
  end
end
