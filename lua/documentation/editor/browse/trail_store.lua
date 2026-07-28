---@module 'documentation.editor.browse.trail_store'
--- Persistence for [`trail.lua`](trail.lua): the working trail across Neovim
--- restarts, plus named trails saved and reloaded on demand.
---
--- Split out rather than folded in because `trail.lua` being pure is a
--- property worth keeping — the whole pin model is driven from a headless
--- spec with no filesystem in sight, and that stops being true the moment it
--- opens a file. So this module is the only one here that touches disk, and it
--- learns about changes by *listening* (`trail.on_change`) rather than by
--- being called at each mutation. A mutation added later cannot forget to
--- persist.
---
--- ## Where
---
---   stdpath("state")/documentation.nvim/trails.json
---
--- `state`, not `data` and emphatically not the repository. A trail is
--- navigation state — where one reader happened to look — with no more claim
--- on the project than a jumplist has. Committing it would put one person's
--- reading path into everyone else's checkout, and `--check` would then have
--- an opinion about it.
---
--- ## Shape
---
--- ```json
--- {
---   "E:/repos/lib.nvim": {
---     "current": [ …pins… ],
---     "saved":   { "notify-refactor": [ …pins… ] }
---   }
--- }
--- ```
---
--- One file for every repository rather than one per root, because the whole
--- thing is a few kilobytes and a single read at startup beats a directory
--- scan. Roots are absolute paths used verbatim as keys: two checkouts of the
--- same project are genuinely two places to have looked around in.
---
--- ## When
---
--- Writes are debounced — pinning six things in a row is one write, not six —
--- with a synchronous flush on `VimLeavePre`, because the debounce timer is
--- exactly the thing that does not survive quitting.

local debounce = require("lib.nvim.debounce")
local mkdirp = require("lib.nvim.fs.mkdirp")
local trail = require("documentation.editor.browse.trail")

local M = {}

local FILE = "trails.json"
local WRITE_MS = 400

---In-memory mirror of the file, or nil before the first read.
---@type table<string, { current: Documentation.Browse.Pin[], saved: table<string, Documentation.Browse.Pin[]> }>|nil
local db = nil

---Roots already seeded into `trail` this session. A root is hydrated once:
---re-reading on every `browse.open()` would throw away pins made since.
---@type table<string, true>
local hydrated = {}

---@type table<string, true>
local dirty = {}

---`lib.nvim.debounce` hands back a plain `{ call, cancel }` table, not a
---callable — annotating it as a function is what made `flush_soon()` a
---"attempt to call a table value" that nothing reported (see `M.schedule`).
---@type Lib.Debounce.Handle|nil
local flush_soon = nil
local attached = false

---Where the store lives.
---
---A function on the module rather than a constant, and every caller here goes
---through `M.path()` rather than a local — which is what lets the spec point
---the whole module at a temp file instead of writing into the user's real
---state directory while the suite runs.
---@return string
function M.path()
  local dir = tostring(vim.fn.stdpath("state"))
  return ((dir .. "/documentation.nvim/" .. FILE):gsub("\\", "/"))
end

---Coerce whatever was decoded into the shape the rest of this file assumes.
---
---Defensive on purpose: this file lives in the user's state directory, where
---it can be edited, truncated by a full disk, or written by an older version
---of this plugin. A malformed entry must cost that root its pins, never an
---error on `:DocBrowse`.
---@param raw any
---@return table
local function normalize(raw)
  local out = {}
  if type(raw) ~= "table" then
    return out
  end
  for root, entry in pairs(raw) do
    if type(root) == "string" and type(entry) == "table" then
      local current = type(entry.current) == "table" and entry.current or {}
      local saved = type(entry.saved) == "table" and entry.saved or {}
      -- `vim.json` decodes an empty JSON object as an empty Lua table, which
      -- is indistinguishable from an empty array — harmless here, since both
      -- iterate to nothing.
      local clean_saved = {}
      for name, list in pairs(saved) do
        if type(name) == "string" and type(list) == "table" then
          clean_saved[name] = list
        end
      end
      out[root] = { current = current, saved = clean_saved }
    end
  end
  return out
end

---The whole store, read once per session.
---@return table
local function load()
  if db then
    return db
  end
  local raw = require("lib.nvim.fs.read")(M.path())
  if not raw or raw == "" then
    db = {}
    return db
  end
  local ok, decoded = pcall(vim.json.decode, raw, { luanil = { object = true, array = true } })
  db = ok and normalize(decoded) or {}
  return db
end

---@param root string
---@return table
local function entry(root)
  local store = load()
  store[root] = store[root] or { current = {}, saved = {} }
  return store[root]
end

---Write the store now.
---
---Whole-file, not per-root: the file is small, and a partial writer would
---have to solve merging against a copy another Neovim instance may have
---written in between — a real problem, but one that a few kilobytes do not
---justify solving. Last writer wins, and each instance's own view is
---internally consistent.
---@return boolean ok
---@return string? err
function M.flush()
  -- Only `dirty` decides. A nil `db` is not "nothing to write" — it is "the
  -- file has not been read yet", which is the state every session starts in;
  -- `entry()` below reads it. Guarding on it too meant a pin made before
  -- anything had hydrated was reported as written and silently dropped.
  if not next(dirty) then
    return true
  end

  for root in pairs(dirty) do
    entry(root).current = trail.snapshot(root)
  end
  dirty = {}

  local path = M.path()
  local ok_dir, derr = mkdirp(vim.fs.dirname(path))
  if not ok_dir then
    return false, derr
  end

  local ok_enc, encoded = pcall(vim.json.encode, db)
  if not ok_enc then
    return false, tostring(encoded)
  end

  local fd, ferr = io.open(path, "wb")
  if not fd then
    return false, ferr
  end
  fd:write(encoded)
  fd:close()
  return true
end

---Mark `root` as needing a write, and schedule one.
---@param root string
function M.schedule(root)
  dirty[root] = true
  if not flush_soon then
    flush_soon = debounce.new(function()
      M.flush()
    end, WRITE_MS)
  end
  -- `.call`, not `flush_soon(...)`: the handle is a plain table. Calling it
  -- raised, `trail.on_change` fans out under `pcall`, and the debounced write
  -- was therefore dead without ever saying so — the pins still reached disk,
  -- but only via `VimLeavePre` and the explicit flushes in `save_named` /
  -- `delete_named`.
  flush_soon.call()
end

---Subscribe to `trail` and arrange the exit flush. Idempotent.
---
---Called from `browse.open` rather than at require time, so merely requiring
---`documentation` never installs an autocmd in the user's editor — the same
---rule `command.setup()` follows for its user commands.
function M.attach()
  if attached then
    return
  end
  attached = true

  trail.on_change(function(root)
    M.schedule(root)
  end)

  -- The debounce timer is precisely what quitting does not wait for, so the
  -- last few pins would be the ones lost — the newest and most likely to
  -- matter.
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("documentation.trail_store", { clear = true }),
    callback = function()
      M.flush()
    end,
    desc = "documentation.editor.browse: persist pinned trails before quitting",
  })
end

---Seed `root`'s trail from disk, once per session.
---@param root string
---@return integer loaded
function M.hydrate(root)
  if hydrated[root] then
    return 0
  end
  hydrated[root] = true

  local list = entry(root).current
  if #list == 0 then
    return 0
  end
  -- Straight in, not through `merge`: this is a restore, so the trail is
  -- empty and there is nothing to deduplicate against. `hydrate` is also the
  -- one mutation that must not announce itself — see `trail.hydrate`.
  trail.hydrate(root, list)
  return #list
end

-- ── Named trails ────────────────────────────────────────────────────────────

---Names saved for `root`, sorted.
---@param root string
---@return string[]
function M.names(root)
  local out = {}
  for name in pairs(entry(root).saved) do
    out[#out + 1] = name
  end
  table.sort(out)
  return out
end

---Save `root`'s current trail under `name`.
---
---An existing name is overwritten, deliberately without asking: the user
---typed a name they have used before, and "save over it" is the only thing
---that can mean. Refusing would leave them re-typing a variant.
---@param root string
---@param name string
---@return boolean ok
---@return string? err
function M.save_named(root, name)
  name = vim.trim(name or "")
  if name == "" then
    return false, "a trail needs a name"
  end
  if trail.count(root) == 0 then
    return false, "nothing pinned to save"
  end
  entry(root).saved[name] = trail.snapshot(root)
  dirty[root] = true
  return M.flush()
end

---Load the saved trail `name` into `root`'s current trail, additively.
---@param root string
---@param name string
---@return string name
---@return integer added
---@return integer skipped Already in the trail, and left alone.
function M.load_named(root, name)
  local list = entry(root).saved[name]
  if not list then
    return name, 0, 0
  end
  -- Copied, not shared: merging the stored table itself would make every
  -- later unpin edit the saved trail too.
  local copy = {}
  for i, p in ipairs(list) do
    local c = {}
    for k, v in pairs(p) do
      c[k] = v
    end
    copy[i] = c
  end
  local added, skipped = trail.merge(root, copy)
  return name, added, skipped
end

---Forget the saved trail `name`.
---@param root string
---@param name string
---@return boolean existed
function M.delete_named(root, name)
  local saved = entry(root).saved
  if saved[name] == nil then
    return false
  end
  saved[name] = nil
  dirty[root] = true
  M.flush()
  return true
end

---Drop the in-memory mirror, the hydration marks and the attach flag.
---Test-support: lets a spec point at a fresh file, and re-attach after
---`trail.reset()` has dropped this module's subscription, without needing a
---new Neovim.
function M.reset()
  db, hydrated, dirty = nil, {}, {}
  attached = false
end

return M
