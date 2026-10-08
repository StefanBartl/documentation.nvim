-- TESTS/testing_config_spec.lua -- the project's .testing.lua stays valid for testing.nvim
--
-- testing.nvim validates every key of `.testing.lua` and drops a key whose value has one bad
-- entry ("using the default"). `env_allow` once listed NVIM_APPNAME, which the runner refuses
-- (names with an NVIM prefix point at the parent editor): the whole list was dropped, the
-- DOCMAP_*_PARSER entries of the same list never reached a child editor, and every run and
-- `:checkhealth testing` warned.

return function(H)
  local eq, ok = H.eq, H.ok

  local root = (vim.fn.getcwd():gsub("\\", "/"))
  local cfg = dofile(root .. "/.testing.lua")
  ok(type(cfg) == "table", ".testing.lua returns a table")
  ok(type(cfg.env_allow) == "table", "env_allow is a list")

  -- The rules of the runner's `env_allow` entry check, restated so that the spec also runs
  -- where testing.nvim is not on the runtimepath.
  local seen = {}
  for _, name in ipairs(cfg.env_allow) do
    ok(type(name) == "string" and name ~= "", "an env_allow entry is a non-empty string")
    ok(
      name:match("^[%w_%(%)%.%-]+%*?$") ~= nil,
      ("env_allow entry %q uses only characters the runner accepts"):format(name)
    )
    ok(
      name:upper():sub(1, 4) ~= "NVIM",
      ("env_allow entry %q has an NVIM prefix: the runner refuses it and drops the list"):format(
        name
      )
    )
    ok(not seen[name], ("env_allow entry %q is listed twice"):format(name))
    seen[name] = true
  end

  -- The runner's own validator, when it is there: no problem, and the list arrives whole.
  local has_runner, project = pcall(require, "testing.config.project")
  if has_runner and type(project.load) == "function" then
    local loaded = project.load(root)
    eq(loaded.error, nil, "testing.nvim loads .testing.lua without an error")
    eq(
      table.concat(loaded.problems or {}, "\n"),
      "",
      "testing.nvim has no complaint about .testing.lua"
    )
    eq(
      table.concat(loaded.config.env_allow, ","),
      table.concat(cfg.env_allow, ","),
      "the validator keeps the whole env_allow list"
    )
  end
end
