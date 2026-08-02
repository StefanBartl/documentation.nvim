---@module 'documentation.bindings.usrcmds.plugins'
--- `:DocMap plugins` — every recognized lazy.nvim spec entry in the tree,
--- into the quickfix list, sorted by repo.
---
--- Instant, unlike `impact`/`churn`: the specs already sit on `ir.nodes[*]
--- .plugins`, extracted during the scan that produced the live handle — no
--- git, no second pass, nothing to wait on.
---
--- Exists for the shape of tree this map was previously blind to: a Neovim
--- *config*, where most of `lua/plugins/*.lua` is `return { {...}, {...} }`
--- with no function in sight. See `core/plugins.lua`'s header for what is
--- and is not recognized.

local M = {}

---One line per trigger kind actually present, so a row reads at a glance
---rather than spelling out four empty arrays.
---@param spec Documentation.PluginSpec
---@return string
local function traits(spec)
  local bits = {}
  if spec.lazy == false then
    bits[#bits + 1] = "eager"
  end
  if #spec.event > 0 then
    bits[#bits + 1] = "event:" .. table.concat(spec.event, ",")
  end
  if #spec.cmd > 0 then
    bits[#bits + 1] = "cmd:" .. table.concat(spec.cmd, ",")
  end
  if #spec.keys > 0 then
    bits[#bits + 1] = "keys:" .. table.concat(spec.keys, ",")
  end
  if #spec.ft > 0 then
    bits[#bits + 1] = "ft:" .. table.concat(spec.ft, ",")
  end
  if spec.enabled == false then
    bits[#bits + 1] = "disabled"
  end
  if #bits == 0 then
    -- No trigger at all is `lazy = false` in effect (lazy.nvim loads it at
    -- startup), which is worth saying rather than leaving the row blank.
    bits[1] = "no trigger — loads at startup"
  end
  return table.concat(bits, "  ")
end

---@param ctx Documentation.Bindings.Ctx
function M.run(ctx)
  local ir = ctx.handle.ir()

  ---@type { spec: Documentation.PluginSpec, node: Documentation.Node }[]
  local all = {}
  ---@type table<string, integer>
  local seen = {}
  ---@type table<string, true>
  local files = {}
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    for _, spec in ipairs(node.plugins or {}) do
      all[#all + 1] = { spec = spec, node = node }
      seen[spec.repo] = (seen[spec.repo] or 0) + 1
      files[node.id] = true
    end
  end
  local nfiles = 0
  for _ in pairs(files) do
    nfiles = nfiles + 1
  end

  if #all == 0 then
    ctx.notify.info(
      "No lazy.nvim-shaped plugin specs found — see :help documentation-plugins "
        .. "for what is recognized."
    )
    return
  end

  table.sort(all, function(a, b)
    if a.spec.repo ~= b.spec.repo then
      return a.spec.repo < b.spec.repo
    end
    return a.node.id < b.node.id
  end)

  -- Same repo, more than one file — a real footgun in a split-file config:
  -- the last one lazy.nvim imports silently wins, and nothing else in this
  -- map would ever surface that. Counted once per repo, not once per extra
  -- occurrence.
  local items = {}
  ---@type table<string, true>
  local counted_dup = {}
  local ndup = 0
  for i, entry in ipairs(all) do
    local spec, node = entry.spec, entry.node
    local dup = seen[spec.repo] > 1
    if dup and not counted_dup[spec.repo] then
      counted_dup[spec.repo] = true
      ndup = ndup + 1
    end
    items[i] = {
      filename = ctx.cfg.root .. "/" .. (node.source or node.path),
      lnum = spec.line,
      text = ("%s%s  ·  %s"):format(
        spec.repo,
        dup and "  [declared more than once]" or "",
        traits(spec)
      ),
    }
  end

  vim.fn.setqflist({}, " ", {
    title = "docmap plugins",
    items = items,
  })
  vim.cmd("copen")

  ctx.notify.info(
    ("%d plugin spec(s) across %d file(s)%s"):format(
      #all,
      nfiles,
      ndup > 0 and ("  ·  %d repo(s) declared more than once"):format(ndup) or ""
    )
  )
end

return M
