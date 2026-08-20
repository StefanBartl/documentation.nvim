-- TESTS/check_tag_requires_spec.lua — `tag-require-missing` and
-- `tag-file-unavailable` in `core/check.lua`.
--
-- The cross-repository half of the drift catalogue, and the mirror of
-- `consumer-require-missing`: that check asks whether a project under
-- `opts.consumers` requires something this library no longer declares, this
-- one asks the same of *this* tree's own dependencies through
-- `opts.tag_files`. Between them both directions of one cross-repository
-- edge are covered, and neither needs new extraction.
--
-- **Both artifacts are written here rather than scanned**, because a tag
-- file *is* a committed `module_map.json` — the check's whole input is
-- another project's artifact, so a fixture that writes one is the honest
-- shape rather than a stand-in for a real repository.
--
-- Measured before this existed: 18 external requires under `lib` from
-- documentation.nvim and 23 from runtime-analysis.nvim, all 41 resolving
-- against lib.nvim's own map — zero findings, which is what a healthy
-- ecosystem produces. So the positive control below is what proves the
-- check works; its silence on real repositories proves nothing.

return function(H)
  local eq, ok = H.eq, H.ok
  local scan = require("documentation.core.scan")
  local check = require("documentation.core.check")
  local tagfiles = require("documentation.core.tagfiles")

  local dr = H.tmpfile("_tag_requires")
  local function dwrite(rel, lines)
    local abs = dr .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "tag-requires spec: fixture must be writable")
    fd:write(table.concat(lines, "\n"))
    fd:close()
  end

  -- This tree: files reaching into another project, one missing module
  -- required from two of them so the "one broken module, several requiring
  -- files" shape is exercised.
  dwrite("lua/t/a/init.lua", {
    "---@module 't.a'",
    "--- Requires a module the other project still has.",
    "local M = {}",
    "local alive = require('other.kept')",
    "---Use it.",
    "function M.go()",
    "  return alive",
    "end",
    "return M",
  })
  dwrite("lua/t/b/init.lua", {
    "---@module 't.b'",
    "--- Requires a module the other project no longer has.",
    "local M = {}",
    "local gone = require('other.renamed_away')",
    "---Use it.",
    "function M.go()",
    "  return gone",
    "end",
    "return M",
  })
  dwrite("lua/t/c/init.lua", {
    "---@module 't.c'",
    "--- Requires the same missing module, from a second file.",
    "local M = {}",
    "local gone = require('other.renamed_away')",
    "---Use it too.",
    "function M.go()",
    "  return gone",
    "end",
    "return M",
  })
  -- Outside every configured prefix — somebody else's business, and
  -- reporting it would bury the one finding that matters.
  dwrite("lua/t/d/init.lua", {
    "---@module 't.d'",
    "--- Requires a third-party plugin nothing here claims.",
    "local M = {}",
    "local p = require('plenary.async')",
    "---Use it.",
    "function M.go()",
    "  return p",
    "end",
    "return M",
  })

  ---The other project's committed artifact: it has `other.kept` and does
  ---not have `other.renamed_away`.
  local function write_map(dir, modules)
    local nodes = {}
    for _, mod in ipairs(modules) do
      local id = "lua/" .. (mod:gsub("%.", "/"))
      nodes[#nodes + 1] = {
        id = id,
        name = mod:match("[^.]+$"),
        module = mod,
        kind = "module",
        children = {},
        functions = {},
        requires = {},
        requires_external = {},
        symbols = {},
        types = {},
      }
    end
    vim.fn.mkdir(dr .. "/" .. dir, "p")
    local fd = assert(io.open(dr .. "/" .. dir .. "/module_map.json", "wb"))
    fd:write(vim.json.encode({ schema = 3, root = "lua", nodes = nodes }))
    fd:close()
  end
  write_map("othermap", { "other.kept" })

  local base = { root = dr, source = "lua/t", lua_root = "lua", extra_checks = {} }
  local function run(tag_files)
    local opts = vim.tbl_extend("force", base, { tag_files = tag_files })
    local ir = scan.scan(opts)
    tagfiles.resolve(ir, opts)
    local out = { missing = {}, unavailable = {}, ir = ir }
    for _, f in ipairs(check.run(ir, opts)) do
      if f.check == "tag-require-missing" then
        out.missing[#out.missing + 1] = f
      elseif f.check == "tag-file-unavailable" then
        out.unavailable[#out.unavailable + 1] = f
      end
    end
    return out
  end

  -- ---------------------------------------------------------------------
  -- The positive control.
  -- ---------------------------------------------------------------------
  local got = run({ other = "othermap" })
  eq(#got.missing, 1, "tag-require-missing: one finding per missing module, not per requiring file")

  local miss = got.missing[1]
  ok(
    miss.message:find("other.renamed_away", 1, true) ~= nil,
    "tag-require-missing: names the module the other project no longer declares"
  )
  ok(
    miss.message:find("lua/t/b", 1, true) ~= nil and miss.message:find("lua/t/c", 1, true) ~= nil,
    "tag-require-missing: names every file that requires it"
  )
  ok(
    miss.message:find("predates a rename", 1, true) ~= nil,
    "tag-require-missing: carries the second reading — a stale map is as likely as a broken require"
  )
  eq(
    miss.severity,
    "warn",
    "tag-require-missing: warn, matching consumer-require-missing, its mirror"
  )
  eq(#got.unavailable, 0, "tag-require-missing: a map that loaded is not reported unavailable")

  ok(
    got.ir.tag_links["other.kept"] ~= nil,
    "tag-require-missing: the module that IS declared still resolves to a link"
  )
  ok(
    miss.message:find("plenary", 1, true) == nil,
    "tag-require-missing: a require outside every configured prefix is somebody else's business"
  )

  -- ---------------------------------------------------------------------
  -- The case this ecosystem is actually in. Every plugin here but this one
  -- gitignores `docs/map/`, so a fresh clone has no artifact to check
  -- against — and reporting a clean bill for a directory that never opened
  -- would be the one unacceptable outcome.
  -- ---------------------------------------------------------------------
  local absent = run({ other = "no/such/dir" })
  eq(#absent.missing, 0, "tag-file-unavailable: nothing is called missing when nothing was read")
  eq(#absent.unavailable, 1, "tag-file-unavailable: fires once for the unreadable tag file")
  eq(
    absent.unavailable[1].severity,
    "info",
    "tag-file-unavailable: info, matching luals-unavailable — a thing that did not run "
      .. "is not a defect in the tree"
  )
  ok(
    absent.unavailable[1].message:find("were not checked", 1, true) ~= nil,
    "tag-file-unavailable: says plainly that the requires went unchecked"
  )

  -- ---------------------------------------------------------------------
  -- Unconfigured. `ir.tag_links` is set unconditionally, so only the audit
  -- being nil can keep this quiet — the same never-ran contract
  -- `types_detail` has.
  -- ---------------------------------------------------------------------
  local none = run(nil)
  eq(none.ir.tag_audit, nil, "tag_audit: nil when opts.tag_files was never set")
  eq(#none.missing + #none.unavailable, 0, "tag checks: silent when nothing was configured")
end
