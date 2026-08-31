-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/tools_spec.lua — `core/tools.lua` (the `lib.nvim.deps` manifest
-- reader behind `:DocMap tools` / `ir.tools`) and the `tools-spec-invalid`
-- check in `core/check.lua`.
--
-- Its own file, not a block in docmap_spec.lua, for the same reason
-- `check_type_vs_class_spec.lua` is: this needs real files on disk (a
-- `docs/install.json`/`docs/INSTALL.md` `core/tools.lua` actually opens),
-- which the hand-built-IR fixtures most of docmap_spec.lua's checks use
-- cannot exercise.

return function(H)
  local fmsg = require("documentation.core.findings").format
  local eq, ok = H.eq, H.ok
  local tools = require("documentation.core.tools")
  local docmap = require("documentation")

  local function dwrite(root, rel, text)
    local abs = root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "tools spec: fixture must be writable")
    fd:write(text)
    fd:close()
  end

  -- ------------------------------------------------------------ core.tools

  -- No docs/install.json, no docs/INSTALL.md at all.
  do
    local dr = H.tmpfile("_tools_none")
    vim.fn.mkdir(dr, "p")
    eq(tools.resolve(dr), nil, "tools.resolve: nil when the repo ships neither spec file")
  end

  -- docs/install.json: one valid entry, one missing `why`.
  do
    local dr = H.tmpfile("_tools_json")
    dwrite(
      dr,
      "docs/install.json",
      vim.json.encode({
        tools = {
          {
            bin = "pdftotext",
            required = false,
            why = "Enables the fast plain-text extraction backend.",
            pkg = { apt = "poppler-utils", brew = "poppler" },
          },
          { bin = "nope", pkg = { apt = "nope" } }, -- no `why` — invalid
        },
      })
    )

    local result = tools.resolve(dr)
    ok(result ~= nil, "tools.resolve: reads a real docs/install.json")
    eq(result.source, "docs/install.json", "tools.resolve: source is repo-relative")
    eq(#result.tools, 1, "tools.resolve: only the valid entry survives into .tools")
    eq(result.tools[1].bin, "pdftotext", "tools.resolve: bin read")
    eq(result.tools[1].required, false, "tools.resolve: required defaults false")
    eq(#result.errors, 1, "tools.resolve: the invalid entry is reported, not silently dropped")
    eq(result.errors[1].field, "why", "tools.resolve: names the missing field")
  end

  -- docs/INSTALL.md fallback when no docs/install.json exists.
  do
    local dr = H.tmpfile("_tools_md")
    dwrite(
      dr,
      "docs/INSTALL.md",
      table.concat({
        "# Install",
        "",
        "```install-tool",
        "bin: pandoc",
        "required: true",
        'why: "Enables Markdown -> PDF export."',
        "pkg:",
        "  apt: pandoc",
        "  brew: pandoc",
        "```",
        "",
      }, "\n")
    )

    local result = tools.resolve(dr)
    ok(result ~= nil, "tools.resolve: falls back to docs/INSTALL.md")
    eq(result.source, "docs/INSTALL.md", "tools.resolve: source names the markdown file")
    eq(#result.tools, 1, "tools.resolve: one fenced install-tool block parsed")
    eq(result.tools[1].bin, "pandoc", "tools.resolve: bin read from YAML-ish block")
    eq(result.tools[1].required, true, "tools.resolve: required: true read")
  end

  -- Both present: JSON wins, same order `lib.nvim.deps.spec`'s own
  -- SPEC_FILES declares.
  do
    local dr = H.tmpfile("_tools_both")
    dwrite(
      dr,
      "docs/install.json",
      vim.json.encode({
        tools = { { bin = "curl", why = "x", pkg = { apt = "curl" } } },
      })
    )
    dwrite(dr, "docs/INSTALL.md", "# Install\n")

    local result = tools.resolve(dr)
    eq(result.source, "docs/install.json", "tools.resolve: JSON preferred when a repo ships both")
  end

  -- ------------------------------------------------------ tools-spec-invalid

  -- A minimal real tree (scan_full needs something to walk) plus a manifest
  -- with one invalid entry — exercised through the real pipeline
  -- (`documentation.scan_full`), not a hand-built IR, since `ir.tools` is
  -- only ever set there.
  do
    local dr = H.tmpfile("_tools_check")
    dwrite(
      dr,
      "lua/t/init.lua",
      table.concat({
        "---@module 't'",
        "--- A trivial module, just so the scan has something to walk.",
        "local M = {}",
        "return M",
      }, "\n")
    )
    dwrite(
      dr,
      "docs/install.json",
      vim.json.encode({
        tools = { { bin = "x" } }, -- no `why`, no `pkg` — two errors on one entry
      })
    )

    local ir, findings =
      docmap.scan_full({ root = dr, source = "lua/t", lua_root = "lua", extra_checks = {} })

    ok(ir.tools ~= nil, "scan_full: ir.tools set when the repo ships a manifest")
    -- `{ bin = "x" }` fails validation twice — missing `why` and missing
    -- `pkg` are reported as two separate errors on the same entry, not
    -- collapsed into one.
    eq(#ir.tools.errors, 2, "scan_full: both missing fields reported")

    local hits = {}
    for _, f in ipairs(findings) do
      if f.check == "tools-spec-invalid" then
        hits[#hits + 1] = f
      end
    end
    eq(#hits, 2, "check.tools-spec-invalid: one finding per manifest error")
    local hit = hits[1]
    eq(hit.severity, "warn", "check.tools-spec-invalid: warn, matching doc-references-missing")
    eq(hit.node, nil, "check.tools-spec-invalid: repo-level finding, no owning node")
    ok(
      fmsg(hit):find("docs/install.json", 1, true) ~= nil,
      "check.tools-spec-invalid: names the source file"
    )
  end

  -- A tree with no manifest at all: `ir.tools` stays nil, and the check
  -- produces nothing — a missing manifest is not itself a defect.
  do
    local dr = H.tmpfile("_tools_check_none")
    dwrite(
      dr,
      "lua/t/init.lua",
      table.concat({
        "---@module 't'",
        "--- A trivial module with no lib.nvim.deps manifest at all.",
        "local M = {}",
        "return M",
      }, "\n")
    )

    local ir, findings =
      docmap.scan_full({ root = dr, source = "lua/t", lua_root = "lua", extra_checks = {} })

    eq(ir.tools, nil, "scan_full: ir.tools stays nil when the repo ships no manifest")
    for _, f in ipairs(findings) do
      ok(f.check ~= "tools-spec-invalid", "check.tools-spec-invalid: never fires with no manifest")
    end
  end
end
