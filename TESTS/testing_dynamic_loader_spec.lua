-- Test code: a nil from a fixture read or a decode must crash the spec and name
-- it; the nil guards LuaLS asks for would hide the failure being tested.
---@diagnostic disable: need-check-nil, undefined-field, param-type-mismatch, assign-type-mismatch
-- TESTS/testing_dynamic_loader_spec.lua -- documentation.testing: `require(variable)` is a gap
--
-- A module that loads others by a computed name has no edge to them in the
-- graph. The affected-selection answer must not call itself complete when such
-- a module could be loading an affected one (the bug: a change of a backend
-- selected too few specs and `complete` stayed true).
--
--   p.a                      the changed module
--   p.loader                 require(modname)            (bare computed name)
--   p.headed                 require("p.zz." .. k)       (computed name under a head)
--   p.zz.impl                only loadable through p.headed
--
-- Kept apart from testing_provider_spec.lua: every generated project costs a
-- scan, and that spec already uses most of its time budget.

return function(H)
  local eq, ok = H.eq, H.ok
  local testing = require("documentation.testing")

  local function write(path, text)
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    local fd = assert(io.open(path, "wb"))
    fd:write(text)
    fd:close()
  end

  local function git(root, ...)
    local res = vim
      .system({
        "git",
        "-C",
        root,
        "-c",
        "user.email=t@example.test",
        "-c",
        "user.name=t",
        "-c",
        "commit.gpgsign=false",
        ...,
      }, { text = true })
      :wait()
    assert(res.code == 0, "git failed: " .. tostring(res.stderr))
  end

  local root = vim.fn.tempname():gsub("\\", "/") .. "/p"
  vim.fn.mkdir(root, "p")

  local function regenerate(msg)
    require("documentation").generate({
      root = root,
      source = "lua/p",
      title = "p",
      luals = false,
    })
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", msg)
  end

  local function module(name, body)
    write(
      root .. "/lua/p/" .. name:gsub("%.", "/") .. ".lua",
      ("---@module 'p.%s'\n--- Module %s.\nlocal M = {}\n%sreturn M\n"):format(
        name,
        name,
        body or ""
      )
    )
  end

  local function loader_gaps(res)
    local out = {}
    for _, g in ipairs(res.graph.gaps) do
      if g.kind == "dynamic_require_in_graph" then
        out[g.module] = g
      end
    end
    return out
  end

  write(root .. "/lua/p/init.lua", "---@module 'p'\n--- The fixture.\nreturn {}\n")
  module("a")
  module("loader", "function M.load(modname) return require(modname) end\n")
  module("headed", "function M.load(k) return require('p.zz.' .. k) end\n")
  module("zz.impl")
  write(root .. "/TESTS/a_spec.lua", "local a = require('p.a')\nreturn function() end\n")
  write(root .. "/README.md", "# p\n")
  git(root, "init", "-q")
  regenerate("init")

  -- A bare computed require may load anything: it is a gap for any change.
  local via_a = testing.affected_specs({ root = root, changed = { "lua/p/a.lua" } })
  local gaps = loader_gaps(via_a)
  ok(gaps["p.loader"] ~= nil, "a bare require(variable) is reported")
  eq(gaps["p.loader"].reason, "dynamic_require", "...with its reason")
  eq(gaps["p.loader"].path, "lua/p/loader.lua", "...and its file")
  eq(gaps["p.headed"], nil, "a head that no affected module matches is not reported")
  eq(via_a.complete, false, "the selection is not complete: a narrowed run may miss a spec")

  -- A literal head limits the risk to modules under it.
  local via_impl = testing.affected_specs({ root = root, changed = { "lua/p/zz/impl.lua" } })
  gaps = loader_gaps(via_impl)
  ok(gaps["p.headed"] ~= nil, "a computed require whose head matches the change is reported")
  eq(gaps["p.headed"].reason, "dynamic_require_prefix", "...with the head reason")
  ok(gaps["p.loader"] ~= nil, "...next to the bare one")
  eq(via_impl.complete, false, "...and the selection is not complete")

  -- Without a changed module there is nothing to guard.
  local docs_only = testing.affected_specs({ root = root, changed = { "README.md" } })
  eq(next(loader_gaps(docs_only)), nil, "no changed module, no loader gap")
  eq(docs_only.complete, true, "...and the answer stays complete")

  -- The documented kinds and reasons are the schema's.
  local fd = assert(io.open(vim.fn.getcwd() .. "/docs/affected-specs.schema.json", "rb"))
  local schema = vim.json.decode(fd:read("*a"))
  fd:close()
  local kinds, reasons = {}, {}
  for _, k in ipairs(schema.definitions.gap.properties.kind.enum) do
    kinds[k] = true
  end
  for _, r in ipairs(schema.definitions.gap.properties.reason.enum) do
    reasons[r] = true
  end
  for _, answer in ipairs({ via_a, via_impl }) do
    for _, g in ipairs(answer.graph.gaps) do
      ok(kinds[g.kind], ("gap kind %q is in the schema"):format(g.kind))
      ok(
        g.reason == nil or reasons[g.reason],
        ("gap reason %q is in the schema"):format(tostring(g.reason))
      )
    end
  end

  -- A loader that is itself affected is covered: its specs are selected anyway.
  module(
    "loader",
    "local _ = require('p.a')\nfunction M.load(modname) return require(modname) end\n"
  )
  regenerate("loader requires a")
  local covered = testing.affected_specs({ root = root, changed = { "lua/p/a.lua" } })
  eq(loader_gaps(covered)["p.loader"], nil, "an affected loader is no gap")
  ok(loader_gaps(covered)["p.headed"] == nil, "...and the headed one still does not match p.a")

  vim.fn.delete(vim.fs.dirname(root), "rf")
end
