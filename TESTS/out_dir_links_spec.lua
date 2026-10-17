-- TESTS/out_dir_links_spec.lua — the engine does not write the map through a
-- link, and does not read the committed one through a link that leaves the
-- project. The same rule holds for the other files a run writes outside the
-- map directory (`--sarif=`, `docs/BINDINGS.md`), and a refusal to read has an
-- exit code of its own.
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

  ---Run `--check` (and `extra` flags) for `root` with `out_dir`, the way the CLI would.
  local function check(root, out_dir, extra)
    local built = config.build(root, { source = "lua/t", lua_root = "lua", out_dir = out_dir })
    local argv = vim.list_extend({ "--check" }, extra or {})
    return capture(function()
      return cli.run(built, argv)
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
    eq(code, 2, "check: a map directory that leaves the project is refused, not 'stale' (1)")
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
      eq(code, 2, "check: a map file that is a link out of the project is refused, not 'stale'")
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
    eq(code, 2, "check: an out_dir with `..` is refused, not 'stale'")
    ok(err:find("not a safe relative path", 1, true), "check: ...as the writer does: " .. err)
  end

  -- ---------------------------------------------------------------------
  -- A refusal is not a verdict, and `--lenient` does not turn it into one.
  --
  -- docmap-desktop asks "is the map current?" with `--check --lenient` and
  -- reads the exit code as staleness and nothing else. A map that cannot be
  -- read must not share the code of one that is out of date: regenerating
  -- fixes the second and not the first.
  -- ---------------------------------------------------------------------
  do
    local root, outside = project("lenient_refused")
    vim.fn.mkdir(root .. "/docs", "p")
    H.link(outside .. "/map", root .. "/docs/map", true)
    local code, _, err = check(root, "docs/map", { "--lenient" })
    eq(code, 2, "lenient: a link that leaves the project is still a refusal")
    ok(err:find("refusing to read", 1, true), "lenient: ...and says so: " .. err)

    local unsafe_root = project("lenient_unsafe")
    code = check(unsafe_root, "../elsewhere", { "--lenient" })
    eq(code, 2, "lenient: an unsafe out_dir is still a refusal")
  end

  do
    local root = project("lenient_stale")
    local built = config.build(root, { source = "lua/t", lua_root = "lua", out_dir = "docs/map" })
    capture(function()
      return docmap.generate(built)
    end)
    H.write(root .. "/docs/map/overview.md", { "NOT THE GENERATED MAP" })
    local code, _, err = check(root, "docs/map", { "--lenient" })
    eq(code, 1, "lenient: a map that is out of date is the exit code 1, as ever")
    ok(err:find("Module map is stale", 1, true), "lenient: ...and says so: " .. err)
  end

  -- ---------------------------------------------------------------------
  -- `--sarif=<path>` is a write of its own. It was a plain `io.open`, so a
  -- link named like the report -- or standing for a directory on the way --
  -- had the run overwrite whatever it led to.
  --
  -- Through the real `cli.run`, from inside the project as CI runs it (the
  -- path is relative to where the run starts), in `--check` and in a plain
  -- generate: they reach the write from different places.
  -- ---------------------------------------------------------------------
  local function build(root)
    return config.build(root, { source = "lua/t", lua_root = "lua", out_dir = "docs/map" })
  end

  ---`cli.run` over `built` with `argv`, started in the project. The working
  ---directory is put back whatever happens.
  local function run_cli(built, argv)
    local old = vim.fn.getcwd()
    vim.fn.chdir(built.root)
    local ran, code, out, err = pcall(capture, function()
      return cli.run(built, argv)
    end)
    vim.fn.chdir(old)
    if not ran then
      error(code, 0)
    end
    return code, out, err
  end

  -- ---------------------------------------------------------------------
  -- A generate refusal, through the real `cli.run`: the one line SECURITY.md
  -- shows, exit 2 like `--check`'s refusals, and the run's list of links not
  -- followed still printed. It used to escape `cli.run` as a Lua error, which
  -- the standalone binary printed with a `[string ...]:N:` prefix and a stack
  -- traceback, exit 1, and the links list was lost.
  -- ---------------------------------------------------------------------
  do
    local root, outside = project("cli_generate_refused")
    vim.fn.mkdir(root .. "/docs", "p")
    ok(H.link(outside .. "/map", root .. "/docs/map", true), "cli generate: a link can be made")
    H.write(outside .. "/src/x.lua", { "return {}" })
    ok(
      H.link(outside .. "/src", root .. "/lua/t/leaving", true),
      "cli generate: a source link can be made"
    )
    local code, out, err = run_cli(build(root), {})
    eq(code, 2, "cli generate: a refusal to write the map is exit 2: " .. err)
    ok(
      err:find("\ndocmap: refusing to write the map: docs/map is a link", 1, true),
      "cli generate: ...one line that starts with the refusal: " .. err
    )
    ok(not err:find("[string", 1, true), "cli generate: ...no source position: " .. err)
    ok(not err:find("traceback", 1, true), "cli generate: ...no traceback: " .. err)
    ok(
      err:find(" not followed:\n", 1, true) and err:find("leaving", 1, true),
      "cli generate: ...and the links not followed are still listed: " .. err
    )
    ok(not out:find("wrote ", 1, true), "cli generate: ...and nothing is said to be written")
    assert_untouched(outside, "cli generate")

    local unsafe = build(project("cli_generate_unsafe"))
    unsafe.out_dir = "../elsewhere"
    code, out, err = run_cli(unsafe, {})
    eq(code, 2, "cli generate: an unsafe out_dir is a refusal too: " .. err)
    ok(
      err:find("^docmap: opts.out_dir is not a safe relative path: ../elsewhere\n$"),
      "cli generate: ...said as one line: " .. err
    )
    ok(not out:find("wrote ", 1, true), "cli generate: ...and nothing is written there either")
  end

  ---A project with its map written (so `--check` gets as far as the report),
  ---and a file outside it that must come out as it went in.
  local function with_map(label)
    local root, outside = project(label)
    local built = build(root)
    capture(function()
      return docmap.generate(built)
    end)
    H.write(outside .. "/victim.sarif", { "VICTIM-SARIF" })
    return built, outside
  end

  for _, mode in ipairs({
    { name = "check", argv = { "--check" } },
    { name = "generate", argv = {} },
  }) do
    local function sarif(built, path)
      return run_cli(built, vim.list_extend(vim.deepcopy(mode.argv), { "--sarif=" .. path }))
    end
    local label = "sarif (" .. mode.name .. "): "

    -- The control: a plain report is written, and is the JSON a consumer reads.
    do
      local built = with_map("sarif_plain_" .. mode.name)
      vim.fn.mkdir(built.root .. "/reports", "p")
      local code, out, err = sarif(built, "drift.sarif")
      eq(code, 0, label .. "a plain path runs as before: " .. err)
      ok(out:find("wrote drift.sarif", 1, true), label .. "...and says it wrote it")
      local decoded = vim.json.decode(H.slurp(built.root .. "/drift.sarif") or "")
      eq(decoded.version, "2.1.0", label .. "...a SARIF document")
      code = sarif(built, "reports/drift.sarif")
      eq(code, 0, label .. "a plain directory on the way is no obstacle")
      ok(H.slurp(built.root .. "/reports/drift.sarif"), label .. "...and the report is in it")
      code = sarif(built, "./drift.sarif")
      eq(code, 0, label .. "a leading ./ is only where the path starts")
    end

    -- The report is a link to a file outside the project.
    do
      local built, outside = with_map("sarif_file_" .. mode.name)
      local made, how = H.link(outside .. "/victim.sarif", built.root .. "/drift.sarif", false)
      if made then
        local code, out, err = sarif(built, "drift.sarif")
        eq(code, 0, label .. "a refused report does not change the exit code")
        ok(err:find("refusing to write drift.sarif", 1, true), label .. "says it refused: " .. err)
        ok(err:find("drift.sarif is a link", 1, true), label .. "...and names the link: " .. err)
        ok(
          not out:find("wrote drift.sarif", 1, true),
          label .. "...and does not claim to have written"
        )
        eq(
          H.slurp(outside .. "/victim.sarif"),
          "VICTIM-SARIF\n",
          label .. "the file it led to is intact"
        )
      else
        ok(vim.fn.has("win32") == 1, label .. "a file link could not be made: " .. tostring(how))
      end
    end

    -- ...or to a place that is not there yet: opening it for writing creates it.
    do
      local built, outside = with_map("sarif_dangling_" .. mode.name)
      local made = H.link(outside .. "/never.sarif", built.root .. "/drift.sarif", false)
      if made then
        local _, _, err = sarif(built, "drift.sarif")
        ok(err:find("refusing to write", 1, true), label .. "a dangling link is refused: " .. err)
        eq(vim.fn.filereadable(outside .. "/never.sarif"), 0, label .. "...and nothing is created")
      end
    end

    -- A link that stays inside the project is a link all the same.
    do
      local built = with_map("sarif_inside_" .. mode.name)
      H.write(built.root .. "/real.sarif", { "REAL-SARIF" })
      local made = H.link(built.root .. "/real.sarif", built.root .. "/drift.sarif", false)
      if made then
        local _, _, err = sarif(built, "drift.sarif")
        ok(
          err:find("refusing to write", 1, true),
          label .. "an inside link is refused too: " .. err
        )
        eq(
          H.slurp(built.root .. "/real.sarif"),
          "REAL-SARIF\n",
          label .. "...and its target is intact"
        )
      end
      vim.fn.mkdir(built.root .. "/real_reports", "p")
      local dir_made = H.link(built.root .. "/real_reports", built.root .. "/reports", true)
      ok(dir_made, label .. "a directory link can be made here")
      local _, _, dir_err = sarif(built, "reports/drift.sarif")
      ok(
        dir_err:find("reports is a link", 1, true),
        label .. "an inside directory link: " .. dir_err
      )
      eq(
        vim.fn.filereadable(built.root .. "/real_reports/drift.sarif"),
        0,
        label .. "...nothing written"
      )
    end

    -- A directory on the way is the link, and leads out of the project.
    do
      local built, outside = with_map("sarif_dir_" .. mode.name)
      vim.fn.mkdir(outside .. "/reports", "p")
      local made, how = H.link(outside .. "/reports", built.root .. "/reports", true)
      ok(made, label .. "a directory link can be made here: " .. tostring(how))

      local code, out, err = sarif(built, "reports/drift.sarif")
      eq(code, 0, label .. "the exit code is unchanged")
      ok(err:find("refusing to write reports/drift.sarif", 1, true), label .. "refused: " .. err)
      ok(err:find("reports is a link", 1, true), label .. "...naming the directory: " .. err)
      ok(not out:find("wrote reports", 1, true), label .. "...and not claiming to have written")
      eq(
        vim.fn.filereadable(outside .. "/reports/drift.sarif"),
        0,
        label .. "nothing appeared behind it"
      )

      -- The same place spelled as an absolute path below the project.
      _, _, err = sarif(built, built.root .. "/reports/drift.sarif")
      ok(err:find("reports is a link", 1, true), label .. "absolute, below the project: " .. err)
      eq(vim.fn.filereadable(outside .. "/reports/drift.sarif"), 0, label .. "...nothing appeared")

      -- A `..` after a name leads somewhere else than it reads if that name
      -- is a link, and the name is not looked at once the path is folded. It is
      -- refused as written rather than guessed at.
      vim.fn.mkdir(built.root .. "/plain", "p")
      _, _, err = sarif(built, "plain/../drift.sarif")
      ok(
        err:find("refusing to write plain/../drift.sarif", 1, true),
        label .. "`..` after a name is refused: " .. err
      )
      ok(err:find("is not a plain path component", 1, true), label .. "...and says why: " .. err)
      eq(vim.fn.filereadable(built.root .. "/drift.sarif"), 0, label .. "...and nothing is written")
    end

    -- Outside the project the person chose the place, so only the report
    -- itself is asked about: a plain file there is written, a link is not.
    do
      local built, outside = with_map("sarif_outside_" .. mode.name)
      local code, out = sarif(built, outside .. "/plain.sarif")
      eq(code, 0, label .. "a path outside the project is not refused for being outside")
      ok(out:find("wrote ", 1, true), label .. "...and is written")
      ok(H.slurp(outside .. "/plain.sarif"), label .. "...there")

      local made = H.link(outside .. "/victim.sarif", outside .. "/linked.sarif", false)
      if made then
        local _, _, err = sarif(built, outside .. "/linked.sarif")
        ok(
          err:find("linked.sarif is a link", 1, true),
          label .. "...but not through a link: " .. err
        )
        eq(
          H.slurp(outside .. "/victim.sarif"),
          "VICTIM-SARIF\n",
          label .. "...the target is intact"
        )
      end

      -- A leading `../` leaves the project by the path the person wrote.
      code = sarif(built, "../up.sarif")
      eq(code, 0, label .. "a path that climbs out of the project is not refused")
      ok(H.slurp(vim.fs.dirname(built.root) .. "/up.sarif"), label .. "...and is written there")
    end
  end

  -- The Windows spelling of a report path -- backslashes, a drive letter, the
  -- project named in another case -- on an in-memory tree: a real link of
  -- that kind cannot be made on the host the suite usually runs on.
  do
    local safe_fs = require("documentation.core.safe_fs")
    local links = {
      ["c:/proj/reports"] = true,
      ["./reports"] = true,
      ["d:/out"] = true,
      ["d:/out/linked.sarif"] = true,
    }
    local fake = vim.tbl_extend("force", safe_fs.host, {
      lstat = function(path)
        if links[path:lower()] then
          return { type = "link" }
        end
        return nil, "ENOENT: no such file or directory", "ENOENT"
      end,
    })
    local saved_host, saved_windows = safe_fs.host, safe_fs.windows
    safe_fs.host, safe_fs.windows = fake, true
    local ran, err = pcall(function()
      local function refusal(path)
        return cli.sarif_refusal(path, "C:/proj") or ""
      end
      ok(
        refusal("C:\\PROJ\\reports\\drift.sarif"):find("reports is a link", 1, true),
        "sarif (windows): backslashes and another case of the project path are the same place"
      )
      ok(
        refusal("reports\\drift.sarif"):find("reports is a link", 1, true),
        "sarif (windows): a relative path is read with its backslashes"
      )
      eq(
        refusal("C:/proj/plain/drift.sarif"),
        "",
        "sarif (windows): a plain path below the project"
      )
      ok(
        refusal("D:\\out\\linked.sarif"):find("linked.sarif is a link", 1, true),
        "sarif (windows): outside the project the report itself is asked about"
      )
      eq(
        refusal("D:\\out\\plain.sarif"),
        "",
        "sarif (windows): ...and only that (the directory above it is a link here, by choice)"
      )
      ok(
        refusal("C:drift.sarif"):find("drive", 1, true),
        "sarif (windows): a path relative to a drive's directory cannot be judged, so it is refused"
      )
    end)
    safe_fs.host, safe_fs.windows = saved_host, saved_windows
    safe_fs.forget()
    if not ran then
      error(err, 0)
    end
  end

  -- ---------------------------------------------------------------------
  -- `scripts/gen_map.lua` writes `docs/BINDINGS.md` itself, after `cli.run`
  -- has written the map. The script is the thing under test, so it runs as
  -- itself: a real headless Neovim over a real minimal project (the script
  -- names `lua/documentation` as its source, so that is the one the project
  -- has).
  -- ---------------------------------------------------------------------
  do
    local repo_root =
      slashed((debug.getinfo(1, "S").source:sub(2):match("(.*)[/\\]TESTS[/\\]")) or ".")
    ---The checkout a module file is found in on this editor's runtimepath.
    local function checkout_of(modfile)
      local found = vim.api.nvim_get_runtime_file(modfile, false)[1]
      return found and slashed(found):sub(1, -(#modfile + 2))
    end
    local lib_dir = checkout_of("lua/lib/nvim/fs/read/init.lua")
    local ui_dir = checkout_of("lua/ui/init.lua")
    ok(lib_dir and ui_dir, "gen_map: lib.nvim and ui.nvim are on the runtimepath of this run")

    local function gen_map(proj)
      return vim
        .system({
          vim.v.progpath,
          "-n",
          "-i",
          "NONE",
          "--headless",
          "--cmd",
          "set rtp+=" .. vim.fn.fnameescape(ui_dir),
          "-l",
          repo_root .. "/scripts/gen_map.lua",
        }, {
          cwd = proj,
          text = true,
          env = { DOCUMENTATION_NVIM_DIR = repo_root, LIB_NVIM_DIR = lib_dir },
        })
        :wait(60000)
    end

    local function map_project(label)
      local base = slashed(vim.fn.tempname()) .. "_" .. label
      bases[#bases + 1] = base
      local proj = base .. "/proj"
      H.write(
        proj .. "/lua/documentation/foo.lua",
        { "---@module 'documentation.foo'", "local M = {}", "return M" }
      )
      H.write(proj .. "/docs/real.md", { "REAL-ORIGINAL" })
      H.write(base .. "/outside/victim.md", { "VICTIM-ORIGINAL" })
      return proj, base .. "/outside"
    end

    -- The control: the page is written when nothing is in the way, whether
    -- the file is absent or an ordinary one.
    do
      local proj = map_project("bindings_plain")
      local res = gen_map(proj)
      eq(res.code, 0, "gen_map: a plain project runs: " .. tostring(res.stderr))
      ok(res.stdout:find("wrote docs/BINDINGS.md", 1, true), "gen_map: ...and writes the page")
      ok(
        (H.slurp(proj .. "/docs/BINDINGS.md") or ""):find("# Bindings", 1, true),
        "gen_map: ...which is the rendered bindings"
      )
      H.write(proj .. "/docs/BINDINGS.md", { "OLD-PAGE" })
      res = gen_map(proj)
      ok(
        res.stdout:find("wrote docs/BINDINGS.md", 1, true),
        "gen_map: an ordinary file is replaced"
      )
      ok(
        (H.slurp(proj .. "/docs/BINDINGS.md") or ""):find("# Bindings", 1, true),
        "gen_map: ...with the rendered bindings"
      )
    end

    -- The page is a link to a file outside the project.
    do
      local proj, outside = map_project("bindings_outside")
      local made, how = H.link(outside .. "/victim.md", proj .. "/docs/BINDINGS.md", false)
      if made then
        local res = gen_map(proj)
        eq(res.code, 0, "gen_map: a refused page does not change the exit code")
        ok(
          res.stderr:find("not writing docs/BINDINGS.md", 1, true),
          "gen_map: ...and the run says it refused: " .. tostring(res.stderr)
        )
        ok(
          res.stderr:find("docs/BINDINGS.md is a link", 1, true),
          "gen_map: ...naming the link: " .. tostring(res.stderr)
        )
        ok(
          not res.stdout:find("wrote docs/BINDINGS.md", 1, true),
          "gen_map: ...and not claiming to have written it"
        )
        eq(
          H.slurp(outside .. "/victim.md"),
          "VICTIM-ORIGINAL\n",
          "gen_map: the file it led to is intact"
        )
        ok(H.slurp(proj .. "/docs/map/index.html"), "gen_map: ...and the map was still written")
      else
        ok(vim.fn.has("win32") == 1, "gen_map: a file link could not be made: " .. tostring(how))
      end
    end

    -- A link that stays inside the project is a link all the same.
    do
      local proj = map_project("bindings_inside")
      local made = H.link(H.canonical(proj) .. "/docs/real.md", proj .. "/docs/BINDINGS.md", false)
      if made then
        local res = gen_map(proj)
        ok(
          res.stderr:find("not writing docs/BINDINGS.md", 1, true),
          "gen_map: an inside link is refused too: " .. tostring(res.stderr)
        )
        eq(
          H.slurp(proj .. "/docs/real.md"),
          "REAL-ORIGINAL\n",
          "gen_map: ...and what it led to is intact"
        )
      end
    end
  end

  for _, base in ipairs(bases) do
    vim.fn.delete(base, "rf")
  end
end
