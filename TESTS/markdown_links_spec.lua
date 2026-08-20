-- TESTS/markdown_links_spec.lua — a summary's relative links survive the
-- copy into `docs/map/`
--
-- **The whole class was broken, not one link.** A module header writes
-- `[DEFAULTS.lua](DEFAULTS.lua)`, which is right where it was written —
-- beside the file it names. `overview.md` copies that sentence into
-- `docs/map/`, where the same text points at `docs/map/DEFAULTS.lua`.
-- Measured across three repositories before the fix: 4 of 4 such links in
-- this one, 1 of 1 in runtime-analysis.nvim, 0 of 0 in lib.nvim. A 100%
-- failure rate for the shape.
--
-- **`dead-readme-link` is right not to catch it**, and establishing that was
-- the first half of the work. `docs.corpus` excludes `out_dir` explicitly,
-- so the check never reads generated output — and should not: you fix a
-- generator rather than lint what it wrote. The defect surfaced from the
-- standalone gate reading the artifact as a plain file, which is exactly the
-- angle a Neovim-side check does not have.
--
-- The two directions of the same path walk now share one implementation
-- (`docs.resolve_link`), which is what this file also pins: `check.lua`
-- resolves a link to find out whether it is dead, the renderer resolves it
-- to rewrite it, and two copies of that walk would be the drift this plugin
-- reports in other people's trees.

return function(H)
  local eq, ok = H.eq, H.ok
  local docs = require("documentation.core.docs")
  local scan = require("documentation.core.scan")
  local render = require("documentation.core.render.markdown")

  -- ---------------------------------------------------------------------
  -- The shared resolver.
  -- ---------------------------------------------------------------------
  eq(
    docs.resolve_link("lua/documentation/config", "DEFAULTS.lua"),
    "lua/documentation/config/DEFAULTS.lua",
    "resolve_link: a bare name resolves beside the file that wrote it"
  )
  eq(
    docs.resolve_link("lua/documentation/core", "../config/init.lua"),
    "lua/documentation/config/init.lua",
    "resolve_link: `..` walks up"
  )
  eq(
    docs.resolve_link("lua/documentation/core", "./x.lua"),
    "lua/documentation/core/x.lua",
    "resolve_link: `.` is a no-op segment, not a directory named `.`"
  )

  -- ---------------------------------------------------------------------
  -- The renderer, end to end over a fixture whose summaries carry every
  -- link shape that matters.
  -- ---------------------------------------------------------------------
  local dr = H.tmpfile("_md_links")
  local function dwrite(rel, lines)
    local abs = dr .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "markdown links spec: fixture must be writable")
    fd:write(table.concat(lines, "\n"))
    fd:close()
  end

  dwrite("lua/t/cfg/DEFAULTS.lua", { "return {}" })
  dwrite("lua/t/cfg/init.lua", {
    "---@module 't.cfg'",
    "--- Defaults live in [DEFAULTS.lua](DEFAULTS.lua), the rule is upstream.",
    "local M = {}",
    "return M",
  })
  dwrite("lua/t/other/init.lua", {
    "---@module 't.other'",
    "--- Reaches [sideways](../cfg/init.lua) and out to "
      .. "[the manual](https://example.com/x) and to [a section](#anchor).",
    "local M = {}",
    "return M",
  })
  dwrite("lua/t/frag/init.lua", {
    "---@module 't.frag'",
    "--- A link with both, [here](../cfg/init.lua#usage).",
    "local M = {}",
    "return M",
  })

  local opts = {
    root = dr,
    source = "lua/t",
    lua_root = "lua",
    out_dir = "docs/map",
    extra_checks = {},
  }
  local ir = scan.scan(opts)
  local md = render(ir, {}, opts)
  ok(type(md) == "string" and #md > 0, "markdown links: the fixture renders")

  ok(
    md:find("](../../lua/t/cfg/DEFAULTS.lua)", 1, true) ~= nil,
    "markdown links: a bare sibling link is rebased to the artifact directory"
  )
  ok(
    md:find("](DEFAULTS.lua)", 1, true) == nil,
    "markdown links: ...and the original, which pointed at docs/map/DEFAULTS.lua, is gone"
  )
  ok(
    md:find("](../../lua/t/cfg/init.lua)", 1, true) ~= nil,
    "markdown links: a `..` link is resolved before being rebased, not concatenated"
  )

  -- Neither of these has a directory to be relative to, so touching them
  -- would be inventing a target.
  ok(
    md:find("](https://example.com/x)", 1, true) ~= nil,
    "markdown links: an absolute URL is left exactly as written"
  )
  ok(md:find("](#anchor)", 1, true) ~= nil, "markdown links: a bare anchor is left alone")

  -- The fragment is not part of the path and must survive the rewrite.
  ok(
    md:find("](../../lua/t/cfg/init.lua#usage)", 1, true) ~= nil,
    "markdown links: a path plus fragment keeps its fragment"
  )

  -- ---------------------------------------------------------------------
  -- And the real artifact, which is what a reader actually clicks. This is
  -- the assertion that would have failed before the fix.
  -- ---------------------------------------------------------------------
  local root = (vim.fn.getcwd():gsub("\\", "/"))
  local fd = io.open(root .. "/docs/map/overview.md", "rb")
  if not fd then
    ok(true, "markdown links: no committed overview.md to check — skipping")
    return
  end
  local committed = fd:read("*a")
  fd:close()

  local broken = {}
  local seen = {}
  for target in committed:gmatch("%]%(([^)]+)%)") do
    if not target:match("^%a[%w+.-]*://") and target:sub(1, 1) ~= "#" and not seen[target] then
      seen[target] = true
      local path = target:match("^([^#]*)") or target
      if path ~= "" then
        local resolved = docs.resolve_link("docs/map", path)
        if vim.uv.fs_stat(root .. "/" .. resolved) == nil then
          broken[#broken + 1] = target .. " -> " .. resolved
        end
      end
    end
  end
  table.sort(broken)
  eq(
    table.concat(broken, "\n    "),
    "",
    "markdown links: every relative link in the committed overview.md resolves to a real file"
  )
end
