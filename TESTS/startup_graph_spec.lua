-- TESTS/startup_graph_spec.lua — the baked-in startup flamegraph
--
-- Three things are worth pinning here, and only one of them is about the
-- picture.
--
-- 1. `is_safe` refuses rather than cleans. The path is configurable, so the
--    content is not always something this ecosystem wrote, and it is
--    interpolated straight into the emitted document.
-- 2. `strip` takes the graph back out for `--check`. Without it a repository
--    that once baked one in reports itself stale forever, which is the exact
--    failure `action.yml` documents for the standalone build.
-- 3. Absence is the normal case and has to be silent: no plugin, no file, no
--    button, no panel — and above all no error.

return function(H)
  local eq, ok = H.eq, H.ok
  -- The harness has no `falsy`; this spec asserts absence a lot.
  local function falsy(v, msg)
    return ok(not v, msg)
  end
  local sg = require("documentation.core.startup_graph")

  local MINIMAL = '<?xml version="1.0" encoding="UTF-8"?>\n'
    .. '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">'
    .. '<rect width="10" height="10" fill="#f2c9a0"/><text x="1" y="8">lua</text></svg>'

  -- ── is_safe: what a flamegraph looks like ───────────────────────────────
  ok(sg.is_safe(MINIMAL), "is_safe: a plain flamegraph passes")

  local refused = {
    { "", "empty" },
    { "not markup at all", "not an SVG" },
    { "<svg><script>alert(1)</script></svg>", "script" },
    { '<svg><a href="javascript:alert(1)">x</a></svg>', "javascript" },
    { "<svg><foreignObject><b>x</b></foreignObject></svg>", "foreignObject" },
    { '<svg><rect onload="alert(1)"/></svg>', "event-handler" },
    { '<svg><rect ONCLICK = "x"/></svg>', "event-handler, whatever the case" },
  }
  for _, case in ipairs(refused) do
    local passed, reason = sg.is_safe(case[1])
    falsy(passed, "is_safe refuses: " .. case[2])
    ok(type(reason) == "string" and reason ~= "", "…with a reason (" .. case[2] .. ")")
  end

  -- A `<script` inside what is otherwise a valid document is still refused —
  -- the check is not "does it start like an SVG".
  falsy(
    sg.is_safe(MINIMAL:gsub("</svg>", "<script>x</script></svg>")),
    "is_safe: a trailing script is caught"
  )

  -- ── strip: the --check exception ────────────────────────────────────────
  local page = '<div id="a"></div><template id="startup-graph" data-measured="2026-08-31">'
    .. MINIMAL
    .. '</template><div id="ctx"></div>'
  local stripped = sg.strip(page)
  eq(
    stripped,
    '<div id="a"></div><div id="ctx"></div>',
    "strip: the whole template goes, nothing else does"
  )
  eq(sg.strip(stripped), stripped, "strip: idempotent — a page without one is unchanged")
  eq(
    sg.strip("<html>no graph</html>"),
    "<html>no graph</html>",
    "strip: leaves an ordinary page alone"
  )

  -- The property `--check` actually depends on: two pages that differ only
  -- in their graph compare equal after stripping.
  local other = page
    :gsub('data%-measured="2026%-08%-31"', 'data-measured="2026-09-01"')
    :gsub('fill="#f2c9a0"', 'fill="#a8d6cf"')
  ok(other ~= page, "strip: the two pages really do differ before stripping")
  eq(
    sg.strip(other),
    sg.strip(page),
    "strip: …and are identical after — which is what --check needs"
  )

  -- ── load: every absence is quiet, and says which absence it was ─────────
  local missing, reason = sg.load({ startup_flamegraph = "/definitely/does/not/exist.svg" })
  falsy(missing, "load: a missing file yields no graph")
  ok((reason or ""):find("no flamegraph", 1, true) ~= nil, "…and names that as the reason")

  local tmp = vim.fn.tempname() .. ".svg"
  local fd = assert(io.open(tmp, "wb"))
  fd:write(MINIMAL)
  fd:close()

  local graph
  graph, reason = sg.load({ startup_flamegraph = tmp })
  ok(graph ~= nil, "load: a real file yields a graph: " .. tostring(reason))
  eq(graph and graph.path, tmp, "…knowing where it came from")
  ok(graph and type(graph.mtime) == "number", "…and when it was measured")
  ok(graph and graph.svg:find("<svg", 1, true) ~= nil, "…with the document itself")

  -- A refused file is not an error and not a graph; it is a reason.
  local bad = vim.fn.tempname() .. ".svg"
  fd = assert(io.open(bad, "wb"))
  fd:write('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>')
  fd:close()
  graph, reason = sg.load({ startup_flamegraph = bad })
  falsy(graph, "load: a file carrying a script is refused")
  ok((reason or ""):find("refused", 1, true) ~= nil, "…and says so rather than failing silently")

  pcall(os.remove, tmp)
  pcall(os.remove, bad)

  -- ── the page: emitted only when there is a graph ────────────────────────
  local html_src_path = (vim.fn.getcwd():gsub("\\", "/"))
    .. "/lua/documentation/core/render/html.lua"
  local f = assert(io.open(html_src_path, "rb"), "startup graph spec: html.lua must be readable")
  local src = f:read("*a")
  f:close()

  ok(src:find('data-atool="startup"', 1, true) ~= nil, "page: the Startup tool exists")
  ok(
    src:find("startup_graph_button", 1, true) ~= nil,
    "page: its button is a variable, so it can be left out when there is nothing to show"
  )
  ok(
    src:find("document.importNode(tpl.content, true)", 1, true) ~= nil,
    "page: the graph is cloned from the template, never re-parsed from a string"
  )
end
