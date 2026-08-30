-- TESTS/runtime_joins_spec.lua — the three crossings from
-- `runtime-analysis.nvim`'s `docs/IDEAS.md` §1.1, §1.2 and §1.3:
-- `telemetry_join.by_node` feeding `churn.rank`'s third axis,
-- `telemetry_join.untested_hot` producing the hot-and-untested list, and
-- `telemetry_join.by_key` weighting `history`'s impact list by runtime reach.
--
-- Hand-built `Data` tables throughout, the same way
-- `browse_telemetry_spec.lua` does the half that needs no live instance:
-- both functions here are pure `(ir, data) -> result`, so a real telemetry
-- recording would make the fixtures harder to read and test nothing extra.
--
-- What these assertions are protecting, in order of how quietly each would
-- break:
--
--   1. **The ranking does not move.** The whole argument for the runtime
--      column is that it separates two rows that look identical and call for
--      opposite actions — *without* making a shared ranking depend on whose
--      machine produced it. A change that folded calls into the score would
--      still look sensible and would be wrong.
--   2. **`nil` is not `0`.** "Nobody measured this" and "measured, saw
--      nothing" are the two answers this ecosystem keeps apart everywhere,
--      and the second is the only one that licenses deleting something.
--   3. **The wording.** Telemetry sees this machine only. The render says
--      "in your sessions", never "unused" — §1.1 states that as a
--      requirement on the render, and the render is `quickfix_items`.

return function(H)
  local eq, ok = H.eq, H.ok
  local churn = require("documentation.core.churn")
  local join = require("documentation.core.telemetry_join")
  local history = require("documentation.core.history")

  ---Two modules: `hot` and `cold`, each with one documented function, both
  ---churning identically so only the runtime axis can tell them apart.
  ---@return Documentation.IR
  local function fake_ir()
    return {
      order = { "hot.lua", "cold.lua" },
      nodes = {
        ["hot.lua"] = {
          id = "hot.lua",
          module = "app.hot",
          source = "hot.lua",
          functions = {
            { name = "run", line = 1, line_end = 9, complexity = 10, tested = false },
          },
        },
        ["cold.lua"] = {
          id = "cold.lua",
          module = "app.cold",
          source = "cold.lua",
          functions = {
            { name = "run", line = 1, line_end = 9, complexity = 10, tested = true },
          },
        },
      },
    }
  end

  ---@param today integer Calls recorded for `hot.run` in today's bucket.
  ---@return RA.Telemetry.Data
  local function fake_data(today)
    return {
      version = 1,
      started_at = 0,
      sessions = 1,
      functions = {
        ["hot.run"] = { calls = 4000 },
        ["cold.run"] = { calls = 0 },
      },
      days = { [os.date("%Y-%m-%d")] = { ["hot.run"] = today or 0 } },
      reminded = {},
      modules = { ["hot.run"] = "hot.lua", ["cold.run"] = "cold.lua" },
      info = {},
    }
  end

  -- ---------------------------------------------------------------------
  -- §1.1 — the third axis
  -- ---------------------------------------------------------------------

  do
    local ir = fake_ir()
    local by_node = join.by_node(ir, fake_data(30))
    eq(by_node["hot.lua"].calls, 4000, "by_node: sums the module's matched functions")
    eq(by_node["hot.lua"].calls_recent, 30, "by_node: and their seven-day window")
    eq(by_node["cold.lua"].calls, 0, "by_node: a matched function with no calls is a real zero")

    -- A module telemetry never matched gets no entry at all. The difference
    -- between this and `calls = 0` is the whole point: one says nobody
    -- looked, the other says somebody looked and saw nothing.
    local ir2 = fake_ir()
    ir2.nodes["cold.lua"].module = "app.cold"
    local partial = fake_data(0)
    partial.modules = { ["hot.run"] = "hot.lua" }
    partial.functions = { ["hot.run"] = { calls = 4000 } }
    eq(join.by_node(ir2, partial)["cold.lua"], nil, "by_node: an unmatched module is absent")
  end

  do
    local ir = fake_ir()
    local counts = { ["hot.lua"] = 5, ["cold.lua"] = 5 }

    local without = churn.rank(counts, ir, 5)
    local with = churn.rank(counts, ir, 5, join.by_node(ir, fake_data(30)))

    -- 1. The ranking is untouched, entry for entry.
    eq(#without.entries, #with.entries, "rank: the runtime axis adds no entries")
    for i, e in ipairs(without.entries) do
      eq(with.entries[i].node, e.node, "rank: order is unchanged by telemetry")
      eq(with.entries[i].score, e.score, "rank: score is unchanged by telemetry")
    end

    -- 2. Absent stays absent.
    for _, e in ipairs(without.entries) do
      eq(e.calls, nil, "rank: no telemetry passed means no calls field, not zero")
    end

    local by_id = {}
    for _, e in ipairs(with.entries) do
      by_id[e.node] = e
    end
    eq(by_id["hot.lua"].calls, 4000, "rank: the column is carried on the entry")
    eq(by_id["cold.lua"].calls, 0, "rank: and a measured zero is carried as zero")
  end

  -- 3. The wording, which is the honest-limit requirement.
  do
    local ir = fake_ir()
    local counts = { ["hot.lua"] = 5, ["cold.lua"] = 5 }
    local result = churn.rank(counts, ir, 5, join.by_node(ir, fake_data(30)))
    local items = churn.quickfix_items(result, "/repo")

    local text = table.concat(
      vim.tbl_map(function(i)
        return i.text
      end, items),
      "\n"
    )
    ok(text:find("not called in your sessions", 1, true), "quickfix: the cold module says whose")
    ok(text:find("4000 calls, 30 this week (yours)", 1, true), "quickfix: the hot one carries both")
    ok(not text:find("unused", 1, true), "quickfix: never the word `unused`")

    -- A total with nothing in the window: ran, but not lately. The middle
    -- state, and the one a two-way rendering would lose.
    local stale = churn.rank(counts, ir, 5, join.by_node(ir, fake_data(0)))
    local stale_text = table.concat(
      vim.tbl_map(function(i)
        return i.text
      end, churn.quickfix_items(stale, "/repo")),
      "\n"
    )
    ok(
      stale_text:find("none in the last week", 1, true),
      "quickfix: a cold-lately module reads differently from a never-called one"
    )

    -- Without telemetry the line is exactly what it always was.
    local plain = churn.quickfix_items(churn.rank(counts, ir, 5), "/repo")
    ok(not plain[1].text:find("yours", 1, true), "quickfix: no telemetry, no column")
  end

  -- ---------------------------------------------------------------------
  -- §1.2 — the four-cell table's one useful cell
  -- ---------------------------------------------------------------------

  do
    local ir = fake_ir()
    local rows = join.untested_hot(ir, fake_data(30))

    eq(#rows, 1, "untested_hot: only the cell that is ran-and-unnamed")
    eq(rows[1].id, "hot.lua", "untested_hot: ... which is the hot, untested one")
    eq(rows[1].calls, 4000, "untested_hot: carries the evidence, not just the verdict")

    -- `cold.run` is tested and never called: a question about the test, not
    -- about the code. `hot.run` tested would leave nothing.
    local tested = fake_ir()
    tested.nodes["hot.lua"].functions[1].tested = true
    eq(#join.untested_hot(tested, fake_data(30)), 0, "untested_hot: a named function drops out")

    -- Never called and untested is `dead-function`'s territory, with its own
    -- suppression rules. A second verdict here would sit beside an existing
    -- one and disagree with it eventually.
    local silent = fake_ir()
    silent.nodes["cold.lua"].functions[1].tested = false
    local rows2 = join.untested_hot(silent, fake_data(30))
    eq(#rows2, 1, "untested_hot: an untested function with zero calls is not this list's problem")
  end

  do
    -- Totals, not the window: "did this ever run without a test watching" is
    -- not a question about this week. A function that ran ten thousand times
    -- last month is exactly as untested as it was.
    local ir = fake_ir()
    local rows = join.untested_hot(ir, fake_data(0))
    eq(#rows, 1, "untested_hot: ranked on total calls, so an idle week changes nothing")
    eq(rows[1].calls_recent, 0, "untested_hot: ... and the window is reported anyway")
  end

  do
    -- Determinism: the quickfix list is read by a person scanning downward,
    -- and two runs over one recording must not shuffle it.
    local ir = fake_ir()
    ir.nodes["cold.lua"].functions[1].tested = false
    local data = fake_data(30)
    data.functions["cold.run"] = { calls = 4000 }
    local a = join.untested_hot(ir, data)
    local b = join.untested_hot(ir, data)
    eq(#a, 2, "untested_hot: both qualify")
    eq(a[1].id .. a[1].fn, b[1].id .. b[1].fn, "untested_hot: ties break the same way twice")
    eq(a[1].id, "cold.lua", "untested_hot: an equal-call tie breaks by node id")
  end

  -- ###################################################################
  -- IDEAS.md §1.3 — `:DocMap impact` weighted by runtime reach.
  --
  -- What these protect, and each would break quietly:
  --
  --   1. **No telemetry changes nothing.** `:DocMap impact` runs in trees
  --      with no runtime-analysis.nvim and in CI. If the column's absence
  --      moved a single row or added a single character, the feature would
  --      have made the base case worse to improve the enriched one.
  --   2. **Recency ranks, not totals** — the opposite call from
  --      `untested_hot`, and the two sit in one file precisely so nobody
  --      "fixes" the inconsistency without reading why.
  --   3. **Absence is not zero.** A function telemetry has no entry for
  --      sinks, but renders no note: "never wrapped" is not "watched and
  --      never called".

  ---One impact result over the same two modules: both touched, so only the
  ---runtime axis can order them.
  ---@return Documentation.History.Impact
  local function fake_impact()
    return {
      files = { "hot.lua", "cold.lua" },
      touched = {
        { node = "cold.lua", fn = "run", line = 1, signature = "cold.run()" },
        { node = "hot.lua", fn = "run", line = 1, signature = "hot.run()" },
      },
      callers = {},
      calling_modules = {},
      impacted_modules = {},
      unattributed = {},
      approximate = false,
    }
  end

  do
    -- The base case, asserted as an identity rather than by inspection: with
    -- no reach the render must be exactly what it was before this existed.
    local ir, impact = fake_ir(), fake_impact()
    local plain = history.quickfix_items(impact, ir, "/repo")

    eq(#plain, 2, "impact: both touched functions are listed")
    ok(
      plain[1].text:find("cold.run()", 1, true) ~= nil,
      "impact: without telemetry the input order stands (cold sorts first by node id)"
    )
    ok(
      plain[1].text:find("calls", 1, true) == nil,
      "impact: ... and no row grows a runtime column out of nothing"
    )
  end

  do
    -- The whole point: `hot.run` ran this week, `cold.run` has no entry, so
    -- the queue puts the live one first even though `cold` sorts before `hot`
    -- alphabetically.
    local ir, impact = fake_ir(), fake_impact()
    local reach = join.by_key(ir, fake_data(30))
    local items = history.quickfix_items(impact, ir, "/repo", reach)

    ok(
      items[1].text:find("hot.run()", 1, true) ~= nil,
      "impact: what ran this week outranks what did not"
    )
    ok(
      items[1].text:find("this week (yours)", 1, true) ~= nil,
      "impact: the evidence rides along, in the shared wording"
    )
  end

  do
    -- Recency, not totals. `hot.run` keeps a large lifetime count but an idle
    -- week; `cold.run` is quiet forever. The ordering must still be stable and
    -- the row must say "none in the last week" rather than implying death.
    local ir, impact = fake_ir(), fake_impact()
    local reach = join.by_key(ir, fake_data(0))
    local items = history.quickfix_items(impact, ir, "/repo", reach)

    ok(
      items[1].text:find("none in the last week (yours)", 1, true) ~= nil,
      "impact: a cold path says so, and never says 'unused'"
    )
  end

  do
    -- The measured zero, which the shared fixture does produce: telemetry
    -- resolved `cold.run` and watched it call nothing. That is a verdict, and
    -- it gets the words for one.
    local ir, impact = fake_ir(), fake_impact()
    local reach = join.by_key(ir, fake_data(30))
    ok(reach["cold.lua#run"] ~= nil, "impact: telemetry did resolve cold.run")

    local items = history.quickfix_items(impact, ir, "/repo", reach)
    local cold = items[2]
    ok(
      cold.text:find("cold.run()", 1, true) ~= nil,
      "impact: the measured-zero row sorts below the live one"
    )
    ok(
      cold.text:find("not called in your sessions", 1, true) ~= nil,
      "impact: ... and says so, since telemetry actually watched it"
    )
  end

  do
    -- Absence, which is the other thing entirely. Drop `cold.run` from the
    -- recording: nothing wrapped it, so nothing can speak for it. It sinks,
    -- and it renders bare -- a zero here would be a claim the data cannot
    -- support.
    local ir, impact = fake_ir(), fake_impact()
    local data = fake_data(30)
    data.functions["cold.run"] = nil
    data.modules["cold.run"] = nil

    local reach = join.by_key(ir, data)
    ok(reach["cold.lua#run"] == nil, "impact: an unwrapped function has no entry at all")

    local items = history.quickfix_items(impact, ir, "/repo", reach)
    eq(items[2].text, "changed: cold.run()   (0 callers)", "impact: absence renders no verdict")
  end

  do
    -- rank_touched hands back a new array. Two renders of one analysis must
    -- not depend on which ran first.
    local ir, impact = fake_ir(), fake_impact()
    local first = impact.touched[1]
    history.quickfix_items(impact, ir, "/repo", join.by_key(ir, fake_data(30)))
    eq(impact.touched[1], first, "impact: ranking leaves the caller's table alone")
  end

  do
    -- Determinism: a reader scans this list downward, and two runs over one
    -- recording must not shuffle it.
    local ir, impact = fake_ir(), fake_impact()
    local reach = join.by_key(ir, fake_data(30))
    local a = history.rank_touched(impact.touched, reach)
    local b = history.rank_touched(impact.touched, reach)
    eq(a[1].node, b[1].node, "impact: ties break the same way twice")
  end
end
