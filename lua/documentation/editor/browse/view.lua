---@module 'documentation.editor.browse.view'
--- Turns a browser state into the three things on screen: the list entries,
--- the detail lines for the selected one, and the status line.
---
--- Deliberately pure — every function here takes an IR plus a state table and
--- returns strings. No window, buffer or keymap is touched, so the mode logic
--- is testable headlessly without mounting anything, which is what
--- `TESTS/docmap_browse_spec.lua` does.
---
--- Why lists and not a graph: a terminal is a fixed cell grid, and boxes with
--- connecting curves need free positions and continuous zoom. Reproducing the
--- HTML diagram here would be a worse version of a page that already exists.
--- What the editor *can* do — jump to source, fill the quickfix list, stay
--- live — needs a navigator over the same edges, not a drawing of them.

local filter = require("documentation.editor.browse.filter")

local M = {}

---Icon for a node kind. ASCII-adjacent glyphs only: these land in a scratch
---buffer that may be read in a terminal with a patchy font, and a missing
---glyph in the *list* column shifts every label after it.
---@param kind string
---@return string
local function node_icon(kind)
  if kind == "module" then
    return "▸"
  elseif kind == "namespace" then
    return "·"
  end
  return " "
end

---@param s string|nil
---@param width integer
---@return string
local function truncate(s, width)
  s = s or ""
  if vim.fn.strdisplaywidth(s) <= width then
    return s
  end
  return vim.fn.strcharpart(s, 0, math.max(1, width - 1)) .. "…"
end

-- ── Entry builders, one per mode ────────────────────────────────────────────

---Children + own functions of the centered node.
---@param ir Documentation.IR
---@param st table
---@return Documentation.Browse.Entry[]
local function structure_entries(ir, st)
  local node = ir.nodes[st.id]
  if not node then
    return { { kind = "message", label = "no such node: " .. tostring(st.id) } }
  end

  local out = {}
  for _, cid in ipairs(node.children or {}) do
    local c = ir.nodes[cid]
    if c then
      out[#out + 1] = {
        kind = "node",
        id = cid,
        source = c.source,
        label = ("%s %s"):format(node_icon(c.kind), c.name),
        detail = c.summary,
      }
    end
  end
  for _, fn in ipairs(node.functions or {}) do
    out[#out + 1] = {
      kind = "function",
      id = st.id,
      fn = fn.name,
      line = fn.line,
      source = node.source,
      label = ("ƒ %s"):format(fn.signature or fn.name),
      detail = fn.summary,
    }
  end

  if #out == 0 then
    out[1] = { kind = "message", label = "(nothing below this node)" }
  end
  return out
end

---Breadth-first walk over the derived `requires`/`required_by` index.
---
---Uses the index rather than filtering `ir.edges` because it is already
---sorted and deduplicated by the scan; re-deriving it here would be a second
---source of truth for the same fact.
---@param ir Documentation.IR
---@param start_id string
---@param dir "in"|"out"
---@param depth integer
---@return { id: string, depth: integer }[]
function M.walk_requires(ir, start_id, dir, depth)
  local field = dir == "in" and "required_by" or "requires"
  local seen = { [start_id] = 0 }
  local queue = { start_id }
  local out = {}

  local qi = 1
  while qi <= #queue do
    local cur = queue[qi]
    qi = qi + 1
    local d = seen[cur]
    if d < depth then
      local node = ir.nodes[cur]
      for _, nid in ipairs((node and node[field]) or {}) do
        if seen[nid] == nil then
          seen[nid] = d + 1
          queue[#queue + 1] = nid
          out[#out + 1] = { id = nid, depth = d + 1 }
        end
      end
    end
  end

  table.sort(out, function(a, b)
    if a.depth ~= b.depth then
      return a.depth < b.depth
    end
    return a.id < b.id
  end)
  return out
end

---@param ir Documentation.IR
---@param st table
---@return Documentation.Browse.Entry[]
local function deps_entries(ir, st)
  local node = ir.nodes[st.id]
  if not node then
    return { { kind = "message", label = "no such node: " .. tostring(st.id) } }
  end

  local reached = M.walk_requires(ir, st.id, st.dir, st.depth)
  local out = {}
  for _, hit in ipairs(reached) do
    local c = ir.nodes[hit.id]
    if c then
      out[#out + 1] = {
        kind = "node",
        id = hit.id,
        source = c.source,
        label = ("%s%s %s"):format(
          string.rep("  ", hit.depth - 1),
          node_icon(c.kind),
          c.module or c.name
        ),
        detail = c.summary,
      }
    end
  end

  -- External requires have no node to navigate to, but hiding them entirely
  -- makes the list look like the module has fewer dependencies than it does.
  if st.dir == "out" then
    for _, ext in ipairs(node.requires_external or {}) do
      out[#out + 1] =
        { kind = "external", label = ("  ○ %s"):format(ext), detail = "outside the scanned tree" }
    end
  end

  if #out == 0 then
    out[1] = {
      kind = "message",
      label = st.dir == "in" and "(nothing requires this)" or "(this requires nothing in the tree)",
    }
  end
  return out
end

---Line a function is declared on, or nil when the map has no detail for it.
---@param ir Documentation.IR
---@param node_id string|nil
---@param fn_name string|nil
---@return integer|nil
function M.declaration_line(ir, node_id, fn_name)
  if not node_id or not fn_name then
    return nil
  end
  local node = ir.nodes[node_id]
  for _, f in ipairs((node and node.functions) or {}) do
    if f.name == fn_name then
      return f.line
    end
  end
  return nil
end

---Call edges touching the centered node, narrowed to one function when the
---state has one pinned.
---@param ir Documentation.IR
---@param st table
---@return Documentation.Browse.Entry[]
local function calls_entries(ir, st)
  local out = {}
  local near_field = st.dir == "in" and "to" or "from"
  local near_fn_field = st.dir == "in" and "to_fn" or "from_fn"
  local far_field = st.dir == "in" and "from" or "to"
  local far_fn_field = st.dir == "in" and "from_fn" or "to_fn"

  for _, e in ipairs(ir.edges or {}) do
    if e.kind == "call" and e[near_field] == st.id and (not st.fn or e[near_fn_field] == st.fn) then
      local far_id = e[far_field]
      local far_fn = e[far_fn_field]
      local far_node = ir.nodes[far_id]
      local label = ("%s%s"):format(
        st.fn and "" or ((e[near_fn_field] or "?") .. "  →  "),
        ("%s#%s"):format((far_node and (far_node.module or far_node.name)) or far_id, far_fn or "?")
      )
      out[#out + 1] = {
        kind = "function",
        id = far_id,
        fn = far_fn,
        -- `gd` on a call entry should land on the far function's
        -- *declaration*, not on `e.line` — an edge's line is the call site,
        -- which lives in the near file and would send every entry in the
        -- list back into the file already being looked at.
        line = M.declaration_line(ir, far_id, far_fn),
        source = far_node and far_node.source,
        -- Kept separately so the detail pane can still name the call site.
        site_source = (ir.nodes[e[near_field]] or {}).source,
        site_line = e.line,
        label = ("  %s%s"):format(e.confidence == "heuristic" and "~ " or "  ", label),
        detail = e.confidence == "heuristic" and "heuristic match — verify before trusting"
          or nil,
      }
    end
  end

  table.sort(out, function(a, b)
    return a.label < b.label
  end)

  if #out == 0 then
    local has_calls = false
    for _, e in ipairs(ir.edges or {}) do
      if e.kind == "call" then
        has_calls = true
        break
      end
    end
    out[1] = {
      kind = "message",
      label = has_calls
          and (st.dir == "in" and "(nothing calls into this)" or "(this calls nothing resolvable)")
        or "(no call data in this map — regenerate with :DocMap)",
    }
  end
  return out
end

---@param ir Documentation.IR
---@param st table
---@return Documentation.Browse.Entry[]
local function types_entries(ir, st)
  local node = ir.nodes[st.id]
  if not node then
    return { { kind = "message", label = "no such node: " .. tostring(st.id) } }
  end
  if node.types_detail == nil then
    return {
      {
        kind = "message",
        label = "(no type data — regenerate with :DocMap full)",
      },
    }
  end

  local out = {}
  for _, t in ipairs(node.types_detail) do
    out[#out + 1] = {
      kind = "type",
      id = st.id,
      type_name = t.name,
      source = t.file,
      label = ("%s %s"):format(t.kind == "alias" and "≡" or "◆", t.name),
      detail = t.desc,
    }
  end
  if #out == 0 then
    out[1] = { kind = "message", label = "(this module declares no types)" }
  end
  return out
end

---History mode, which has two levels: the commit list, and — once one is
---opened — the functions that commit's diff touches.
---
---This is the one mode whose data does not come from the IR. `init.lua` runs
---git and puts the results on the state (`st.commits`, `st.impact`), so this
---stays as pure as every other builder here; the alternative would be a
---`view` that shells out, which would make the whole module untestable
---headlessly for the sake of one mode.
---@param ir Documentation.IR
---@param st table
---@return Documentation.Browse.Entry[]
local function history_entries(ir, st)
  if not st.sha then
    if not st.commits then
      return { { kind = "message", label = "(loading commits…)" } }
    end
    if #st.commits == 0 then
      return { { kind = "message", label = "(no commits)" } }
    end
    local out = {}
    for _, c in ipairs(st.commits) do
      out[#out + 1] = {
        kind = "commit",
        sha = c.sha,
        commit = c,
        label = ("%s  %s"):format(c.short, c.subject),
        detail = c.date .. "  " .. c.author,
      }
    end
    return out
  end

  local im = st.impact
  if not im then
    return { { kind = "message", label = "(analysing " .. st.sha:sub(1, 8) .. "…)" } }
  end

  local out = {}
  for _, t in ipairs(im.touched) do
    local node = ir.nodes[t.node]
    local callers = im.callers[t.node .. "#" .. t.fn] or {}
    out[#out + 1] = {
      kind = "function",
      id = t.node,
      fn = t.fn,
      callers = callers,
      -- The declaration in the *current* tree, so `gd` lands somewhere that
      -- still exists. A commit can name a function since moved or deleted;
      -- then there is simply no source and `gd` says so, which beats jumping
      -- to a stale line number.
      source = node and node.source or nil,
      line = t.line,
      label = ("  %s   %d caller%s"):format(
        t.signature or t.fn,
        #callers,
        #callers == 1 and "" or "s"
      ),
      detail = node and (node.module or node.path) or t.node,
    }
  end

  -- Changed files nothing could be attributed to are still information — they
  -- are why the list is shorter than the diff looks — but they are not
  -- navigable, so they sit at the end as messages rather than pretending to
  -- be entries.
  for _, path in ipairs(im.unattributed or {}) do
    out[#out + 1] = { kind = "message", label = "  · " .. path .. "  (nothing to trace)" }
  end

  if #out == 0 then
    out[1] = { kind = "message", label = "(no scanned function contains the changed lines)" }
  end
  return out
end

---The pinned positions, in the order they were pinned.
---
---Each entry keeps its `pin` so `<CR>` can restore the mode and axes it was
---taken in, and re-exposes `kind`/`id`/`fn`/`source`/`line` at the top level
---so every action that already reads those — the detail pane, `gd`, `gq` —
---works here with no trail-specific branch. A pin is a position, and this
---mode is a list of positions like any other.
---@param ir Documentation.IR
---@param st table
---@return Documentation.Browse.Entry[]
local function trail_entries(ir, st)
  local list = st.pins or {}
  if #list == 0 then
    return {
      { kind = "message", label = "(nothing pinned)" },
      { kind = "message", label = "" },
      { kind = "message", label = "  p   pin the entry under the cursor, in any mode" },
      { kind = "message", label = "  d   unpin, here" },
    }
  end

  local out = {}
  for i, p in ipairs(list) do
    -- The node is looked up in the *current* IR rather than trusted from the
    -- pin, so a pin whose node was renamed or deleted since says so instead of
    -- rendering a label for something that is no longer there. Same rule the
    -- HTML map's History tab follows for module chips.
    local node = p.id and ir.nodes[p.id]
    local gone = p.id ~= nil and node == nil
    out[#out + 1] = {
      kind = gone and "message" or (p.fn and "function" or "node"),
      id = p.id,
      fn = p.fn,
      sha = p.sha,
      pin = p,
      pin_index = i,
      source = not gone and p.source or nil,
      line = p.line,
      label = gone and ("  %s   (no longer in the map)"):format(p.label)
        or ("%d. %s"):format(i, p.label),
      detail = p.detail,
    }
  end
  return out
end

---Every call-based route registration across the whole tree — not centered
---on `st.id`, the same shape `trail_entries` already has for "spans
---something other than one node's neighborhood." Straight off
---`n.endpoints`, the same data `core/endpoints.lua` already extracted for
---the static page's Analysis panel and `:DocMap endpoints`'s quickfix list —
---no new extraction here, only a third reader of the same field.
---
---Enriched with the static x runtime join (`runtime-analysis.nvim`) when that
---plugin is installed and this project has
---request history: a leading `○` marks a declared route history has never
---matched — a real, actionable "this is dead weight or untested", the
---same reading the `telemetry` mode's own `○` gives a cold function.
---Absence of a match is never claimed as certainty, only as "nothing
---recorded a send to it yet" — the identical honest-limits posture the
---telemetry join already states for its own "no data" case.
---@param ir Documentation.IR
---@param st table
---@return Documentation.Browse.Entry[]
local function endpoints_entries(ir, st)
  local coverage = require("documentation.core.endpoint_coverage")
  local history = st.opts and st.opts.root and coverage.load(st.opts.root)

  local out = {}
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    for _, spec in ipairs(node.endpoints or {}) do
      local sends = history and coverage.matches(spec, history) or nil
      local badge = ""
      local detail = spec.handler or "(inline handler)"
      if history then
        if sends and #sends > 0 then
          detail = ("%s · sent %d time%s"):format(detail, #sends, #sends == 1 and "" or "s")
        else
          badge = "○ "
          detail = detail .. " · never sent"
        end
      end

      out[#out + 1] = {
        kind = "endpoint",
        id = id,
        source = node.source,
        line = spec.line,
        spec = spec,
        endpoint_sends = sends,
        label = ("%s%-7s %s"):format(badge, spec.method:upper(), spec.path),
        detail = detail,
      }
    end
  end

  if #out == 0 then
    return { { kind = "message", label = "(no call-based route registrations found)" } }
  end

  table.sort(out, function(a, b)
    if a.spec.path ~= b.spec.path then
      return a.spec.path < b.spec.path
    end
    return a.spec.method < b.spec.method
  end)
  return out
end

---Static x runtime join — ECOSYSTEM.md step 8. Every function `check.
---used_keys(ir)` and `runtime-analysis.telemetry`'s join together have an
---opinion about, one row per function, badge-prefixed by which of the four
---cells it falls in:
---
---  ✕  high-confidence dead — no static caller *and* never called
---  !  dead-function false positive — telemetry proves it alive; static
---     analysis alone would have flagged it (callback, dynamic dispatch, a
---     cross-repo consumer)
---  ○  cold path — a real static caller, but nothing exercised it
---  (blank)  normal, healthy — called, and statically reachable
---
---A function with no telemetry data at all (unmatched key, or telemetry
---never enabled here) is listed too, undecorated except a trailing "no
---telemetry data" — the Honest Limits section this join's own module is
---built around is explicit that absence of data must never render as if it
---were evidence.
---
---Like `trail`/`history`/`endpoints`, this spans the whole tree rather than
---one node's neighborhood: the badge is a cross-module question, not
---something a single centered node's subtree could answer on its own.
---@param ir Documentation.IR
---@param st table
---@return Documentation.Browse.Entry[]
local function telemetry_entries(ir, st)
  local telemetry_join = require("documentation.core.telemetry_join")
  local namespace = telemetry_join.namespace(st.opts)
  local data = namespace and telemetry_join.load(namespace)
  if not data then
    return {
      {
        kind = "message",
        label = namespace
            and ("(no telemetry data for %q — install/enable runtime-analysis.nvim, or :RATelemetry start there)"):format(
              namespace
            )
          or "(no telemetry namespace configured — set opts.title or opts.telemetry_namespace)",
      },
    }
  end

  local used = require("documentation.core.check").used_keys(ir)
  local by_key = telemetry_join.by_key(ir, data)

  local out = {}
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    for _, fn in ipairs(node.functions) do
      local key = id .. "#" .. fn.name
      local row = by_key[key]
      local has_static_caller = used[key] == true

      local badge, note
      if not row then
        badge, note = " ", "no telemetry data"
      elseif row.calls > 0 and not has_static_caller then
        badge, note = "!", "no static caller"
      elseif row.calls == 0 and has_static_caller then
        badge, note = "○", "0 calls"
      elseif row.calls == 0 and not has_static_caller then
        badge, note = "✕", "0 calls · no static caller"
      else
        badge, note = " ", nil
      end

      out[#out + 1] = {
        kind = "telemetry",
        id = id,
        fn = fn.name,
        source = node.source,
        line = fn.line,
        telemetry_row = row,
        label = ("%s %-46s %s"):format(
          badge,
          ("%s#%s"):format(node.module or id, fn.name),
          row and ("%d call%s"):format(row.calls, row.calls == 1 and "" or "s") or "·"
        ),
        detail = note,
      }
    end
  end

  table.sort(out, function(a, b)
    local ca = a.telemetry_row and a.telemetry_row.calls or -1
    local cb = b.telemetry_row and b.telemetry_row.calls or -1
    if ca ~= cb then
      return ca > cb
    end
    return a.label < b.label
  end)

  if #out == 0 then
    return { { kind = "message", label = "(no functions in this tree)" } }
  end
  return out
end

---Diff loaded-vs-declared with `runtime-analysis.nvim`. One row per discrepancy `documentation.core.loaded_diff` finds:
---`✕` a declared, exported function `package.loaded` does not have right
---now (dead file, or genuinely lazy — this session simply never required
---it); `!` the reverse, a function-valued key present on the module table
---with no matching declaration (generated, wrapped with an extra key, a
---typo'd export). Like `telemetry`/`endpoints`, spans the whole tree
---rather than one node's neighborhood.
---@param ir Documentation.IR
---@param _st table Unused — the join reads `package.loaded` directly, not anything centered on `st.id`.
---@return Documentation.Browse.Entry[]
local function loaded_entries(ir, _st)
  local loaded_diff = require("documentation.core.loaded_diff")
  local rows = loaded_diff.rows(ir)
  if not rows then
    return {
      {
        kind = "message",
        label = "(no data — install/enable runtime-analysis.nvim to diff loaded-vs-declared)",
      },
    }
  end
  if #rows == 0 then
    return {
      {
        kind = "message",
        label = "(no discrepancies — everything declared is loaded, and vice versa)",
      },
    }
  end

  local out = {}
  for _, row in ipairs(rows) do
    local node = ir.nodes[row.id]
    local mod = (node and node.module) or row.id
    if row.kind == "declared_only" then
      out[#out + 1] = {
        kind = "loaded_diff",
        id = row.id,
        fn = row.declared_name,
        source = node and node.source,
        line = row.line,
        loaded_diff_row = row,
        label = ("✕ %s#%s"):format(mod, row.name),
        detail = "declared, not loaded in this session",
      }
    else
      out[#out + 1] = {
        kind = "loaded_diff",
        id = row.id,
        source = node and node.source,
        loaded_diff_row = row,
        label = ("! %s#%s"):format(mod, row.name),
        detail = "loaded, not declared anywhere in the source",
      }
    end
  end
  return out
end

---Build the list entries for the current state.
---@param ir Documentation.IR
---@param st table
---@return Documentation.Browse.Entry[]
function M.entries(ir, st)
  if st.mode == "deps" then
    return deps_entries(ir, st)
  elseif st.mode == "calls" then
    return calls_entries(ir, st)
  elseif st.mode == "types" then
    return types_entries(ir, st)
  elseif st.mode == "history" then
    return history_entries(ir, st)
  elseif st.mode == "trail" then
    return trail_entries(ir, st)
  elseif st.mode == "endpoints" then
    return endpoints_entries(ir, st)
  elseif st.mode == "telemetry" then
    return telemetry_entries(ir, st)
  elseif st.mode == "loaded" then
    return loaded_entries(ir, st)
  end
  return structure_entries(ir, st)
end

---Rendered list lines. Kept separate from `entries` so the entries stay
---navigable data and only this step is about presentation.
---@param entries Documentation.Browse.Entry[]
---@param width integer
---@return string[]
function M.list_lines(entries, width)
  local lines = {}
  for i, e in ipairs(entries) do
    lines[i] = truncate(e.label, math.max(8, width - 1))
  end
  return lines
end

-- ── Detail pane ─────────────────────────────────────────────────────────────

---@param node Documentation.Node
---@param ir Documentation.IR
---@return string[]
local function node_detail(node, ir)
  local out = { node.module or node.name, "" }

  if node.summary and node.summary ~= "" then
    out[#out + 1] = node.summary
    out[#out + 1] = ""
  end

  out[#out + 1] = ("kind    %s"):format(node.kind)
  out[#out + 1] = ("path    %s"):format(node.path or node.id)
  if node.export then
    out[#out + 1] = ("export  %s"):format(node.export)
  end

  local s = node.stats
  if s then
    out[#out + 1] = ""
    out[#out + 1] = ("%d modules · %d namespaces · %d lua · %d md"):format(
      s.modules or 0,
      s.namespaces or 0,
      s.files_lua or 0,
      s.files_md or 0
    )
    out[#out + 1] = ("%d lines · %d functions · %d symbols · %d types"):format(
      s.lines or 0,
      s.functions or 0,
      s.symbols or 0,
      s.types or 0
    )
  end

  out[#out + 1] = ""
  out[#out + 1] = ("requires %d · required by %d · external %d"):format(
    #(node.requires or {}),
    #(node.required_by or {}),
    #(node.requires_external or {})
  )

  -- Blast radius. Stated even at zero, because "nothing depends on this" is
  -- itself the answer to "is this safe to change".
  local hull = require("documentation.core.deps").impact(ir, node.id)
  out[#out + 1] = ("impact   %d module%s would be affected  (gI for the list)"):format(
    #hull,
    #hull == 1 and "" or "s"
  )

  if node.body and node.body ~= "" then
    out[#out + 1] = ""
    for _, l in ipairs(vim.split(node.body, "\n", { plain = true })) do
      out[#out + 1] = l
    end
  end

  local syms = node.symbols or {}
  if #syms > 0 then
    out[#out + 1] = ""
    out[#out + 1] = ("Symbols (%d)"):format(#syms)
    for _, sym in ipairs(syms) do
      out[#out + 1] = ("  %-22s %s  %s"):format(sym.name, sym.kind, sym.detail or "")
    end
  end

  return out
end

---@param node Documentation.Node
---@param fn_name string
---@param ir Documentation.IR
---@param node_id string
---@return string[]
local function function_detail(node, fn_name, ir, node_id)
  local fn
  for _, f in ipairs((node and node.functions) or {}) do
    if f.name == fn_name then
      fn = f
      break
    end
  end

  if not fn then
    -- A call edge can point at a function whose own module was not scanned
    -- with the same detail (or at all). Say so instead of rendering blanks.
    return {
      fn_name or "?",
      "",
      ("in %s"):format((node and (node.module or node.name)) or node_id or "?"),
      "",
      "(no declaration detail for this function in the map)",
    }
  end

  local out = { fn.signature or fn.name, "" }
  if node then
    out[#out + 1] = ("in %s"):format(node.module or node.name)
    out[#out + 1] = ""
  end
  if fn.deprecated then
    out[#out + 1] = ("DEPRECATED  %s"):format(fn.deprecated)
    out[#out + 1] = ""
  end
  if fn.summary and fn.summary ~= "" then
    out[#out + 1] = fn.summary
    out[#out + 1] = ""
  end

  local flags = {}
  if fn.async then
    flags[#flags + 1] = "async"
  end
  if fn.nodiscard then
    flags[#flags + 1] = "nodiscard"
  end
  if fn.internal then
    flags[#flags + 1] = "internal"
  end
  if #(fn.generic or {}) > 0 then
    flags[#flags + 1] = "generic<" .. table.concat(fn.generic, ", ") .. ">"
  end
  if #flags > 0 then
    out[#out + 1] = table.concat(flags, " · ")
    out[#out + 1] = ""
  end

  for _, p in ipairs(fn.params or {}) do
    out[#out + 1] = ("@param  %s%s %s  %s"):format(
      p.name,
      p.optional and "?" or "",
      p.type or "",
      p.desc or ""
    )
  end
  for _, r in ipairs(fn.returns or {}) do
    out[#out + 1] = ("@return %s %s  %s"):format(r.type or "", r.name or "", r.desc or "")
  end

  -- Callers/callees are the reason to be in this pane at all, so they get a
  -- line even when both are zero.
  local key = ("%s#%s"):format(node_id, fn_name)
  local callers, callees = 0, 0
  for _, e in ipairs(ir.edges or {}) do
    if e.kind == "call" then
      if e.to == node_id and e.to_fn == fn_name then
        callers = callers + 1
      elseif e.from == node_id and e.from_fn == fn_name then
        callees = callees + 1
      end
    end
  end
  out[#out + 1] = ""
  out[#out + 1] = ("%d callers · %d callees      (3 to browse them)"):format(callers, callees)
  out[#out + 1] = ("key  %s"):format(key)

  if fn.example then
    out[#out + 1] = ""
    out[#out + 1] = "Example"
    for _, l in ipairs(vim.split(fn.example, "\n", { plain = true })) do
      out[#out + 1] = "  " .. l
    end
  end

  return out
end

---@param node Documentation.Node
---@param type_name string
---@return string[]
local function type_detail(node, type_name)
  for _, t in ipairs((node and node.types_detail) or {}) do
    if t.name == type_name then
      local out = { t.name, "", ("%s in %s"):format(t.kind, t.file or "?"), "" }
      if t.desc and t.desc ~= "" then
        out[#out + 1] = t.desc
        out[#out + 1] = ""
      end
      for _, f in ipairs(t.fields or {}) do
        out[#out + 1] = ("  %-20s %s  %s"):format(f.name, f.view or "", f.desc or "")
      end
      return out
    end
  end
  return { type_name or "?", "", "(not found in this node's types)" }
end

-- ── History detail ──────────────────────────────────────────────────────────

---The degradation note for an analysis, or nothing when it was exact.
---
---Two different states, kept apart on purpose: a revision older than the map
---has no artifact to resolve against at all, while one older than `line_end`
---has spans that had to be guessed. Merging them into "approximate" would
---tell the reader less than either.
---@param st table
---@return string[]
local function history_caveat(st)
  if st.impact_has_map == false then
    return {
      "⚠ This revision predates the committed map, so nothing could be",
      "  attributed to functions — only the changed files are known.",
      "",
    }
  end
  if st.impact and st.impact.approximate then
    return {
      "⚠ Function spans were approximated: the map at this revision predates",
      "  `line_end`, so a function's extent was taken as up to the next one.",
      "  Attribution errs toward over-reaching into the gaps between them.",
      "",
    }
  end
  return {}
end

---@param c table|nil A `{ sha, short, author, date, subject, body }` record.
---@return string[]
local function commit_detail(c)
  if not c then
    return { "(no commit)" }
  end
  local out = { c.subject or "", "" }
  out[#out + 1] = ("commit  %s"):format(c.sha or "?")
  out[#out + 1] = ("author  %s"):format(c.author or "?")
  out[#out + 1] = ("date    %s"):format(c.date or "?")
  out[#out + 1] = ""
  if c.body and c.body ~= "" then
    for _, l in ipairs(vim.split(c.body, "\n", { plain = true })) do
      out[#out + 1] = l
    end
    out[#out + 1] = ""
  end
  out[#out + 1] = "<CR> analyse this commit · gD show its diff"
  return out
end

---Shown when History mode has no selectable row: before the commit list has
---loaded, and for a commit whose diff touched no scanned function.
---@param st table
---@return string[]
local function history_fallback_detail(st)
  if not st.sha then
    return { "History", "", "Commits, newest first.", "", "<CR> opens one." }
  end
  local out = { st.sha:sub(1, 10), "" }
  vim.list_extend(out, history_caveat(st))
  local im = st.impact
  if im then
    out[#out + 1] = ("%d file(s) changed."):format(#(im.files or {}))
    out[#out + 1] = ""
    out[#out + 1] = "No scanned function contains any of the changed lines."
    out[#out + 1] = "(module-level code, docs, or paths outside the scanned tree)"
    out[#out + 1] = ""
    out[#out + 1] = "gD shows the diff · - goes back to the commit list"
  end
  return out
end

---A function touched by the opened commit: who calls it, and how far the
---change radiates.
---@param ir Documentation.IR
---@param st table
---@param entry Documentation.Browse.Entry
---@return string[]
local function history_function_detail(ir, st, entry)
  local node = ir.nodes[entry.id]
  local out = { entry.fn or "?", "" }
  vim.list_extend(out, history_caveat(st))

  out[#out + 1] = ("in      %s"):format(node and (node.module or node.path) or entry.id)
  if entry.line then
    out[#out + 1] = ("line    %d"):format(entry.line)
  end
  out[#out + 1] = ""

  local callers = entry.callers or {}
  if #callers == 0 then
    out[#out + 1] = "No resolved caller in the tree."
    out[#out + 1] = "(a public entry point, or reached by dynamic dispatch)"
  else
    out[#out + 1] = ("Called by %d:"):format(#callers)
    for _, c in ipairs(callers) do
      local cn = ir.nodes[c.node]
      out[#out + 1] = ("  ← %-26s %s"):format(
        c.fn or "?",
        cn and (cn.module or cn.path) or c.node
      )
    end
  end

  local im = st.impact
  if im then
    out[#out + 1] = ""
    out[#out + 1] = ("%d module(s) hold a call site · %d impacted transitively"):format(
      #(im.calling_modules or {}),
      #(im.impacted_modules or {})
    )
  end
  out[#out + 1] = ""
  out[#out + 1] = "<CR> callers · gd source · gq list to quickfix · gD diff"
  return out
end

---Detail lines for the selected entry.
---@param ir Documentation.IR
---@param st table
---@param entry Documentation.Browse.Entry|nil
---@return string[]
function M.detail(ir, st, entry)
  if entry and entry.kind == "commit" then
    return commit_detail(entry.commit)
  end

  -- A touched function in History mode is described by the *commit*, not by
  -- the current tree: its callers come from the analysis, and saying "3
  -- callers" here while the Calls mode says something else would be a
  -- contradiction the reader cannot resolve.
  if st.mode == "history" and st.sha and entry and entry.kind == "function" then
    return history_function_detail(ir, st, entry)
  end

  if not entry or entry.kind == "message" then
    -- In History mode the fallback subject is the commit, not the centered
    -- node — the node has nothing to do with what is on screen there.
    if st.mode == "history" then
      return history_fallback_detail(st)
    end
    -- Fall back to the centered node so the pane is never blank — an empty
    -- list still has a subject.
    local node = ir.nodes[st.id]
    return node and node_detail(node, ir) or { "(nothing to show)" }
  end

  if entry.kind == "external" then
    return {
      (entry.label or ""):gsub("^%s*○%s*", ""),
      "",
      "An external require: this module path resolves to nothing",
      "inside the scanned tree, so the map has no node for it.",
    }
  end

  if entry.kind == "function" then
    return function_detail(ir.nodes[entry.id], entry.fn, ir, entry.id)
  end

  if entry.kind == "type" then
    return type_detail(ir.nodes[entry.id], entry.type_name)
  end

  if entry.kind == "endpoint" then
    local spec = entry.spec
    local out = {
      ("%s %s"):format(spec.method:upper(), spec.path),
      "",
    }
    if spec.framework then
      out[#out + 1] = "Framework: " .. spec.framework
    end
    out[#out + 1] = "Handler: " .. (spec.handler or "(inline — no name to show)")
    out[#out + 1] = spec.documented and "Documented" or "Not documented"

    -- runtime-analysis.nvim — `endpoint_sends` is
    -- `nil` when no history data was available at all (plugin absent, or
    -- nothing recorded for this project yet), an empty list when history
    -- exists but never matched this route, and a real list otherwise. The
    -- three render differently on purpose: only the middle case is the
    -- "this looks untested" finding.
    if entry.endpoint_sends then
      out[#out + 1] = ""
      if #entry.endpoint_sends == 0 then
        out[#out + 1] = "Never sent — no matching request in this project's history."
      else
        out[#out + 1] = ("Sent %d time%s (newest first):"):format(
          #entry.endpoint_sends,
          #entry.endpoint_sends == 1 and "" or "s"
        )
        for i, e in ipairs(entry.endpoint_sends) do
          if i > 5 then
            out[#out + 1] = ("  … and %d more"):format(#entry.endpoint_sends - 5)
            break
          end
          local outcome = e.status and tostring(e.status) or (e.note or "?")
          out[#out + 1] = ("  %s  %s"):format(os.date("%Y-%m-%d %H:%M", e.at), outcome)
        end
      end
    end

    out[#out + 1] = ""
    out[#out + 1] = "gd source · gs send a request (needs runtime-analysis.nvim)"
    return out
  end

  if entry.kind == "telemetry" then
    local row = entry.telemetry_row
    local out = {
      ("%s#%s"):format(ir.nodes[entry.id] and ir.nodes[entry.id].module or entry.id, entry.fn),
      "",
    }
    if not row then
      out[#out + 1] = "No telemetry data for this function."
      out[#out + 1] = "Neither a matched telemetry key nor a live call count —"
      out[#out + 1] = "not evidence of anything, just nothing recorded yet."
    else
      out[#out + 1] = ("Calls: %d"):format(row.calls)
      out[#out + 1] = "Static caller: " .. (row.has_static_caller and "yes" or "no")
      out[#out + 1] = ""
      if row.calls > 0 and not row.has_static_caller then
        out[#out + 1] = "dead-function false positive — telemetry proves this is alive"
        out[#out + 1] = "(a callback, dynamic dispatch, or a cross-repo consumer)."
      elseif row.calls == 0 and row.has_static_caller then
        out[#out + 1] = "Cold path: reachable, but nothing exercised it recently."
      elseif row.calls == 0 and not row.has_static_caller then
        out[#out + 1] = "High-confidence dead: no static caller and never called."
        out[#out + 1] = "A prompt to look, not a delete list."
      end
    end
    out[#out + 1] = ""
    out[#out + 1] = "gd source · gq quickfix"
    return out
  end

  if entry.kind == "loaded_diff" then
    local row = entry.loaded_diff_row
    local node = ir.nodes[entry.id]
    local mod = (node and node.module) or entry.id
    local out = { ("%s#%s"):format(mod, row.name), "" }
    if row.kind == "declared_only" then
      out[#out + 1] = ("Declared as `%s`, not on package.loaded[%q] right now."):format(
        row.declared_name,
        mod
      )
      out[#out + 1] = ""
      out[#out + 1] = "Either this file was never required this session, or it is"
      out[#out + 1] = "genuinely lazy-loaded and simply hasn't fired yet — package.loaded"
      out[#out + 1] = "reflects THIS process, not every process that ever ran this tree."
    else
      out[#out + 1] = ("A function-valued key on package.loaded[%q], no matching"):format(mod)
      out[#out + 1] = "declaration anywhere in the source."
      out[#out + 1] = ""
      out[#out + 1] = "Generated at runtime, wrapped with an extra key (see :RA provenance"
      out[#out + 1] = "if runtime-analysis.nvim is installed), or a typo'd export name."
    end
    out[#out + 1] = ""
    out[#out + 1] = row.kind == "declared_only" and "gd source · gq quickfix"
      or "gq quickfix (no static declaration to jump to)"
    return out
  end

  local node = ir.nodes[entry.id]
  return node and node_detail(node, ir) or { "(no such node)" }
end

-- ── Status line ─────────────────────────────────────────────────────────────

---Breadcrumb from the root down to `id`.
---@param ir Documentation.IR
---@param id string
---@return string
function M.breadcrumb(ir, id)
  local parts = {}
  local cur = id
  local guard = 0
  while cur and guard < 64 do
    local node = ir.nodes[cur]
    if not node then
      break
    end
    table.insert(parts, 1, node.name)
    cur = node.parent
    guard = guard + 1
  end
  return table.concat(parts, " ▸ ")
end

---What every status line ends with, whichever of the three shapes below it
---took.
---
---An active filter has to appear in all of them: it is the one piece of view
---state that *removes rows*, so a list shortened by a filter and a list that
---is genuinely that short are indistinguishable without it. The hidden count
---is half the point — it says the rest is one keystroke away rather than
---gone.
---@param st table
---@return string
local function status_tail(st)
  local out = ""
  local q = filter.describe(st.filter)
  if q then
    out = out .. ("   ⌕ %s (%d hidden)"):format(q, st.filter_hidden or 0)
  end
  if st.hint then
    out = out .. "   ⚠ " .. st.hint
  end
  return out
end

---The one-line status bar: what is being shown, along which axes, and what
---is currently being hidden from it.
---@param ir Documentation.IR
---@param st table
---@return string
function M.status(ir, st)
  -- History is not about the centered node, so the breadcrumb would be
  -- pointing at something unrelated to everything on screen.
  if st.mode == "history" then
    local subject = st.sha and (st.sha:sub(1, 8)) or ("%d commits"):format(#(st.commits or {}))
    local axes = { "history" }
    if st.impact and st.impact.approximate then
      axes[#axes + 1] = "approx"
    end
    if st.impact_has_map == false then
      axes[#axes + 1] = "no map at this rev"
    end
    return ("%s   [%s]"):format(subject, table.concat(axes, " ")) .. status_tail(st)
  end

  local npins = #(st.pins or {})

  -- Trail, like History, is not about the centered node: the list spans
  -- whatever was pinned, so a breadcrumb would point at something unrelated
  -- to everything on screen.
  if st.mode == "trail" then
    return ("%d pinned   [trail]"):format(npins) .. status_tail(st)
  end

  -- Endpoints, like Trail and History, spans the whole tree rather than one
  -- node's neighborhood — a breadcrumb here would point at whatever happens
  -- to be centered, unrelated to the routes actually on screen.
  if st.mode == "endpoints" then
    return ("%d route(s)   [endpoints]"):format(#(st.entries or {})) .. status_tail(st)
  end

  -- Telemetry, like Endpoints, spans the whole tree — a breadcrumb here
  -- would point at whatever happens to be centered, unrelated to the join
  -- actually on screen.
  if st.mode == "telemetry" then
    local n, with_data = 0, 0
    for _, e in ipairs(st.entries or {}) do
      if e.kind == "telemetry" then
        n = n + 1
        if e.telemetry_row then
          with_data = with_data + 1
        end
      end
    end
    return ("%d function(s), %d with telemetry data   [telemetry]"):format(n, with_data)
      .. status_tail(st)
  end

  -- Loaded-vs-declared, like Telemetry/Endpoints, spans the whole tree.
  if st.mode == "loaded" then
    local declared_only, loaded_only = 0, 0
    for _, e in ipairs(st.entries or {}) do
      if e.kind == "loaded_diff" then
        if e.loaded_diff_row.kind == "declared_only" then
          declared_only = declared_only + 1
        else
          loaded_only = loaded_only + 1
        end
      end
    end
    return ("%d declared-not-loaded, %d loaded-not-declared   [loaded]"):format(
      declared_only,
      loaded_only
    ) .. status_tail(st)
  end

  local bits = { M.breadcrumb(ir, st.id) }
  if st.fn then
    bits[#bits + 1] = "ƒ " .. st.fn
  end

  local axes = { st.mode }
  if st.mode == "deps" or st.mode == "calls" then
    axes[#axes + 1] = st.dir == "in" and "←in" or "out→"
  end
  if st.mode == "deps" then
    axes[#axes + 1] = "depth " .. tostring(st.depth)
  end
  -- Shown everywhere, but only once there is something to show: a trail is
  -- worth nothing if it is invisible from the mode you pinned things in, and
  -- a permanent "0 pinned" would be noise on every other line of every
  -- session that never uses the feature.
  if npins > 0 then
    axes[#axes + 1] = ("📌%d"):format(npins)
  end

  return ("%s   [%s]"):format(table.concat(bits, "  "), table.concat(axes, " ")) .. status_tail(st)
end

return M
