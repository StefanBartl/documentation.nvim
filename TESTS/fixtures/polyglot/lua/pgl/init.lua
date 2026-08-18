---@module 'pgl'
--- The Lua half of the polyglot fixture.
---
--- Function names here are deliberately unlike anything in this repository's
--- own tree: `core/coverage.lua` reads every `.lua` under `TESTS/` looking
--- for mentions of real function names, so a fixture calling something
--- `read` or `parse` would silently credit an unrelated function with being
--- tested.

local M = {}

---Add two numbers.
---@param a number
---@param b number
---@return number
function M.polyglot_fixture_add(a, b)
  if a > b then
    return a + b
  end
  return b + a
end

return M
