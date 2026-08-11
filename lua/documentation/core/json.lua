---@module 'documentation.core.json'
--- Deterministic JSON encoding for docmap artifacts.
---
--- `vim.json.encode` gives no ordering guarantee for object keys, because Lua
--- table iteration order is unspecified. That is fine for transport and fatal
--- here: two runs over an unchanged tree produced byte-different files, so
--- `--check` reported the map as stale immediately after generating it, and
--- every regeneration would have shown up as a meaningless diff.
---
--- This encoder sorts keys, so identical input always yields identical bytes.
--- Scalars are delegated to `vim.json.encode`, which already escapes strings
--- correctly — only the container ordering is reimplemented.

local M = {}

---True when `t` should be encoded as a JSON array.
---@param t table
---@return boolean
local function is_array(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" then
      return false
    end
    n = n + 1
  end
  return n == #t
end

---@param value any
---@return string
function M.encode(value)
  local ty = type(value)

  if value == nil then
    return "null"
  end
  if ty == "number" then
    -- Determinism across host Lua implementations, not just across runs.
    --
    -- Every number in the IR that came out of a division is a float, and
    -- LuaJIT (what Neovim embeds) writes an integral float as `100` while
    -- PUC Lua 5.3+ writes `100.0`. Since `--check` byte-compares the
    -- artifact, that difference is not cosmetic: the same tree scanned by
    -- `nvim --headless` and by `standalone/docmap.lua` produced maps that
    -- differed in exactly these characters and nothing else, which reads as
    -- "the map is stale" rather than as "two Lua versions print floats
    -- differently". Normalising here keeps the guarantee this module exists
    -- for. Under LuaJIT it changes no byte — `%d` and `%.14g` agree on an
    -- integral value — so the committed artifact is unaffected.
    if value == value and value - value == 0 and value % 1 == 0 and math.abs(value) < 2 ^ 53 then
      return string.format("%d", value)
    end
    return vim.json.encode(value)
  end
  if ty == "boolean" then
    return vim.json.encode(value)
  end
  if ty == "string" then
    return vim.json.encode(value)
  end
  if ty ~= "table" then
    return "null"
  end

  -- vim.NIL and empty tables: an empty table is ambiguous, and every empty
  -- container in the IR is a list (children, types, findings).
  if next(value) == nil then
    return "[]"
  end

  if is_array(value) then
    local parts = {}
    for i = 1, #value do
      parts[i] = M.encode(value[i])
    end
    return "[" .. table.concat(parts, ",") .. "]"
  end

  local keys = {}
  for k in pairs(value) do
    keys[#keys + 1] = tostring(k)
  end
  table.sort(keys)

  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = vim.json.encode(k) .. ":" .. M.encode(value[k])
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

return M
