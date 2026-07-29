---@module 'documentation.bindings.docs'
--- Renders `docs/BINDINGS.md` from the live binding tables.
---
--- Generated, not written by hand, and that is not a convenience: a
--- hand-maintained list of keys inside a plugin whose entire purpose is
--- detecting drift between documentation and code would be indefensible. The
--- `?` cheatsheet already renders from `KEYS` for the same reason; this is the
--- same read, aimed at a file instead of a float.
---
--- Three sources, each the only place its facts exist:
---   keymaps      `browse.keyspecs()`            — the `KEYS` table
---   usercommands `bindings.autocmds.usrcmds`    — the command manifest
---   autocommands `bindings.autocmds.list`       — the autocmd manifest
---
--- Pure: takes nothing, returns a string. `scripts/gen_map.lua` writes it, and
--- a spec asserts every bound key appears in the output — so the file cannot
--- go stale without something going red.

local M = {}

---Escape a key notation for a Markdown table cell.
---
---`<CR>`, `<C-o>` and friends are read as HTML tags by every Markdown renderer
---GitHub included, so they vanish from the rendered page entirely. Backticks
---alone do not save them inside a table cell when the cell also contains a
---pipe, so the pipe is escaped too.
---@param s string
---@return string
local function cell(s)
  return (s:gsub("|", "\\|"))
end

---`only` as readable prose.
---@param spec Documentation.Browse.KeySpec
---@return string
local function scope(spec)
  if not spec.only then
    return "all"
  end
  if type(spec.only) == "string" then
    return tostring(spec.only)
  end
  return table.concat(spec.only --[[@as string[] ]], ", ")
end

---@return string
function M.render()
  local browse = require("documentation.editor.browse")
  local manifest = require("documentation.bindings.autocmds")
  local specs, modes = browse.keyspecs()

  local out = {}
  local function put(s)
    out[#out + 1] = s
  end

  put("# Bindings")
  put("")
  put("Every key, user command and autocommand this plugin installs.")
  put("")
  put("**Generated** by `documentation.bindings.docs` from the tables that")
  put("actually drive the plugin — do not edit by hand. Regenerate with")
  put("`nvim --headless -l scripts/gen_map.lua`.")
  put("")

  -- Commands ---------------------------------------------------------------
  put("## User commands")
  put("")
  put("| Command | Arguments | What it is |")
  put("|---|---|---|")
  for _, c in ipairs(manifest.usrcmds) do
    put(("| `:%s` | `%s` | %s |"):format(c.name, cell(c.args), cell(c.why)))
  end
  put("")
  put("Both names are configurable — `opts.command_name` and")
  put("`opts.browse_command_name` — so a second `setup()` call (a plugin")
  put("generating its own map) does not overwrite this one.")
  put("")

  -- Keymaps ----------------------------------------------------------------
  put("## Keymaps")
  put("")
  put("**The plugin installs no global keymaps.** Every binding below is")
  put("buffer-local to the `:DocBrowse` scratch buffer and set with `nowait`,")
  put("so it can only ever shadow a key *inside* that buffer.")
  put("")
  put(
    ("Modes (`1`…`%d`): %s. These are positional and deliberately not"):format(
      #modes,
      table.concat(modes, ", ")
    )
  )
  put("rebindable — see `Documentation.Browse.KeyAction`.")
  put("")
  put("| Keys | Action | Modes | Does |")
  put("|---|---|---|---|")
  for _, spec in ipairs(specs) do
    local keys = {}
    for _, k in ipairs(spec.keys) do
      keys[#keys + 1] = "`" .. k .. "`"
    end
    -- The one distinction a generated list must not lose: `run == nil` means
    -- documented but deliberately left native, not "missing".
    local desc = spec.desc
    if not spec.run then
      desc = desc .. " *(native Vim key, not bound)*"
    end
    put(
      ("| %s | `%s` | %s | %s |"):format(
        cell(table.concat(keys, " ")),
        spec.id,
        scope(spec),
        cell(desc)
      )
    )
  end
  put("")
  put("Rebind or disable any of them with `opts.keys`, keyed by the **Action**")
  put("column — not by the default key, so a rebinding survives a change of")
  put("defaults. `false` disables an action; it then still appears in the `?`")
  put("cheatsheet, marked `(disabled)`.")
  put("")

  -- Autocommands -----------------------------------------------------------
  put("## Autocommands")
  put("")
  put("All created lazily. Requiring `documentation` installs none of them.")
  put("")
  for _, a in ipairs(manifest.list) do
    put(("### `%s` — %s"):format(table.concat(a.events, "`, `"), a.scope))
    put("")
    put(("**Owner:** `%s`  "):format(a.owner))
    put(("**Lifetime:** %s"):format(a.lifetime))
    put("")
    put(a.why)
    put("")
  end

  return table.concat(out, "\n")
end

return M
