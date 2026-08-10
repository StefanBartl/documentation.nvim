-- TESTS/snippet_spec.lua — documentation.core.snippet, and functions.lua's
-- wiring of it into Documentation.FunctionInfo.
--
-- Unconditional, unlike lang_js_spec.lua: core/snippet.lua takes a plain
-- string and two row numbers, never a treesitter node, so there is nothing
-- here that needs a real parser on the runtimepath.

return function(H)
  local eq, ok = H.eq, H.ok
  local snippet = require("documentation.core.snippet")

  -- A short span, well under the cap: kept whole, nothing omitted.
  do
    local src = table.concat({ "line1", "line2", "line3", "line4" }, "\n")
    local text, omitted = snippet.extract(src, 1, 2) -- 0-based: "line2".."line3"
    eq(text, "line2\nline3", "snippet.extract: exact span kept verbatim")
    eq(omitted, 0, "snippet.extract: nothing omitted under the cap")
  end

  -- Exactly at the cap: still nothing omitted — the boundary itself must not
  -- be misread as "one over."
  do
    local lines = {}
    for i = 1, snippet.MAX_LINES do
      lines[i] = "l" .. i
    end
    local src = table.concat(lines, "\n")
    local text, omitted = snippet.extract(src, 0, snippet.MAX_LINES - 1)
    eq(omitted, 0, "snippet.extract: a span exactly at MAX_LINES omits nothing")
    local _, n = text:gsub("\n", "")
    eq(n + 1, snippet.MAX_LINES, "snippet.extract: ... and keeps every one of them")
  end

  -- Over the cap: truncated, with an honest count of what was cut — the
  -- same "N more, not carried into the artifact" shape docs.lua already
  -- uses for an overflowing reference list.
  do
    local lines = {}
    for i = 1, snippet.MAX_LINES + 22 do
      lines[i] = "l" .. i
    end
    local src = table.concat(lines, "\n")
    local text, omitted = snippet.extract(src, 0, #lines - 1)
    eq(omitted, 22, "snippet.extract: lines past the cap are counted, not silently dropped")
    local _, n = text:gsub("\n", "")
    eq(n + 1, snippet.MAX_LINES, "snippet.extract: ... and the kept text stops exactly at the cap")
  end

  -- An invalid/empty span (erow < srow) is a real absence, not an empty
  -- string standing in for one.
  do
    local text, omitted = snippet.extract("a\nb\nc", 2, 0)
    eq(text, nil, "snippet.extract: an inverted span returns nil, not an empty string")
    eq(omitted, 0, "snippet.extract: ... and reports nothing omitted")
  end

  -- End to end: functions.lua actually calls this during a real scan, on a
  -- real Lua fixture — not just unit-tested in isolation.
  do
    local functions = require("documentation.core.functions")
    local fixture = H.tmpfile(".lua")
    local lines = { "local M = {}", "", "function M.short()", "  return 1", "end", "" }
    lines[#lines + 1] = "function M.long()"
    for i = 1, 60 do
      lines[#lines + 1] = "  local x" .. i .. " = " .. i
    end
    lines[#lines + 1] = "end"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "return M"

    local fw = assert(io.open(fixture, "w"))
    fw:write(table.concat(lines, "\n"))
    fw:close()

    local fns = functions.scan_file(fixture)
    local by_name = {}
    for _, fn in ipairs(fns) do
      by_name[fn.name] = fn
    end

    ok(by_name["M.short"].snippet ~= nil, "functions.lua: a short function gets a real snippet")
    eq(by_name["M.short"].snippet_omitted, 0, "functions.lua: ... with nothing omitted")
    ok(
      by_name["M.short"].snippet:find("return 1", 1, true) ~= nil,
      "functions.lua: ... and the snippet is the function's actual body"
    )

    eq(
      by_name["M.long"].snippet_omitted,
      22,
      "functions.lua: a function longer than the cap reports the real overflow"
    )

    os.remove(fixture)
  end

  -- opts.snippet_max_lines: a real config option, not just the module
  -- global directly — confirmed with the user 2026-08-10 after finding
  -- MAX_LINES was a real feature with no way to configure it. Goes through
  -- `M.scan(opts)` (`core/scan.lua`), the actual resolution point, not
  -- `snippet.MAX_LINES` set by hand.
  do
    local scan = require("documentation.core.scan")

    local dr = H.tmpfile("_snippet_opt")
    local lines = { "local M = {}", "", "function M.long()" }
    for i = 1, 30 do
      lines[#lines + 1] = "  local x" .. i .. " = " .. i
    end
    lines[#lines + 1] = "end"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "return M"
    local abs = dr .. "/lua/t/init.lua"
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fw = assert(io.open(abs, "w"))
    fw:write(table.concat(lines, "\n"))
    fw:close()

    local ir_capped =
      scan.scan({ root = dr, source = "lua/t", lua_root = "lua", snippet_max_lines = 10 })
    eq(
      ir_capped.nodes["lua/t"].functions[1].snippet_omitted,
      22,
      "opts.snippet_max_lines=10: 32-line function omits 22"
    )
    eq(
      snippet.MAX_LINES,
      10,
      "opts.snippet_max_lines resolved into snippet.MAX_LINES for this scan"
    )

    -- The very next scan, no override: back to the real default, not stuck
    -- at 10 from the call above — the whole reason this is reset per scan
    -- rather than left as a permanent mutation.
    local ir_default = scan.scan({ root = dr, source = "lua/t", lua_root = "lua" })
    eq(
      snippet.MAX_LINES,
      snippet.DEFAULT_MAX_LINES,
      "a scan with no override resets MAX_LINES, does not inherit the previous scan's"
    )
    eq(
      ir_default.nodes["lua/t"].functions[1].snippet_omitted,
      0,
      "same function, no override: nothing omitted (32 lines, cap is 40)"
    )
  end
end
