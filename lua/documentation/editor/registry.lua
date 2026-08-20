---@module 'documentation.editor.registry'
--- `install()` / `uninstall()`: a live, in-memory `Documentation.Handle` around
--- a scanned IR, as opposed to `generate()`'s one-shot scan-render-write.
---
--- This is the "objects in source code" half of docmap — another plugin's
--- Lua code reaches for `handle.ir()` directly instead of reading and
--- parsing `module_map.json` off disk, and can subscribe to `on_change` to
--- react when the tree does.
---
--- Deliberately has no opinion about user commands: it does not create
--- `:DocMap` or any other usercmd itself. `docmap.command.setup()` is what
--- layers a named command on top of a handle, precisely so two independent
--- `install()` calls (this repo's own map, and a consuming plugin's map)
--- never fight over registering the same command name — that collision was
--- the actual bug this split avoids, not a hypothetical one.

local notify = require("lib.nvim.notify").create("[documentation]")
local autocmd = require("lib.nvim.autocmd")

local M = {}

---@type table<string, { opts: Documentation.Opts, ir: Documentation.IR, findings: Documentation.Finding[], watchers: fun(ir: Documentation.IR, findings: Documentation.Finding[])[], augroup: integer?, debounce: Lib.Debounce.Handle?, ch_augroup: integer?, diag_augroup: integer?, diag_unsub: (fun())?, mdview_wired: boolean?, handle: Documentation.Handle, rescan_fn: fun(opts?: table): Documentation.IR, Documentation.Finding[] }>
local registry = {}

---@param root string
---@return string
local function norm_root(root)
  return (root:gsub("\\", "/"):gsub("/+$", ""))
end

---@param entry table
local function notify_watchers(entry)
  for _, cb in ipairs(entry.watchers) do
    -- One misbehaving subscriber must not break the others or the rescan
    -- that triggered this.
    local ok, err = pcall(cb, entry.ir, entry.findings)
    if not ok then
      vim.schedule(function()
        notify.warn("on_change subscriber errored: " .. tostring(err))
      end)
    end
  end
end

---Start watching an already-installed root, if it is not watching already.
---
---Split out of `install()` so a handle can be *upgraded* to watching without
---being replaced. That distinction is the whole point: `install()` treats a
---collision as "replace, don't stack", which tears down `entry.watchers` —
---so upgrading by re-installing would silently unsubscribe everyone who had
---registered an `on_change`.
---
---The case that made this necessary: `docmap.command.setup()` installs with
---the plain config, which sets no `watch`. Any later `:DocBrowse live` then
---found that non-watching handle, reused it as designed, and produced a
---"live" view that never re-scanned on write. The mode's entire promise,
---broken by nothing more than which command ran first.
---
---Idempotent: called on a root that is already watching, or one that was
---never installed, it does nothing.
---@param root string
---@return boolean watching True if the root is watching when this returns.
function M.ensure_watch(root)
  root = norm_root(root)
  local entry = registry[root]
  if not entry then
    return false
  end
  if entry.augroup then
    return true
  end

  local opts = entry.opts
  -- Every source root, not one: this decides whether a buffer belongs to the
  -- tree, and with `lua/` beside `src/` a single directory would silently
  -- stop watching half of it.
  local source_dirs = {}
  for _, src in ipairs(require("documentation.config").sources(opts)) do
    source_dirs[#source_dirs + 1] = root .. "/" .. src
  end
  local is_subpath = require("lib.nvim.fs.is_subpath")
  -- Raw nvim_create_augroup on purpose, not autocmd.group(): uninstall()
  -- below deletes this group by numeric id (nvim_del_augroup_by_id), which
  -- autocmd.group()'s name -> id cache has no visibility into — a second
  -- install() for the same root would hand back the now-stale cached id
  -- instead of creating a fresh group.
  local group = vim.api.nvim_create_augroup("LibDocmapWatch:" .. root, { clear = true })
  local debounce = require("lib.nvim.debounce").new(function()
    entry.rescan_fn()
  end, opts.watch_ms or 500)

  -- Scoping via an autocmd *glob pattern* (e.g. "<root>/<source>/**/*.lua")
  -- is the obvious approach and the wrong one: Vim's pattern matcher compares
  -- against the raw buffer path, which is OS-native (backslashes on
  -- Windows), while any path built here is forward-slash — verified this
  -- mismatches and the autocmd silently never fires. `is_subpath` already
  -- exists for exactly this normalize-both-sides comparison (its own
  -- history has the same backslash bug on record), so scope with a cheap
  -- extension-only pattern and an explicit subpath check in the callback
  -- instead of trusting the glob engine with directory structure.
  autocmd.create({ "BufWritePost" }, function(args)
    local buf_path = vim.api.nvim_buf_get_name(args.buf)
    local in_tree = false
    if buf_path ~= "" then
      for _, dir in ipairs(source_dirs) do
        if is_subpath(buf_path, dir) then
          in_tree = true
          break
        end
      end
    end
    if in_tree then
      debounce.call()
    end
  end, {
    group = group,
    pattern = "*.lua",
  })

  entry.augroup = group
  entry.debounce = debounce
  return true
end

---Attach the second, narrow LSP client `documentation.editor.callhierarchy`
---implements — `textDocument/prepareCallHierarchy`, `callHierarchy/
---incomingCalls`/`outgoingCalls`, and a hover-injected caller/callee count —
---to Lua buffers under this root's own source dir, if not attached already.
---
---Split out of `install()` the same way `ensure_watch` is above, for the
---identical reason: a handle installed without `callhierarchy` can be
---upgraded later without being replaced or losing its `on_change`
---subscribers.
---
---Idempotent: called on a root already wired for this, or one that was
---never installed, it does nothing.
---@param root string
---@return boolean wired True if call-hierarchy attachment is wired when this returns.
function M.ensure_callhierarchy(root)
  root = norm_root(root)
  local entry = registry[root]
  if not entry then
    return false
  end
  if entry.ch_augroup then
    return true
  end

  local opts = entry.opts
  -- Every source root, not one: this decides whether a buffer belongs to the
  -- tree, and with `lua/` beside `src/` a single directory would silently
  -- stop watching half of it.
  local source_dirs = {}
  for _, src in ipairs(require("documentation.config").sources(opts)) do
    source_dirs[#source_dirs + 1] = root .. "/" .. src
  end
  local is_subpath = require("lib.nvim.fs.is_subpath")
  local callhierarchy = require("documentation.editor.callhierarchy")

  local group = vim.api.nvim_create_augroup("LibDocmapCallHierarchy:" .. root, { clear = true })
  -- BufReadPost/BufNewFile, not FileType: a buffer can be `lua`-filetyped
  -- before its name is set (a `:enew` later saved as `.lua`), and the path
  -- check below needs a real name to compare against `source_dirs`. Both
  -- events fire with the buffer name already in place for the cases that
  -- matter here — an existing file being opened, or a new one being
  -- written for the first time.
  autocmd.create({ "BufReadPost", "BufNewFile" }, function(args)
    local buf_path = vim.api.nvim_buf_get_name(args.buf)
    local in_tree = false
    if buf_path ~= "" then
      for _, dir in ipairs(source_dirs) do
        if is_subpath(buf_path, dir) then
          in_tree = true
          break
        end
      end
    end
    if in_tree then
      -- `entry.handle` is read here, not captured — at the time this
      -- function is *defined* (inside `install()`, before the handle table
      -- exists yet), it would be nil; by the time an autocmd actually
      -- *fires*, `install()` has long since returned and set it.
      -- The namespace is resolved here rather than inside the client:
      -- `entry.opts` is the only place `telemetry_namespace` exists, and a
      -- handle carries no options at all.
      callhierarchy.attach(
        args.buf,
        entry.handle,
        require("documentation.core.telemetry_join").namespace(opts)
      )
    end
  end, {
    group = group,
    pattern = "*.lua",
  })

  entry.ch_augroup = group
  return true
end

---Publish `documentation.bindings.diagnostics` for this root: an initial
---pass over every buffer already open under `source`, plus a live refresh
---on every subsequent `on_change` (a watch-triggered rescan, or a manual
---`:DocMap`) and on every later buffer open under `source` too.
---
---Unlike `ensure_watch`/`ensure_callhierarchy` above, this needs
---`entry.handle` to exist *synchronously* at call time — `handle.on_change`
---is subscribed to once, right here, not read lazily from inside a later
---autocmd callback the way `ensure_callhierarchy`'s does — so `install()`
---calls this only after `entry.handle` is actually built, not alongside
---`watch`/`callhierarchy` above where the handle does not exist yet.
---
---Idempotent: called on a root already wired for this, or one that was
---never installed, it does nothing.
---@param root string
---@return boolean wired True if diagnostics publishing is wired when this returns.
function M.ensure_diagnostics(root)
  root = norm_root(root)
  local entry = registry[root]
  if not entry or not entry.handle then
    return false
  end
  if entry.diag_augroup then
    return true
  end

  local opts = entry.opts
  -- Every source root, not one: this decides whether a buffer belongs to the
  -- tree, and with `lua/` beside `src/` a single directory would silently
  -- stop watching half of it.
  local source_dirs = {}
  for _, src in ipairs(require("documentation.config").sources(opts)) do
    source_dirs[#source_dirs + 1] = root .. "/" .. src
  end
  local is_subpath = require("lib.nvim.fs.is_subpath")
  local diagnostics = require("documentation.bindings.diagnostics")

  diagnostics.publish(root, entry.handle)
  entry.diag_unsub = entry.handle.on_change(function()
    diagnostics.publish(root, entry.handle)
  end)

  local group = vim.api.nvim_create_augroup("LibDocmapDiagnostics:" .. root, { clear = true })
  autocmd.create({ "BufReadPost", "BufNewFile" }, function(args)
    local buf_path = vim.api.nvim_buf_get_name(args.buf)
    local in_tree = false
    if buf_path ~= "" then
      for _, dir in ipairs(source_dirs) do
        if is_subpath(buf_path, dir) then
          in_tree = true
          break
        end
      end
    end
    if in_tree then
      diagnostics.publish(root, entry.handle)
    end
  end, {
    group = group,
    pattern = "*.lua",
  })

  entry.diag_augroup = group
  return true
end

---Push a live, mdview-shaped Markdown rendering of this root's IR to an
---already-running mdview.nvim session, so a browser tab previewing this
---root's `overview.md` path stays in sync with the in-memory IR instead of
---only with whatever `generate()` last wrote to disk. Tier A of the roadmap's
---"mdview.nvim integration" item — see `core/render/mdview.lua`'s own header
---for the two ammonia/Mermaid constraints that shape its output.
---
---Soft dependency, the same posture `opts.pdf`'s pdfport.nvim has:
---`core.soft_require.probe("mdview.core.state")` is the presence probe, so
---documentation.nvim never hard-depends on mdview.nvim. Not installed at
---all → silent no-op. Installed but no session attached (`:MDViewStart`
---never run, or already stopped) → each push checks `state.is_attached()`/
---`state.get_server()` (the same guard `mdview.open()` itself uses) and
---skips rather than queuing a doomed HTTP POST — avoids retry-exhausted
---error notifications for a user who enabled `opts.mdview` but has not
---started a session yet, and avoids the alternative of a `wait_ready()`
---health poll (up to 10s of `/health` polling) firing on every single
---rescan while no server is running at all.
---
---Pushes to `<root>/<out_dir>/overview.md` — the same path `generate()`
---writes `overview.md` to — so opening that file and running `:MDViewStart`
---is the whole setup; no separate mdview-specific path or command.
---
---Note: like `watch`/`callhierarchy`/`diagnostics`, this only reacts to
---`on_change` — which fires on `install()`'s initial scan and on any
---rescan (watch-triggered or manual `:DocMap`). `opts.mdview` without
---`opts.watch` still works, but the preview only updates when something
---calls `handle.rescan()`, not automatically on every save.
---
---Idempotent: called on a root already wired for this, or one that was
---never installed, it does nothing.
---@param root string
---@return boolean wired True if mdview.nvim is installed and this root is wired for it (an inactive session is checked per-push, not here).
function M.ensure_mdview(root)
  root = norm_root(root)
  local entry = registry[root]
  if not entry or not entry.handle then
    return false
  end
  if entry.mdview_wired then
    return true
  end

  local probe = require("documentation.core.soft_require").probe("mdview.core.state")
  if not probe then
    return false
  end

  local function publish()
    local state = require("mdview.core.state")
    if not state.is_attached() or not state.get_server() then
      return -- no mdview session running right now; the next change tries again
    end
    local opts = entry.opts
    local out_dir = opts.out_dir or "docs/map"
    local path = root .. "/" .. out_dir .. "/overview.md"
    local markdown = require("documentation.core.render.mdview")(entry.ir, entry.findings, opts)
    require("mdview.adapter.ws_client").send_markdown(path, markdown, { immediate = true })
  end

  publish()
  entry.handle.on_change(publish)
  entry.mdview_wired = true
  return true
end

---Install a live handle for `opts.root`. Runs an initial scan immediately
---(synchronously — including the LuaLS shell-out if `opts.luals` is set, so
---a caller passing `luals = true` here is opting into that cost up front,
---not just on some later rescan).
---@param opts Documentation.Opts
---@return Documentation.Handle
function M.install(opts)
  assert(
    type(opts) == "table" and type(opts.root) == "string" and opts.root ~= "",
    "docmap.install: opts.root is required"
  )

  local root = norm_root(opts.root)
  opts = vim.tbl_extend("force", {}, opts, { root = root })

  if registry[root] then
    -- Re-installing over an existing handle for the same root is treated as
    -- "replace, don't stack": tearing down the old watch/augroup first keeps
    -- a caller's repeated setup()-under-hot-reload from leaking timers.
    M.uninstall(registry[root].handle)
  end

  local docmap = require("documentation")
  local entry = { opts = opts, watchers = {} }
  registry[root] = entry

  local function rescan(rescan_opts)
    local scan_opts = rescan_opts and vim.tbl_extend("force", opts, rescan_opts) or opts
    entry.ir, entry.findings = docmap.scan_full(scan_opts)
    notify_watchers(entry)
    return entry.ir, entry.findings
  end
  entry.rescan_fn = rescan

  -- initial scan; handle.ir() must never observe an unset IR. Guarded
  -- (unlike a bare call) because `registry[root] = entry` above already ran:
  -- a failed scan must not leave a dangling entry with no `.handle` for a
  -- later M.install to silently overwrite rather than one that visibly
  -- failed. Re-raises the same string a bare call would have (preserving
  -- the existing raise-a-string contract every caller already handles),
  -- now carrying a full traceback via lib.lua.error.safe_call rather than
  -- just the point M.install itself re-raises from.
  local ok_rescan, rescan_err = require("lib.lua.error").safe_call(rescan)
  if not ok_rescan then
    registry[root] = nil
    error(rescan_err.message, 0)
  end

  if opts.watch then
    M.ensure_watch(root)
  end
  if opts.callhierarchy then
    M.ensure_callhierarchy(root)
  end

  ---Filter the current IR's edges. The graph queries below all reduce to
  ---"edges of kind K whose near end is X", so the walk exists once.
  ---@param kind Documentation.EdgeKind
  ---@param field string Edge field to match against `value`.
  ---@param value string
  ---@return Documentation.Edge[]
  local function edges_where(kind, field, value)
    local out = {}
    for _, e in ipairs(entry.ir.edges or {}) do
      if e.kind == kind and e[field] == value then
        out[#out + 1] = e
      end
    end
    return out
  end

  ---Split a `"<node id>#<function name>"` key. The same id scheme the HTML
  ---uses, so a link copied out of the map is a valid argument here.
  ---@param key string
  ---@return string node_id
  ---@return string fn_name
  local function split_fn(key)
    local node_id, fn_name = key:match("^(.*)#([^#]+)$")
    return node_id or key, fn_name or ""
  end

  ---@type Documentation.Handle
  local handle = {
    root = root,
    ir = function()
      return entry.ir
    end,
    -- The graph queries a consumer would otherwise reimplement by filtering
    -- `ir.edges` themselves. Kept on the handle rather than as free functions
    -- so they always answer against *this* handle's current IR, including
    -- after a watch-triggered rescan.
    requires = function(id)
      return edges_where("require", "from", id)
    end,
    required_by = function(id)
      return edges_where("require", "to", id)
    end,
    callees = function(key)
      local node_id, fn_name = split_fn(key)
      local out = {}
      for _, e in ipairs(entry.ir.edges or {}) do
        if e.kind == "call" and e.from == node_id and e.from_fn == fn_name then
          out[#out + 1] = e
        end
      end
      return out
    end,
    callers = function(key)
      local node_id, fn_name = split_fn(key)
      local out = {}
      for _, e in ipairs(entry.ir.edges or {}) do
        if e.kind == "call" and e.to == node_id and e.to_fn == fn_name then
          out[#out + 1] = e
        end
      end
      return out
    end,
    findings = function()
      return entry.findings
    end,
    node = function(id)
      return entry.ir.nodes[id]
    end,
    rescan = rescan,
    on_change = function(cb)
      entry.watchers[#entry.watchers + 1] = cb
      return function()
        for i, existing in ipairs(entry.watchers) do
          if existing == cb then
            table.remove(entry.watchers, i)
            return
          end
        end
      end
    end,
    uninstall = function()
      M.uninstall(root)
    end,
  }
  entry.handle = handle

  if opts.diagnostics then
    M.ensure_diagnostics(root)
  end
  if opts.mdview then
    M.ensure_mdview(root)
  end

  return handle
end

---Look up an existing handle by root, without installing one.
---@param root string
---@return Documentation.Handle?
function M.get(root)
  local entry = registry[norm_root(root)]
  return entry and entry.handle
end

---Tear down a handle: cancels the watch debounce/autocmd, drops it from the
---registry. Idempotent — uninstalling twice, or a handle/root that was never
---installed, is a no-op returning `false`, not an error, matching this
---repo's own `usercmd.create` tolerance for repeated setup/teardown under
---hot-reload configs.
---@param handle_or_root Documentation.Handle|string
---@return boolean uninstalled
function M.uninstall(handle_or_root)
  local root = type(handle_or_root) == "table" and handle_or_root.root or handle_or_root
  if type(root) ~= "string" then
    return false
  end
  root = norm_root(root)

  local entry = registry[root]
  if not entry then
    return false
  end

  if entry.debounce then
    entry.debounce.cancel()
  end
  if entry.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, entry.augroup)
  end
  if entry.ch_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, entry.ch_augroup)
  end
  if entry.diag_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, entry.diag_augroup)
  end
  -- `entry.diag_unsub` needs no explicit call: it is just one more entry in
  -- `entry.watchers`, which the blanket clear below already drops. Existing
  -- diagnostics on any buffer are left as they were, same posture as
  -- call-hierarchy's own teardown note below. `ensure_mdview`'s `publish`
  -- subscription is the same story: no separate unsub, no `mdview_unwired`
  -- flag to reset — `registry[root] = nil` below drops the whole `entry`
  -- (including `mdview_wired`), so a fresh `install()` for this root starts
  -- from an unwired state without any extra teardown here.
  -- Stops *future* attachments only, same posture as `watch`'s own teardown
  -- above (which cancels the debounce but does not chase down an in-flight
  -- rescan): a buffer the call-hierarchy client already attached to keeps
  -- it running, now answering off a frozen `entry.ir` that will never
  -- update again. Rare in practice — uninstalling a handle a buffer was
  -- actively using is not the common shutdown path — and the worst case is
  -- stale results, not a crash, the same tradeoff `watch` already accepts.
  entry.watchers = {}
  registry[root] = nil
  return true
end

return M
