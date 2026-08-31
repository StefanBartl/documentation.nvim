-- TESTS/loaded_suppression_spec.lua — runtime evidence as a *check input*:
-- `unreferenced-module` suppressed for a module a real session had loaded.
--
-- The second place this ecosystem lets runtime evidence silence a static
-- finding, after `dead-function`'s telemetry join, and the rule is the same
-- one `PLAN.md` §7 draws: **suppression only, never escalation**. A warning
-- that appears on one machine and not another is worse than no warning, so
-- evidence may only ever remove a finding.
--
-- What these assertions protect, in order of how quietly each would break:
--
--   1. **Absence is not evidence.** No snapshot, no runtime-analysis, no root
--      prefix — each must leave the check behaving exactly as it always has.
--      That is CI's normal state, and a check that quietly changed shape
--      there would make `--check` mean something different on two machines.
--   2. **Evidence never manufactures a finding.** A module the snapshot does
--      *not* mention must be reported exactly as before, and a snapshot must
--      never make a referenced module suspicious.
--   3. **The newest snapshot is the one read.** `list_snapshots` documents
--      newest-first; reading `[1]` is the whole of that contract, and reading
--      the wrong end would silently act on months-old evidence.

return function(H)
  local eq, ok = H.eq, H.ok
  local check = require("documentation.core.check")

  local opts = {
    root = "/fake",
    source = "lua/x",
    lua_root = "lua",
    title = "x",
    extra_checks = {},
  }

  ---Two modules under one root: `used` is required by another node, `orphan`
  ---is required by nothing — the only difference the check can see.
  ---@return Documentation.IR
  local function fake_ir()
    ---@param id string
    ---@param module string
    ---@param required_by string[]
    local function node(id, module, required_by)
      return {
        id = id,
        kind = "module",
        name = module,
        path = id,
        source = id .. "/init.lua",
        module = module,
        summary = "s",
        body = "",
        readme = "r.md",
        types = {},
        export = "table",
        depth = 1,
        children = {},
        functions = {},
        required_by = required_by,
        requires = {},
      }
    end

    return {
      meta = {
        title = "x",
        source = "lua/x",
        types_dir = "@types",
        branch = "main",
        schema = 1,
        counts = { module = 3, namespace = 0, file = 0 },
      },
      root = "lua/x",
      order = { "lua/x", "lua/x/used", "lua/x/orphan" },
      nodes = {
        ["lua/x"] = node("lua/x", "x", {}),
        ["lua/x/used"] = node("lua/x/used", "x.used", { "lua/x" }),
        ["lua/x/orphan"] = node("lua/x/orphan", "x.orphan", {}),
      },
      edges = {},
    }
  end

  ---Every module reported as unreferenced, sorted.
  ---@return string[]
  local function orphans()
    local out = {}
    for _, f in ipairs(check.run(fake_ir(), opts)) do
      if f.check == "unreferenced-module" then
        out[#out + 1] = (f.params or {}).module
      end
    end
    table.sort(out)
    return out
  end

  ---Install a fake `runtime-analysis.loaded` for the duration of `fn`.
  ---The same technique browse_loaded_spec.lua and browse_endpoints_spec.lua
  ---already use for this dependency: it is optional by design, so the probe
  ---goes through `package.loaded` and a stub is the honest way to exercise
  ---both branches without requiring it to be installed.
  ---@param stub table|nil
  ---@param fn fun()
  local function with_loaded(stub, fn)
    local saved = package.loaded["runtime-analysis.loaded"]
    package.loaded["runtime-analysis.loaded"] = stub
    local ran, err = pcall(fn)
    package.loaded["runtime-analysis.loaded"] = saved
    if not ran then
      error(err, 0)
    end
  end

  ---@param snapshots { name: string, saved_at: integer }[]
  ---@param modules table<string, table<string, table<string, true>>> by snapshot name
  local function fake_loaded(snapshots, modules)
    return {
      list_snapshots = function()
        return snapshots
      end,
      load_snapshot = function(_, name)
        local m = modules[name]
        return m and { version = 1, prefix = "x", captured_at = 1, modules = m }
      end,
    }
  end

  -- ---------------------------------------------------------------------
  -- Absence is not evidence.
  -- ---------------------------------------------------------------------

  eq(
    table.concat(orphans(), " "),
    "x.orphan",
    "orphans: without runtime-analysis, exactly the unreferenced module"
  )

  with_loaded(fake_loaded({}, {}), function()
    eq(
      table.concat(orphans(), " "),
      "x.orphan",
      "orphans: runtime-analysis installed but no snapshot taken changes nothing"
    )
  end)

  with_loaded({
    list_snapshots = function()
      error("no such prefix")
    end,
    load_snapshot = function() end,
  }, function()
    eq(
      table.concat(orphans(), " "),
      "x.orphan",
      "orphans: a runtime-analysis that raises is absence, not a failed scan"
    )
  end)

  with_loaded(fake_loaded({ { name = "gone", saved_at = 2 } }, {}), function()
    eq(
      table.concat(orphans(), " "),
      "x.orphan",
      "orphans: a listed snapshot that cannot be read is absence too"
    )
  end)

  -- ---------------------------------------------------------------------
  -- Evidence suppresses, and only that.
  -- ---------------------------------------------------------------------

  with_loaded(
    fake_loaded({ { name = "now", saved_at = 2 } }, { now = { ["x.orphan"] = {} } }),
    function()
      eq(
        #orphans(),
        0,
        "orphans: a module a real session loaded is not unreferenced, whatever the scan saw"
      )
    end
  )

  -- An empty function set is still a loaded module — `runtime-analysis.loaded`
  -- writes one for a module of pure data, and reading that as "not loaded"
  -- would put the finding back for exactly the aggregate modules most likely
  -- to be reached through a string map.
  with_loaded(
    fake_loaded(
      { { name = "now", saved_at = 2 } },
      { now = { ["x.orphan"] = {}, ["x.used"] = { go = true } } }
    ),
    function()
      eq(#orphans(), 0, "orphans: an empty field set still means loaded")
    end
  )

  with_loaded(
    fake_loaded({ { name = "now", saved_at = 2 } }, { now = { ["x.used"] = { go = true } } }),
    function()
      eq(
        table.concat(orphans(), " "),
        "x.orphan",
        "orphans: a snapshot that does not mention the module leaves it reported"
      )
    end
  )

  -- ---------------------------------------------------------------------
  -- The newest snapshot is the one read.
  -- ---------------------------------------------------------------------

  with_loaded(
    fake_loaded(
      -- `list_snapshots` documents newest-first; reading anything but `[1]`
      -- would act on the older evidence here and report nothing.
      { { name = "newest", saved_at = 9 }, { name = "older", saved_at = 1 } },
      { newest = { ["x.used"] = {} }, older = { ["x.orphan"] = {} } }
    ),
    function()
      eq(
        table.concat(orphans(), " "),
        "x.orphan",
        "orphans: the newest snapshot decides, not an older one that disagrees"
      )
    end
  )

  -- ---------------------------------------------------------------------
  -- `loaded_modules` itself.
  -- ---------------------------------------------------------------------
  local loaded_diff = require("documentation.core.loaded_diff")

  with_loaded(
    fake_loaded({ { name = "now", saved_at = 2 } }, { now = { ["x.a"] = {}, ["x.b"] = {} } }),
    function()
      local mods = loaded_diff.loaded_modules(opts)
      ok(mods, "loaded_modules: a snapshot produces a set")
      assert(mods)
      eq(mods["x.a"], true, "loaded_modules: keyed by module id")
      eq(mods["x.c"], nil, "loaded_modules: and holds only what the snapshot held")
    end
  )

  with_loaded(fake_loaded({}, {}), function()
    eq(
      loaded_diff.loaded_modules(opts),
      nil,
      "loaded_modules: no snapshot is nil, never an empty set"
    )
  end)

  with_loaded(
    fake_loaded({ { name = "now", saved_at = 2 } }, { now = { ["x.a"] = {} } }),
    function()
      -- No single root module to name means no prefix to look a snapshot up
      -- by — the same "no opinion" answer `prefix()` already gives.
      local flat = vim.tbl_extend("force", opts, { source = "lua" })
      eq(
        loaded_diff.loaded_modules(flat),
        nil,
        "loaded_modules: a tree with no single root prefix has no evidence to read"
      )
    end
  )
end
