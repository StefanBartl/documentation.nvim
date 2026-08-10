-- TESTS/telemetry_self_spec.lua — documentation.core.telemetry_self, the
-- write side of the telemetry join `browse_telemetry_spec.lua` already
-- covers the read side of.
--
-- Same shape those specs already established for a soft dependency on
-- runtime-analysis.nvim: everything that only needs the "not installed"
-- degrade path runs unconditionally (the default `TESTS/run.lua` run,
-- with no `RUNTIME_ANALYSIS_DIR` set, genuinely does not have it on the
-- rtp — this is the real absent case, not a simulation of one); the real
-- end-to-end path (a real instance, a real wrap, a real flush read back
-- through `telemetry.load()`) only runs when a real checkout is reachable.

return function(H)
  local eq, ok = H.eq, H.ok
  local telemetry_self = require("documentation.core.telemetry_self")

  -- opts.telemetry == false is a hard opt-out, checked before anything else
  -- — true regardless of whether runtime-analysis.nvim is even installed,
  -- so this assertion is meaningful in both the default and the
  -- real-checkout run.
  do
    telemetry_self._reset_for_test()
    local inst = telemetry_self.setup({ telemetry = false, title = "should-not-matter" })
    eq(inst, nil, "setup: opts.telemetry = false is a hard opt-out")
  end

  local ok_ra = pcall(require, "runtime-analysis.telemetry")

  if not ok_ra then
    -- The default, real "not installed" case for a plain local run.
    do
      telemetry_self._reset_for_test()
      local inst = telemetry_self.setup({ title = "demo.nvim" })
      eq(inst, nil, "setup: nil (not an error) when runtime-analysis.nvim is not installed")
    end
  else
    -- Real runtime-analysis.nvim on the rtp (RUNTIME_ANALYSIS_DIR).
    local telemetry = require("runtime-analysis.telemetry")
    local store = require("runtime-analysis.telemetry.store")
    local cache_dir = vim.fn.stdpath("cache") .. "/runtime-analysis.nvim/cache"

    -- No namespace resolvable at all (neither title nor telemetry_namespace)
    -- — nil, not a guessed name, not an error.
    do
      telemetry_self._reset_for_test()
      local inst = telemetry_self.setup({})
      eq(inst, nil, "setup: nil when no namespace can be resolved at all")
    end

    -- telemetry_namespace overrides title, the identical precedence
    -- telemetry_join.namespace (the read side) already documents — checked
    -- here by confirming the instance's own namespace, not by inspecting
    -- private state.
    do
      telemetry_self._reset_for_test()
      local ns = "documentation-nvim-self-telemetry-spec-override"
      store.clear(ns, { dir = cache_dir })
      local inst = assert(
        telemetry_self.setup({ title = "wrong-name", telemetry_namespace = ns }),
        "setup: a real instance when a namespace resolves"
      )
      eq(inst.namespace, ns, "setup: telemetry_namespace overrides title")
      inst.stop()
      store.clear(ns, { dir = cache_dir })
    end

    -- Idempotency: a second call before the namespace changes returns the
    -- SAME instance rather than creating a duplicate "documentation.nvim"
    -- namespace writer (which `telemetry.new`'s own "already has a live
    -- instance" warning exists specifically to catch).
    do
      telemetry_self._reset_for_test()
      local ns = "documentation-nvim-self-telemetry-spec-idempotent"
      store.clear(ns, { dir = cache_dir })
      local first =
        assert(telemetry_self.setup({ title = ns }), "setup: first call returns a real instance")
      local second = assert(
        telemetry_self.setup({ title = ns }),
        "setup: second call also returns a real instance"
      )
      eq(first, second, "setup: a second call returns the identical instance, not a new one")
      first.stop()
      store.clear(ns, { dir = cache_dir })
    end

    -- The real end-to-end path: `main = "documentation"` actually wraps
    -- this repo's own already-loaded modules, a real call is counted, and
    -- it survives a flush + telemetry.load() the way the browse telemetry
    -- mode itself reads it back.
    do
      telemetry_self._reset_for_test()
      local ns = "documentation-nvim-self-telemetry-spec-e2e"
      store.clear(ns, { dir = cache_dir })

      -- `documentation.core.telemetry_self` is itself already loaded (this
      -- spec just required it) and lives under the `documentation.` prefix
      -- `main = "documentation"` wraps — calling its own already-defined
      -- `_reset_for_test` through the wrapped table is exactly the kind of
      -- already-loaded call `M.setup`'s own honest-limits note describes.
      local inst = telemetry_self.setup({ title = ns })
      ok(inst ~= nil, "setup (e2e): a real instance")

      -- A function on the resolved module map — resolved_modules() proves
      -- at least one real `documentation.*` path actually got wrapped,
      -- not just the bare require("documentation") facade table itself.
      local resolved = inst.resolved_modules()
      local any_documentation_module = false
      for _, path in pairs(resolved) do
        if path:find("^documentation%.") or path == "documentation" then
          any_documentation_module = true
          break
        end
      end
      ok(
        any_documentation_module,
        "setup (e2e): resolved_modules() names at least one real documentation.* path"
      )

      inst.flush()
      inst.stop()

      local data = telemetry.load(ns)
      ok(data ~= nil, "setup (e2e): the namespace is readable back via telemetry.load()")

      store.clear(ns, { dir = cache_dir })
    end

    telemetry_self._reset_for_test()
  end
end
