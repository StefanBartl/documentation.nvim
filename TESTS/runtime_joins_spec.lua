-- TESTS/runtime_joins_spec.lua — the two crossings from
-- `runtime-analysis.nvim`'s `docs/IDEAS.md` §1.1 and §1.2:
-- `telemetry_join.by_node` feeding `churn.rank`'s third axis, and
-- `telemetry_join.untested_hot` producing the hot-and-untested list.
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
end
