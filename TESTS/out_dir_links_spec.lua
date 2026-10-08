-- TESTS/out_dir_links_spec.lua — the engine does not write the map through a
-- link, and does not read the committed one through a link that leaves the
-- project.
--
-- `out_dir_traversal_spec.lua` pins the string checks (`..`, a leading `/`, a
-- drive letter). A link makes a perfectly clean string lead anywhere, so
-- these run the **real** write routine (`documentation.generate`,
-- `write_artifacts`, `write_pdf_artifact`) and the **real** `--check` against
-- a real project whose output path goes through a real link -- a symlink, or
-- a directory junction on Windows (`H.link`) -- and then look at the places
-- the link leads to.
--
-- The file the link leads to is given known content first, and each case
-- ends by checking that content is as it was and that nothing new appeared
-- beside it. "The call raised" alone would pass a version that raised *after*
-- writing.

-- luacheck: ignore 122
-- (`capture` below swaps `io.stdout`/`io.stderr` to read what `cli.run` says,
-- and puts them back.)
return function(H)
  local eq, ok = H.eq, H.ok
  local docmap = require("documentation")
  local config = require("documentation.config")
  local cli = require("documentation.core.cli")

  local function slashed(p)
    return (p:gsub("\\", "/"))
  end

  local bases = {}

  ---A project and, next to it, a directory the project must never write into.
  local function project(label)
    local base = slashed(vim.fn.tempname()) .. "_" .. label
    bases[#bases + 1] = base
    local root = base .. "/repo"
    local outside = base .. "/outside"
    H.write(root .. "/lua/t/init.lua", { "---@module 't'", "local M = {}", "return M" })
    H.write(outside .. "/map/index.html", { "VICTIM-HTML" })
    H.write(outside .. "/map/module_map.json", { "VICTIM-JSON" })
    H.write(outside .. "/map/overview.md", { "VICTIM-MD" })
    return root, outside
  end

  local function opts_for(root, out_dir, extra)
    return vim.tbl_extend("force", {
      root = root,
      source = "lua/t",
      lua_root = "lua",
      out_dir = out_dir,
    }, extra or {})
  end

  local function generate(root, out_dir, extra)
    return pcall(docmap.generate, opts_for(root, out_dir, extra))
  end

  ---The directory the link leads to is exactly as it was.
  local function assert_untouched(outside, label)
    eq(H.slurp(outside .. "/map/index.html"), "VICTIM-HTML\n", label .. ": index.html")
    eq(H.slurp(outside .. "/map/module_map.json"), "VICTIM-JSON\n", label .. ": module_map.json")
    eq(H.slurp(outside .. "/map/overview.md"), "VICTIM-MD\n", label .. ": overview.md")
    local names = {}
    for name in vim.fs.dir(outside .. "/map") do
      names[#names + 1] = name
    end
    table.sort(names)
    eq(
      table.concat(names, ","),
      "index.html,module_map.json,overview.md",
      label .. ": nothing new appeared there"
    )
  end

  ---Run `fn` with stdout and stderr captured. Both are put back whatever
  ---happens: the runner in this process still has to print.
  local function capture(fn)
    local real_out, real_err = io.stdout, io.stderr
    local out, err = {}, {}
    local function sink(into)
      return {
        write = function(self, ...)
          for _, part in ipairs({ ... }) do
            into[#into + 1] = tostring(part)
          end
          return self
        end,
      }
    end
    io.stdout, io.stderr = sink(out), sink(err)
    local ran, result = pcall(fn)
    io.stdout, io.stderr = real_out, real_err
    if not ran then
      error(result, 0)
    end
    return result, table.concat(out), table.concat(err)
  end

  -- ---------------------------------------------------------------------
  -- The control: a plain directory still works, so every refusal below is
  -- about the link and not about the setup.
  -- ---------------------------------------------------------------------
  do
    local root = project("plain")
    local generated, err = generate(root, "docs/map")
    ok(generated, "control: a plain out_dir generates: " .. tostring(err))
    ok(H.slurp(root .. "/docs/map/module_map.json") ~= nil, "control: ...and the file is there")
  end

  -- ---------------------------------------------------------------------
  -- The output directory itself is a link.
  -- ---------------------------------------------------------------------
  do
    local root, outside = project("dir_link")
    vim.fn.mkdir(root .. "/docs", "p")
    local made, how = H.link(outside .. "/map", root .. "/docs/map", true)
    ok(made, "dir link: a link can be made here: " .. tostring(how))

    local generated, err = generate(root, "docs/map")
    eq(generated, false, "dir link: `docs/map` is a link -> generate refuses")
    ok(
      tostring(err):find("refusing to write the map", 1, true),
      "dir link: ...with a message that says so: " .. tostring(err)
    )
    ok(
      tostring(err):find("docs/map", 1, true),
      "dir link: ...and names the link, not just 'a link': " .. tostring(err)
    )
    assert_untouched(outside, "dir link")
  end

  -- ---------------------------------------------------------------------
  -- `out_dir` set the way a hostile repository sets it: a `.docmap.json` in
  -- the tree, naming a link that is also in the tree. Through the real
  -- config loader, so what is tested is the path a cloned repository takes.
  -- ---------------------------------------------------------------------
  do
    local root, outside = project("docmap_json")
    H.write(root .. "/.docmap.json", { '{ "out_dir": "outlink", "source": "lua/t" }' })
    local made, how = H.link(outside .. "/map", root .. "/outlink", true)
    ok(made, ".docmap.json: a link can be made here: " .. tostring(how))

    local built = config.build(root, { lua_root = "lua" })
    eq(built.out_dir, "outlink", ".docmap.json: the repository's out_dir is what the engine has")
    local generated, err = pcall(docmap.generate, built)
    eq(generated, false, ".docmap.json: an out_dir that is a link -> generate refuses")
    ok(tostring(err):find("outlink", 1, true), ".docmap.json: ...and names it: " .. tostring(err))
    assert_untouched(outside, ".docmap.json")
  end

  -- ---------------------------------------------------------------------
  -- A link *above* the output directory: `docs` is the link, `docs/map` is a
  -- real directory on the other side of it.
  -- ---------------------------------------------------------------------
  do
    local root, outside = project("parent_link")
    H.write(outside .. "/docs/map/index.html", { "VICTIM-HTML" })
    H.write(outside .. "/docs/map/module_map.json", { "VICTIM-JSON" })
    H.write(outside .. "/docs/map/overview.md", { "VICTIM-MD" })
    local made = H.link(outside .. "/docs", root .. "/docs", true)
    ok(made, "parent link: a link can be made here")

    local generated, err = generate(root, "docs/map")
    eq(generated, false, "parent link: a link above the output directory -> generate refuses")
    ok(
      tostring(err):find("docs", 1, true),
      "parent link: ...naming the component: " .. tostring(err)
    )
    eq(
      H.slurp(outside .. "/docs/map/index.html"),
      "VICTIM-HTML\n",
      "parent link: ...and what lies behind it is untouched"
    )
    eq(vim.fn.filereadable(outside .. "/docs/map/coverage.svg"), 0, "parent link: nothing new")
  end

  -- ---------------------------------------------------------------------
  -- A link that stays inside the project is a link all the same: the
  -- writer's rule is that none is allowed, not that none may leave.
  -- ---------------------------------------------------------------------
  do
    local root = project("inside_link")
    vim.fn.mkdir(root .. "/real_map", "p")
    vim.fn.mkdir(root .. "/docs", "p")
    local made = H.link(root .. "/real_map", root .. "/docs/map", true)
    ok(made, "inside link: a link can be made here")
    local generated, err = generate(root, "docs/map")
    eq(generated, false, "inside link: a link that stays in the project is refused for writing")
    ok(tostring(err):find("docs/map", 1, true), "inside link: ...naming it: " .. tostring(err))
    eq(vim.fn.filereadable(root .. "/real_map/module_map.json"), 0, "inside link: nothing written")
  end

  -- ---------------------------------------------------------------------
  -- The directory is plain; one of the files in it is a link. Writing that
  -- file would replace what it leads to -- and the files before it in the
  -- loop must not have been written either: a refusal leaves the tree as it
  -- was.
  -- ---------------------------------------------------------------------
  do
    local root, outside = project("file_link")
    vim.fn.mkdir(root .. "/docs/map", "p")
    H.write(outside .. "/target.txt", { "VICTIM-FILE" })
    local made = H.link(outside .. "/target.txt", root .. "/docs/map/index.html", false)
    if made then
      local generated, err = generate(root, "docs/map")
      eq(generated, false, "file link: an artifact file that is a link -> generate refuses")
      ok(
        tostring(err):find("docs/map/index.html", 1, true),
        "file link: ...naming the file: " .. tostring(err)
      )
      eq(
        H.slurp(outside .. "/target.txt"),
        "VICTIM-FILE\n",
        "file link: what it leads to is intact"
      )
      eq(
        vim.fn.filereadable(root .. "/docs/map/module_map.json"),
        0,
        "file link: no sibling was written before the refusal"
      )
    else
      -- Windows without the symlink privilege: a file link cannot be made,
      -- so there is nothing to refuse. The directory cases above carry it.
      ok(
        vim.fn.has("win32") == 1,
        "file link: could not be made on a platform that should allow it"
      )
    end
  end

  -- The badge is an artifact only some runs write; the check is on whatever
  -- the run writes, not on a list kept beside it.
  do
    local root, outside = project("badge_link")
    vim.fn.mkdir(root .. "/docs/map", "p")
    H.write(outside .. "/badge.svg", { "VICTIM-SVG" })
    local made = H.link(outside .. "/badge.svg", root .. "/docs/map/coverage.svg", false)
    if made then
      local generated = generate(root, "docs/map", { badge = true })
      eq(generated, false, "badge: coverage.svg that is a link -> generate refuses")
      eq(H.slurp(outside .. "/badge.svg"), "VICTIM-SVG\n", "badge: ...and its target is intact")
      eq(
        vim.fn.filereadable(root .. "/docs/map/index.html"),
        0,
        "badge: ...and nothing else was written"
      )
      -- Without the badge that file is not one this run writes, so the link
      -- beside the real artifacts is not in the way.
      local without = generate(root, "docs/map", { badge = false })
      ok(without, "badge: a run that does not write coverage.svg is not stopped by it")
      eq(H.slurp(outside .. "/badge.svg"), "VICTIM-SVG\n", "badge: ...and still leaves it alone")
    end
  end

  -- ---------------------------------------------------------------------
  -- `write_pdf_artifact`: asynchronous, so it reports through a callback,
  -- and it took `opts.out_dir` as it came.
  -- ---------------------------------------------------------------------
  do
    local root, outside = project("pdf")
    vim.fn.mkdir(root .. "/docs", "p")
    H.link(outside .. "/map", root .. "/docs/map", true)
    local o = opts_for(root, "docs/map")
    local ir, findings = docmap.scan_full(o)

    local created = 0
    package.loaded["pdfport"] = {
      can_create = function()
        return true
      end,
      create = function(call)
        created = created + 1
        call.__callback({ status = "ok", path = call.output })
      end,
    }

    local got
    docmap.write_pdf_artifact(ir, findings, o, function(is_ok, msg)
      got = { ok = is_ok, msg = msg }
    end)
    eq(got.ok, false, "pdf: an out_dir that is a link -> reports failure")
    ok(tostring(got.msg):find("refusing", 1, true), "pdf: ...and says why: " .. tostring(got.msg))
    eq(created, 0, "pdf: ...without asking pdfport to write anything")

    got = nil
    docmap.write_pdf_artifact(ir, findings, opts_for(root, "../escape"), function(is_ok, msg)
      got = { ok = is_ok, msg = msg }
    end)
    eq(got.ok, false, "pdf: an out_dir with `..` -> reports failure")
    ok(
      tostring(got.msg):find("not a safe relative path", 1, true),
      "pdf: ...as the other writer does: " .. tostring(got.msg)
    )
    eq(created, 0, "pdf: ...without asking pdfport to write anything")

    local plain_root = project("pdf_plain")
    local plain_opts = opts_for(plain_root, "docs/map")
    local pir, pfindings = docmap.scan_full(plain_opts)
    docmap.write_pdf_artifact(pir, pfindings, plain_opts, function(is_ok, msg)
      got = { ok = is_ok, msg = msg }
    end)
    ok(got.ok, "pdf: a plain out_dir still works: " .. tostring(got.msg))
    eq(created, 1, "pdf: ...and reaches pdfport once")
    package.loaded["pdfport"] = nil
  end

  -- ---------------------------------------------------------------------
  -- `--check` reads the committed map. Through the real CLI function.
  -- ---------------------------------------------------------------------

  ---Run `--check` for `root` with `out_dir`, the way the CLI would.
  local function check(root, out_dir)
    local built = config.build(root, { source = "lua/t", lua_root = "lua", out_dir = out_dir })
    return capture(function()
      return cli.run(built, { "--check" })
    end)
  end

  -- The map a repository committed, read back through a link that stays in
  -- the project: still works.
  do
    local root = project("check_inside")
    local built = config.build(root, { source = "lua/t", lua_root = "lua", out_dir = "docs/map" })
    capture(function()
      return docmap.generate(built)
    end)
    local code, _, err = check(root, "docs/map")
    eq(code, 0, "check: a freshly generated map is up to date: " .. err)

    -- A hidden directory, because the prose corpus (every `.md` outside
    -- `out_dir`) skips those: the map must differ only by where it is read.
    vim.uv.fs_rename(root .. "/docs/map", root .. "/.real_map")
    local made = H.link(H.canonical(root) .. "/.real_map", root .. "/docs/map", true)
    ok(made, "check: a link inside the project can be made here")
    local out
    code, out, err = check(root, "docs/map")
    eq(
      code,
      0,
      "check: the same map behind a link that stays in the project is still read: " .. err
    )
    ok(out:find("up to date", 1, true), "check: ...and reported up to date")
  end

  -- The directory is a link that leaves the project.
  do
    local root, outside = project("check_dir_link")
    vim.fn.mkdir(root .. "/docs", "p")
    H.link(outside .. "/map", root .. "/docs/map", true)
    local code, _, err = check(root, "docs/map")
    eq(code, 1, "check: a map directory that leaves the project is not read")
    ok(err:find("refusing to read", 1, true), "check: ...and the message says so: " .. err)
    ok(not err:find("VICTIM", 1, true), "check: ...and nothing of the file behind it is printed")
    assert_untouched(outside, "check dir link")
  end

  -- One file of the map is a link that leaves the project: the stale report
  -- prints an excerpt of the committed side, which is exactly where another
  -- file's content would have come out.
  do
    local root, outside = project("check_file_link")
    vim.fn.mkdir(root .. "/docs/map", "p")
    H.write(outside .. "/target.json", { "SECRET-CONTENT-NOT-A-MAP" })
    local made = H.link(outside .. "/target.json", root .. "/docs/map/module_map.json", false)
    if made then
      local code, _, err = check(root, "docs/map")
      eq(code, 1, "check: a map file that is a link out of the project is not read")
      ok(err:find("refusing to read", 1, true), "check: ...and the message says so: " .. err)
      ok(not err:find("SECRET", 1, true), "check: ...and none of the file it led to is printed")
    else
      ok(vim.fn.has("win32") == 1, "check: could not make a file link on a platform that should")
    end
  end

  -- `--check` used to read `out_dir` unvetted.
  do
    local root = project("check_unsafe")
    local code, _, err = check(root, "../elsewhere")
    eq(code, 1, "check: an out_dir with `..` is refused")
    ok(err:find("not a safe relative path", 1, true), "check: ...as the writer does: " .. err)
  end

  for _, base in ipairs(bases) do
    vim.fn.delete(base, "rf")
  end
end
