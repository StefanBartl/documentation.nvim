---@module 'documentation.core.rules_join'
--- Bridge to `rules.nvim`'s catalog for the `rules` browse mode — the
--- `--format=json` consumer sketched in `rules.nvim`'s own BACKLOG.md
--- ("documentation.nvim browser-tab integration"), wired as one more list
--- the same way `telemetry`/`endpoints`/`loaded` already are.
---
--- **Live, not artifact-first.** `telemetry_join` reads a namespace straight
--- off disk with no live Neovim instance required, because the tree being
--- analyzed usually has none for itself. A rules check is different: it
--- needs a loaded ruleset and a running Neovim to evaluate `grep`/
--- `lua_predicate` checks against the very repository this browser is
--- already open inside — there is nothing to read off disk that isn't
--- staler than just asking. `rules.nvim`'s own `M.run_gate_json` already
--- returns a live `Rules.Result[]` table (see its `lua/rules/init.lua`), so
--- this calls that directly rather than shelling out or round-tripping
--- through the JSON string it also returns.
---
--- **Soft dependency throughout**, the same posture `telemetry_join` states
--- for `runtime-analysis.nvim`: `rules.nvim` not being installed, or a gate
--- name nothing is configured for, are both "no data", never an error.

local M = {}

---Which gate `opts` joins against.
---
---Unlike `telemetry_join.namespace` (which falls back to `opts.title`),
---there is no sensible default to derive here: a gate name (`"review"`,
---`"release"`, `"new_project"`) is a `setup({ gates = {...} })` key from the
---checked repository's own `rules.nvim` config, not this tree's display
---name — guessing one would silently join against the wrong gate instead of
---saying "unconfigured".
---@param opts Documentation.Browse.Opts
---@return string?
function M.gate(opts)
  return opts.rules_gate
end

---Run `gate_name` against `root` through a live `rules.nvim`, if installed
---and the gate resolves.
---@param gate_name string
---@param root string
---@return Rules.Result[]? results `nil` when `rules.nvim` is not installed, the gate name is not configured on it, or the call itself errors.
function M.load(gate_name, root)
  local rules = require("documentation.core.soft_require").probe("rules")
  if not rules then
    return nil
  end
  -- `run_gate_json` itself already returns `nil` results (plus an `error`
  -- string) for an unknown gate name rather than raising — the `pcall` here
  -- is only for the case `rules.nvim` is on the rtp but its `setup()` was
  -- never called, which some of its accessors surface as a hard error.
  local ok, _, _, results = pcall(rules.run_gate_json, gate_name, root)
  if not ok or not results then
    return nil
  end
  return results
end

return M
