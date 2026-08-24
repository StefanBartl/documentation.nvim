---@module 'documentation.integrations.menu'
---@brief Context-menu entries for nvzone/menu (soft, opt-in integration).
---@description
--- documentation.nvim "owns" the `:DocBrowse` list buffer it creates, so
--- this ships both the item builder (this file) and the mouse trigger
--- (wired in `documentation.editor.browse`'s `bind(st)`, via
--- `lib.nvim.contextmenu.bind_buffer`). Entries mirror `st.keys` — the
--- browse session's resolved key table, already reflecting any
--- `opts.keys` overrides/disables — one-to-one, so right-click never
--- offers anything the keyboard doesn't already provide.
---
--- Only list-buffer entries are included (`where == "detail"` keys are
--- excluded, since the trigger lives on the list buffer, not the detail
--- pane), and only the ones applicable to the browser's *current* mode
--- (deps/calls/trail/history/endpoints/…), same as the `?` cheatsheet
--- shows. Self-gating via `opts.menu` (default true, mirrors
--- `opts.which_key`'s opt-out shape).

local contextmenu = require("lib.nvim.contextmenu")

local M = {}

---@internal
--- Mirrors `documentation.editor.browse`'s private `applies_in` — duplicated
--- rather than exported, since it's an internal implementation detail of
--- the browse state machine, not part of its public surface.
---@param spec table
---@param mode string
---@return boolean
local function applies_in(spec, mode)
  if not spec.only then
    return true
  end
  if type(spec.only) == "string" then
    return spec.only == mode
  end
  return vim.tbl_contains(spec.only, mode)
end

--- Build the DocBrowse context-menu entries for a browse session.
--- Returns an empty list when `st` is missing/malformed, so a trigger can
--- call this unconditionally.
---@param st table browse session state, as bound in `browse/init.lua`'s `bind(st)` (`st.keys`, `st.mode`)
---@return Lib.ContextMenu.Item[]
function M.items(st)
  if type(st) ~= "table" or type(st.keys) ~= "table" then
    return {}
  end

  local out = {}
  for _, spec in ipairs(st.keys) do
    if spec.run and not spec.disabled and spec.where ~= "detail" and applies_in(spec, st.mode) then
      local label = (spec.desc:gsub("^%l", string.upper))
      local rtxt = spec.keys and spec.keys[1]
      local e = contextmenu.entry(true, "  " .. label, function()
        spec.run(st)
      end, rtxt)
      if e then
        out[#out + 1] = e
      end
    end
  end
  return out
end

--- Convenience: the entries wrapped as a single nested submenu entry, for
--- hosts that prefer a "DocBrowse ▸" fly-out. Returns nil when there is
--- nothing to show.
---@param label? string
---@param st table
---@return Lib.ContextMenu.Item|nil
function M.submenu(label, st)
  return contextmenu.submenu(label or "  DocBrowse", M.items(st))
end

return M
