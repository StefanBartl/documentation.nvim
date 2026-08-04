-- TESTS/browse_telemetry_spec.lua — the static x runtime join, ECOSYSTEM.md
-- step 8: `documentation.core.check.used_keys`, `documentation.core.
-- telemetry_join`, the Telemetry mode in `documentation.editor.browse.view`,
-- and dead-function suppression in `documentation.core.check`.
--
-- Same shape `browse_endpoints_spec.lua` already established for a soft
-- dependency on `runtime-analysis.nvim`: every assertion that only needs
-- fake data runs unconditionally; the real end-to-end path (a live
-- telemetry instance, wrapped, called, flushed, then read back through
-- `telemetry.load()`) only runs when a real checkout is on the rtp
-- (`RUNTIME_ANALYSIS_DIR`, wired the same way in TESTS/run.lua).

return function(H)
  local eq, ok = H.eq, H.ok
  local check = require("documentation.core.check")
  local telemetry_join = require("documentation.core.telemetry_join")
  local view = require("documentation.editor.browse.view")

  ---A small tree: one call edge (a#used_by_edge -> a#callee), one @see
  ---reference (a#seen_by_see), one local_refs count (a#used_as_value), and
  ---one function nothing reaches at all (a#truly_unused).
  ---@return Documentation.IR
  local function fake_ir()
    return {
      order = { "a" },
      nodes = {
        a = {
          id = "a",
          module = "app.mod",
          source = "app/mod.lua",
          functions = {
            { name = "callee", line = 1, line_end = 2, local_refs = 0, see = {} },
            { name = "used_by_edge", line = 3, line_end = 4, local_refs = 0, see = {} },
            { name = "seen_by_see", line = 5, line_end = 6, local_refs = 0, see = {} },
            { name = "used_as_value", line = 7, line_end = 8, local_refs = 2, see = {} },
            { name = "truly_unused", line = 9, line_end = 10, local_refs = 0, see = {} },
            {
              name = "documents_it",
              line = 11,
              line_end = 12,
              local_refs = 0,
              see = { "seen_by_see" },
            },
          },
        },
      },
      edges = {
        { kind = "call", from = "a", to = "a", to_fn = "callee" },
      },
    }
  end

  -- check.used_keys: the three "used" signals, and the one function none of
  -- them reach.
  do
    local used = check.used_keys(fake_ir())
    ok(used["a#callee"], "used_keys: a real call edge counts as used")
    ok(not used["a#used_by_edge"], "used_keys: ... but only the callee, not the caller")
    ok(used["a#seen_by_see"], "used_keys: an @see target counts as used")
    ok(used["a#used_as_value"], "used_keys: local_refs > 0 counts as used")
    ok(not used["a#truly_unused"], "used_keys: nothing reaches this one")
  end

  -- telemetry_join.namespace: title by default, explicit override wins.
  do
    eq(
      telemetry_join.namespace({ title = "demo.nvim" }),
      "demo.nvim",
      "namespace: falls back to opts.title"
    )
    eq(
      telemetry_join.namespace({ title = "demo.nvim", telemetry_namespace = "other" }),
      "other",
      "namespace: telemetry_namespace overrides title"
    )
    eq(telemetry_join.namespace({}), nil, "namespace: nil when neither is set")
  end

  -- telemetry_join.rows / by_key: pure join logic against a hand-built
  -- Data table — no real telemetry instance needed for this half.
  do
    local ir = fake_ir()
    ---@type RA.Telemetry.Data
    local data = {
      version = 1,
      started_at = 0,
      sessions = 1,
      functions = {
        ["mod.callee"] = { calls = 5 },
        ["mod.truly_unused"] = { calls = 0 },
        ["mod.unmatched_key"] = { calls = 99 },
      },
      days = {},
      reminded = {},
      -- "mod.callee"/"mod.truly_unused" resolve to a real node ("a"); the
      -- third telemetry key was never resolved to any module at all, the
      -- ordinary "wrap() with no module_id" case — dropped, not guessed.
      modules = {
        ["mod.callee"] = "a",
        ["mod.truly_unused"] = "a",
        ["mod.does_not_exist"] = "gone", -- resolved once, node since removed
      },
      info = {},
    }

    local rows = telemetry_join.rows(ir, data)
    eq(#rows, 2, "rows: only keys that resolve to a real, still-present node")

    local by_key = telemetry_join.by_key(ir, data)
    ok(by_key["a#callee"] ~= nil, "by_key: resolvable key present")
    eq(by_key["a#callee"].calls, 5, "by_key: the real call count carried through")
    eq(by_key["a#callee"].has_static_caller, true, "by_key: joined against check.used_keys")
    eq(
      by_key["a#truly_unused"].has_static_caller,
      false,
      "by_key: ... correctly false for the one nothing reaches"
    )
    eq(by_key["a#unmatched_key"], nil, "by_key: an unresolved telemetry key is not a row at all")
  end

  -- Telemetry mode, no namespace configured at all: an honest message, not
  -- an empty list or an error.
  do
    local ir = fake_ir()
    local entries = view.entries(ir, { mode = "telemetry", opts = {} })
    eq(#entries, 1, "telemetry mode: one message entry with no namespace configured")
    eq(entries[1].kind, "message", "telemetry mode: ... and it says so")
  end

  -- Telemetry mode with a namespace nothing was ever recorded for — the
  -- ordinary case for most trees, most of the time, and it must render as
  -- "no data" rather than a graveyard of ✕ badges — the Honest Limits rule
  -- this whole join is built around.
  do
    local ir = fake_ir()
    local entries = view.entries(
      ir,
      { mode = "telemetry", opts = { title = "documentation-nvim-spec-no-such-namespace" } }
    )
    eq(#entries, 1, "telemetry mode: one message entry when nothing was ever recorded")
    eq(entries[1].kind, "message", "telemetry mode: ... never a fabricated per-function list")
  end

  -- The real end-to-end path: only when a real runtime-analysis.nvim
  -- checkout is reachable. Degrading correctly when it is not is already
  -- covered by the two blocks above (both exercise the exact same "no data"
  -- code path a missing plugin takes).
  local ok_ra = pcall(require, "runtime-analysis.telemetry")
  if ok_ra then
    local telemetry = require("runtime-analysis.telemetry")
    local store = require("runtime-analysis.telemetry.store")
    local namespace = "documentation-nvim-telemetry-join-spec"

    -- No `dir` override on the instances below: `telemetry_join.load` (like
    -- the real `:DocMap check`/`:DocBrowse telemetry` it backs) always reads
    -- `telemetry.load(namespace)` with no live instance and no dir override,
    -- so this has to flush to the same real default cache dir to be found
    -- at all. `store.clear` itself does *not* default to that dir the way
    -- `telemetry.new`/`telemetry.load` do — it is a thin forward straight to
    -- `lib.nvim.cache.disk`, whose own default differs — so the dir has to
    -- be named explicitly here or `clear` silently touches a different file
    -- than `flush` just wrote, leaving stale counts to inflate every
    -- subsequent run (merge-on-write). Cleared both before (self-healing
    -- after an earlier failed run) and after this block.
    local cache_dir = vim.fn.stdpath("cache") .. "/runtime-analysis.nvim/cache"
    store.clear(namespace, { dir = cache_dir })
    store.clear(namespace .. "-alive", { dir = cache_dir })

    local mod = {
      callee = function() end,
      truly_unused = function() end,
    }
    local inst = telemetry.new({ namespace = namespace, persist = true })
    inst.wrap(mod, "mod", { module_id = "a" })
    inst.start()
    mod.callee()
    mod.callee()
    inst.flush()
    inst.stop()

    local ir = fake_ir()
    local opts = { title = namespace }
    local entries = view.entries(ir, { mode = "telemetry", opts = opts })

    local by_fn = {}
    for _, e in ipairs(entries) do
      if e.kind == "telemetry" then
        by_fn[e.fn] = e
      end
    end

    ok(by_fn.callee ~= nil, "telemetry mode (real): callee is listed")
    eq(by_fn.callee.telemetry_row.calls, 2, "telemetry mode (real): the real call count")
    eq(
      by_fn.callee.telemetry_row.has_static_caller,
      true,
      "telemetry mode (real): callee has a real static caller (the call edge)"
    )
    ok(
      by_fn.callee.label:find("^%s", 1) ~= nil,
      "telemetry mode (real): called + statically reachable -> no badge"
    )

    ok(by_fn.truly_unused ~= nil, "telemetry mode (real): truly_unused is listed too")
    eq(by_fn.truly_unused.telemetry_row.calls, 0, "telemetry mode (real): never called")
    eq(
      by_fn.truly_unused.telemetry_row.has_static_caller,
      false,
      "telemetry mode (real): ... and no static caller either"
    )
    ok(
      by_fn.truly_unused.label:find("✕", 1, true) ~= nil,
      "telemetry mode (real): high-confidence dead badge"
    )

    -- Dead-function suppression: `truly_unused` (0 calls, no static caller)
    -- is genuinely dead-looking and must still be reported; a matched
    -- function telemetry actually proves alive must not be, even though its
    -- static analysis is identical. `used_by_edge` has 0 calls recorded in
    -- telemetry (never wrapped in this test), so it is unaffected by the
    -- suppression and reported on its own static-only grounds as always.
    local mod2 = { used_as_value_target = function() end }
    local inst2 = telemetry.new({ namespace = namespace .. "-alive", persist = true })
    inst2.wrap(mod2, "mod2", { module_id = "a" })
    inst2.start()
    -- `a#truly_unused`'s telemetry key must be "mod2.truly_unused" to join —
    -- reuse the same node id ("a") a second wrap call, naming the function
    -- this check would otherwise flag.
    local mod3 = { truly_unused = function() end }
    inst2.wrap(mod3, "mod3", { module_id = "a" })
    -- `truly_unused` fires here matches key "mod3.truly_unused", which
    -- resolves to "a#truly_unused" — the exact function `check.used_keys`
    -- already says has no static caller.
    mod3.truly_unused()
    inst2.flush()
    inst2.stop()

    -- `check.run` exercises every check, not only dead-function — several
    -- of them (`missing-summary`, `undocumented-param`, ...) index fields
    -- `fake_ir()` above deliberately leaves out, since none of the earlier
    -- blocks in this spec go anywhere near `check.run`. A second, fully-
    -- shaped fixture, the same fields `docmap_spec.lua`'s own `fn_info`/
    -- `make_ir` helpers already establish as the minimum `check.run` needs.
    ---@param name string
    ---@param over table?
    local function fn_info(name, over)
      over = over or {}
      return vim.tbl_extend("force", {
        name = name,
        signature = name .. "()",
        summary = "x",
        line = 1,
        line_end = 2,
        params = {},
        returns = {},
        generic = {},
        deprecated = nil,
        async = false,
        nodiscard = false,
        internal = false,
        local_refs = 0,
        see = {},
        overload = {},
        example = nil,
        since = nil,
      }, over)
    end

    ---@param functions_by_node table<string, table[]>
    ---@param edges table[]?
    local function make_ir(functions_by_node, edges)
      local nodes, order = {}, {}
      for id, fns in pairs(functions_by_node) do
        nodes[id] = {
          id = id,
          kind = "module",
          name = id,
          path = id,
          source = id .. "/init.lua",
          module = id:gsub("/", "."),
          summary = "x",
          body = "",
          readme = "x.md",
          types = {},
          export = "table",
          parent = nil,
          depth = 0,
          children = {},
          functions = fns,
        }
        order[#order + 1] = id
      end
      table.sort(order)
      return { meta = { title = "t" }, order = order, nodes = nodes, edges = edges or {} }
    end

    local ir2 = make_ir({
      a = {
        fn_info("truly_unused"),
        fn_info("used_by_edge"),
      },
    })
    local opts2 = {
      root = "/fake",
      lua_root = "lua",
      extra_checks = {},
      title = namespace .. "-alive",
      dead_code = true,
    }
    local findings = check.run(ir2, opts2)
    local dead = {}
    for _, f in ipairs(findings) do
      if f.check == "dead-function" then
        dead[#dead + 1] = f.message
      end
    end
    local joined = table.concat(dead, "\n")
    ok(
      joined:find("used_by_edge", 1, true) ~= nil,
      "dead-function: an ordinary unused function is still reported — suppression is selective, not blanket"
    )
    ok(
      joined:find("truly_unused", 1, true) == nil,
      "dead-function: suppressed once telemetry proves this exact function alive"
    )

    store.clear(namespace, { dir = cache_dir })
    store.clear(namespace .. "-alive", { dir = cache_dir })
  end
end
