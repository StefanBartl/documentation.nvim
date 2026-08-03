---@module 'documentation.bindings.usrcmds.browse'
--- `:DocBrowse [live] [history|trail|endpoints|module]` — the same map,
--- navigated inside the editor.
---
--- Its own command rather than a `:DocMap browse` subcommand: `:DocMap` is a
--- *generator* (every action of it writes or verifies artifacts), while this
--- only ever reads. Folding a read-only viewer into a command whose bare form
--- rewrites files on disk is the kind of surprise that gets a command bound to
--- a key and then regretted.

local M = {}

---Parse `:DocBrowse`'s argument string.
---
---Split out and returned as a table so the spec can exercise the grammar
---without mounting a browser: `live` is a *prefix* the module name follows,
---while `history` and `trail` stand where a module name would.
---@param rest string
---@return { live: boolean, mode: string?, center: string? }
function M.parse(rest)
  rest = vim.trim(rest or "")

  local live = false
  local mode = nil
  local target = rest

  local head, tail = rest:match("^(%S+)%s*(.-)$")
  if head == "live" then
    live = true
    target = tail
    head, tail = target:match("^(%S+)%s*(.-)$")
  end
  -- `history`, `trail` and `endpoints` open straight into their own list.
  -- None takes a module, so anything after them would be meaningless.
  if head == "history" or head == "trail" or head == "endpoints" then
    mode = head
    target = tail or ""
  end

  return { live = live, mode = mode, center = target ~= "" and target or nil }
end

---@param ctx Documentation.Bindings.Ctx
---@param arg string The whole argument string.
function M.run(ctx, arg)
  local parsed = M.parse(arg)
  local cfg = ctx.cfg

  require("documentation.editor.browse").open({
    root = cfg.root,
    source = cfg.source,
    out_dir = cfg.out_dir,
    lua_root = cfg.lua_root,
    -- Forwarded rather than defaulted here: `nil` means "the browser's own
    -- default", and re-stating those defaults in this call would be a second
    -- copy of them that only this entry point gets.
    keys = cfg.keys,
    which_key = cfg.which_key,
    live = parsed.live,
    mode = parsed.mode,
    center = parsed.center,
  })
end

return M
