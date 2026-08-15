---@module 'documentation.bindings.usrcmds.bindings'
--- `:DocMap bindings` — every recognized keymap, user command and autocmd in
--- the tree, into the quickfix list.
---
--- Instant, like `plugins` and unlike `impact`/`churn`: the registrations
--- already sit on `ir.nodes[*].bindings`, extracted during the scan that
--- produced the live handle — no git, no second pass, nothing to wait on.
---
--- Exists for the same shape of tree `:DocMap plugins` does: a Neovim
--- *config*, where a `lua/bindings/mappings/*.lua` full of `map("n", …)`
--- has no functions and no symbols and therefore says nothing on a map,
--- even though "what do I have bound, and where" is one of the questions a
--- config is most often opened to answer.
---
--- **Collisions are the reason this sorts by left-hand side.** The same
--- `<leader>x` bound in two files is a real and genuinely hard-to-find
--- config bug — whichever module loads last silently wins, exactly like
--- `:DocMap plugins`'s duplicate-repo case — and sorting by lhs puts the
--- two rows adjacent instead of leaving them a screen apart. Counted per
--- distinct (mode, lhs) pair rather than per extra occurrence.
---
--- See `core/bindings.lua` for what is recognized: the `vim.*` APIs always,
--- a config's own wrapper (`map`, `usercmd.create`, …) only once declared
--- in `opts.bindings.wrappers`. An empty result for a file that visibly
--- binds keys almost always means the wrapper is not declared.

local M = {}

---What a row is keyed by for collision purposes. A keymap collides per
---(mode, lhs) — the same lhs in normal and visual mode is two different
---bindings, not a clash — while a user command's name is global, and an
---autocmd does not collide at all (many handlers per event is the normal,
---intended shape, not a mistake).
---@param spec Documentation.BindingSpec
---@return string?
local function collision_key(spec)
  if spec.kind == "keymap" and spec.lhs then
    -- Buffer-local bindings are scoped to one buffer and legitimately
    -- shadow a global one; treating that as a collision would report the
    -- normal ftplugin idiom as a bug.
    if spec.buffer then
      return nil
    end
    local modes = #spec.modes > 0 and table.concat(spec.modes, ",") or "?"
    return ("keymap\0%s\0%s"):format(modes, spec.lhs)
  end
  if spec.kind == "usercmd" and spec.name then
    return ("usercmd\0%s"):format(spec.name)
  end
  return nil
end

---The identifying text of a binding, whatever kind it is.
---@param spec Documentation.BindingSpec
---@return string
local function label(spec)
  if spec.kind == "keymap" then
    local modes = #spec.modes > 0 and table.concat(spec.modes, "/") or "?"
    return ("[%s] %s"):format(modes, spec.lhs or "?")
  end
  if spec.kind == "usercmd" then
    return ":" .. (spec.name or "?")
  end
  return table.concat(spec.events, ",")
end

---Sort key: kind first (all keymaps together, then commands, then
---autocmds), then the identifying text, so colliding rows land adjacent.
---@param spec Documentation.BindingSpec
---@return string
local function sort_key(spec)
  local kind_rank = spec.kind == "keymap" and "1" or (spec.kind == "usercmd" and "2" or "3")
  return kind_rank .. "\0" .. (spec.lhs or spec.name or spec.events[1] or "")
end

---@param ctx Documentation.Bindings.Ctx
function M.run(ctx)
  local ir = ctx.handle.ir()

  ---@type { spec: Documentation.BindingSpec, node: Documentation.Node }[]
  local all = {}
  ---@type table<string, integer>
  local seen = {}
  ---@type table<string, true>
  local files = {}
  local counts = { keymap = 0, usercmd = 0, autocmd = 0 }

  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    for _, spec in ipairs(node.bindings or {}) do
      all[#all + 1] = { spec = spec, node = node }
      counts[spec.kind] = (counts[spec.kind] or 0) + 1
      files[node.id] = true
      local key = collision_key(spec)
      if key then
        seen[key] = (seen[key] or 0) + 1
      end
    end
  end

  local nfiles = 0
  for _ in pairs(files) do
    nfiles = nfiles + 1
  end

  if #all == 0 then
    ctx.notify.info(
      "No keymaps, user commands or autocmds found. The vim.* APIs are always "
        .. "recognized; a config binding through its own helper (map(...), "
        .. "usercmd.create(...)) must declare it in opts.bindings.wrappers — "
        .. "see :help documentation-bindings."
    )
    return
  end

  table.sort(all, function(a, b)
    local ka, kb = sort_key(a.spec), sort_key(b.spec)
    if ka ~= kb then
      return ka < kb
    end
    return a.node.id < b.node.id
  end)

  local items = {}
  ---@type table<string, true>
  local counted_dup = {}
  local ndup = 0
  for i, entry in ipairs(all) do
    local spec, node = entry.spec, entry.node
    local key = collision_key(spec)
    local dup = key ~= nil and seen[key] > 1
    if dup and not counted_dup[key] then
      counted_dup[key] = true
      ndup = ndup + 1
    end
    items[i] = {
      filename = ctx.cfg.root .. "/" .. (node.source or node.path),
      lnum = spec.line,
      text = ("%s%s%s  ·  %s"):format(
        label(spec),
        dup and "  [bound more than once]" or "",
        spec.buffer and "  [buffer-local]" or "",
        spec.desc or ("via " .. spec.callee)
      ),
    }
  end

  vim.fn.setqflist({}, " ", {
    title = "docmap bindings",
    items = items,
  })
  vim.cmd("copen")

  ctx.notify.info(
    ("%d keymap(s), %d command(s), %d autocmd(s) across %d file(s)%s"):format(
      counts.keymap,
      counts.usercmd,
      counts.autocmd,
      nfiles,
      ndup > 0 and ("  ·  %d bound more than once"):format(ndup) or ""
    )
  )
end

return M
