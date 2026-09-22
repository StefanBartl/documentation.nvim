-- Test code: when something here comes back nil -- a fixture write, the
-- scanned IR -- this file must crash and name it. The nil guards LuaLS asks
-- for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/scan_repo_url_derive_spec.lua — `scan()`'s repo_url/branch
-- auto-derivation from a real git remote/branch (GS-16), when neither a
-- `.docmap.json`, a CLI flag nor the host supplied them.
--
-- Its own file, not part of config_file_spec.lua: the derivation itself
-- lives in `core/scan.lua`, not `config.build` (see that file's own
-- comment on why -- `config.build` is relied on as cheap by
-- `bindings/usrcmds/init.lua`'s per-keystroke completion, so a git
-- subprocess belongs in scan(), which already walks the whole tree once
-- per real scan).
--
-- Real git fixtures, not mocks: the point under test is that `scan()`
-- actually reaches a real "origin" remote and a real current branch, not
-- that some fake plumbing agrees with itself.

return function(H)
  local eq = H.eq
  local cfg = require("documentation.config")
  local scan = require("documentation.core.scan")

  local root_dir = (vim.fn.tempname():gsub("\\", "/"))

  ---A minimal repository: one Lua module, nothing else.
  ---@param name string
  ---@return string abs
  local function repo(name)
    local abs = root_dir .. "/" .. name
    vim.fn.mkdir(abs .. "/lua/thing", "p")
    local fd = assert(io.open(abs .. "/lua/thing/init.lua", "w"))
    fd:write("---@module 'thing'\nlocal M = {}\nreturn M\n")
    fd:close()
    return abs
  end

  ---@param dir string
  ---@param args string[]
  local function git_run(dir, args)
    local argv = {
      "git",
      "-c",
      "user.name=docs-spec",
      "-c",
      "user.email=docs-spec@example.invalid",
      "-C",
      dir,
    }
    vim.list_extend(argv, args)
    local res = vim.system(argv, { text = true }):wait()
    assert(
      res.code == 0,
      ("fixture: git %s failed: %s"):format(table.concat(args, " "), res.stderr)
    )
  end

  local git_derived = repo("git_derived")
  git_run(git_derived, { "init", "-q", "-b", "feature/derived" })
  git_run(git_derived, { "remote", "add", "origin", "https://github.com/someone/derived-repo.git" })
  git_run(git_derived, { "add", "-A" })
  git_run(git_derived, { "commit", "-q", "-m", "init" })

  local ir = scan.scan(cfg.build(git_derived))
  eq(
    ir.meta.repo_url,
    "https://github.com/someone/derived-repo",
    "scan: repo_url auto-derives from the real 'origin' remote"
  )
  eq(ir.meta.branch, "feature/derived", "scan: branch auto-derives from the real current branch")

  -- An explicit override still wins over derivation -- config.build's merge
  -- order runs before scan() ever sees opts, same precedence as every other
  -- option.
  local overridden_ir = scan.scan(cfg.build(git_derived, { branch = "explicit" }))
  eq(overridden_ir.meta.branch, "explicit", "scan: an explicit branch still beats git derivation")

  -- Not a git repository at all: derivation finds nothing, scan()'s own
  -- `branch or "main"` fallback (not config.build's -- that one no longer
  -- has a static default, see DEFAULTS.lua) is what actually answers.
  local no_repo = repo("no_repo")
  local no_repo_ir = scan.scan(cfg.build(no_repo))
  eq(no_repo_ir.meta.repo_url, nil, "scan: repo_url stays nil outside a git repository")
  eq(no_repo_ir.meta.branch, "main", 'scan: branch falls back to "main" outside a git repository')
end
