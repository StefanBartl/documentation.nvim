---@module 'documentation.editor.browse.source'
--- Where the browser's IR comes from: the generated artifact by default, a
--- live `docmap.install()` handle on request.
---
--- Artifact-first is a measured decision, not a stylistic one. Scanning
--- lib.nvim costs ~0.65s of *blocking* editor time; decoding
--- `module_map.json` costs ~0.01s. Two thirds of a second between pressing a
--- key and seeing a window is the difference between "opens" and "hangs", so
--- the fast path is the default and the live path is opt-in.
---
--- The cost of that choice is staleness: the artifact shows the tree as of
--- the last `:DocMap`. Rather than silently showing wrong data, `M.stale()`
--- compares its mtime against the newest source file so the caller can say
--- so in the status line.

local M = {}

local uv = vim.uv

-- The three artifact-shape functions below moved to
-- `documentation.core.artifact` and are re-exported here unchanged. They
-- are not editor work — they read a file and reshape a table — and the
-- standalone build needs them, which the layer rule (core may not reach
-- editor) correctly forbids reaching back for. Kept as names on this module
-- because several callers already go through it (`bindings/usrcmds/diff`,
-- `impact`, `browse/init`, `serve`, and this file's own tests).
local artifact = require("documentation.core.artifact")

-- Normalize a repo root the same way `docmap.registry` does, so a handle
-- installed there and an artifact read here agree on the key.
M.norm_root = artifact.norm_root

-- Where a project's generated artifact lives.
M.artifact_path = artifact.artifact_path

-- Turn a decoded artifact into the in-memory IR shape every reader expects.
-- See `core/artifact.lua` for why the two documents differ.
M.rehydrate = artifact.rehydrate

---Read and decode `module_map.json`.
---
---Wraps `core.artifact.load` to add the two things only this layer cares
---about: an error *message* naming the path (a browser has a status line to
---put it in; the core reader's callers all have to say "absent" in their own
---words anyway), and the `root` field check — the artifact contract this
---side relies on, which the core reader deliberately does not require, since
---a telemetry join never reads it.
---@param opts Documentation.Browse.Opts
---@return Documentation.IR|nil ir
---@return string|nil err
function M.load_artifact(opts)
  local path = M.artifact_path(opts)
  local read = require("lib.nvim.fs.read")

  local content = read(path)
  if not content then
    return nil, ("no map at %s — run :DocMap first"):format(path)
  end

  local ir = artifact.decode(content)
  if not ir or type(ir.root) ~= "string" then
    return nil, ("map at %s is not a readable docmap artifact"):format(path)
  end

  return ir
end

---True when the artifact is older than the newest Lua source under `source`.
---
---Walks the source tree and stats each file rather than trusting a directory
---mtime: on every platform this repo runs on, a directory's mtime does not
---move when a file *inside* it is edited in place, so a directory-only check
---would report "fresh" for exactly the edit-then-browse case this exists to
---catch.
---@param opts Documentation.Browse.Opts
---@return boolean stale
function M.stale(opts)
  local st = uv.fs_stat(M.artifact_path(opts))
  if not st then
    return true
  end
  local map_mtime = st.mtime.sec

  -- The first root, not every one: this resolves a single directory to read
  -- a file from, and widening it to the repository root would make an
  -- unrelated file outside every source root look like part of the tree.
  local source_dir = M.norm_root(opts.root)
    .. "/"
    .. require("documentation.config").sources(opts)[1]
  local ok, files = pcall(function()
    return require("lib.nvim.fs.collect_recursive").files(source_dir)
  end)
  if not ok then
    return false
  end

  for _, p in ipairs(files) do
    if p:sub(-4) == ".lua" then
      local fs = uv.fs_stat(p)
      if fs and fs.mtime.sec > map_mtime then
        return true
      end
    end
  end
  return false
end

---Acquire an IR for the browser.
---
---`opts.live` installs (or reuses) a watching `docmap.install()` handle and
---returns its IR; everything else reads the artifact. The handle is returned
---alongside so the caller can subscribe to `on_change` — the whole point of
---the live mode.
---@param opts Documentation.Browse.Opts
---@return Documentation.IR|nil ir
---@return Documentation.Handle|nil handle
---@return string|nil err_or_hint
function M.acquire(opts)
  if opts.live then
    local docmap = require("documentation")
    local registry = require("documentation.editor.registry")
    local root = M.norm_root(opts.root)

    -- Reuse an already-installed handle rather than installing a second one:
    -- `install()` replaces on collision, which would tear down a watch some
    -- other caller (a plugin's own setup) is still relying on — and, worse,
    -- drop every `on_change` subscriber with it.
    --
    -- Reusing alone is not enough though. `docmap.command.setup()` installs
    -- with the plain config, which sets no `watch`, so a `:DocMap` earlier in
    -- the session left exactly the handle this finds — and "live" then meant
    -- a view that never re-scanned on write. `ensure_watch` upgrades it in
    -- place instead, keeping the subscribers.
    local handle = registry.get(root)
    if handle then
      registry.ensure_watch(root)
    else
      handle = docmap.install(vim.tbl_extend("force", opts, { root = root, watch = true }))
    end
    return handle.ir(), handle, nil
  end

  local ir, err = M.load_artifact(opts)
  if not ir then
    return nil, nil, err
  end
  return ir, nil, M.stale(opts) and "map is stale — run :DocMap" or nil
end

return M
