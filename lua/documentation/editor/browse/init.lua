---@module 'documentation.editor.browse'
--- `:DocBrowse` — the module map inside the editor.
---
--- Explicitly **not** the HTML diagram in a terminal. Boxes with connecting
--- curves need pixels: free positions, curves, continuous zoom. A terminal
--- gives a fixed cell grid, and what comes out of that is a worse version of
--- a page that already exists. This is a *navigator over the same edges*, so
--- the hierarchy is a drill-down list and Deps/Calls are lists, not graphs.
---
--- What justifies it existing next to the generated page — three things the
--- page cannot do at all:
---   1. jump to the source at the line (`gd`);
---   2. fill the quickfix list (`gq`) — the point where call edges stop being
---      decorative and start saving work;
---   3. be live (`:DocBrowse live`), where the page is a snapshot of the last
---      `:DocMap`.
---
---   :DocBrowse            read docs/map/module_map.json (~10ms)
---   :DocBrowse live       install a watching handle instead (~0.65s once)
---   :DocBrowse my.module  open centered on a module
---   :DocBrowse history    open on the commit list
---   :DocBrowse trail      open on the pinned positions
---
--- Keys: 1..6 modes · j/k move · <CR> descend · -/<BS> up · <C-o>/<C-i>
--- history · h/l direction · +/_ depth · p pin · d unpin, S/L/X save, load
--- and forget a trail (all Trail) · gd source · gq quickfix · gI impact · gO
--- open the page here · gD the opened commit's diff · f filter this list · /
--- search across everything · ? this list · q close.
---
--- The authoritative key list is the `KEYS` table below: `bind()` installs
--- from it and `?` renders from it, so neither this header nor any document
--- is what the browser actually reads. Every entry is rebindable or
--- disableable through `opts.keys`, keyed by the entry's `id` — `resolve_keys`
--- applies those once per open, and both `bind()` and `?` then work off the
--- resolved list, so a configured browser documents itself as accurately as
--- an unconfigured one.

require("documentation.editor.browse.@types")

local filter = require("documentation.editor.browse.filter")
local kit = require("lib.nvim.ui.kit")
local map = require("lib.nvim.map")
-- Names the command, not the module path. `:DocBrowse` is what the reader
-- typed; `documentation.editor.browse` is an implementation detail that grew
-- a segment when the tree was split, and a message prefix has no business
-- tracking that.
local notify = require("lib.nvim.notify").create("[DocBrowse]")
local source = require("documentation.editor.browse.source")
local trail = require("documentation.editor.browse.trail")
local trail_store = require("documentation.editor.browse.trail_store")
local view = require("documentation.editor.browse.view")

local M = {}

---Single active browser, mirroring the chooser/confirm single-instance model
---in `lib.nvim.ui.kit`: two of these on screen at once would fight over the
---same keys and the same "which window am I in" question.
---@type table|nil
local state = nil

-- "telemetry" is 8th, not 7th — the design doc it implements
-- (`docs/ROADMAP/telemetry-documentation-bridge.md` in lib.nvim) calls it
-- "Mode 7", written before "endpoints" above claimed position 7 in this
-- actual list; see ECOSYSTEM.md step 8 for that renumbering note.
-- "loaded" (§5.3, runtime-analysis.nvim's own docs/ROADMAP.md) is 9th.
local MODES = {
  "structure",
  "deps",
  "calls",
  "types",
  "history",
  "trail",
  "endpoints",
  "telemetry",
  "loaded",
}

-- ── History mode: the git half ──────────────────────────────────────────────
--
-- `view.lua` is pure and stays that way, so everything that shells out lives
-- here and hands the results over on the state. Same split as `history.lua`
-- (pure) plus `command.lua` (git) — and the same reason: the mode logic is
-- then testable headlessly without a repository.

---@param st table
---@param args string[]
---@return string|nil stdout
---@return string|nil err
local function git(st, args)
  local cmd = { "git" }
  vim.list_extend(cmd, args)
  local proc = vim.system(cmd, { cwd = st.opts.root, text = true }):wait()
  if proc.code ~= 0 then
    return nil, vim.trim(proc.stderr or "git failed")
  end
  return proc.stdout or ""
end

---Load the commit list once per session. Cached on the state: it is the same
---list every time the mode is entered, and re-running `git log` on each `5`
---keypress would make the mode feel slower than it is.
---@param st table
local function load_commits(st)
  if st.commits then
    return
  end
  -- Unit/record separators, not a printable delimiter: a subject can contain
  -- whatever character looked safe.
  local out, err =
    git(st, { "log", "-n", "200", "--date=short", "--format=%H%x1f%h%x1f%an%x1f%ad%x1f%s%x1e" })
  if not out then
    st.commits = {}
    notify.warn("git log failed: " .. tostring(err))
    return
  end

  local commits = {}
  for record in out:gmatch("([^\30]+)") do
    local rec = vim.trim(record)
    if rec ~= "" then
      local f = vim.split(rec, "\31", { plain = true })
      if #f >= 5 then
        commits[#commits + 1] =
          { sha = f[1], short = f[2], author = f[3], date = f[4], subject = f[5] }
      end
    end
  end
  st.commits = commits
end

---Analyse one commit: its diff, the artifacts either side of it, and the
---pure `history.analyze` over both.
---
---`git show` rather than `git diff <sha>^ <sha>` because it also handles the
---root commit, which has no parent to name. Excluding `out_dir` is not
---cosmetic: measured here, a commit's full diff is 4.8 MB of which all but
---~16 KB is the regenerated map.
---@param st table
---@param sha string
local function load_impact(st, sha)
  local out_dir = st.opts.out_dir or "docs/map"

  local diff_text, derr = git(st, {
    "show",
    "--unified=0",
    "--format=",
    sha,
    "--",
    ".",
    (":(exclude)%s"):format(out_dir),
  })
  if not diff_text then
    notify.warn("git show failed: " .. tostring(derr))
    st.impact = nil
    return
  end
  st.diff_text = diff_text

  ---@param rev string
  ---@return Documentation.IR|nil
  local function ir_at(rev)
    local rel = out_dir .. "/module_map.json"
    local raw = git(st, { "show", ("%s:%s"):format(rev, rel) })
    if not raw or raw == "" then
      return nil
    end
    local ok, doc = pcall(vim.json.decode, raw, { luanil = { object = true, array = true } })
    if not ok or type(doc) ~= "table" or type(doc.nodes) ~= "table" then
      return nil
    end
    return require("documentation.editor.browse.source").rehydrate(doc)
  end

  local ir_after = ir_at(sha)
  local ir_before = ir_at(sha .. "^")
  st.impact_has_map = ir_after ~= nil
  st.impact = require("documentation.core.history").analyze(diff_text, ir_after, ir_before)
end

---@return boolean
function M.is_open()
  return state ~= nil and state.group ~= nil and state.slots.list:is_valid()
end

---Close the browser (idempotent).
function M.close()
  local st = state
  state = nil
  if not st then
    return
  end
  if st.unsubscribe then
    pcall(st.unsubscribe)
  end
  if st.group then
    pcall(st.group.close)
  end
end

-- ── Rendering ───────────────────────────────────────────────────────────────

---@param st table
local function render(st)
  -- History's data comes from git, not the IR, so it is fetched here rather
  -- than in `go`: `<C-o>` restores a `sha` straight onto the state without
  -- passing through `go` at all, and the analysis has to follow it. Keyed on
  -- `impact_sha` so stepping back onto a commit already looked at costs
  -- nothing.
  if st.mode == "history" then
    load_commits(st)
    if st.sha and st.impact_sha ~= st.sha then
      load_impact(st, st.sha)
      st.impact_sha = st.sha
    elseif not st.sha then
      st.impact, st.impact_sha, st.impact_has_map, st.diff_text = nil, nil, nil, nil
    end
  end

  -- Re-read every frame rather than caching on the state: the trail is keyed
  -- by root, not by browser instance, so a pin taken in a previous session of
  -- this window is already in it and a cached copy would be one close/reopen
  -- behind. `view` stays pure and reads it off `st`, same as `st.commits`.
  st.pins = trail.list(st.root)

  -- Narrowed after the mode has built its list, never inside it: every mode
  -- gets the filter for free and none of them has to know it exists.
  local kept, hidden = filter.apply(st.filter, view.entries(st.ir, st))
  st.filter_hidden = hidden

  -- An empty result says so. A blank list column is the one outcome a reader
  -- cannot tell apart from a broken render, and one typo reaches it.
  if #kept == 0 and st.filter then
    kept = { { kind = "message", label = ("(no row matches — %d hidden)"):format(hidden) } }
  end
  st.entries = kept

  if st.cursor > #st.entries then
    st.cursor = #st.entries
  end
  if st.cursor < 1 then
    st.cursor = 1
  end

  local list_w = vim.api.nvim_win_get_width(st.slots.list.winid)
  st.slots.list:set_lines(view.list_lines(st.entries, list_w))
  st.slots.list:set_title((" %s "):format(st.mode))

  if st.slots.list:is_valid() and #st.entries > 0 then
    pcall(vim.api.nvim_win_set_cursor, st.slots.list.winid, { st.cursor, 0 })
  end

  st.slots.detail:set_lines(view.detail(st.ir, st, st.entries[st.cursor]))
  st.slots.status:set_lines({ view.status(st.ir, st) })
end

---The entry under the cursor.
---
---Reads the window rather than a cached index on purpose. `st.cursor` is kept
---in step by a `CursorMoved` autocmd, which is fine for *rendering* but must
---not be what an action trusts: any path that moves the cursor without firing
---that autocmd (a mapping with `noautocmd`, a `feedkeys` batch, `:normal!`
---from another plugin) would leave the cache stale and make `<CR>` act on a
---row the user is not looking at. The window position is the truth; the cache
---only exists so a redraw can restore it.
---@param st table
---@return Documentation.Browse.Entry|nil
local function selected(st)
  if st.slots.list:is_valid() and #st.entries > 0 then
    local row = vim.api.nvim_win_get_cursor(st.slots.list.winid)[1]
    st.cursor = math.max(1, math.min(row, #st.entries))
  end
  return st.entries[st.cursor]
end

---Re-render only the detail pane — what `j`/`k` need. Rebuilding the list on
---every cursor move would reset the cursor and fight the movement.
---@param st table
local function render_detail(st)
  st.slots.detail:set_lines(view.detail(st.ir, st, selected(st)))
  st.slots.status:set_lines({ view.status(st.ir, st) })
end

-- ── Navigation ──────────────────────────────────────────────────────────────

---@param st table
---@return table
local function snapshot(st)
  return {
    mode = st.mode,
    id = st.id,
    fn = st.fn,
    dir = st.dir,
    depth = st.depth,
    cursor = st.cursor,
    sha = st.sha,
    filter = st.filter,
    filter_raw = st.filter_raw,
  }
end

-- `sha` travels with the trail so `<C-o>` out of a commit lands back on the
-- list rather than on the same commit with a different cursor. The analysis
-- itself is not snapshotted — it is derived, and re-deriving on the way back
-- is cheaper than carrying a copy of it per history entry.
--
-- The filter travels with a position rather than sitting outside the history,
-- which removes every special case rather than adding one: `<C-o>` back onto
-- a narrowed list finds it narrowed the same way, and stepping off it drops
-- the filter without anything having to remember to. The parsed table is
-- never mutated after `filter.parse`, so sharing the reference across
-- snapshots is safe.
local SNAP_KEYS = { "mode", "id", "fn", "dir", "depth", "cursor", "sha", "filter", "filter_raw" }

--- A patch cannot say "clear this field" with `nil`: `pairs` never yields a
--- key whose value is nil, so `{ sha = nil }` *is* the empty table and the
--- move silently keeps the old value. Found the honest way — `-` out of an
--- opened commit redrew the same function list, because `go` had been handed
--- nothing at all. Hence a sentinel.
local CLEAR = setmetatable({}, {
  __tostring = function()
    return "<clear>"
  end,
})

---Keep the entry for the position being left in step with the window before
---moving off it, so coming back restores the row the user was actually on
---rather than the row they arrived at.
---@param st table
local function sync_snapshot(st)
  selected(st)
  local snap = st.history[st.hindex]
  if snap then
    snap.cursor = st.cursor
  end
end

---Record the current position, then apply `changes`.
---
---`history` holds the whole trail **including where we are now**, and `hindex`
---points at it. That is the model the HTML renderer uses and the one every
---browser uses, and it is worth stating because the alternative — recording
---only *past* positions — is what this did first and it could not work: after
---a move `hindex` addressed the entry before the current one, so the first
---`<C-o>` fell off the front and the second landed one stop too far back.
---@param st table
---@param changes table
local function go(st, changes)
  sync_snapshot(st)

  -- A new move truncates any forward history, exactly like a browser.
  for i = #st.history, st.hindex + 1, -1 do
    st.history[i] = nil
  end

  local was = { mode = st.mode, id = st.id, fn = st.fn }

  for k, v in pairs(changes) do
    if v == CLEAR then
      st[k] = nil
    else
      st[k] = v
    end
  end
  if changes.cursor == nil then
    st.cursor = 1
  end

  -- A filter belongs to the list it was typed against. Changing the *subject*
  -- drops it; changing an axis keeps it, and that asymmetry is the feature:
  -- narrowing a Deps list and then flipping direction or depth to see the
  -- same narrowing is the reason to narrow it at all, while carrying the
  -- query into a different module's list would present a short list as a
  -- complete one. `changes` is not consulted for this — `enter` can hand over
  -- an `id` equal to the current one, and it is what actually changed that
  -- decides.
  if st.mode ~= was.mode or st.id ~= was.id or st.fn ~= was.fn then
    st.filter, st.filter_raw = nil, nil
  end

  st.history[#st.history + 1] = snapshot(st)
  st.hindex = #st.history
  render(st)
end

---@param st table
---@param delta integer
local function history_step(st, delta)
  local target = st.hindex + delta
  if target < 1 or target > #st.history then
    return
  end
  sync_snapshot(st)
  st.hindex = target
  local snap = st.history[target]
  for _, k in ipairs(SNAP_KEYS) do
    st[k] = snap[k]
  end
  render(st)
end

---Descend: into a node's children, or onto a function's own call view.
---@param st table
local function enter(st)
  local e = selected(st)
  if not e then
    return
  end

  -- A pin restores the mode and axes it was taken in, not just its node.
  -- Half-restoring — landing on the right module in whatever mode happened to
  -- be current — is the failure that makes bookmarks feel unreliable: the pin
  -- was "this module's incoming requires at depth 3", and arriving at its
  -- child list is not that place.
  if e.pin then
    local p = e.pin
    go(st, {
      mode = p.mode,
      id = p.id or st.id,
      fn = p.fn or CLEAR,
      sha = p.sha or CLEAR,
      dir = p.dir or st.dir,
      depth = p.depth or st.depth,
    })
    return
  end

  -- History descends within its own mode first: commit → the functions it
  -- touched. Only from there does `<CR>` leave for the call graph.
  if e.kind == "commit" and e.sha then
    go(st, { sha = e.sha })
    return
  end
  if st.mode == "history" and st.sha and e.kind == "function" and e.id and e.fn then
    -- `dir = "in"` because the question the History mode is asking is "who
    -- calls the thing that changed" — leaving on `out` would answer a
    -- question nobody was on this screen to ask.
    go(st, { mode = "calls", id = e.id, fn = e.fn, dir = "in", sha = CLEAR })
    return
  end

  if e.kind == "node" and e.id then
    -- In deps/calls, following an edge re-centers on the far node while
    -- keeping the mode — that *is* "follow the edge".
    go(st, { id = e.id, fn = CLEAR })
  elseif e.kind == "function" and e.id and e.fn then
    go(st, { mode = "calls", id = e.id, fn = e.fn, dir = "out" })
  end
end

---@param st table
local function up(st)
  -- Trail is a flat list with no hierarchy to climb. Without this guard `-`
  -- silently re-centered the node axis underneath an unchanged screen, so the
  -- key looked broken and then, on switching back to Structure, the browser
  -- had moved somewhere nobody asked it to go.
  if st.mode == "trail" then
    return
  end

  -- In History, "out" is the commit list, not the parent node — the node
  -- hierarchy has nothing to do with what this mode is showing.
  if st.mode == "history" and st.sha then
    go(st, { sha = CLEAR })
    return
  end
  if st.fn then
    go(st, { fn = CLEAR, mode = st.mode == "calls" and "structure" or st.mode })
    return
  end
  local node = st.ir.nodes[st.id]
  if node and node.parent then
    go(st, { id = node.parent })
  end
end

-- ── Actions ─────────────────────────────────────────────────────────────────

---Absolute path for a repo-relative source path.
---@param st table
---@param rel string
---@return string
local function abs(st, rel)
  return source.norm_root(st.opts.root) .. "/" .. rel
end

---`p` — pin or unpin the entry under the cursor.
---
---The **entry**, not the centered node. "Pin this" means the thing being
---looked at, and in every mode that is the row under the cursor — centering
---on it first just to pin it would be two moves for one intention, and would
---also leave the browser somewhere the user did not ask to be.
---
---The axes travel with the pin (`dir`, `depth`, `sha`) so a jump restores the
---view, not merely the subject. See `enter`.
---@param st table
local function pin_current(st)
  local e = selected(st)
  if not e then
    return
  end

  -- A commit is a real place; a message row and an external require are not.
  -- The external case is the same call the HTML map's Deps view makes about
  -- its grey boxes: the module resolves to nothing in the scanned tree, so
  -- there is no position to return to, and a pin that navigates nowhere is
  -- worse than a refusal that says why.
  if e.kind == "message" then
    return
  end
  if e.kind == "external" then
    notify.warn("external requires have no node to return to")
    return
  end
  if not (e.id or e.sha) then
    return
  end

  local label = vim.trim((e.label or ""):gsub("^%s*%d+%.%s*", ""))
  local verb, count = trail.toggle(st.root, {
    mode = e.pin and e.pin.mode or st.mode,
    id = e.id,
    fn = e.fn,
    sha = e.sha or st.sha,
    dir = st.dir,
    depth = st.depth,
    source = e.source,
    line = e.line,
    label = label ~= "" and label or (e.id or e.sha),
    detail = e.detail,
  })

  render(st)
  notify.info(("%s — %d pinned"):format(verb, count))
end

---`d` — unpin the entry under the cursor, in Trail mode.
---@param st table
local function unpin_current(st)
  if st.mode ~= "trail" then
    return
  end
  local e = selected(st)
  if not e or not e.pin_index then
    return
  end
  local removed = trail.remove_at(st.root, e.pin_index)
  if removed then
    render(st)
    notify.info(("unpinned — %d left"):format(trail.count(st.root)))
  end
end

---`S` — save the current trail under a name.
---
---Trail mode only, like `L` and `X`. The verbs are about the list, and the
---list is what mode 6 shows; binding them everywhere would spend three of the
---remaining single keys on something reachable with one keystroke more.
---@param st table
local function save_trail(st)
  if st.mode ~= "trail" then
    return
  end
  if trail.count(st.root) == 0 then
    notify.warn("nothing pinned to save")
    return
  end

  kit.input({
    title = " save trail as ",
    theme = st.opts.theme,
    on_submit = function(line)
      local ok, err = trail_store.save_named(st.root, line)
      if ok then
        notify.info(("saved %q — %d pins"):format(vim.trim(line), trail.count(st.root)))
      else
        notify.warn(tostring(err))
      end
    end,
  })
end

---`L` — load a saved trail into the current one.
---@param st table
local function load_trail(st)
  if st.mode ~= "trail" then
    return
  end
  local names = trail_store.names(st.root)
  if #names == 0 then
    notify.info("no saved trails for this repository")
    return
  end

  kit.select({
    title = " load trail ",
    items = names,
    theme = st.opts.theme,
    -- Defer to the user's own picker when they have one (telescope-ui-select,
    -- fzf-lua, dressing), falling back to kit's chooser when they do not.
    --
    -- Right for *these two* pickers specifically: both are a plain list of
    -- names with no rendering the browser's theme contributes anything to, and
    -- a published plugin that ignores a configured picker for a bare name list
    -- is being opinionated about someone else's editor. The browser's own
    -- panes stay kit-themed — they are the view, not a prompt over it.
    respect_override = true,
    on_select = function(name)
      local _, added, skipped = trail_store.load_named(st.root, name)
      render(st)
      if added == 0 then
        notify.info(("%q — every pin was already in the trail"):format(name))
      else
        notify.info(
          ("loaded %q — %d added%s"):format(
            name,
            added,
            skipped > 0 and (", %d already there"):format(skipped) or ""
          )
        )
      end
    end,
  })
end

---`X` — forget a saved trail.
---@param st table
local function delete_trail(st)
  if st.mode ~= "trail" then
    return
  end
  local names = trail_store.names(st.root)
  if #names == 0 then
    notify.info("no saved trails for this repository")
    return
  end

  kit.select({
    title = " delete saved trail ",
    items = names,
    theme = st.opts.theme,
    respect_override = true,
    on_select = function(name)
      -- Deletes a *saved* trail, never the pins on screen. Those are what the
      -- reader is looking at, and a key that could clear them from behind a
      -- picker would be the one destructive surprise in this whole feature.
      if trail_store.delete_named(st.root, name) then
        notify.info(("deleted saved trail %q"):format(name))
      end
    end,
  })
end

---`gd` — open the source and close the browser.
---
---Closing is deliberate: the floats sit over the whole editor, and leaving
---them up means jumping "to" a file the user cannot see.
---@param st table
local function goto_source(st)
  local e = selected(st) or {}
  local rel = e.source or (st.ir.nodes[st.id] or {}).source
  if not rel then
    notify.warn("nothing to open here")
    return
  end
  local line = e.line
  local path = abs(st, rel)

  M.close()
  vim.cmd.edit(vim.fn.fnameescape(path))
  if line then
    pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
    vim.cmd("normal! zz")
  end
end

---`gq` — the current list into the quickfix list.
---@param st table
local function to_quickfix(st)
  local items = {}
  for _, e in ipairs(st.entries) do
    if e.source then
      items[#items + 1] = {
        filename = abs(st, e.source),
        lnum = e.line or 1,
        col = 1,
        text = (e.label or ""):gsub("^%s+", ""),
      }
    end
  end

  if #items == 0 then
    notify.warn("nothing in this list has a source location")
    return
  end

  vim.fn.setqflist({}, " ", {
    title = ("DocMap %s: %s"):format(st.mode, view.breadcrumb(st.ir, st.id)),
    items = items,
  })
  M.close()
  vim.cmd("copen")
end

---`gI` — the blast radius of the centered node into the quickfix list.
---
---The counterpart to `gq`: `gq` sends what is *on screen*, this sends what
---would break. Transitive, so it answers the question actually being asked
---before a refactor rather than only naming the immediate dependents.
---Acts on whatever the **detail pane** is describing, not on the centered
---node. Those differ the moment the cursor moves off the first row, and a
---`gI` that reported a different number from the one just read two panes over
---would be worse than no number at all.
---@param st table
local function impact_to_quickfix(st)
  local entry = selected(st)
  local target = (entry and entry.id) or st.id
  local hull, direct = require("documentation.core.deps").impact(st.ir, target)
  if #hull == 0 then
    notify.info("nothing depends on this — safe to change")
    return
  end

  local items = {}
  for _, id in ipairs(hull) do
    local node = st.ir.nodes[id]
    if node and node.source then
      items[#items + 1] = {
        filename = abs(st, node.source),
        lnum = 1,
        col = 1,
        text = node.module or node.path or id,
      }
    end
  end

  vim.fn.setqflist({}, " ", {
    title = ("DocMap impact: %s (%d, %d direct)"):format(
      view.breadcrumb(st.ir, target),
      #hull,
      direct
    ),
    items = items,
  })
  M.close()
  vim.cmd("copen")
end

---`gD` — the opened commit's diff in a scratch buffer.
---
---A buffer rather than a pane: the diff is the one part of this that is
---ordinary text a reader wants to scroll, search and yank, and Neovim already
---does all three better than a third list column would. `filetype=diff` gets
---the syntax highlighting for free.
---
---The view closes first, for the same reason `gd` and `gq` close it: the
---floats cover the editor, and putting a buffer *behind* them would be a jump
---to somewhere the reader cannot see.
---@param st table
local function show_diff(st)
  if st.mode ~= "history" or not st.sha then
    notify.warn("gD shows a commit's diff — open one in History mode (5) first")
    return
  end
  local text = st.diff_text
  if not text or vim.trim(text) == "" then
    notify.info("that commit changed nothing outside the generated map")
    return
  end

  local sha = st.sha
  M.close()
  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n", { plain = true }))
  vim.bo[buf].filetype = "diff"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  pcall(vim.api.nvim_buf_set_name, buf, ("documentation://diff/%s"):format(sha:sub(1, 10)))
end

---`gO` — hand the current position over to the generated HTML page.
---
---The navigator knows mode, center, direction, depth and function; the page's
---whole state lives in its URL fragment. So this is a `format()` and the
---existing opener — and it answers "actually, I want to see that as a
---picture" without hunting for the place again.
---@param st table
local function open_in_browser(st)
  local target = source.norm_root(st.opts.root)
    .. "/"
    .. (st.opts.out_dir or "docs/map")
    .. "/index.html"
  if not (vim.uv or vim.loop).fs_stat(target) then
    notify.warn("no generated page yet — run :DocMap first")
    return
  end

  -- The page has no Structure mode; its equivalent is the Modules hierarchy.
  local view_name = st.mode == "structure" and "modules" or st.mode
  local hash = ("#tab=hierarchy&center=%s&view=%s&dir=%s&depth=%d"):format(
    vim.uri_encode(st.id, "rfc2396"),
    view_name,
    st.dir or "out",
    st.depth or 2
  )
  if st.mode == "calls" and st.fn then
    hash = hash .. "&fn=" .. vim.uri_encode(st.id .. "#" .. st.fn, "rfc2396")
  end

  require("lib.nvim.fs.open.url.system_opener").open(vim.uri_from_fname(target) .. hash)
end

---`gs` — send the selected route as a request via `runtime-analysis.nvim`,
---if it is installed. A soft dependency, the same pattern this ecosystem
---already uses for `progress`->fidget and `check.lua`->lua-language-server:
---the keymap exists in Endpoints mode regardless, and degrades to a clear
---message when the other plugin is absent rather than being silently
---unreachable. Checked at call time, not cached at this file's own load
---time — `runtime-analysis.nvim` being installed is not a fact about when
---documentation.nvim started.
---
---Opens a pre-filled request buffer rather than sending immediately: a
---route's `path` is relative (`/users/:id`), never a full URL — this plugin
---has no base URL to guess, and a route with path params needs the reader
---to fill in a real id before the request means anything. `runtime-
---analysis.nvim`'s own `:RASend`, run from that buffer once it is
---complete, is what actually sends it.
---@param st table
local function send_request(st)
  local e = selected(st)
  if not e or e.kind ~= "endpoint" then
    notify.warn("nothing to send here")
    return
  end

  local ok_ra, runtime_analysis = pcall(require, "runtime-analysis")
  if not ok_ra then
    notify.warn("runtime-analysis.nvim is not installed — see :help documentation-endpoints")
    return
  end

  local spec = e.spec
  M.close()
  runtime_analysis.open_request({
    ("%s %s"):format(spec.method:upper(), spec.path),
    "",
  })
end

---`/` — fuzzy jump across every module and function in the map.
---@param st table
local function search(st)
  local candidates = {}
  for _, id in ipairs(st.ir.order or {}) do
    local node = st.ir.nodes[id]
    if node then
      candidates[#candidates + 1] = { label = node.module or node.name, id = id }
      for _, fn in ipairs(node.functions or {}) do
        candidates[#candidates + 1] = {
          label = ("%s#%s"):format(node.module or node.name, fn.name),
          id = id,
          fn = fn.name,
        }
      end
    end
  end

  local matches = candidates
  local picker
  picker = kit.picker({
    on_change = function(query)
      matches = {}
      local needle = query:lower()
      for _, c in ipairs(candidates) do
        if needle == "" or c.label:lower():find(needle, 1, true) then
          matches[#matches + 1] = c
        end
      end
      local lines = {}
      for i, c in ipairs(matches) do
        lines[i] = c.label
      end
      picker.set_results(lines)
    end,
    on_submit = function(idx)
      local hit = matches[idx]
      if not hit or not M.is_open() then
        return
      end
      if hit.fn then
        go(st, { mode = "calls", id = hit.id, fn = hit.fn, dir = "out" })
      else
        go(st, { mode = "structure", id = hit.id, fn = CLEAR })
      end
      st.slots.list:focus()
    end,
  })
  if picker then
    local lines = {}
    for i, c in ipairs(candidates) do
      lines[i] = c.label
    end
    picker.set_results(lines)
  end
end

---`f` — narrow the current list in place.
---
---One key, not two. It opens prefilled with the query already in effect, so
---editing a filter and clearing it are the same gesture — submit an empty
---line and it is gone. A separate "clear" key would only exist because this
---one refused to show what it had, the same reasoning that gave `p` a single
---toggle instead of wayfinder's `p`/`a`/`A`.
---
---Not routed through `go`: a filter is not a position. Making it a history
---stop would mean `<C-o>` sometimes undoes a move and sometimes undoes a
---keystroke of typing, and the two are not the same kind of "back". It still
---travels *with* positions — see `SNAP_KEYS`.
---@param st table
local function set_filter(st)
  kit.input({
    title = " filter this list ",
    default = st.filter_raw or "",
    theme = st.opts.theme,
    on_submit = function(query)
      if not M.is_open() then
        return
      end
      st.filter = filter.parse(query)
      st.filter_raw = st.filter and query or nil
      -- Back to the top: the row the cursor sat on very likely no longer
      -- exists, and carrying a row index into a shorter list lands somewhere
      -- arbitrary rather than somewhere related.
      st.cursor = 1
      render(st)

      -- The current position's snapshot, patched in place rather than through
      -- `sync_snapshot` — that reads the cursor back out of the window, which
      -- would undo the line above. Written so `<C-o>` away and `<C-i>` back
      -- returns to the list as narrowed, not as it was before the filter.
      local snap = st.history[st.hindex]
      if snap then
        snap.cursor, snap.filter, snap.filter_raw = st.cursor, st.filter, st.filter_raw
      end
      st.slots.list:focus()
    end,
  })
end

-- ── Keymaps ─────────────────────────────────────────────────────────────────

---Change the direction axis, but only where it means something and only when
---it actually changes. Same reasoning as the mode keys: a move that changes
---nothing must not become a history stop, or Back appears to stall on it.
---@param st table
---@param dir "in"|"out"
local function set_dir(st, dir)
  if (st.mode == "deps" or st.mode == "calls") and st.dir ~= dir then
    go(st, { dir = dir })
  end
end

---Depth is a Deps-only axis: `walk_requires` is the only thing that reads it.
---Ungated, `+` in Structure or Types pushed a history stop that changed
---nothing on screen — and a `<C-o>` that visibly does nothing reads as the
---history being broken rather than as the depth key having been a no-op.
---@param st table
---@param delta integer
local function set_depth(st, delta)
  if st.mode ~= "deps" then
    return
  end
  local want = math.max(1, math.min(9, st.depth + delta))
  if want ~= st.depth then
    go(st, { depth = want })
  end
end

---Forward declaration: the `help` entry in `KEYS` below runs `cheatsheet`,
---and `cheatsheet` renders `KEYS`. One of the two has to be named before it
---is defined, and this is the cheaper direction.
---@type fun(st: table)
local cheatsheet

---The keymap table, and the **only** description of what the browser's keys
---do. `bind()` installs from it and the `?` cheatsheet renders from it, so
---the two cannot disagree — a hand-maintained second list of keys is exactly
---the drift this plugin exists to detect, and shipping one inside it would be
---hard to defend.
---
---`only` is the mode (or set of modes) an entry applies in. It is not a
---binding condition — the handlers already gate themselves, and gating the
---*binding* would make a key fall through to Vim's own meaning on the wrong
---mode (`+` moves the cursor down a line, which is worse than nothing
---happening). It is presentation: the cheatsheet greys out what the current
---mode ignores, which is the question someone presses `?` to answer.
---
---`run == nil` means "documented, deliberately not bound" — `j`/`k` stay
---native so counts and `scrolloff` behave, and a cheatsheet that omitted them
---would read as if the browser had no movement keys at all.
---
---`id` is the stable name a user's `opts.keys` table keys on. It is
---deliberately not the default left-hand side: rebinding `<CR>` should not
---change what the entry is *called*, and `docs/BINDINGS.md` is generated
---against these ids too. Renaming one is a breaking change to user config;
---adding one is not.
---@class Documentation.Browse.KeySpec
---@field id Documentation.Browse.KeyAction Stable action name; what `opts.keys` addresses.
---@field keys string[] Left-hand sides, all doing the same thing.
---@field desc string Cheatsheet text.
---@field only string|string[]|nil Mode(s) this applies in; nil = everywhere.
---@field run fun(st: table)|nil Handler, or nil for a native key.
---@field disabled boolean|nil Set by `resolve_keys` when the user passed `false`. Never set in the defaults.

---@type Documentation.Browse.KeySpec[]
local KEYS = {
  { id = "move", keys = { "j", "k" }, desc = "move; the detail pane follows" },
  { id = "enter", keys = { "<CR>" }, desc = "descend a level, or follow the edge", run = enter },
  {
    id = "up",
    keys = { "-", "<BS>" },
    desc = "up a level (×count)",
    run = function(st)
      for _ = 1, vim.v.count1 do
        up(st)
      end
    end,
  },
  {
    id = "back",
    keys = { "<C-o>" },
    desc = "back through the visit history (×count)",
    run = function(st)
      history_step(st, -vim.v.count1)
    end,
  },
  {
    id = "forward",
    keys = { "<C-i>" },
    desc = "forward through the visit history (×count)",
    run = function(st)
      history_step(st, vim.v.count1)
    end,
  },
  {
    id = "dir_in",
    keys = { "h" },
    desc = "direction: incoming edges",
    only = { "deps", "calls" },
    run = function(st)
      set_dir(st, "in")
    end,
  },
  {
    id = "dir_out",
    keys = { "l" },
    desc = "direction: outgoing edges",
    only = { "deps", "calls" },
    run = function(st)
      set_dir(st, "out")
    end,
  },
  {
    id = "depth_inc",
    keys = { "+" },
    desc = "depth +1 (×count)",
    only = "deps",
    run = function(st)
      set_depth(st, vim.v.count1)
    end,
  },
  {
    id = "depth_dec",
    keys = { "_" },
    desc = "depth -1 (×count)",
    only = "deps",
    run = function(st)
      set_depth(st, -vim.v.count1)
    end,
  },
  {
    id = "goto_source",
    keys = { "gd" },
    desc = "open the source at the line (closes)",
    run = goto_source,
  },
  {
    id = "quickfix",
    keys = { "gq" },
    desc = "current list into the quickfix list (closes)",
    run = to_quickfix,
  },
  {
    id = "impact",
    keys = { "gI" },
    desc = "blast radius into the quickfix list (closes)",
    run = impact_to_quickfix,
  },
  {
    id = "open_page",
    keys = { "gO" },
    desc = "open the generated page here",
    run = open_in_browser,
  },
  {
    id = "send_request",
    keys = { "gs" },
    desc = "send a request to this route (needs runtime-analysis.nvim)",
    only = "endpoints",
    run = send_request,
  },
  {
    id = "commit_diff",
    keys = { "gD" },
    desc = "the opened commit's diff",
    only = "history",
    run = show_diff,
  },
  {
    id = "pin",
    keys = { "p" },
    desc = "pin / unpin the entry under the cursor",
    run = pin_current,
  },
  { id = "unpin", keys = { "d" }, desc = "unpin", only = "trail", run = unpin_current },
  {
    id = "trail_save",
    keys = { "S" },
    desc = "save this trail under a name",
    only = "trail",
    run = save_trail,
  },
  {
    id = "trail_load",
    keys = { "L" },
    desc = "load a saved trail (adds to this one)",
    only = "trail",
    run = load_trail,
  },
  {
    id = "trail_delete",
    keys = { "X" },
    desc = "forget a saved trail",
    only = "trail",
    run = delete_trail,
  },
  {
    id = "filter",
    keys = { "f" },
    desc = 'filter this list in place (-negate, "phrase"; empty clears)',
    run = set_filter,
  },
  { id = "search", keys = { "/" }, desc = "fuzzy jump across modules and functions", run = search },
  {
    id = "help",
    keys = { "?" },
    desc = "this list",
    run = function(st)
      -- Assigned below: `cheatsheet` renders the very table this entry lives
      -- in, so it cannot be defined before it. Forward-declared rather than
      -- special-cased in `bind()`, which is what made `?` the one key a user
      -- could not rebind or disable.
      cheatsheet(st)
    end,
  },
  {
    id = "close",
    keys = { "q", "<Esc>" },
    desc = "close",
    run = function()
      M.close()
    end,
  },
}

---Apply a user's `opts.keys` over `KEYS`.
---
---The rule itself — validate the action names, replace or disable, never
---mutate the defaults — lives in `documentation.bindings.keymaps`, which is
---generic over any table of `{ id, keys }`. `KEYS` stays here because every
---entry's `run` closes over this module's navigation state; see that module's
---header for why the table was not moved out with the rule.
---@param opts Documentation.Browse.Opts
---@return Documentation.Browse.KeySpec[]
local function resolve_keys(opts)
  return require("documentation.bindings.keymaps").resolve(KEYS, opts and opts.keys, notify)
end

---True when `spec` applies in `mode`.
---@param spec Documentation.Browse.KeySpec
---@param mode string
---@return boolean
local function applies_in(spec, mode)
  if not spec.only then
    return true
  end
  if type(spec.only) == "string" then
    return spec.only == mode
  end
  return vim.tbl_contains(spec.only, mode)
end

---Render the `?` cheatsheet for the current mode.
---
---A `kit.viewer` rather than a hand-rolled float: read-only, auto-sized,
---`q`/`<Esc>` to close and — the part that matters here — it dismisses itself
---the moment focus returns to the list, so the overlay never has to be
---explicitly closed before carrying on. The browser's own layout has no
---focus-loss teardown, so nothing underneath it goes away with it.
---@param st table
cheatsheet = function(st)
  local lines = { "" }
  local pad = 14

  local modes = {}
  for i, mode in ipairs(MODES) do
    modes[#modes + 1] = ("%d %s"):format(i, mode)
  end
  lines[#lines + 1] = ("  %-" .. pad .. "s%s"):format(
    "1 … " .. #MODES,
    table.concat(modes, "  ·  ")
  )
  lines[#lines + 1] = ""

  -- `st.keys`, not `KEYS`: the panel has to show what is actually bound in
  -- *this* browser, overrides included. Rendering the defaults here would
  -- reintroduce exactly the drift the shared table was built to prevent, only
  -- now invisible — the panel would be right for an unconfigured user and
  -- quietly wrong for a configured one.
  for _, spec in ipairs(st.keys) do
    local lhs = spec.disabled and "—" or table.concat(spec.keys, " ")
    -- Marked rather than hidden: "why did `+` do nothing" is precisely the
    -- question this overlay is opened to answer, and a key that vanishes from
    -- the list looks like it was never there.
    local suffix = ""
    if spec.disabled then
      suffix = "   (disabled)"
    elseif not applies_in(spec, st.mode) then
      suffix = "   (not in this mode)"
    end
    lines[#lines + 1] = ("  %-" .. pad .. "s%s%s"):format(lhs, spec.desc, suffix)
  end
  lines[#lines + 1] = ""

  kit.viewer({
    title = (" DocBrowse keys — %s "):format(st.mode),
    lines = lines,
    theme = st.opts.theme,
    filetype = "documentation-browse-help",
  })
end

---@param st table
local function bind(st)
  local bufnr = st.slots.list.bufnr

  ---A **fresh** options table per binding, never a shared one.
  ---
  ---`lib.nvim.map` mutates what it is handed — it writes `desc`, `noremap`,
  ---`silent` and the normalised `buffer` back into the table before calling
  ---`vim.keymap.set`. One `mo` reused across every call therefore carried the
  ---previous binding's `desc` into the next one, which is invisible until a
  ---`desc` is actually set (as it now is) and then shows up as every key in
  ---which-key being labelled "close".
  ---@param desc string
  ---@return table
  local function mo(desc)
    return { buffer = bufnr, nowait = true, desc = desc }
  end

  for i, mode in ipairs(MODES) do
    map("n", tostring(i), function()
      if st.mode ~= mode then
        -- Leaving History drops the opened commit: coming back should land on
        -- the list, and a stale `sha` would otherwise make mode `5` reopen a
        -- commit the reader had already navigated away from.
        go(st, { mode = mode, sha = CLEAR })
      end
    end, mo(("show the %s list"):format(mode)))
  end

  -- j/k stay native so counts and scrolloff behave; CursorMoved drives the
  -- detail pane instead of re-implementing movement.
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = st.slots.list.bufnr,
    callback = function()
      if M.is_open() then
        render_detail(st)
      end
    end,
    desc = "documentation.editor.browse: detail follows the list cursor",
  })

  -- `st.keys` rather than `KEYS`: the resolved set, with the user's overrides
  -- already applied. A `disabled` entry has an empty `keys` list, so it falls
  -- out here without needing its own branch.
  for _, spec in ipairs(st.keys) do
    local run = spec.run
    if run then
      for _, key in ipairs(spec.keys) do
        map("n", key, function()
          run(st)
        end, mo(spec.desc))
      end
    end
  end

  -- Opt-out, and a no-op when which-key is not installed. Last, so it can
  -- describe exactly what was bound above rather than what was intended.
  if st.opts.which_key ~= false then
    require("documentation.editor.browse.whichkey").register(bufnr, st.keys, MODES)
  end
end

-- ── Entry point ─────────────────────────────────────────────────────────────

---Open the browser.
---@param opts Documentation.Browse.Opts
---@return boolean opened
function M.open(opts)
  opts = opts or {}
  assert(
    type(opts.root) == "string" and opts.root ~= "",
    "docmap.browse.open: opts.root is required"
  )

  M.close()

  -- Here rather than at require time, so merely requiring `documentation`
  -- installs no autocmd — the same rule `command.setup()` follows for its
  -- user commands. Both calls are idempotent and hydration happens once per
  -- root, so re-opening never re-reads over pins made since.
  trail_store.attach()
  trail_store.hydrate(source.norm_root(opts.root))

  local ir, handle, hint = source.acquire(opts)
  if not ir then
    notify.error(hint or "could not load the map")
    return false
  end

  local group = kit.layout.mount({
    width = opts.width or 0.86,
    height = opts.height or 0.86,
    gap = 0,
    rows = {
      {
        cols = {
          { name = "list", width = opts.list_width or 0.38 },
          { name = "detail", width = 1 - (opts.list_width or 0.38) },
        },
      },
      { name = "status", height = 3 },
    },
  }, {
    theme = opts.theme,
    enter = "list",
    slot = {
      list = { wo = { cursorline = true }, filetype = "documentation-browse-list" },
      detail = { filetype = "documentation-browse-detail" },
      status = { filetype = "documentation-browse-status" },
    },
  })

  if not (group and group.slots.list and group.slots.detail and group.slots.status) then
    if group then
      group.close()
    end
    notify.error("could not mount the browser layout")
    return false
  end

  -- Center on the requested module, else the root.
  --
  -- Resolution goes through `command.find_node` rather than a local
  -- `node.module == name` scan, and that matters for exactly the case a user
  -- is most likely to type: `lua/lib/nvim/fs` is a *namespace* with no
  -- `init.lua`, so it declares no `@module` at all — yet `lib.nvim.fs` is the
  -- name in everyone's head, and namespaces are the aggregation points a
  -- dependency view is most useful at. `find_node` already falls back to the
  -- module path a node's location implies; duplicating that here would mean
  -- re-fixing the same bug in a second place. (It was found here by typing
  -- `:DocBrowse lib.nvim.fs` and silently landing on the root.)
  local center = ir.root
  if opts.center and opts.center ~= "" then
    local found =
      require("documentation.editor.command").find_node(ir, opts.center, opts.lua_root or "lua")
    if found then
      center = found
    else
      notify.warn(("no module matching '%s' — opening at the root"):format(opts.center))
    end
  end

  state = {
    opts = opts,
    -- Resolved once per open, not per bind or per cheatsheet render: the
    -- override warning for an unknown action then fires exactly once, and
    -- `bind()` and `cheatsheet()` are guaranteed to be looking at the same
    -- list.
    keys = resolve_keys(opts),
    root = source.norm_root(opts.root),
    ir = ir,
    handle = handle,
    group = group,
    slots = group.slots,
    mode = opts.mode or "structure",
    id = center,
    fn = nil,
    dir = "out",
    depth = opts.depth or 2,
    cursor = 1,
    entries = {},
    history = {},
    hindex = 1,
    hint = hint,
  }
  -- The trail starts with where we are, not empty: `hindex` always addresses
  -- a real entry, which is what lets `history_step` be a plain bounds check.
  state.history[1] = snapshot(state)

  if handle then
    state.unsubscribe = handle.on_change(function(new_ir)
      if M.is_open() then
        state.ir = new_ir
        -- The centered node can vanish across a rescan (file deleted while
        -- watching); falling back to the root beats rendering an empty pane
        -- with no way out.
        if not state.ir.nodes[state.id] then
          state.id = state.ir.root
          state.fn = nil
        end
        render(state)
      end
    end)
  end

  bind(state)
  render(state)
  return true
end

---Toggle: open when closed, close when open.
---@param opts Documentation.Browse.Opts
function M.toggle(opts)
  if M.is_open() then
    M.close()
  else
    M.open(opts)
  end
end

---The default key table and the mode list, for anything that needs to
---*describe* the browser rather than run it — `bindings/docs.lua` generates
---`docs/BINDINGS.md` from exactly this.
---
---Exported deliberately narrowly: a copy of the specs, not `KEYS` itself, so a
---caller cannot mutate the defaults every later browser will be built from.
---`run` travels with each entry because it is what distinguishes a bound key
---from a documented-but-native one (`j`/`k`), which any honest description has
---to state — but calling it from outside a live browser is not supported and
---will fail on the state it expects.
---
---Applying a user's `opts.keys` is *not* done here: that is
---`bindings/keymaps.resolve`, and a doc generator wants the defaults, not one
---particular user's configuration.
---@return Documentation.Browse.KeySpec[] specs
---@return string[] modes
function M.keyspecs()
  return vim.deepcopy(KEYS, true), vim.deepcopy(MODES)
end

return M
