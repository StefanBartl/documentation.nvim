-- TESTS/tools_links_spec.lua -- the install manifest (`docs/install.json`,
-- `docs/INSTALL.md`) is read through `core/safe_fs.lua`.
--
-- `core/tools.lua` used to hand `<root>/<install_dir>/install.json` to
-- `lib.nvim.deps.spec.load`, a bare `io.open` + `read("*a")`. Both the file and
-- `install_dir` (a `.docmap.json` key) are the repository's to choose, so a
-- link, or a `..`, led it to somebody else's manifest -- whose tool names land in
-- the committed `module_map.json` -- and a link to a device never ended.
--
-- Each case has a manifest outside the project with a marker in it, and a twin
-- that stays inside, so "refuse everything" cannot pass. `safe_fs.read` and its
-- size bound are checked on their own at the end.

-- luacheck: ignore 122
-- (The size bound is checked with a stand-in for `io.open`, put back after.)
return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("documentation.config")
  local docmap = require("documentation")
  local tools = require("documentation.core.tools")
  local safe_fs = require("documentation.core.safe_fs")

  local base = (vim.fn.tempname():gsub("\\", "/")) .. "_tools_links"
  local root = base .. "/repo"
  local outside = base .. "/outside"

  local function manifest(bin)
    return {
      vim.json.encode({ tools = { { bin = bin, why = bin .. "-WHY", pkg = { apt = "x" } } } }),
    }
  end
  local function markdown(bin)
    return {
      "# Install",
      "",
      "```install-tool",
      "bin: " .. bin,
      "required: false",
      'why: "' .. bin .. '-WHY"',
      "pkg:",
      "  apt: x",
      "```",
    }
  end

  H.write(root .. "/lua/t/init.lua", { "---@module 't'", "local M = {}", "return M" })
  H.write(root .. "/inside/install.json", manifest("INSIDE-BIN"))
  H.write(root .. "/inside_md/INSTALL.md", markdown("INSIDE-MD-BIN"))
  H.write(root .. "/plain/install.json", manifest("PLAIN-BIN"))
  H.write(outside .. "/install/install.json", manifest("OUTSIDE-BIN"))
  H.write(outside .. "/install/INSTALL.md", markdown("OUTSIDE-MD-BIN"))

  local here = H.canonical(root)
  ok(H.link(outside .. "/install", root .. "/dir_out", true), "a directory link out can be made")
  ok(H.link(here .. "/inside", root .. "/dir_in", true), "a directory link inside can be made")
  -- File links need a privilege on Windows that a test account may not have.
  local file_links = vim.fn.has("win32") == 0
  if file_links then
    vim.fn.mkdir(root .. "/file_out", "p")
    vim.fn.mkdir(root .. "/file_out_md", "p")
    vim.fn.mkdir(root .. "/file_in", "p")
    vim.fn.mkdir(root .. "/file_in_md", "p")
    ok(
      H.link(outside .. "/install/install.json", root .. "/file_out/install.json", false),
      "a file link out can be made"
    )
    ok(
      H.link(outside .. "/install/INSTALL.md", root .. "/file_out_md/INSTALL.md", false),
      "a markdown file link out can be made"
    )
    ok(
      H.link(here .. "/inside/install.json", root .. "/file_in/install.json", false),
      "a file link inside can be made"
    )
    ok(
      H.link(here .. "/inside_md/INSTALL.md", root .. "/file_in_md/INSTALL.md", false),
      "a markdown file link inside can be made"
    )
  end

  local function first_bin(result)
    return result and result.tools[1] and result.tools[1].bin or nil
  end

  -- ------------------------------------------------------ the folder is a link
  local plain = tools.resolve(root, "plain")
  eq(first_bin(plain), "PLAIN-BIN", "a plain folder is read")
  eq(plain.source, "plain/install.json", "...and the source is the written, relative path")

  eq(tools.resolve(root, "dir_out"), nil, "a folder that is a link out of the project is no folder")
  local inside = tools.resolve(root, "dir_in")
  eq(first_bin(inside), "INSIDE-BIN", "one that stays inside is read")
  eq(inside.source, "dir_in/install.json", "...as written, not as resolved")

  -- ------------------------------------------------------------- `..` climbs out
  eq(
    tools.resolve(root, "../outside/install"),
    nil,
    "an install_dir that climbs out of the project is not read"
  )
  eq(tools.resolve(root, "inside/../../outside/install"), nil, "...whatever it goes through first")
  eq(
    first_bin(tools.resolve(root, "inside/../plain")),
    "PLAIN-BIN",
    "a `..` that stays inside is fine"
  )

  -- ----------------------------------------------------- the file is a link
  if file_links then
    eq(tools.resolve(root, "file_out"), nil, "install.json as a link out is not read")
    eq(tools.resolve(root, "file_out_md"), nil, "...nor INSTALL.md, the fallback")
    eq(
      first_bin(tools.resolve(root, "file_in")),
      "INSIDE-BIN",
      "install.json as a link inside is read"
    )
    eq(first_bin(tools.resolve(root, "file_in_md")), "INSIDE-MD-BIN", "...and INSTALL.md as one")
    -- A refused install.json does not shadow a usable INSTALL.md beside it.
    H.link(outside .. "/install/install.json", root .. "/inside_md/install.json", false)
    local fallback = tools.resolve(root, "inside_md")
    eq(
      first_bin(fallback),
      "INSIDE-MD-BIN",
      "a link out as install.json falls through to INSTALL.md"
    )
    eq(fallback.source, "inside_md/INSTALL.md", "...and the source names the file that was read")
  end

  -- ---------------------------------------------------------- what is said about it
  safe_fs.clear_skipped()
  tools.resolve(root, "dir_out")
  local skipped = {}
  for _, s in ipairs(safe_fs.skipped) do
    skipped[s.path] = s.why
  end
  eq(skipped["dir_out/install.json"], "leaves", "a link left alone is noted, with its reason")
  safe_fs.clear_skipped()
  tools.resolve(root, "../outside/install")
  eq(safe_fs.skipped[1] and safe_fs.skipped[1].why, "leaves", "...as is a `..` that leaves")
  safe_fs.clear_skipped()
  tools.resolve(root, "dir_in")
  eq(#safe_fs.skipped, 0, "...and one that stays inside is not")

  -- --------------------------------------------------- through the real scan
  vim.fn.mkdir(root .. "/docs", "p")
  local opts = config.build(root, { source = "lua/t", lua_root = "lua", install_dir = "dir_out" })
  local ir = docmap.scan_full(opts)
  eq(ir.tools, nil, "scan_full: a manifest behind a link out is no manifest")
  eq(docmap.to_json(ir):find("OUTSIDE", 1, true), nil, "...and nothing of it is in module_map.json")
  local climbing = docmap.scan_full(
    config.build(root, { source = "lua/t", lua_root = "lua", install_dir = "../outside/install" })
  )
  eq(climbing.tools, nil, "scan_full: ...nor one named with `..`")
  local in_ir = docmap.scan_full(
    config.build(root, { source = "lua/t", lua_root = "lua", install_dir = "dir_in" })
  )
  eq(first_bin(in_ir.tools), "INSIDE-BIN", "scan_full: one behind a link that stays inside is read")

  -- ------------------------------------------------------------ the size bound
  H.write(root .. "/big/install.json", manifest("BIG-BIN"))
  local length = #table.concat(manifest("BIG-BIN"), "\n") + 1 -- writefile adds the newline
  local kept = tools.MAX_BYTES
  local function resolve_with(limit, dir)
    tools.MAX_BYTES = limit
    local done, result = pcall(tools.resolve, root, dir)
    tools.MAX_BYTES = kept
    assert(done, result)
    return result
  end
  eq(first_bin(resolve_with(length, "big")), "BIG-BIN", "a manifest of exactly the limit is read")
  local large = resolve_with(length - 1, "big")
  ok(large ~= nil, "a manifest over the limit is answered, not dropped")
  eq(#large.tools, 0, "...but nothing of it is read")
  eq(large.source, "big/install.json", "...it names the file")
  ok(
    tostring(large.errors[1] and large.errors[1].message):find("larger than", 1, true) ~= nil,
    "...and says why: " .. vim.inspect(large.errors)
  )
  local empty = resolve_with(10, "empty_dir")
  eq(empty, nil, "a folder without a manifest is still none")
  H.write(root .. "/blank/install.json", {})
  local blank = resolve_with(10, "blank")
  ok(
    blank ~= nil and #blank.errors > 0,
    "an empty manifest is read (as an invalid one), not dropped"
  )

  -- ------------------------------------------------------ safe_fs.read itself
  local payload = "0123456789"
  H.write(root .. "/ten.txt", { payload })
  local ten = root .. "/ten.txt"
  eq((safe_fs.read(root, ten)), payload .. "\n", "read: without a limit the whole file")
  eq((safe_fs.read(root, ten, 11)), payload .. "\n", "read: a file of exactly the limit")
  local cut, kind, why = safe_fs.read(root, ten, 10)
  eq(cut, nil, "read: a file over the limit gives no content, not a cut one")
  eq(kind, "large", "read: ...and says it is too large")
  eq(why, "larger than 10 bytes", "read: ...with the limit")
  H.write(root .. "/nothing.txt", {})
  local nothing = safe_fs.read(root, root .. "/nothing.txt", 10)
  eq(nothing, "", "read: an empty file is empty, not missing")
  local _, absent = safe_fs.read(root, root .. "/nope.txt", 10)
  eq(absent, "missing", "read: a file that is not there is missing")
  local _, directory = safe_fs.read(root, root .. "/plain", 10)
  eq(directory, nil, "read: a directory is neither content nor missing")
  local _, refused = safe_fs.read(root, root .. "/dir_out/install.json", 10)
  eq(refused, "refused", "read: a link out is refused whatever the limit")

  -- The bound is on what is read, not only on what is kept: a device that never
  -- ends (`/dev/zero` behind a name the repository chose) must not be slurped.
  -- A stand-in for the file records what it is asked for.
  local real_open, asked = io.open, {}
  io.open = function(path, mode)
    if path:sub(-8) ~= "/ten.txt" then
      return real_open(path, mode)
    end
    return {
      read = function(_, n)
        asked[#asked + 1] = n
        if type(n) ~= "number" then
          error("an unbounded read")
        end
        return ("x"):rep(math.min(n, 3))
      end,
      close = function() end,
    }
  end
  local bounded, bounded_err = pcall(safe_fs.read, root, ten, 10)
  io.open = real_open
  assert(bounded, bounded_err)
  eq(asked[1], 11, "read: asks for one byte more than the limit, never for the whole file")

  vim.fn.delete(base, "rf")
end
