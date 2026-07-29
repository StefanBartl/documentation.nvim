---@module 'documentation.editor.browse.whichkey'
--- Optional which-key registration for the `:DocBrowse` list buffer.
---
--- Its own file, lazily required from `bind()`, for the same reason `browse`
--- itself is lazily required from `documentation/init.lua`: nothing on the
--- generate/check path needs which-key, and a `require` at the top of
--- `browse/init.lua` would make a headless `--check` run load a UI plugin.
---
--- Registration is **descriptive, not authoritative**. The keys are already
--- bound by `bind()` with a `desc` on each one, and which-key can discover
--- those on its own; what this adds is the grouping and the guarantee that the
--- popup names an action the way the `?` cheatsheet does. If which-key is
--- absent, or its API is a version this does not know, nothing happens and the
--- browser is exactly what it was.
---
--- Two API generations are handled because both are in wide use: v3's
--- `wk.add(specs)` and v2's `wk.register(mappings, opts)`. Neither is probed
--- by version number — the presence of the function is the test, which does
--- not go stale when someone's pinned commit sits between releases.

local M = {}

---Modes a spec does *not* apply in, as a short parenthetical.
---
---which-key has no notion of the browser's internal mode, and the popup is
---read at the moment a key is being looked for — so an entry that will do
---nothing right now has to say so in its own text or not at all. The
---cheatsheet greys those out live; this is the static approximation of that.
---@param spec Documentation.Browse.KeySpec
---@return string
local function scope_hint(spec)
  local only = spec.only
  if not only then
    return ""
  end
  -- Branch rather than `type(x) == "string" and {x} or x`: the and/or form is
  -- equivalent at runtime but leaves `only` un-narrowed for the type checker,
  -- which then reads the `string` arm as a possible argument to `concat`.
  local modes
  if type(only) == "string" then
    modes = { only }
  else
    modes = only
  end
  return ("  (%s only)"):format(table.concat(modes, "/"))
end

---Register `specs` for `bufnr` with which-key, if it is installed.
---
---Returns whether anything was registered, so a caller (or a spec) can tell
---"which-key is absent" apart from "which-key is present and refused".
---@param bufnr integer List buffer the bindings are local to.
---@param specs Documentation.Browse.KeySpec[] The **resolved** key set, from `resolve_keys`.
---@param modes string[] Browser modes, for the numeric mode-switch keys.
---@return boolean registered
function M.register(bufnr, specs, modes)
  local ok, wk = pcall(require, "which-key")
  if not ok or type(wk) ~= "table" then
    return false
  end

  ---@type { lhs: string, desc: string }[]
  local flat = {}

  for i, mode in ipairs(modes or {}) do
    flat[#flat + 1] = { lhs = tostring(i), desc = ("show the %s list"):format(mode) }
  end

  for _, spec in ipairs(specs) do
    -- `run == nil` is the documented-but-native case (`j`/`k`), and
    -- `disabled` leaves an empty `keys` list. Neither is bound, and which-key
    -- listing an unbound key is worse than silence: the popup becomes a menu
    -- of things that do not happen.
    if spec.run then
      for _, key in ipairs(spec.keys) do
        flat[#flat + 1] = { lhs = key, desc = spec.desc .. scope_hint(spec) }
      end
    end
  end

  if #flat == 0 then
    return false
  end

  -- v3.
  if type(wk.add) == "function" then
    local items = {}
    for _, e in ipairs(flat) do
      items[#items + 1] = { e.lhs, desc = e.desc, buffer = bufnr, mode = "n" }
    end
    return (pcall(wk.add, items))
  end

  -- v2.
  if type(wk.register) == "function" then
    local mappings = {}
    for _, e in ipairs(flat) do
      mappings[e.lhs] = { e.desc }
    end
    return (pcall(wk.register, mappings, { mode = "n", buffer = bufnr }))
  end

  return false
end

return M
