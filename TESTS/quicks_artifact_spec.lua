-- TESTS/quicks_artifact_spec.lua — the artifact keeps the numbers and drops
-- the sentences (schema 5)
--
-- `I18N.md`'s task 0 asks for a `module_map.json` with no English sentence in
-- it. Measured over this repository's own artifact, that turned out to be a
-- much narrower change than the wording suggests, and the numbers are the
-- argument: of the sentences in it, **820 are node summaries** and 118 more
-- are the repository's own docs and features — all of which are the
-- *subject*, and rule 2.4 is explicit that the subject is never translated.
-- Exactly **10** were the tool talking about the tree in English, and all ten
-- were `quicks`.
--
-- So the split this file gates is a narrow one: `headline`, `basis` and
-- `detail` ride on the page, which builds its own payload, and the artifact
-- keeps `value`/`n`/`total` instead. That is the same division `glossaries`
-- and `marker_kinds` already take, for the reason html.lua states there — the
-- artifact is byte-deterministic and describes the repository, the
-- renderer's vocabulary belongs to the renderer.
--
-- **Both directions are asserted here on purpose.** Dropping the strings is
-- half a change; the other half is that nothing was lost, and only the
-- numbers arriving in their place makes that true.

return function(H)
  local eq, ok = H.eq, H.ok
  local docmap = require("documentation")
  local scan = require("documentation.core.scan")

  local dr = H.tmpfile("_quicks_artifact")
  local function dwrite(rel, lines)
    local abs = dr .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "quicks artifact spec: fixture must be writable")
    fd:write(table.concat(lines, "\n"))
    fd:close()
  end

  -- Undocumented, untested, no examples: enough negative verdicts that the
  -- fixture produces quicks at all, which everything below depends on.
  for _, name in ipairs({ "a", "b", "c" }) do
    dwrite("lua/t/" .. name .. "/init.lua", {
      "---@module 't." .. name .. "'",
      "--- A module.",
      "local M = {}",
      "function M.one(x)",
      "  return x",
      "end",
      "function M.two(x, y)",
      "  return x, y",
      "end",
      "return M",
    })
  end

  local opts = { root = dr, source = "lua/t", lua_root = "lua", extra_checks = {} }
  local ir = scan.scan(opts)
  ir.quicks = require("documentation.core.quicks").compute(ir, {}, opts)

  local all = {}
  for _, bucket in ipairs({ "good", "bad" }) do
    for _, q in ipairs(ir.quicks[bucket]) do
      all[#all + 1] = q
    end
  end
  ok(#all > 0, "quicks artifact: the fixture produces verdicts to inspect")

  -- In memory the verdict still carries its sentence: the page renders from
  -- this, and nothing about the split changes what a reader sees.
  local live = all[1]
  ok(live.headline and live.headline ~= "", "quicks: the verdict still carries its headline")
  ok(live.basis and live.basis ~= "", "quicks: ...and the basis behind it")
  ok(live.detail and live.detail ~= "", "quicks: ...and the rendered detail")

  local decoded = vim.json.decode(docmap.to_json(ir), { luanil = { object = true, array = true } })

  eq(decoded.meta.schema, scan.SCHEMA, "quicks artifact: the artifact reports the live schema")
  ok(scan.SCHEMA >= 5, "quicks artifact: dropping the prose is schema 5 or later")

  local serialised = {}
  for _, bucket in ipairs({ "good", "bad" }) do
    for _, q in ipairs(decoded.quicks[bucket] or {}) do
      serialised[#serialised + 1] = q
    end
  end
  eq(
    #serialised,
    #all,
    "quicks artifact: every verdict still reaches the artifact — this drops fields, not rows"
  )

  for _, q in ipairs(serialised) do
    eq(q.headline, nil, "quicks artifact: no headline in module_map.json")
    eq(q.basis, nil, "quicks artifact: no basis in module_map.json")
    eq(q.detail, nil, "quicks artifact: no detail in module_map.json")

    -- The half that makes the other half honest.
    ok(q.id ~= nil, "quicks artifact: the verdict is still identifiable")
    ok(q.value ~= nil, "quicks artifact: the measured number survives")
    ok(q.polarity ~= nil, "quicks artifact: and which side of the threshold it fell on")
    if q.unit == "percent" then
      ok(
        q.n ~= nil and q.total ~= nil,
        "quicks artifact: a percentage carries its two numbers, so '45 of 72' is "
          .. "recoverable in any language rather than lost with the English"
      )
    end
  end

  -- The counts are structure, not prose, and stay.
  eq(decoded.quicks.total_good, ir.quicks.total_good, "quicks artifact: total_good survives")
  eq(decoded.quicks.total_bad, ir.quicks.total_bad, "quicks artifact: total_bad survives")

  -- An empty result must still serialise as the shape consumers expect,
  -- rather than as null — the defect `duplicates`/`docs`/`quicks` each hit
  -- once already, per payload_contract_spec.lua's own history.
  local bare = scan.scan(opts)
  bare.quicks = nil
  local without =
    vim.json.decode(docmap.to_json(bare), { luanil = { object = true, array = true } })
  eq(type(without.quicks), "table", "quicks artifact: a scan with no quicks still emits the shape")
  eq(without.quicks.total_good, 0, "quicks artifact: ...with zeroed counts")
end
