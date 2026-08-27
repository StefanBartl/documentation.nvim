---@module 'documentation.bindings.keymaps'
--- Resolving user key overrides against a default binding table.
---
--- **The bindings themselves are not here, deliberately.** `:DocBrowse`'s
--- `KEYS` table lives beside its handlers in `editor/browse/init.lua`, because
--- every entry's `run` closes over that module's navigation state (`go`,
--- `enter`, `set_dir`, the trail helpers). Moving the table here would mean
--- exporting a dozen internal functions purely to let a second file reference
--- them — the cohesion that makes the table trustworthy as the single source
--- of what the keys do is exactly what the move would break.
---
--- What *is* generic is the override rule: apply `opts.keys`, validate the
--- action names, mark disabled entries. That is what this module owns, and it
--- takes the defaults as a parameter, so a second keymapped surface added
--- later gets the same semantics for free rather than reimplementing them.
---
--- The plugin installs **no global keymaps at all**. Everything it binds is
--- buffer-local to a scratch buffer it created, which is why an override only
--- has to be free inside that buffer. See `bindings/autocmds.lua` for the same
--- accounting of autocommands.
---
--- **Why not `lib.nvim.bindings.keymap`'s registry** (2026-08-27), when every
--- other plugin here now declares its keymaps through it: the registry earns
--- its keep by turning a plugin's *fixed preset* into named, overridable
--- actions and recording them centrally. This surface already has all of
--- that -- named ids, list-or-single overrides, `false` for "declared but
--- off", an unknown-id report -- and it has three things the registry has no
--- shape for: `where`, which decides whether a key lands on the list pane or
--- the detail pane; `only`, which scopes a key to some of the browser's
--- modes; and the `run(st)` closures over one browser instance's state, of
--- which two may be open at once with different bindings. The central record
--- would fill with per-instance duplicates of keys that live and die with a
--- float. Passing on it here is the same judgement that keeps `KEYS` beside
--- its handlers rather than in this file.

local M = {}

---Apply `overrides` over `defaults`.
---
---Returns a fresh list rather than mutating `defaults`: two browsers opened
---with different options in one session must not see each other's bindings,
---and the defaults are a module-level table that would otherwise carry the
---first caller's overrides for the rest of the process.
---
---An unknown id is reported rather than ignored. A silently dropped override
---is the worst outcome here — the user typed a rebinding, the surface opened
---with the default key, and nothing anywhere says why.
---@generic T: { id: string, keys: string[] }
---@param defaults T[] The authoritative binding table.
---@param overrides table<string, string|string[]|false>? User overrides, by action id.
---@param notify table? `lib.nvim.notify` instance for the unknown-id warning.
---@return T[] resolved
function M.resolve(defaults, overrides, notify)
  overrides = overrides or {}

  local known = {}
  for _, spec in ipairs(defaults) do
    known[spec.id] = true
  end

  local unknown = {}
  for id in pairs(overrides) do
    if not known[id] then
      unknown[#unknown + 1] = tostring(id)
    end
  end
  if #unknown > 0 and notify then
    table.sort(unknown)
    notify.warn(
      ("opts.keys: no such action: %s  (known: %s)"):format(
        table.concat(unknown, ", "),
        table.concat(
          vim.tbl_map(function(s)
            return s.id
          end, defaults),
          ", "
        )
      )
    )
  end

  local out = {}
  for _, spec in ipairs(defaults) do
    local o = overrides[spec.id]
    if o == false then
      -- Kept in the list, marked: a cheatsheet that still names the action and
      -- says it is off is a far better answer to "where did `p` go" than an
      -- entry that vanished.
      out[#out + 1] = vim.tbl_extend("force", {}, spec, { keys = {}, disabled = true })
    elseif o ~= nil then
      local keys
      if type(o) == "string" then
        keys = { o }
      else
        keys = o
      end
      out[#out + 1] = vim.tbl_extend("force", {}, spec, { keys = keys })
    else
      out[#out + 1] = spec
    end
  end
  return out
end

return M
