-- TESTS/browse_loaded_spec.lua — the Loaded-vs-declared mode in
-- documentation.editor.browse.view, joined against runtime-analysis.nvim.
--
-- Its own file, not a block in docmap_browse_spec.lua: that file already
-- sits near Lua's 200-local-per-function ceiling — the same rationale
-- browse_telemetry_spec.lua and browse_endpoints_spec.lua already state for
-- themselves.

return function(H)
  local eq, ok = H.eq, H.ok
  local view = require("documentation.editor.browse.view")
  local loaded_diff = require("documentation.core.loaded_diff")

  ---@return Documentation.IR
  local function fake_ir()
    return {
      order = { "a", "b" },
      nodes = {
        a = {
          id = "a",
          module = "app.widgets",
          source = "app/widgets.lua",
          kind = "module",
          functions = {
            { name = "M.make", signature = "M.make()", line = 5 },
            { name = "M.destroy", signature = "M.destroy()", line = 9 },
            { name = "local_helper", signature = "local_helper()", line = 12 },
          },
        },
        b = {
          id = "b",
          module = "app.namespace_only",
          source = "app/namespace_only.lua",
          kind = "namespace",
          functions = { { name = "M.ignored", signature = "M.ignored()", line = 1 } },
        },
      },
    }
  end

  -- Every block below that exercises real discrepancies needs a real
  -- `runtime-analysis.nvim` checkout reachable (`loaded_diff.rows` requires
  -- `runtime-analysis.loaded`, which only resolves off a real rtp entry) --
  -- gated the same way browse_telemetry_spec.lua's own end-to-end block is,
  -- rather than assumed, since this spec also runs in CI legs with no such
  -- checkout on the runtimepath at all.
  local ok_ra = pcall(require, "runtime-analysis.loaded")

  -- loaded_diff.rows: pure logic, real package.loaded fixture.
  if ok_ra then
    package.loaded["__browse_loaded_spec_fixture"] = {
      make = function() end,
      extra = function() end,
    }

    local ir = fake_ir()
    ir.nodes.a.module = "__browse_loaded_spec_fixture"
    local rows = loaded_diff.rows(ir)
    ok(rows ~= nil, "rows: runtime-analysis.loaded is installed in this checkout, so not nil")

    local by_name = {}
    for _, row in ipairs(rows) do
      by_name[row.kind .. ":" .. row.name] = row
    end
    ok(
      by_name["declared_only:destroy"] ~= nil,
      "rows: M.destroy is declared but not on the fixture table"
    )
    ok(by_name["loaded_only:extra"] ~= nil, "rows: extra is loaded but never declared")
    ok(
      by_name["declared_only:make"] == nil and by_name["loaded_only:make"] == nil,
      "rows: make is both declared and loaded, so no discrepancy row for it"
    )
    ok(
      by_name["declared_only:local_helper"] == nil,
      "rows: a file-local declaration is excluded outright, not flagged"
    )
    ok(
      by_name["declared_only:ignored"] == nil and by_name["loaded_only:ignored"] == nil,
      "rows: a namespace node (no init.lua) contributes nothing"
    )

    package.loaded["__browse_loaded_spec_fixture"] = nil
  end

  -- entries: nil rows (runtime-analysis.nvim not installed at all) render
  -- an honest "no data" message, not a silently empty list. Forced by
  -- monkey-patching `documentation.core.loaded_diff` itself -- the same
  -- technique browse_endpoints_spec.lua uses on `runtime-analysis.history`
  -- -- since a real checkout of runtime-analysis.nvim is genuinely present
  -- in this test environment (RUNTIME_ANALYSIS_DIR), so `loaded_diff.rows`
  -- would otherwise never actually return nil here.
  do
    package.loaded["documentation.core.loaded_diff"] = {
      rows = function()
        return nil
      end,
    }
    local ir = fake_ir()
    local entries = view.entries(ir, { mode = "loaded" })
    eq(#entries, 1, "loaded mode: one message entry when runtime-analysis.nvim is absent")
    eq(entries[1].kind, "message", "loaded mode: ... and it says so")
    ok(
      entries[1].label:find("no data", 1, true) ~= nil,
      "loaded mode: 'no data', not 'no discrepancies' -- the plugin itself is not installed"
    )
    package.loaded["documentation.core.loaded_diff"] = nil
  end

  -- entries: real discrepancies, badges and detail lines.
  if ok_ra then
    package.loaded["__browse_loaded_spec_fixture2"] = {
      make = function() end,
      extra = function() end,
    }
    local ir = fake_ir()
    ir.nodes.a.module = "__browse_loaded_spec_fixture2"
    ir.nodes.b.functions = {}

    local entries = view.entries(ir, { mode = "loaded" })
    eq(#entries, 2, "loaded mode: one entry per discrepancy row")

    local by_kind = {}
    for _, e in ipairs(entries) do
      by_kind[e.loaded_diff_row.kind] = e
    end

    local declared_only = by_kind["declared_only"]
    ok(declared_only ~= nil, "loaded mode: the declared-only entry is present")
    eq(declared_only.kind, "loaded_diff", 'loaded mode: entry kind is "loaded_diff"')
    ok(
      declared_only.label:find("✕", 1, true) ~= nil,
      "loaded mode: declared-only carries the ✕ badge"
    )
    eq(
      declared_only.detail,
      "declared, not loaded in this session",
      "loaded mode: declared-only detail line"
    )

    local loaded_only = by_kind["loaded_only"]
    ok(loaded_only ~= nil, "loaded mode: the loaded-only entry is present")
    ok(loaded_only.label:find("!", 1, true) ~= nil, "loaded mode: loaded-only carries the ! badge")
    eq(
      loaded_only.detail,
      "loaded, not declared anywhere in the source",
      "loaded mode: loaded-only detail line"
    )

    -- detail: the fuller explanation, direction-specific.
    local declared_lines = view.detail(ir, { mode = "loaded" }, declared_only)
    ok(
      table.concat(declared_lines, "\n"):find("never required", 1, true) ~= nil,
      "loaded detail: declared-only explains the 'never required this session' angle"
    )
    ok(
      table.concat(declared_lines, "\n"):find("gd source", 1, true) ~= nil,
      "loaded detail: declared-only offers gd (it has a real declaration to jump to)"
    )

    local loaded_lines = view.detail(ir, { mode = "loaded" }, loaded_only)
    ok(
      table.concat(loaded_lines, "\n"):find("Generated at runtime", 1, true) ~= nil,
      "loaded detail: loaded-only explains the generated/wrapped/typo angle"
    )
    ok(
      table.concat(loaded_lines, "\n"):find("no static declaration", 1, true) ~= nil,
      "loaded detail: loaded-only says there is nothing to gd to"
    )

    -- status: spans the whole tree, like Telemetry/Endpoints.
    local st = { mode = "loaded", entries = entries }
    local status = view.status(ir, st)
    ok(status:find("1 declared%-not%-loaded", 1) ~= nil, "loaded status: the real counts")
    ok(status:find("1 loaded%-not%-declared", 1) ~= nil, "loaded status: both directions counted")
    ok(status:find("%[loaded%]") ~= nil, "loaded status: the mode tag")

    package.loaded["__browse_loaded_spec_fixture2"] = nil
  end

  -- No discrepancies at all: an honest, distinct message from "no data".
  if ok_ra then
    package.loaded["__browse_loaded_spec_clean"] = {
      make = function() end,
    }
    local ir = {
      order = { "a" },
      nodes = {
        a = {
          id = "a",
          module = "__browse_loaded_spec_clean",
          kind = "module",
          functions = { { name = "M.make", line = 1 } },
        },
      },
    }
    local entries = view.entries(ir, { mode = "loaded" })
    eq(#entries, 1, "loaded mode: one message entry when nothing disagrees")
    eq(entries[1].kind, "message", "loaded mode: ... and it says so")
    ok(
      entries[1].label:find("no discrepancies", 1, true) ~= nil,
      "loaded mode: 'no discrepancies', distinct from 'no data'"
    )
    package.loaded["__browse_loaded_spec_clean"] = nil
  end

  -- :DocBrowse's own parser recognizes "loaded" as a bare mode argument.
  do
    local browse_cmd = require("documentation.bindings.usrcmds.browse")
    local parsed = browse_cmd.parse("loaded")
    eq(parsed.mode, "loaded", "parse: 'loaded' is recognized as a bare mode argument")
    eq(parsed.center, nil, "parse: 'loaded' takes no module, like history/trail/endpoints")

    local parsed_live = browse_cmd.parse("live loaded")
    ok(parsed_live.live, "parse: 'live loaded' still sets live")
    eq(parsed_live.mode, "loaded", "parse: ... and still recognizes loaded after it")
  end

  -- ------------------------------------------- persisted snapshots (§5.4)

  -- M.prefix: the dotted root prefix `runtime-analysis.loaded.snapshot`'s
  -- own room key has to agree with, derived independently on both sides
  -- from opts.source/opts.lua_root rather than a shared config value.
  do
    eq(
      loaded_diff.prefix({ source = "lua/documentation", lua_root = "lua" }),
      "documentation",
      "prefix: lua/<name> under lua_root 'lua' resolves to the dotted name"
    )
    eq(
      loaded_diff.prefix({ source = "lua", lua_root = "lua" }),
      nil,
      "prefix: source == lua_root has no single root module, honestly nil"
    )
    eq(
      loaded_diff.prefix({ source = "lua/a/b", lua_root = "lua" }),
      "a.b",
      "prefix: a nested source path dots every segment, not just the last"
    )
  end

  -- M.rows_from_snapshot: same diff logic as M.rows, but against a plain
  -- snapshot table instead of a live runtime-analysis.loaded read — no
  -- runtime-analysis.nvim checkout needed at all, unlike the M.rows block
  -- above, since nothing here touches package.loaded.
  do
    local ir = fake_ir()
    ir.nodes.a.module = "app.widgets"
    local snapshot = {
      version = 1,
      prefix = "app",
      captured_at = 1234567890,
      modules = {
        ["app.widgets"] = { make = true, extra = true },
      },
    }
    local rows = loaded_diff.rows_from_snapshot(ir, snapshot)

    local by_name = {}
    for _, row in ipairs(rows) do
      by_name[row.kind .. ":" .. row.name] = row
    end
    ok(
      by_name["declared_only:destroy"] ~= nil,
      "rows_from_snapshot: M.destroy declared but absent from the snapshot"
    )
    ok(
      by_name["loaded_only:extra"] ~= nil,
      "rows_from_snapshot: extra present in the snapshot but never declared"
    )
    ok(
      by_name["declared_only:make"] == nil and by_name["loaded_only:make"] == nil,
      "rows_from_snapshot: make is both declared and in the snapshot, no discrepancy"
    )

    -- A module the snapshot never captured (never loaded at capture time)
    -- reads as fully declared-only for every exported function — the same
    -- "absent module" answer M.rows gives for a module with no live
    -- package.loaded entry, not an error.
    local ir2 = fake_ir()
    ir2.nodes.a.module = "never.captured"
    local rows2 = loaded_diff.rows_from_snapshot(ir2, { modules = {} })
    local declared_only_count = 0
    for _, row in ipairs(rows2) do
      if row.id == "a" and row.kind == "declared_only" then
        declared_only_count = declared_only_count + 1
      end
    end
    eq(
      declared_only_count,
      2,
      "rows_from_snapshot: a module absent from the snapshot reads as fully declared-only"
    )
  end
end
