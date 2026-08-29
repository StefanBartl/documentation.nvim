---@module 'documentation.bindings.usrcmds.endpoints'
--- `:DocMap endpoints` — every recognized call-based route registration in
--- the tree, into the quickfix list, sorted by path.
---
--- Instant, unlike `impact`/`churn`: the routes already sit on `ir.nodes[*]
--- .endpoints`, extracted during the scan that produced the live handle — no
--- git, no second pass, nothing to wait on. Mirrors
--- `bindings/usrcmds/plugins.lua` exactly, the same "already on the node,
--- just list it" shape.
---
--- See `core/endpoints.lua`'s header for what is and is not recognized —
--- call-based routing (Express/Fastify/Koa-shaped) only; file-based routing
--- (Next.js/SvelteKit/Nuxt/Remix) belongs in a Hierarchy view instead, per
--- `docs/ECOSYSTEM.md` §3.1, and is not what this lists.

local list = require("lib.nvim.ui.list")

local M = {}

---@param ctx Documentation.Bindings.Ctx
function M.run(ctx)
  local ir = ctx.handle.ir()

  ---@type { spec: Documentation.EndpointSpec, node: Documentation.Node }[]
  local all = {}
  ---@type table<string, true>
  local files = {}
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    for _, spec in ipairs(node.endpoints or {}) do
      all[#all + 1] = { spec = spec, node = node }
      files[node.id] = true
    end
  end
  local nfiles = 0
  for _ in pairs(files) do
    nfiles = nfiles + 1
  end

  if #all == 0 then
    ctx.notify.info(
      "No call-based route registrations found — see :help documentation-endpoints "
        .. "for what is recognized."
    )
    return
  end

  table.sort(all, function(a, b)
    if a.spec.path ~= b.spec.path then
      return a.spec.path < b.spec.path
    end
    return a.spec.method < b.spec.method
  end)

  local items = {}
  local ndoc = 0
  for i, entry in ipairs(all) do
    local spec, node = entry.spec, entry.node
    if spec.documented then
      ndoc = ndoc + 1
    end
    items[i] = {
      filename = ctx.cfg.root .. "/" .. (node.source or node.path),
      lnum = spec.line,
      text = ("%-7s %s  ·  %s%s"):format(
        spec.method:upper(),
        spec.path,
        spec.handler or "(inline handler)",
        spec.framework and ("  ·  " .. spec.framework) or ""
      ),
    }
  end

  list.qf(items, "docmap endpoints")

  ctx.notify.info(("%d route(s) across %d file(s)  ·  %d documented"):format(#all, nfiles, ndoc))
end

return M
