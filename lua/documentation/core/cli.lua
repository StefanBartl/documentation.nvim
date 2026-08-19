---@module 'documentation.core.cli'
--- The `nvim --headless -l ... [--check|--full]` entry point, as a function
--- rather than a script. Extracted out of `scripts/gen_map.lua` so a
--- consuming plugin's own generator script — and its own pre-commit hook —
--- can be the same three lines calling into this, instead of a second copy of
--- the staleness check and the reporting format drifting from this repo's.
---
--- `scripts/gen_map.lua` is the thin, repo-specific wrapper:
---
---   local root = vim.uv.cwd():gsub("\\", "/"):gsub("/+$", "")
---   vim.opt.runtimepath:prepend(root)
---   local opts = require("documentation.core.config")(root)
---   vim.cmd("cq " .. require("documentation.core.cli").run(opts, _G.arg or {}))
---
--- Returns an exit code rather than calling `vim.cmd("cq ...")` itself, so it
--- stays a plain function a test can call and assert on, and so the one
--- caller that actually needs the process to exit is the wrapper script, not
--- this module.

local M = {}

---@param findings Documentation.Finding[]
---@return table<Documentation.Severity, integer>
local function report(findings)
  local docmap = require("documentation")
  local tally = docmap.tally(findings)
  for _, f in ipairs(findings) do
    if f.severity ~= "info" then
      io.stderr:write(("  [%s] %-22s %s\n"):format(f.severity, f.check, f.message))
    end
  end
  io.stdout:write(
    ("\n%d errors, %d warnings, %d info\n"):format(tally.error, tally.warn, tally.info)
  )
  return tally
end

---Write `findings` as SARIF to `path`, when one was asked for.
---
---A failure to write is reported and does not change the exit code: the
---drift verdict is what the run is *for*, and losing a machine-readable copy
---of it must not turn a passing tree into a failing build.
---@param path string?
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
---@param opts Documentation.Opts
local function write_sarif(path, ir, findings, opts)
  if not path or path == "" then
    return
  end
  local body = require("documentation.core.render.sarif").render(ir, findings, opts)
  local fd, err = io.open(path, "w")
  if not fd then
    io.stderr:write(("could not write %s: %s\n"):format(path, tostring(err)))
    return
  end
  fd:write(body)
  fd:close()
  io.stdout:write("wrote " .. path .. "\n")
end

---Run the CLI over `opts` with `argv` (`_G.arg`-shaped: `--check`, `--lenient`,
---`--full`). Writes to stdout/stderr as a side effect; returns the process
---exit code rather than calling `os.exit`/`vim.cmd("cq ...")`, so the caller
---decides how to actually exit.
---@param opts Documentation.Opts
---@param argv string[]
---@return integer exit_code
function M.run(opts, argv)
  local docmap = require("documentation")
  local root = opts.root:gsub("\\", "/"):gsub("/+$", "")

  local check_only, strict = false, true
  ---@type string?
  local sarif_path = nil
  for _, a in ipairs(argv) do
    if a == "--check" then
      check_only = true
    elseif a == "--lenient" then
      strict = false
    elseif a == "--full" then
      opts.luals = true
    elseif a:match("^%-%-sarif=") then
      -- A path rather than stdout: the report already owns stdout, and a CI
      -- step wants a file to hand to `upload-sarif` anyway.
      sarif_path = a:sub(#"--sarif=" + 1)
    end
  end

  if check_only then
    local ir, findings = docmap.scan_full(opts)

    local expected = {
      ["module_map.json"] = docmap.to_json(ir),
      ["index.html"] = docmap.render.html(ir, findings, opts),
      ["overview.md"] = docmap.render.markdown(ir, findings, opts),
    }
    if opts.badge then
      expected["coverage.svg"] = require("documentation.core.doccoverage").badge_svg(ir)
    end

    local read = require("lib.nvim.fs.read")
    local stale = {}
    for name, content in pairs(expected) do
      local path = root .. "/" .. opts.out_dir .. "/" .. name
      if read(path) ~= content then
        stale[#stale + 1] = opts.out_dir .. "/" .. name
      end
    end
    table.sort(stale)

    if #stale > 0 then
      io.stderr:write("Module map is stale:\n")
      for _, s in ipairs(stale) do
        io.stderr:write("  " .. s .. "\n")
      end
      io.stderr:write(
        "\nRun :DocMap (or nvim --headless -l scripts/gen_map.lua) and commit the result.\n\n"
      )
      report(findings)
      return 1
    end

    write_sarif(sarif_path, ir, findings, opts)
    local tally = report(findings)

    if tally.error > 0 then
      if strict then
        io.stderr:write("\nModule map has " .. tally.error .. " error-severity drift findings.\n")
        return 1
      end
      io.stdout:write(tally.error .. " error-severity findings (--lenient: not failing).\n")
    end

    io.stdout:write("Module map is up to date.\n")
    return 0
  end

  local ir, findings, written = docmap.generate(opts)
  for _, w in ipairs(written) do
    io.stdout:write("wrote " .. w .. "\n")
  end
  io.stdout:write(
    ("%d modules, %d namespaces, %d files\n"):format(
      ir.meta.counts.module,
      ir.meta.counts.namespace,
      ir.meta.counts.file
    )
  )
  -- The one coverage gap unambiguous enough to print on every run: a whole
  -- language that has files in this tree and contributed nothing to the map,
  -- because all of them sit outside every source root. That is a fixable
  -- configuration fact, not an opinion, and nothing else in this output
  -- would ever mention it.
  --
  -- `ir.meta.unclaimed` (files in scope that no backend reads) is
  -- deliberately *not* printed here. It is mostly READMEs in every healthy
  -- repository, so a line on every run would be noise; it stays in the
  -- artifact, where a surface that can rank and filter -- the page, the
  -- desktop app -- can show it usefully.
  if ir.meta.outside then
    local parts = {}
    for name, n in pairs(ir.meta.outside) do
      -- Only a language that contributed *nothing* to the map. A `scripts/`
      -- of Lua beside a `lua/` source root is outside it on purpose and
      -- reporting that on every run would be the noise this line exists to
      -- avoid being. A language with files in the tree and no nodes in the
      -- map is the opposite: nobody chose that, and nothing else says it.
      if not (ir.meta.claimed and ir.meta.claimed[name]) then
        parts[#parts + 1] = ("%s %d"):format(name, n)
      end
    end
    table.sort(parts)
    local total = 0
    for name, n in pairs(ir.meta.outside) do
      if not (ir.meta.claimed and ir.meta.claimed[name]) then
        total = total + n
      end
    end
    if total > 0 then
      io.stdout:write(
        ("%d file%s of a language this map contains none of, outside every source root (%s)\n"):format(
          total,
          total == 1 and "" or "s",
          table.concat(parts, ", ")
        )
      )
    end
  end
  local tested, tested_total = require("documentation.core.coverage").summary(ir)
  if tested_total > 0 then
    io.stdout:write(
      ("%d/%d functions found by name in %s (%.0f%%)\n"):format(
        tested,
        tested_total,
        opts.tests_dir or "TESTS",
        100 * tested / tested_total
      )
    )
  end
  local doccoverage = require("documentation.core.doccoverage")
  local documented, doc_total = doccoverage.summary(ir)
  if doc_total > 0 then
    io.stdout:write(
      ("%d/%d published functions fully documented (%.0f%%)\n"):format(
        documented,
        doc_total,
        100 * documented / doc_total
      )
    )
    -- The per-language split, and only when the tree has more than one
    -- language to split into: a breakdown of one row is the line above it
    -- with extra words. Nine backends do not set the same documentation bar
    -- — Javadoc has a tool behind it, an assembly label has no parameter
    -- list at all — so an average across them can be true of no language in
    -- the tree.
    local per = doccoverage.by_language(ir)
    if #per > 1 then
      for _, row in ipairs(per) do
        io.stdout:write(
          ("  %-6s %d/%d (%.0f%%)\n"):format(
            row.language,
            row.documented,
            row.total,
            100 * row.documented / row.total
          )
        )
      end
    end
  end
  -- ECOSYSTEM.md step 8's two aggregate lines — silently absent, not zero,
  -- when no telemetry data exists for this run: see telemetry_join.lua's own
  -- doc-comment for why "no data" and "zero" must never be the same message.
  local telemetry_summary = require("documentation.core.telemetry_join").doc_usage_summary(ir, opts)
  if telemetry_summary then
    io.stdout:write(
      ("%d documented function(s) never called — maintenance cost\n"):format(
        telemetry_summary.documented_unused
      )
    )
    io.stdout:write(
      ("%d undocumented function(s) actually called — prioritized backlog\n"):format(
        telemetry_summary.undocumented_used
      )
    )
  end
  write_sarif(sarif_path, ir, findings, opts)
  local tally = report(findings)
  return (strict and tally.error > 0) and 1 or 0
end

return M
