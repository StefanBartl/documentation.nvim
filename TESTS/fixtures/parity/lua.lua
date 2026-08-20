---@module 'parity.lua'
--- Parity fixture — Lua.
---
--- One documented export, one internal helper, a require, a call, a
--- module-level constant and a marker. See `scripts/parity.lua`.

local other = require("parity.other")

local MAX = 10

local M = {}

---@internal
---@param n integer
---@return integer
local function double(n)
  return n * 2
end

---Widen a value.
---@param n integer How much.
---@return integer widened
function M.widen(n)
  -- TODO: cap at MAX
  return double(n) + other.bump(MAX)
end

return M
