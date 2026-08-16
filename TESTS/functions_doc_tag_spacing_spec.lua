-- TESTS/functions_doc_tag_spacing_spec.lua — functions.lua's doc-comment tag
-- parser must accept `--- @param` (a space after the three dashes) exactly
-- like `---@param` (no space). Both are valid, common LuaCATS style --
-- lua-language-server itself accepts both -- but `parse_doc_block`'s tag
-- regex, `^%-%-%-@(%a+)%s*(.*)$`, required the `@` immediately after the
-- third dash. A function documented entirely in the spaced style parsed as
-- having zero `@param`/`@return`/etc lines at all, which
-- `check_undocumented_params` (and every other doc-derived check) then
-- reported as a real gap even though the function was fully documented.
--
-- Found while working through this exact false positive in a real config
-- repo: several files there consistently use `--- @param`, and every
-- function in them came back as "undocumented" despite having a `@param`
-- line for every parameter.

return function(H)
  local eq, ok = H.eq, H.ok
  local functions = require("documentation.core.functions")

  local fixture = H.tmpfile(".lua")
  local lines = {
    "local M = {}",
    "",
    "--- Uses the spaced tag style throughout.",
    "--- @param a string",
    "--- @param b integer",
    "--- @return boolean",
    "function M.spaced(a, b)",
    "  return a ~= nil and b ~= nil",
    "end",
    "",
    "--- Uses the tight tag style throughout, for comparison.",
    "---@param a string",
    "---@param b integer",
    "---@return boolean",
    "function M.tight(a, b)",
    "  return a ~= nil and b ~= nil",
    "end",
    "",
    "return M",
  }

  local fw = assert(io.open(fixture, "w"))
  fw:write(table.concat(lines, "\n"))
  fw:close()

  local fns = functions.scan_file(fixture)
  local by_name = {}
  for _, fn in ipairs(fns) do
    by_name[fn.name] = fn
  end

  os.remove(fixture)

  eq(
    #by_name["M.spaced"].params,
    2,
    "functions.lua: `--- @param` (spaced) is parsed just like `---@param`"
  )
  eq(#by_name["M.spaced"].returns, 1, "functions.lua: `--- @return` (spaced) is parsed too")
  ok(
    by_name["M.spaced"].summary:find("spaced tag style", 1, true) ~= nil,
    "functions.lua: prose above a spaced-tag block is still captured as the summary"
  )

  eq(
    #by_name["M.tight"].params,
    2,
    "functions.lua: `---@param` (tight) still parses, unaffected by the fix"
  )
  eq(
    #by_name["M.tight"].returns,
    1,
    "functions.lua: `---@return` (tight) still parses, unaffected by the fix"
  )
end
