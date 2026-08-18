-- TESTS/sarif_spec.lua — core/render/sarif.lua
--
-- A serialiser, so the spec is about shape and honesty rather than analysis:
-- the levels a consumer keys on, the location a finding without a node must
-- *not* invent, the determinism an upload depends on, and the stated absence
-- of line numbers.

return function(H)
  local eq, ok = H.eq, H.ok
  local sarif = require("documentation.core.render.sarif")

  local ir = {
    nodes = {
      ["lua/x"] = { id = "lua/x", path = "lua/x", source = "lua/x/init.lua" },
      ["lua/ns"] = { id = "lua/ns", path = "lua/ns" },
    },
    order = { "lua/x", "lua/ns" },
    meta = {},
  }
  local opts = { root = "/repo", source = { "lua/x", "src" } }

  local findings = {
    { severity = "error", check = "missing-module-tag", node = "lua/x", message = "no tag" },
    { severity = "warn", check = "missing-summary", node = "lua/ns", message = "no summary" },
    { severity = "info", check = "missing-readme", node = "lua/x", message = "no readme" },
    { severity = "warn", check = "missing-summary", message = "nowhere in particular" },
  }

  local doc = vim.json.decode(sarif.render(ir, findings, opts), {
    luanil = { object = true, array = true },
  })

  eq(doc.version, "2.1.0", "sarif: declares the version consumers switch on")
  eq(#doc.runs, 1, "sarif: one run")

  local run = doc.runs[1]
  eq(#run.results, 4, "sarif: every finding becomes a result")

  -- The three-way mapping. `info` becomes `note` rather than being dropped:
  -- an info finding is the one a reviewer most often wants to see and least
  -- often wants to fail a build over.
  eq(run.results[1].level, "error", "sarif: error stays error")
  eq(run.results[2].level, "warning", "sarif: warn becomes warning")
  eq(run.results[3].level, "note", "sarif: info becomes note, not nothing")

  -- A node with a source file points at the file; a namespace has none, and
  -- its directory beats no location at all.
  eq(
    run.results[1].locations[1].physicalLocation.artifactLocation.uri,
    "lua/x/init.lua",
    "sarif: a node with a source points at the source file"
  )
  eq(
    run.results[2].locations[1].physicalLocation.artifactLocation.uri,
    "lua/ns",
    "sarif: a namespace points at its directory"
  )

  -- The one a fabricating implementation would get wrong.
  eq(
    run.results[4].locations,
    nil,
    "sarif: a finding with no node carries no location rather than an invented one"
  )

  -- Stated in the artifact, not just in the module header, because a
  -- reviewer seeing every annotation at line 1 deserves to be told why.
  eq(
    run.results[1].locations[1].physicalLocation.region.startLine,
    1,
    "sarif: results point at line 1, since findings carry no line"
  )
  ok(
    run.invocation.properties.lineNumbers:find("not available", 1, true) ~= nil,
    "sarif: ... and the run says so out loud"
  )

  -- Rules are the checks that actually fired. A full catalogue would list
  -- rules a reviewer never sees a result for, which reads as "these all
  -- fired".
  local ids = {}
  for _, r in ipairs(run.tool.driver.rules) do
    ids[#ids + 1] = r.id
  end
  eq(
    table.concat(ids, ","),
    "missing-module-tag,missing-readme,missing-summary",
    "sarif: one rule per check that occurred, sorted, no duplicates"
  )

  -- An upload that differs between identical runs makes every re-run look
  -- like new findings.
  eq(
    sarif.render(ir, findings, opts),
    sarif.render(ir, findings, opts),
    "sarif: byte-identical for an unchanged tree"
  )

  -- Multi-root scans record which roots were walked, since a finding's path
  -- only means something against them.
  eq(run.invocation.properties.source, "lua/x, src", "sarif: several source roots are recorded")
end
