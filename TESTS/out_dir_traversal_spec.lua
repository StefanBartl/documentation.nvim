-- TESTS/out_dir_traversal_spec.lua — `documentation.write_artifacts` refuses
-- an `opts.out_dir` that would write outside `opts.root` (SEC-42).
--
-- `out_dir` is repository input (`.docmap.json`'s `REPO_KEYS.out_dir`), so a
-- cloned tree can set it. Before this fix it was pasted straight onto `root`
-- with no check, and `"../../../../somewhere"` made `mkdirp` create that tree
-- outside the repository from a plain `:DocMap` run.

return function(H)
  local eq, ok = H.eq, H.ok
  local docmap = require("documentation")

  local root = H.tmpfile("_out_dir_traversal")
  vim.fn.mkdir(root .. "/lua/t", "p")
  local fd = assert(io.open(root .. "/lua/t/init.lua", "w"))
  fd:write("---@module 't'\nlocal M = {}\nreturn M\n")
  fd:close()

  local function gen(out_dir)
    return pcall(
      docmap.generate,
      { root = root, source = "lua/t", lua_root = "lua", out_dir = out_dir }
    )
  end

  -- A normal, nested-but-relative out_dir still works.
  local ok_good = gen("generated/map")
  ok(ok_good, "write_artifacts: an ordinary relative out_dir still generates")
  ok(
    vim.fn.filereadable(root .. "/generated/map/module_map.json") == 1,
    "write_artifacts: ...and lands exactly where it was told to"
  )

  -- `..` segments, in either slash spelling, are refused rather than walked.
  local ok_dotdot = gen("../../../../somewhere_outside")
  ok(not ok_dotdot, "write_artifacts: a `..`-traversing out_dir is refused")
  eq(
    vim.fn.isdirectory(root .. "/../../../../somewhere_outside"),
    0,
    "write_artifacts: ...and nothing was created outside the repository"
  )

  local ok_dotdot_bs = gen("..\\..\\somewhere_outside")
  ok(not ok_dotdot_bs, "write_artifacts: a backslash-spelled `..`-traversal is refused too")

  -- An absolute path is not a relative out_dir either.
  local ok_abs = gen("/etc/somewhere_outside")
  ok(not ok_abs, "write_artifacts: a leading-slash absolute out_dir is refused")

  local ok_drive = gen("C:/somewhere_outside")
  ok(not ok_drive, "write_artifacts: a Windows drive-letter out_dir is refused")

  -- The unconfigured default keeps working.
  local ok_default = gen(nil)
  ok(ok_default, "write_artifacts: an absent out_dir still falls back to the default")
  ok(
    vim.fn.filereadable(root .. "/docs/map/module_map.json") == 1,
    "write_artifacts: ...and the default lands at docs/map"
  )

  vim.fn.delete(root, "rf")
end
