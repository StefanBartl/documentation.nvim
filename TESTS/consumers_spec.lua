---@diagnostic disable: missing-fields
-- The fixtures below carry only the fields the unit under test reads; a full
-- IR, node, finding or entry per case would be noise, not coverage.
-- TESTS/consumers_spec.lua — core/consumers.lua
--
-- The reverse index: given a library and the committed maps of projects that
-- depend on it, which of its modules does anyone require.
--
-- The distinction the cases below defend is the whole feature. A two-way
-- "used/unused" answer said 141 of lib.nvim's 248 modules were unused; the
-- real number is 33, and the 108 in between are modules the library requires
-- itself. Every one of those would have been reported as dead.

return function(H)
  local eq = H.eq
  local consumers = require("documentation.core.consumers")

  ---A library IR, rehydrated-shaped: nodes keyed by id, walked via `order`.
  ---@param nodes table[] Each `{ id, module, requires? }`.
  ---@return Documentation.IR
  local function lib(nodes)
    local ir = { nodes = {}, order = {}, meta = {}, edges = {} }
    for _, n in ipairs(nodes) do
      ir.nodes[n.id] = {
        id = n.id,
        module = n.module,
        kind = n.kind or "module",
        requires = n.requires or {},
      }
      ir.order[#ir.order + 1] = n.id
    end
    return ir
  end

  ---A consumer map in the same rehydrated shape `artifact.decode` returns.
  ---@param name string
  ---@param externals string[]
  local function consumer(name, externals)
    return {
      name = name,
      ir = {
        order = { "root" },
        nodes = { root = { id = "root", requires_external = externals } },
      },
    }
  end

  local library = lib({
    { id = "lua/l/used", module = "l.used" },
    { id = "lua/l/inner", module = "l.inner" },
    { id = "lua/l/nobody", module = "l.nobody" },
    -- Requires `l.inner`, which is what makes it internal rather than dead.
    { id = "lua/l/init", module = "l", requires = { "lua/l/inner" } },
  })

  local index = consumers.index(library, {
    consumer("alpha.nvim", { "l.used", "l.notmine" }),
    consumer("beta.nvim", { "l.used" }),
  })

  eq(index.maps, 2, "consumers: reports how many maps it read")

  local by_module = {}
  for _, e in ipairs(index.entries) do
    by_module[e.module] = e
  end

  eq(by_module["l.used"].kind, "external", "consumers: a module two projects require is external")
  eq(
    table.concat(by_module["l.used"].consumers, ","),
    "alpha.nvim,beta.nvim",
    "consumers: ... naming them, sorted"
  )

  -- The distinction the naive version gets wrong, and the reason this spec
  -- exists at all.
  eq(
    by_module["l.inner"].kind,
    "internal",
    "consumers: a module only the library itself requires is internal, not dead"
  )
  eq(
    by_module["l.nobody"].kind,
    "unreferenced",
    "consumers: a module nobody requires anywhere is unreferenced"
  )

  eq(index.counts.external, 1, "consumers: counts per class, external")
  eq(index.counts.internal, 1, "consumers: ... internal")
  eq(index.counts.unreferenced, 2, "consumers: ... unreferenced (l.nobody and the root itself)")

  -- A module path the library does not have is simply not its business: a
  -- consumer requiring half a dozen other libraries must not inflate
  -- anything here.
  eq(
    by_module["l.notmine"],
    nil,
    "consumers: a foreign external is ignored, not invented as a node"
  )

  -- One consumer requiring the same module from many of its own files is one
  -- consumer. Counting files would make the biggest project look like the
  -- broadest adoption.
  local twice = consumers.index(library, {
    {
      name = "alpha.nvim",
      ir = {
        order = { "a", "b" },
        nodes = {
          a = { id = "a", requires_external = { "l.used" } },
          b = { id = "b", requires_external = { "l.used" } },
        },
      },
    },
  })
  local used
  for _, e in ipairs(twice.entries) do
    if e.module == "l.used" then
      used = e
    end
  end
  eq(#used.consumers, 1, "consumers: a consumer is counted once however often it requires")

  -- The caveat has to be in the output, not only in the module header: the
  -- number is a floor, and a reader acting on it deserves to know that.
  local lines = table.concat(consumers.render(index, "Consumers of l"), "\n")
  eq(
    lines:find("does not mean dead", 1, true) ~= nil,
    true,
    "consumers: the report says what unreferenced does not mean"
  )
end
