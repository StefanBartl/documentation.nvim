---@module 'documentation.bindings.usrcmds.browse'
--- `:DocBrowse [live] [history|trail|endpoints|telemetry|loaded|module]` —
--- the same map, navigated inside the editor.
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
  -- `history`, `trail`, `endpoints`, `telemetry` and `loaded` open straight
  -- into their own list. None takes a module, so anything after them would
  -- be meaningless.
  if
    head == "history"
    or head == "trail"
    or head == "endpoints"
    or head == "telemetry"
    or head == "loaded"
  then
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

  -- `opts.browse` is presentation, so it is read as a whole table rather
  -- than field by field: every key of `Documentation.BrowseConfig` is a
  -- passthrough to `Documentation.Browse.Opts` under the same name, and a
  -- per-field list here would be a second place to update each time one is
  -- added — which is exactly how `width`/`height`/`list_width`/`theme`/
  -- `depth` came to exist on the browser and be unreachable from a spec.
  local browse = cfg.browse or {}

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
    menu = cfg.menu,
    width = browse.width,
    height = browse.height,
    list_width = browse.list_width,
    theme = browse.theme,
    depth = browse.depth,
    -- `telemetry` mode's own join (ECOSYSTEM.md step 8) needs a namespace to
    -- read `runtime-analysis.telemetry` data by — see `Documentation.Browse.
    -- Opts.title`'s own doc-comment for why this is the same `title` every
    -- other command already has, not a second thing to configure.
    title = cfg.title,
    telemetry_namespace = cfg.telemetry_namespace,
    live = parsed.live,
    -- The argument wins over the configured default, and `nil` from the
    -- parser is what lets it: `:DocBrowse history` says which list to open,
    -- `opts.browse.mode` says which one to open when the command says
    -- nothing. A configured default that overrode an explicit argument
    -- would make the command's own grammar unreliable.
    mode = parsed.mode or browse.mode,
    center = parsed.center,
  })
end

return M
