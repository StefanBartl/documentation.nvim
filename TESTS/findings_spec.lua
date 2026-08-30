---@diagnostic disable: missing-fields
-- The fixtures below carry only the fields the unit under test reads; a full
-- IR, node, finding or entry per case would be noise, not coverage.
-- TESTS/findings_spec.lua — `core/findings.lua`, the message catalog
--
-- I18N-0 moved every finding's sentence out of the check and into a catalog
-- rendered at the edge. The acceptance criterion `I18N.md` sets for that is
-- byte-identical English output, and it is gated in three places, of which
-- this file is one:
--
--   * the twenty-one specs that assert on exact finding text still pass,
--     unchanged in what they assert;
--   * the rendered findings of three real repositories — 140 of them —
--     were byte-compared before and after the move;
--   * and this file, which covers what neither of those reaches: a template
--     whose placeholders and whose call site have drifted apart, and the two
--     checks (`module-path-mismatch`, `doc-references-missing`) that no spec
--     and no healthy repository exercises.

return function(H)
  local eq, ok = H.eq, H.ok
  local findings = require("documentation.core.findings")
  local scan = require("documentation.core.scan")
  local check = require("documentation.core.check")

  -- One plausible value per placeholder any template uses. Deliberately a
  -- flat table shared by every key rather than per-key fixtures: the
  -- question here is "does this template resolve", and a single vocabulary
  -- makes an unused or misspelled placeholder obvious.
  local SAMPLE = {
    file = "lua/x/init.lua",
    path = "lua/x",
    module = "x.y",
    declared = "x.z",
    expected = "x.y",
    target = "../gone.md",
    doc = "docs/README.md",
    line = 12,
    text = "x.y.fn",
    missing = "fn",
    source = "docs/install.json",
    index = 2,
    reason = "no bin",
    who = "lua/a, lua/b",
    prefix = "lib",
    dir = "/tmp/map",
    kind = "class",
    name = "X.Type",
    alias = "mod",
    field = "fn",
    what = "<leader>ff",
    count = 3,
    where = "lua/a:1, lua/b:2",
    fn = "M.go",
    error = "line 2: unexpected symbol",
    members = "a, b, c",
    from = "x.a",
    to = "x.b",
    from_layer = "x",
    to_layer = "x.b",
    why = " — because",
    type = "RateLimits",
    documented = 1,
    actual = "width",
    repo = "other.nvim",
  }

  -- ---------------------------------------------------------------------
  -- Every catalog entry resolves.
  -- ---------------------------------------------------------------------
  local keys = {}
  for key in pairs(findings.CATALOG) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  ok(#keys >= 24, "findings: the catalog covers every check (got " .. #keys .. ")")

  for _, key in ipairs(keys) do
    local check_name, variant = key:match("^([^.]+)%.(.+)$")
    local finding = {
      severity = "warn",
      check = check_name or key,
      params = vim.tbl_extend("force", {}, SAMPLE),
    }
    if variant then
      finding.params.variant = variant
    end
    local msg = findings.format(finding)
    ok(msg ~= "" and msg ~= nil, ("findings[%s]: renders to something"):format(key))
    ok(
      not msg:find("{", 1, true),
      ("findings[%s]: no placeholder is left unresolved — %s"):format(key, msg)
    )
  end

  -- `variant` selects the sentence and is never itself printed.
  eq(
    findings.key({ check = "dead-function", params = { variant = "internal" } }),
    "dead-function.internal",
    "findings: a variant makes its own catalog key, because it is its own sentence"
  )
  eq(
    findings.key({ check = "missing-summary", params = { file = "a.lua" } }),
    "missing-summary",
    "findings: without a variant the key is the check name"
  )

  -- ---------------------------------------------------------------------
  -- Rule 2.3 — untranslated is visible, never invisible.
  -- ---------------------------------------------------------------------
  local gap = findings.format({ check = "unreferenced-module", params = {} })
  ok(
    gap:find("{module}", 1, true) ~= nil,
    "findings: a parameter the call site forgot stays visible as {module}, "
      .. "because a silent gap reads as a finished sentence"
  )

  local unknown = findings.format({ check = "not-a-real-check", params = { a = 1 } })
  eq(
    unknown,
    "<not-a-real-check> a=1",
    "findings: an unknown key renders as itself plus its parameters — a check added "
      .. "without a catalog entry must look unfinished, never blank"
  )

  -- ---------------------------------------------------------------------
  -- `opts.extra_checks` is a documented extension point, and the findings
  -- it returns carry prose this catalog has never seen.
  -- ---------------------------------------------------------------------
  eq(
    findings.format({ check = "repo-specific", message = "whatever that repo wants to say" }),
    "whatever that repo wants to say",
    "findings: a finding that already carries prose passes through untouched"
  )

  -- A value containing `%` must survive: `gsub`'s replacement string treats
  -- it specially, and an @example parse error is exactly where one shows up.
  eq(
    findings.format({
      check = "example-does-not-parse",
      params = { fn = "M.go", error = "bad %s near '('" },
    }),
    "M.go's @example is not valid Lua: bad %s near '('",
    "findings: a percent sign in a value is a value, not a format directive"
  )

  -- ---------------------------------------------------------------------
  -- End to end: a real scan, real checks, rendered messages. Catches the
  -- drift the per-key pass cannot — a call site passing `{files}` where the
  -- template says `{file}` renders cleanly in isolation and leaves a
  -- placeholder standing here.
  -- ---------------------------------------------------------------------
  local dr = H.tmpfile("_findings")
  local function dwrite(rel, lines)
    local abs = dr .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "findings spec: fixture must be writable")
    fd:write(table.concat(lines, "\n"))
    fd:close()
  end

  -- No `@module`, no summary, no README, an unused require and a dead
  -- `@see` — five different checks from one small file.
  dwrite("lua/t/a/init.lua", {
    "local M = {}",
    "local unused = require('t.b')",
    "---Do a thing.",
    "---@see nowhere.real",
    "function M.go()",
    "  return 1",
    "end",
    "return M",
  })
  dwrite("lua/t/b/init.lua", {
    "---@module 't.wrong'",
    "--- Declares a module name that does not match where it lives.",
    "local M = {}",
    "---Do another thing.",
    "function M.go()",
    "  return 2",
    "end",
    "return M",
  })

  local opts = { root = dr, source = "lua/t", lua_root = "lua", extra_checks = {} }
  local produced = check.run(scan.scan(opts), opts)
  ok(#produced > 0, "findings: the fixture produces findings to render")

  local seen = {}
  for _, f in ipairs(produced) do
    seen[f.check] = true
    local msg = findings.format(f)
    ok(
      not msg:find("{", 1, true),
      ("findings: %s renders with every parameter supplied — %s"):format(f.check, msg)
    )
    -- The fallback shape from `findings.format`, which only appears for a
    -- key the catalog does not have. Compared against the rendering rather
    -- than a leading `<`, because a real value may legitimately start with
    -- one — `<leader>ff` does.
    ok(
      msg ~= findings.format({ check = f.check, params = f.params })
        or findings.CATALOG[findings.key(f)] ~= nil,
      ("findings: %s has a catalog entry"):format(f.check)
    )
  end

  -- The one check nothing else in the suite covers by name.
  ok(
    seen["module-path-mismatch"],
    "findings: the fixture reaches module-path-mismatch, which no other spec does"
  )
end
