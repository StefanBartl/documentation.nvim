---@module 'documentation.config'
--- Resolving a full `Documentation.Opts` for a repository: the defaults in
--- [`DEFAULTS.lua`](DEFAULTS.lua), what can be derived from `root`, and the
--- merge rule every entry point runs user options through.
---
--- This is the file that used to know one particular repository's layout. It
--- knows none now: `build()` derives everything it can from `root` itself and
--- takes the rest as overrides, which is what lets `:DocMap` work in a checkout
--- nobody configured and lets a plugin pin its own layout in three lines.
---
--- Auto-detection is deliberately shallow — one `lua/<name>` probe, no
--- walking, no guessing at nested trees. A wrong guess that looks confident is
--- worse than an obvious default the user overrides once in their spec.
---
--- Deliberately **not** under `core/`, where it lived until the config/bindings
--- split: `documentation.core` is the pipeline (scan → check → render), and
--- both halves plus the command layer read their options from here. A base
--- module that every layer depends on is not part of any one of them.
--- `documentation.core.config` remains as a deprecated alias.

local DEFAULTS = require("documentation.config.DEFAULTS")

local M = {}

---Directory names under `lua/` that are never a plugin's own source root.
---@type table<string, true>
local NOT_SOURCE = { ["@types"] = true, spec = true, tests = true }

---Guess `source` for `root`: `lua/<single subdirectory>` when `lua/` holds
---exactly one candidate directory, otherwise plain `lua`.
---
---Neovim plugins almost always have exactly that shape (`lua/documentation`,
---`lua/telescope`, …), and scanning `lua` itself instead would put a
---meaningless extra root node above every real module. When the shape is not
---that — several directories, or none — `lua` is the honest answer rather than
---picking one of several arbitrarily.
---@param root string Absolute repository root, forward slashes.
---@return string source Relative to `root`.
function M.detect_source(root)
  local lua_dir = root .. "/lua"
  if vim.fn.isdirectory(lua_dir) == 0 then
    return "lua"
  end

  local found
  for name, kind in vim.fs.dir(lua_dir) do
    if kind == "directory" and not NOT_SOURCE[name] then
      if found then
        return "lua" -- more than one candidate: do not guess
      end
      found = name
    end
  end

  return found and ("lua/" .. found) or "lua"
end

---Build a full `Documentation.Opts` for `root`, with `overrides` winning over
---every derived default.
---
---`root` is normalised here rather than at each call site: every consumer
---compares it (the registry keys handles on it, `--check` joins it with
---`out_dir`), and a trailing slash or a backslash on Windows would make two
---spellings of the same repository look like two repositories.
---@param root string Absolute repository root.
---@param overrides Documentation.Opts? Merged over the defaults, shallowly.
---@return Documentation.Opts
function M.build(root, overrides)
  root = (tostring(root):gsub("\\", "/"):gsub("/+$", ""))

  ---A copy per call, never `DEFAULTS` itself: the merge below writes into this
  ---table, and mutating the shared defaults would leak one caller's options
  ---into every later `build()` in the process.
  ---@type Documentation.Opts
  local opts = vim.tbl_extend("force", {}, DEFAULTS, {
    root = root,
    source = M.detect_source(root),
    title = vim.fn.fnamemodify(root, ":t"),
  })

  for k, v in pairs(overrides or {}) do
    opts[k] = v
  end

  -- After the merge, not before: an override may have changed `root`, and the
  -- normalisation above would then apply to the wrong value.
  opts.root = (tostring(opts.root):gsub("\\", "/"):gsub("/+$", ""))
  return opts
end

return setmetatable(M, {
  ---`require("documentation.config")(root)` as shorthand for `.build(root)` —
  ---the form `scripts/gen_map.lua` uses.
  __call = function(_, root, overrides)
    return M.build(root, overrides)
  end,
})
