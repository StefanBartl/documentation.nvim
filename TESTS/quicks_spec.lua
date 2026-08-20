-- TESTS/quicks_spec.lua — documentation.core.quicks
--
-- Hand-built IRs rather than a real scan, for the reason `docs_spec.lua`
-- gives: `compute` takes an IR and a finding list, so a scan would only make
-- the fixtures harder to read while testing nothing extra.
--
-- What these assertions are actually protecting, in order of how easily each
-- would break unnoticed:
--
--   1. **The unremarkable band.** A verdict is emitted only when a value
--      passes one of two cut points; between them it says nothing. That band
--      is most of a healthy tree, and a regression that collapsed it would
--      turn the tab into a wall of noise that still looked plausible.
--   2. **Determinism.** The result is serialised into a committed artifact
--      and `--check` byte-compares it. Two runs over one IR must produce
--      identical output, including ordering.
--   3. **Evidence keys.** They are handed straight to the page's compare
--      marks, so they have to be in `"<node id>#<fn>"` form — a shape that is
--      easy to get subtly wrong and impossible to notice from Lua alone.

return function(H)
  local eq, ok = H.eq, H.ok
  local quicks = require("documentation.core.quicks")

  ---Build an IR whose published functions have the given traits.
  ---@param fns table[]
  ---@param extra table?
  local function ir_with(fns, extra)
    local ir = {
      order = { "n/mod" },
      nodes = {
        ["n/mod"] = {
          id = "n/mod",
          kind = "module",
          module = "demo",
          path = "lua/demo",
          summary = "A module.",
          functions = fns,
        },
      },
    }
    for k, v in pairs(extra or {}) do
      ir[k] = v
    end
    return ir
  end

  ---One function, fully specified so a test never depends on a default.
  local function fn(name, t)
    t = t or {}
    return {
      name = name,
      signature = name .. "()",
      line = 1,
      line_end = 5,
      complexity = t.complexity or 1,
      internal = t.internal or false,
      tested = t.tested or false,
      documented = t.documented or false,
      summary = t.summary or "Does a thing.",
      params = {},
      returns = {},
      todo = {},
      bug = {},
      example = t.example,
      deprecated = t.deprecated,
    }
  end

  ---@param res Documentation.Quicks.Result
  ---@param id string
  local function find(res, id)
    for _, q in ipairs(res.good) do
      if q.id == id then
        return q
      end
    end
    for _, q in ipairs(res.bad) do
      if q.id == id then
        return q
      end
    end
    return nil
  end

  -- ---------------------------------------------------------------------
  -- Polarity, and the band between the cut points
  -- ---------------------------------------------------------------------

  -- 10 functions, none tested: 0%, well under the `bad` cut of 30.
  local none_tested = {}
  for i = 1, 10 do
    none_tested[i] = fn("M.f" .. i)
  end
  local res = quicks.compute(ir_with(none_tested), {})
  local tc = find(res, "test-coverage")
  ok(tc ~= nil, "quicks: 0% test coverage produces a verdict")
  eq(tc.polarity, "bad", "quicks: 0% test coverage is a negative verdict")

  -- 10 functions, 9 tested: 90%, over the `good` cut of 70.
  local mostly_tested = {}
  for i = 1, 10 do
    mostly_tested[i] = fn("M.f" .. i, { tested = i > 1 })
  end
  local good_res = quicks.compute(ir_with(mostly_tested), {})
  eq(find(good_res, "test-coverage").polarity, "good", "quicks: 90% test coverage is positive")

  -- 10 functions, 5 tested: 50% — between `bad` (30) and `good` (70). The
  -- band that must stay silent.
  local middling = {}
  for i = 1, 10 do
    middling[i] = fn("M.f" .. i, { tested = i > 5 })
  end
  local mid = quicks.compute(ir_with(middling), {})
  eq(find(mid, "test-coverage"), nil, "quicks: a mid-band value produces no verdict at all")

  -- ---------------------------------------------------------------------
  -- Evidence
  -- ---------------------------------------------------------------------

  local ev = find(quicks.compute(ir_with(none_tested), {}), "test-coverage").evidence
  ok(ev ~= nil and #ev > 0, "quicks: a negative coverage verdict carries evidence")
  eq(ev[1], "n/mod#M.f1", "quicks: evidence uses the '<node id>#<fn>' compare-mark key scheme")
  ok(#ev <= quicks.MAX_EVIDENCE, "quicks: evidence is capped")

  -- A positive verdict has nothing to act on, so it carries no list — an
  -- offer to "mark all" that marks nothing is worse than no offer.
  eq(
    find(good_res, "test-coverage").evidence,
    nil,
    "quicks: a positive verdict carries no evidence"
  )

  -- Capping: 30 untested functions, cap is 20.
  local many = {}
  for i = 1, 30 do
    many[i] = fn(("M.g%02d"):format(i))
  end
  local capped = find(quicks.compute(ir_with(many), {}), "test-coverage")
  eq(#capped.evidence, quicks.MAX_EVIDENCE, "quicks: evidence is capped at MAX_EVIDENCE exactly")

  -- ---------------------------------------------------------------------
  -- `@internal` is out of scope, matching doccoverage's own rule
  -- ---------------------------------------------------------------------

  local internal_only = {}
  for i = 1, 10 do
    internal_only[i] = fn("helper" .. i, { internal = true })
  end
  local int_res = quicks.compute(ir_with(internal_only), {})
  eq(find(int_res, "test-coverage"), nil, "quicks: an all-internal tree yields no coverage verdict")

  -- ---------------------------------------------------------------------
  -- Findings feed the drift verdicts — the reason `compute` runs after
  -- `check` rather than alongside the other derived tables
  -- ---------------------------------------------------------------------

  local clean = quicks.compute(ir_with({ fn("M.a", { tested = true }) }), {})
  eq(find(clean, "drift-errors").polarity, "good", "quicks: no findings means the map is in sync")

  local drifted = quicks.compute(ir_with({ fn("M.a", { tested = true }) }), {
    { severity = "error", check = "missing-summary", message = "x" },
    { severity = "error", check = "missing-module-tag", message = "y" },
  })
  local de = find(drifted, "drift-errors")
  eq(de.polarity, "bad", "quicks: error findings make the drift verdict negative")
  eq(de.value, 2, "quicks: the drift verdict counts the errors it was given")

  -- ---------------------------------------------------------------------
  -- Every verdict states its basis. This is the rule the module header
  -- argues for at length; a verdict without one is the failure mode.
  -- ---------------------------------------------------------------------

  local all = quicks.compute(ir_with(none_tested), {
    { severity = "error", check = "c", message = "m" },
  })
  local checked = 0
  for _, list in ipairs({ all.good, all.bad }) do
    for _, q in ipairs(list) do
      ok(type(q.basis) == "string" and #q.basis > 0, "quicks: " .. q.id .. " states its basis")
      ok(type(q.headline) == "string" and #q.headline > 0, "quicks: " .. q.id .. " has a headline")
      ok(type(q.tab) == "string" and #q.tab > 0, "quicks: " .. q.id .. " points at a tab")
      checked = checked + 1
    end
  end
  ok(checked > 0, "quicks: the basis check actually ran over some verdicts")

  -- ---------------------------------------------------------------------
  -- Determinism: the artifact is committed and `--check` byte-compares it
  -- ---------------------------------------------------------------------

  local a = quicks.compute(ir_with(none_tested), {})
  local b = quicks.compute(ir_with(none_tested), {})
  eq(vim.inspect(a), vim.inspect(b), "quicks: two runs over one IR produce identical output")

  -- ---------------------------------------------------------------------
  -- Caps and thresholds are configurable
  -- ---------------------------------------------------------------------

  local limited = quicks.compute(ir_with(none_tested), {
    { severity = "error", check = "c", message = "m" },
  }, { quicks = { limit_bad = 1 } })
  eq(#limited.bad, 1, "quicks: limit_bad caps the negative list")
  ok(limited.total_bad >= 1, "quicks: total_bad reports the count before the cap")

  -- With `bad` moved below 0%, nothing can fall under it any more.
  local retuned = quicks.compute(
    ir_with(none_tested),
    {},
    { quicks = { thresholds = { test_coverage = { good = 0, bad = -1 } } } }
  )
  eq(find(retuned, "test-coverage").polarity, "good", "quicks: thresholds override the defaults")

  -- ---------------------------------------------------------------------
  -- Absent optional inputs are absences, not zeroes
  -- ---------------------------------------------------------------------

  -- A tree with no `.md` corpus must not be scored 0% on documentation
  -- mentions — the question does not apply, which is different from failing
  -- it.
  eq(
    find(quicks.compute(ir_with(none_tested), {}), "docs-mentions"),
    nil,
    "quicks: no docs corpus means no docs-mentions verdict, not a zero"
  )

  -- Same for duplicates: `scan()` alone leaves `ir.duplicates` unset.
  eq(
    find(quicks.compute(ir_with(none_tested), {}), "duplicates"),
    nil,
    "quicks: an IR without duplicate detection yields no duplicates verdict"
  )
  local dup =
    quicks.compute(ir_with(none_tested, { duplicates = { groups = {}, functions = 0 } }), {})
  eq(
    find(dup, "duplicates").polarity,
    "good",
    "quicks: zero duplicate groups is a positive verdict"
  )

  -- ---------------------------------------------------------------------
  -- Recorded defects: the author's claim, counted and never gated
  -- ---------------------------------------------------------------------

  ---An IR whose one module carries the given marker comments.
  ---@param markers table[]
  local function ir_with_markers(markers)
    local ir = ir_with({ fn("M.f") })
    ir.nodes["n/mod"].markers = markers
    return ir
  end

  local function marker(kind, word, line)
    return { kind = kind, word = word, text = "something", line = line }
  end

  -- Only the `FIX` family. `TODO`, `HACK` and `PERF` are work the author
  -- scheduled; this verdict is about what the author says is wrong *now*.
  local mixed = quicks.compute(
    ir_with_markers({
      marker("TODO", "TODO", 3),
      marker("HACK", "HACK", 9),
      marker("PERF", "PERF", 11),
      marker("FIX", "BUG", 20),
      marker("FIX", "FIXME", 24),
    }),
    {}
  )
  local rec = find(mixed, "recorded-defects")
  ok(rec ~= nil, "quicks: FIX-family markers produce a verdict")
  eq(rec.value, 2, "quicks: only FIX-family markers are counted")
  eq(rec.polarity, "bad", "quicks: a marked defect is a negative verdict")

  -- The whole point of the decision: it says so, and it fails nothing.
  ok(
    rec.basis:find("author's own claim", 1, true) ~= nil,
    "quicks: the basis says whose claim the number is"
  )
  ok(rec.basis:find("DocMap check", 1, true) ~= nil, "quicks: the basis says it fails no gate")

  -- Three markers in one file are three defects and one thing to open.
  local repeated = quicks.compute(
    ir_with_markers({
      marker("FIX", "BUG", 2),
      marker("FIX", "BUG", 4),
      marker("FIX", "ISSUE", 6),
    }),
    {}
  )
  local rep = find(repeated, "recorded-defects")
  eq(rep.value, 3, "quicks: every FIX marker counts, including repeats in one file")
  eq(#rep.evidence, 1, "quicks: evidence names the file once, not once per marker")
  eq(rep.evidence[1], "n/mod", "quicks: evidence is a node id the page can mark")

  -- A map written before schema 4 has no `markers` at all. That is not the
  -- same fact as a tree with none, and a confident "no defects here" over an
  -- older artifact would be the silent-degradation failure this ecosystem
  -- treats as the expensive one.
  eq(
    find(quicks.compute(ir_with({ fn("M.f") }), {}), "recorded-defects"),
    nil,
    "quicks: an artifact without markers yields no verdict, not a zero"
  )

  -- `findings` is optional at the boundary; nil must behave as "none", not
  -- crash — `install()`'s rescan path can reach here before a check has run.
  local no_findings = quicks.compute(ir_with(none_tested), nil)
  ok(no_findings ~= nil, "quicks: a nil finding list is tolerated")
  eq(find(no_findings, "drift-errors").value, 0, "quicks: nil findings counts as zero errors")
end
