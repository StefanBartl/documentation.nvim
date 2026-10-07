-- TESTS/readme_scope_spec.lua — which modules `missing-readme` asks a README
-- of, and that `<plugin>.health` is not reported as unreferenced.
--
-- Driven through the REAL scanner over small trees on disk, not a synthetic
-- IR. The first version of this spec built the IR by hand with the plugin at
-- depth 1, which is only one of three shapes the scanner produces
-- (`source = "lua/<plugin>"` puts the plugin at depth 0), so it passed while
-- `sessions.nvim` — the repository the rule was written for — still had its
-- `config/` and `marks/` folders reported.
--
-- Both rules came out of one real report: a map of `sessions.nvim` listed five
-- README-less subfolders and an orphaned `sessions.health`. Neither is a
-- defect in that repository — a README for `config/` is not something anyone
-- writes, and `:checkhealth` loads `<plugin>.health` by name.

return function(H)
  local eq = H.eq
  local scan = require("documentation.core.scan")
  local check = require("documentation.core.check")

  ---@param root string
  ---@param rel string
  ---@param module string?
  local function write(root, rel, module)
    local abs = root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "readme_scope: fixture must be writable")
    local lines
    if module then
      lines =
        { "---@module '" .. module .. "'", "--- A fixture module.", "local M = {}", "return M" }
    else
      lines = { "# readme" }
    end
    fd:write(table.concat(lines, "\n"))
    fd:close()
  end

  ---@param root string
  ---@param source string
  ---@return table ir
  local function scanned(root, source)
    return scan.scan({ root = root, source = source, lua_root = "lua" })
  end

  ---@param ir table
  ---@param code string
  ---@return string ids Comma-joined and sorted, because `H.eq` compares tables by identity.
  local function flagged(ir, code)
    local out = {}
    for _, f in ipairs(check.run(ir, { root = "/fake", lua_root = "lua", extra_checks = {} })) do
      if f.check == code then
        out[#out + 1] = f.node
      end
    end
    table.sort(out)
    return table.concat(out, ",")
  end

  -- The shape that started this: `lua/<plugin>` is the source, so the plugin
  -- itself is the scan root (depth 0) and `config/` is depth 1.
  local a = H.tmpfile("_readme_scope_a")
  write(a, "lua/sessions/init.lua", "sessions")
  write(a, "lua/sessions/health.lua", "sessions.health")
  write(a, "lua/sessions/orphan.lua", "sessions.orphan")
  write(a, "lua/sessions/config/init.lua", "sessions.config")
  write(a, "lua/sessions/marks/init.lua", "sessions.marks")
  write(a, "lua/sessions/bindings/keymaps/init.lua", "sessions.bindings.keymaps")
  write(a, "lua/sessions/bindings/usercmds/init.lua", "sessions.bindings.usercmds")
  local ir_a = scanned(a, "lua/sessions")
  eq(
    flagged(ir_a, "missing-readme"),
    "lua/sessions",
    "readme: with source = lua/<plugin> only the plugin is asked, not config/, marks/ or bindings/*"
  )

  -- `<plugin>.health` has no caller by design; a real orphan still is one.
  local orphans = flagged(ir_a, "unreferenced-module")
  eq(
    orphans:find("health", 1, true),
    nil,
    "orphans: a health module is loaded by :checkhealth, not required"
  )
  eq(
    orphans:find("orphan", 1, true) ~= nil,
    true,
    "orphans: a module nothing requires is still reported"
  )

  -- `source = "lua"`: the plugin is depth 1 below the `lua` namespace.
  local b = H.tmpfile("_readme_scope_b")
  write(b, "lua/plug/init.lua", "plug")
  write(b, "lua/plug/sub/init.lua", "plug.sub")
  write(b, "lua/other/init.lua", "other")
  eq(
    flagged(scanned(b, "lua"), "missing-readme"),
    "lua/other,lua/plug",
    "readme: with source = lua each plugin is asked, nested folders are not"
  )

  -- Size: ten source files make a nested module a subsystem; nine do not.
  local c = H.tmpfile("_readme_scope_c")
  write(c, "lua/p/init.lua", "p")
  write(c, "lua/p/big/init.lua", "p.big")
  write(c, "lua/p/small/init.lua", "p.small")
  for i = 1, 9 do
    write(c, ("lua/p/big/f%d.lua"):format(i), ("p.big.f%d"):format(i))
  end
  for i = 1, 8 do
    write(c, ("lua/p/small/f%d.lua"):format(i), ("p.small.f%d"):format(i))
  end
  eq(
    flagged(scanned(c, "lua/p"), "missing-readme"),
    "lua/p,lua/p/big",
    "readme: ten files (init + nine) is big, nine (init + eight) is not"
  )

  -- A module that has a README is never reported, at any size.
  write(c, "lua/p/big/README.md")
  write(c, "lua/p/README.md")
  eq(flagged(scanned(c, "lua/p"), "missing-readme"), "", "readme: a module with a README is silent")
end
