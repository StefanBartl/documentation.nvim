-- TESTS/browse_rules_spec.lua — `documentation.core.rules_join` and the
-- Rules mode in `documentation.editor.browse.view`.
--
-- Same shape `browse_telemetry_spec.lua`/`browse_endpoints_spec.lua` already
-- established for a soft dependency: the pure logic (join + entry shaping)
-- runs unconditionally against a hand-built fake `rules` module; the real
-- end-to-end path (a genuine `rules.nvim` checkout, a real ruleset, a real
-- `run_gate_json` call) only runs when one is reachable on the rtp
-- (`RULES_DIR`, wired the same way `RUNTIME_ANALYSIS_DIR` is in
-- `TESTS/run.lua`).

return function(H)
  local eq, ok = H.eq, H.ok
  local rules_join = require("documentation.core.rules_join")
  local view = require("documentation.editor.browse.view")

  ---@return Documentation.IR
  local function fake_ir()
    return { order = {}, nodes = {}, edges = {} }
  end

  ---A fabricated `rules` module, installed at `package.loaded["rules"]` for
  ---the duration of one test block and restored after — `rules.nvim` itself
  ---may or may not be on this repo's rtp, and the pure join/shaping logic
  ---under test here does not need the real plugin to exercise it.
  ---@param results Rules.Result[]
  ---@return fun() restore
  local function stub_rules(results)
    local previous = package.loaded["rules"]
    package.loaded["rules"] = {
      run_gate_json = function(_gate_name, _root)
        return "[]", 0, results
      end,
    }
    return function()
      package.loaded["rules"] = previous
    end
  end

  -- rules_join.gate: no fallback, unlike telemetry_join.namespace -- a gate
  -- name is not derivable from opts.title.
  do
    eq(rules_join.gate({ rules_gate = "review" }), "review", "gate: opts.rules_gate, verbatim")
    eq(rules_join.gate({ title = "demo.nvim" }), nil, "gate: no fallback to title")
    eq(rules_join.gate({}), nil, "gate: nil when unset")
  end

  -- rules_join.load: nil, not an error, when rules.nvim is not on the rtp
  -- at all (the ordinary case for most projects most of the time).
  do
    local previous = package.loaded["rules"]
    package.loaded["rules"] = nil
    -- Force soft_require to actually try requiring "rules" rather than
    -- reusing a real one some earlier block in this run already loaded.
    package.preload["rules"] = nil
    local results = rules_join.load("review", "/fake")
    eq(results, nil, "load: nil when rules.nvim is absent")
    package.loaded["rules"] = previous
  end

  -- rules_join.load: the fake module's results pass through unchanged --
  -- this is a live call-through, not a decode of anything.
  do
    ---@type Rules.Result[]
    local fake_results = {
      { rule = { id = "X-01", severity = "critical" }, status = "pass", findings = {} },
    }
    local restore = stub_rules(fake_results)
    local results = rules_join.load("review", "/fake/root")
    restore()
    eq(results, fake_results, "load: the fake module's results, unchanged")
  end

  -- Rules mode, no gate configured at all: an honest message, not an empty
  -- list or an error -- the same posture Telemetry takes for no namespace.
  do
    local ir = fake_ir()
    local entries = view.entries(ir, { mode = "rules", opts = {} })
    eq(#entries, 1, "rules mode: one message entry with no gate configured")
    eq(entries[1].kind, "message", "rules mode: ... and it says so")
  end

  -- Rules mode, a gate configured but rules.nvim absent: same "no data"
  -- message shape, never a fabricated empty catalog.
  do
    local previous = package.loaded["rules"]
    package.loaded["rules"] = nil
    package.preload["rules"] = nil
    local ir = fake_ir()
    local entries = view.entries(ir, { mode = "rules", opts = { rules_gate = "review" } })
    package.loaded["rules"] = previous
    eq(#entries, 1, "rules mode: one message entry when rules.nvim is absent")
    eq(entries[1].kind, "message", "rules mode: ... never a fabricated per-rule list")
  end

  -- Rules mode with fake data: sorting (fail/error first, then waived, then
  -- manual, then pass), badges, and root-relative source stripping for `gd`.
  do
    ---@type Rules.Result[]
    local fake_results = {
      {
        rule = { id = "Z-99", severity = "nice-to-have" },
        status = "pass",
        findings = {},
      },
      {
        rule = {
          id = "A-01",
          severity = "critical",
          source_file = "/rulesets/a.md",
          source_line = 3,
        },
        status = "manual",
        findings = {},
      },
      {
        rule = { id = "M-05", severity = "recommended" },
        status = "waived",
        waiver_reason = "false positive in fixtures",
        findings = { { file = "/repo/root/lua/x.lua", line = 7, text = "x" } },
      },
      {
        rule = { id = "B-02", severity = "critical" },
        status = "fail",
        findings = { { file = "/repo/root/lua/y.lua", line = 12, text = "bad thing" } },
      },
    }
    local restore = stub_rules(fake_results)
    local ir = fake_ir()
    local entries =
      view.entries(ir, { mode = "rules", opts = { rules_gate = "review", root = "/repo/root" } })
    restore()

    eq(#entries, 4, "rules mode: one entry per result")
    eq(entries[1].rules_row.rule.id, "B-02", "rules mode: fail sorts first")
    eq(entries[2].rules_row.rule.id, "M-05", "rules mode: waived sorts second")
    eq(entries[3].rules_row.rule.id, "A-01", "rules mode: manual sorts third")
    eq(entries[4].rules_row.rule.id, "Z-99", "rules mode: pass sorts last")

    ok(entries[1].label:find("✕", 1, true) ~= nil, "rules mode: fail gets the ✕ badge")
    ok(entries[2].label:find("○", 1, true) ~= nil, "rules mode: waived gets the ○ badge")

    eq(entries[1].source, "lua/y.lua", "rules mode: finding path stripped root-relative for gd")
    eq(entries[1].line, 12, "rules mode: finding line carried through")
    eq(entries[4].source, nil, "rules mode: no findings, no source -- not a fabricated jump target")

    local detail = view.detail(ir, { mode = "rules" }, entries[1])
    ok(
      table.concat(detail, "\n"):find("bad thing", 1, true) ~= nil,
      "rules mode detail: the finding text is shown"
    )

    local status = view.status(ir, { mode = "rules", entries = entries, opts = {} })
    ok(status:find("1 fail", 1, true) ~= nil, "rules mode status: fail count")
    ok(status:find("1 manual", 1, true) ~= nil, "rules mode status: manual count")
    ok(status:find("1 waived", 1, true) ~= nil, "rules mode status: waived count")
  end

  -- The real end-to-end path: only when a real rules.nvim checkout is
  -- reachable. Degrading correctly when it is not is already covered above.
  local ok_rules = pcall(require, "rules")
  if ok_rules then
    local rules = require("rules")

    local ruleset_dir = vim.fn.tempname()
    vim.fn.mkdir(ruleset_dir, "p")
    local checked_root = vim.fn.tempname()
    vim.fn.mkdir(checked_root, "p")
    vim.fn.writefile({ "local x = vim.loop.new_timer()" }, checked_root .. "/bad.lua")

    vim.fn.writefile({
      "# Fixture",
      "",
      "## Deprecated loop API",
      "",
      "```rule",
      'id = "FIX-01",',
      'severity = "critical",',
      'check = { type = "grep", pattern = "vim%.loop%." },',
      "```",
      "",
      "Do not use `vim.loop` directly.",
      "",
    }, ruleset_dir .. "/fixture.md")

    rules.setup({
      rulesets = { ruleset_dir },
      gates = { fixture_gate = { "FIX" } },
    })

    local results = rules_join.load("fixture_gate", checked_root)
    ok(results ~= nil, "load (real): a genuine rules.nvim call returns results")
    if results then
      eq(#results, 1, "load (real): the one fixture rule")
      eq(results[1].status, "fail", "load (real): the fixture file trips the pattern")
      eq(#results[1].findings, 1, "load (real): one finding")
    end

    local ir = fake_ir()
    local entries = view.entries(
      ir,
      { mode = "rules", opts = { rules_gate = "fixture_gate", root = checked_root } }
    )
    eq(#entries, 1, "rules mode (real): one entry for the one fixture rule")
    eq(entries[1].rules_row.status, "fail", "rules mode (real): fail status carried through")
    eq(entries[1].source, "bad.lua", "rules mode (real): finding path stripped root-relative")
  end
end
