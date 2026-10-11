-- TESTS/serve_links_spec.lua — `:DocMap serve` does not hand out a file through
-- a link that leaves the project.
--
-- The static route serves the committed map directory, which the repository
-- names: `docs/map` (or any file in it) can be a link to somebody else's file,
-- and the page the same directory ships is same-origin with every name it
-- serves. `docmap_spec.lua` pins the string rules (`safe_static_name`,
-- `safe_out_dir`); a link makes a clean name lead anywhere, so these run the
-- **real** route (`serve.static_answer`, which the socket handler only wraps;
-- the suite's network guard does not let a spec connect to the server) against
-- real links -- a symlink, or a directory junction on Windows (`H.link`). Each
-- case is given a file outside the project that holds a marker, and a twin
-- link that stays inside, so "refuse every link" cannot pass.

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("documentation.config")
  local serve = require("documentation.editor.serve")

  local MARKER = "PRIVATE-MARKER-OUTSIDE"

  local base = (vim.fn.tempname():gsub("\\", "/")) .. "_serve_links"
  local outside = base .. "/outside"

  ---A project whose `docs/map` is a plain directory with a map in it.
  ---@param name string
  ---@return string root
  local function project(name)
    local root = base .. "/" .. name
    H.write(root .. "/docs/map/index.html", { "<html>INDEX-INSIDE</html>" })
    H.write(root .. "/docs/map/module_map.json", { "{}" })
    H.write(root .. "/README.md", { "# README-INSIDE" })
    return root
  end

  ---The answer to one name, as a table.
  local function answer(cfg, name)
    local code, ctype, body = serve.static_answer(cfg, name)
    return { code = code, ctype = ctype, body = body }
  end

  local function run()
    H.write(outside .. "/target_private.txt", { MARKER })
    H.write(outside .. "/map/index.html", { MARKER .. "-INDEX" })
    H.write(outside .. "/map/private.json", { MARKER .. "-JSON" })

    -- ----------------------------------------------- links to files, A
    local root_a = project("a")
    H.write(root_a .. "/docs/map/adir/inner.txt", { "a name that is a directory" })
    local here_a = H.canonical(root_a)
    local leak_abs = H.link(outside .. "/target_private.txt", root_a .. "/docs/map/leak.txt", false)
    local leak_rel =
      H.link("../../../outside/target_private.txt", root_a .. "/docs/map/leak_rel.txt", false)
    local in_rel = H.link("../../README.md", root_a .. "/docs/map/inside.md", false)
    local in_abs = H.link(here_a .. "/README.md", root_a .. "/docs/map/inside_abs.md", false)

    local cfg_a = config.build(root_a, {})
    local index = answer(cfg_a, "")
    eq(index.code, 200, "serve: the index of a plain map directory is served")
    ok(index.body:find("INDEX-INSIDE", 1, true) ~= nil, "serve: ...with its own content")
    eq(index.ctype, "text/html; charset=utf-8", "serve: ...as html")
    eq(answer(cfg_a, "module_map.json").code, 200, "serve: so is a plain file")
    eq(answer(cfg_a, "nothere.txt").code, 404, "serve: a name that is not there is a 404")
    ok(
      answer(cfg_a, "nothere.txt").body:find("not found", 1, true) ~= nil,
      "serve: ...that says it is not there"
    )
    eq(answer(cfg_a, "adir").code, 404, "serve: a name that is a directory is a 404, not a listing")
    eq(answer(cfg_a, "../README.md").code, 400, "serve: a name with a dot-dot is still refused")

    for _, case in ipairs({
      { made = leak_abs, name = "leak.txt", what = "a file link to an absolute target outside" },
      { made = leak_rel, name = "leak_rel.txt", what = "a file link to a relative target outside" },
    }) do
      if case.made then
        local got = answer(cfg_a, case.name)
        eq(got.code, 404, "serve: " .. case.what .. " is not served")
        ok(got.body:find(MARKER, 1, true) == nil, "serve: ...and nothing of the target is sent")
        ok(
          got.body:find("outside the project", 1, true) ~= nil,
          "serve: ...and the answer says why: " .. got.body
        )
        ok(
          got.body:find(base, 1, true) == nil and got.body:find("target_private", 1, true) == nil,
          "serve: ...without naming where the link leads"
        )
      end
    end
    if in_rel then
      local got = answer(cfg_a, "inside.md")
      eq(got.code, 200, "serve: a file link that stays inside (relative) is served")
      ok(got.body:find("README-INSIDE", 1, true) ~= nil, "serve: ...with its target's content")
    end
    if in_abs then
      local got = answer(cfg_a, "inside_abs.md")
      eq(got.code, 200, "serve: a file link that stays inside (absolute) is served")
      ok(got.body:find("README-INSIDE", 1, true) ~= nil, "serve: ...with its target's content")
    end

    -- ------------------------------ docs/map itself a link out of the project, B
    local root_b = base .. "/b"
    H.write(root_b .. "/README.md", { "# README-B" })
    vim.fn.mkdir(root_b .. "/docs", "p")
    ok(H.link(outside .. "/map", root_b .. "/docs/map", true), "the map directory link can be made")
    local cfg_b = config.build(root_b, {})
    for _, name in ipairs({ "", "index.html", "private.json" }) do
      local got = answer(cfg_b, name)
      eq(
        got.code,
        404,
        ("serve: %q behind a map directory that is a link out is not served"):format(name)
      )
      ok(got.body:find(MARKER, 1, true) == nil, "serve: ...and nothing of the target is sent")
    end

    -- --------------------- docs/map a link that stays inside the project, C
    local root_c = base .. "/c"
    H.write(root_c .. "/real_map/index.html", { "<html>INDEX-REAL</html>" })
    H.write(root_c .. "/real_map/module_map.json", { "{}" })
    vim.fn.mkdir(root_c .. "/docs", "p")
    ok(
      H.link(H.canonical(root_c) .. "/real_map", root_c .. "/docs/map", true),
      "the inside map directory link can be made"
    )
    local cfg_c = config.build(root_c, {})
    local inside_index = answer(cfg_c, "")
    eq(inside_index.code, 200, "serve: a map directory that is a link inside the project is served")
    ok(inside_index.body:find("INDEX-REAL", 1, true) ~= nil, "serve: ...with its content")
    eq(answer(cfg_c, "module_map.json").code, 200, "serve: ...so are the others")
  end

  local finished, err = pcall(run)
  serve.stop()
  vim.fn.delete(base, "rf")
  if not finished then
    error(err, 0)
  end
end
