---@module 'documentation.browse.trail'
--- Pinned positions: the places worth coming back to, kept apart from the
--- plain back/forward history `<C-o>`/`<C-i>` walks.
---
--- The two are genuinely different questions and conflating them helps
--- neither. History answers "where was I a moment ago" — it is automatic,
--- ordered by time, and truncated the moment a new move happens, exactly like
--- a browser's. A trail answers "where do I want to be able to get back to" —
--- it is deliberate, ordered by when it was pinned, and nothing but an
--- explicit unpin removes an entry. Reading a dependency graph produces dozens
--- of history stops and about four places actually worth returning to.
---
--- Pure, and deliberately so: a table of plain records with no window, no
--- buffer and no `vim` API in sight, which is what lets the whole model be
--- driven from a headless spec without mounting a single float. Same split
--- `diff.lua` and `history.lua` already follow.
---
--- Keyed by **repository root**, not by browser instance, so pins survive
--- `browse.close()` and reopening — a pin that vanished when the window shut
--- would be a bookmark with the lifetime of a scrollbar. They do not yet
--- survive Neovim itself; persisting them is the roadmap's next item and this
--- module is where it will land.

local M = {}

---@class Documentation.Browse.Pin
---@field mode string The mode the pin was taken in; restored on jump.
---@field id string? IR node id.
---@field fn string? Declared function name, when the pin is a function.
---@field sha string? Commit, when the pin was taken in History mode.
---@field dir "in"|"out"|nil Edge direction in force when pinned; restored on jump.
---@field depth integer? Deps walk depth in force when pinned; restored on jump.
---@field label string Display text.
---@field detail string? Secondary display text.
---@field source string? Repo-relative source path, for `gd`/`gq`.
---@field line integer? Declaration line, same.

---Pins per normalized root.
---@type table<string, Documentation.Browse.Pin[]>
local pins = {}

---Identity of a pin: what it is *about*, not how it was being looked at.
---
---`dir` and `depth` are deliberately not part of this. Pinning a module in
---Deps at depth 2 and again at depth 3 is the same bookmark seen through a
---different lens, and a trail that grew a second entry for it would fill up
---with near-duplicates nobody meant to create. Those axes still travel *on*
---the pin and are restored on jump; they just do not make it a different one.
---
---The `\0` separator rather than a printable one, for the usual reason: a node
---id is a path and a function name is arbitrary text, so any separator that
---could occur inside either can be made to collide.
---@param pin Documentation.Browse.Pin
---@return string
function M.key(pin)
  return table.concat({ pin.mode or "", pin.id or "", pin.fn or "", pin.sha or "" }, "\0")
end

---Pins for `root`, in the order they were added.
---
---The live array, not a copy: the only writers are the functions below, and
---handing back a copy would mean the caller's `st.pins` silently went stale
---the moment anything was pinned. The renderer re-reads it every frame
---anyway.
---@param root string Already normalized.
---@return Documentation.Browse.Pin[]
function M.list(root)
  pins[root] = pins[root] or {}
  return pins[root]
end

---@param root string
---@return integer
function M.count(root)
  return #M.list(root)
end

---Index of `key` in `root`'s trail, or nil.
---@param root string
---@param key string
---@return integer?
function M.index_of(root, key)
  for i, p in ipairs(M.list(root)) do
    if M.key(p) == key then
      return i
    end
  end
  return nil
end

---Add `pin`, or remove it if an equal one is already there.
---
---A toggle rather than separate add/remove keys because pressing `p` on
---something already pinned has exactly one sensible meaning, and spending a
---second key on the other half of it would be spending a key to make the
---first one worse.
---@param root string
---@param pin Documentation.Browse.Pin
---@return "pinned"|"unpinned"
---@return integer count Trail length afterwards.
function M.toggle(root, pin)
  local list = M.list(root)
  local at = M.index_of(root, M.key(pin))
  if at then
    table.remove(list, at)
    return "unpinned", #list
  end
  list[#list + 1] = pin
  return "pinned", #list
end

---Remove the pin at `index`.
---@param root string
---@param index integer
---@return Documentation.Browse.Pin? removed
function M.remove_at(root, index)
  local list = M.list(root)
  if index < 1 or index > #list then
    return nil
  end
  return table.remove(list, index)
end

---Drop every pin for `root`.
---@param root string
---@return integer removed
function M.clear(root)
  local n = M.count(root)
  pins[root] = {}
  return n
end

---Drop every pin for every root. Test-support, and the one function here a
---consumer should not need.
function M.reset()
  pins = {}
end

return M
