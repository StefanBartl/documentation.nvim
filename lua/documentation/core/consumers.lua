---@module 'documentation.core.consumers'
--- Who uses this library, read out of its consumers' own committed maps.
---
--- `core/tagfiles.lua` already resolves one direction: a require in *this*
--- tree that lands in someone else's map. This is the other one — given a
--- library and a set of maps belonging to projects that depend on it, which
--- of its modules does anyone actually require, and which does nobody.
---
--- This was rated "needs a real multi-repo case first" and left there. The case exists: 33 `.nvim` repositories
--- beside this one, ~30 with a committed map, one shared `lib.nvim` they
--- consume 9–25 modules of apiece.
---
--- ## The join, and why it needs no shared table
---
--- A consumer's `requires_external` holds the module paths its own scan
--- could not resolve internally — which is exactly what a foreign library's
--- modules look like from inside it. The library's own map names those
--- modules in `node.module`. Both sides already speak module paths, so
--- neither has to be taught the other's vocabulary. Verified before this
--- module was written: 17 of 17 `lib.*` externals in `documentation.nvim`'s
--- map resolve against `lib.nvim`'s own.
---
--- ## Three answers, not two
---
--- "Used" and "unused" is the version that would be wrong, and measurably so:
--- the naive count said 141 of `lib.nvim`'s 248 modules were unused. The real
--- number is 33, and the 108 in between are what the naive count silently
--- folded in.
---
---   * **`external`** — at least one consumer map requires it (107).
---   * **`internal`** — no consumer does, but the library requires it itself
---     (108). Not dead by any definition, and the entire difference between
---     the naive answer and the real one.
---   * **`unreferenced`** — nobody, inside or out (33: 26 module nodes and 7
---     helper files). The only class worth looking at, and even then see the
---     caveat below.
---
--- A node with no module path never enters this index at all. A namespace —
--- a directory with no module file — cannot be required by name, so it is
--- neither used nor unused; counting it either way would be a category
--- error.
---
--- ## What `unreferenced` does not mean
---
--- **Not "dead".** It means "no consumer among the maps you supplied". A
--- library's consumers are open-ended: a project not in the set, a map not
--- regenerated since its last require was added, or a user who never
--- committed a map at all are all invisible here and all perfectly normal.
--- The report says so rather than implying a verdict it cannot support —
--- the same posture the Telemetry panel takes about absent data.

local M = {}

---@class Documentation.Consumers.Entry
---@field module string
---@field kind "external"|"internal"|"unreferenced"
---@field consumers string[] Names of the maps that require it, sorted. Empty for every kind but `external`.

---@class Documentation.Consumers.Index
---@field entries Documentation.Consumers.Entry[] Sorted by module path.
---@field counts table<string, integer> One tally per `kind`.
---@field maps integer How many consumer maps were actually read.

---Modules this library requires from itself, by module path.
---
---Read off `node.requires` (resolved node ids) rather than `requires_raw`,
---because a rehydrated artifact has the first and not the second — and this
---runs against committed maps, not live scans.
---@param ir Documentation.IR
---@return table<string, true>
local function internal_uses(ir)
  local by_id, used = {}, {}
  for _, id in ipairs(ir.order) do
    by_id[id] = ir.nodes[id]
  end
  for _, id in ipairs(ir.order) do
    for _, req in ipairs(ir.nodes[id].requires or {}) do
      local target = by_id[req]
      if target and target.module then
        used[target.module] = true
      end
    end
  end
  return used
end

---Every committed consumer map under `dir`, excluding `self_root`.
---
---Lifted out of the `:DocMap consumers` command so the check below and that
---command load the same way. Two loaders would be two answers to "which
---projects count as consumers", and the check would eventually disagree with
---the report a reader is looking at.
---
---Skipping `self_root` is not an optimisation: a library requires itself
---internally, and counting that as a consumer would make every
---internally-used module look externally adopted.
---@param dir string Directory holding sibling checkouts.
---@param self_root string This project's own root, forward-slashed.
---@return { name: string, ir: Documentation.IR }[] maps
---@return integer unreadable Maps found but not decodable — reported, never treated as "this project uses nothing".
function M.load(dir, self_root)
  local artifact = require("documentation.core.artifact")
  local read = require("lib.nvim.fs.read")
  local maps, unreadable = {}, 0
  if vim.fn.isdirectory(dir) == 0 then
    return maps, unreadable
  end
  for name, kind in vim.fs.dir(dir) do
    local candidate = dir .. "/" .. name
    if kind == "directory" and candidate ~= self_root then
      local content = read(candidate .. "/docs/map/module_map.json")
      if content then
        local decoded = artifact.decode(content)
        if decoded then
          maps[#maps + 1] = { name = name, ir = decoded }
        else
          unreadable = unreadable + 1
        end
      end
    end
  end
  return maps, unreadable
end

---The top-level namespaces this library owns, from its own module paths.
---
---Derived rather than configured: a library that calls its modules `lib.*`
---says so 248 times in its own map, and asking it to also declare the prefix
---would be a second source of truth for a fact already stated.
---@param ir Documentation.IR
---@return table<string, true>
function M.namespaces(ir)
  local roots = {}
  for _, id in ipairs(ir.order) do
    local module = ir.nodes[id].module
    if module then
      roots[module:match("^([^.]+)") or module] = true
    end
  end
  return roots
end

---Build the reverse index.
---
---@param ir Documentation.IR The library's own IR or rehydrated artifact.
---@param maps { name: string, ir: Documentation.IR }[] Consumer maps, each with a display name, **already rehydrated** — `core/artifact.lua`'s `decode` does that for you, and passing a raw decoded document instead silently matches nothing.
---@return Documentation.Consumers.Index
function M.index(ir, maps)
  local mods = {}
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.module then
      mods[node.module] = node
    end
  end

  local internal = internal_uses(ir)

  ---@type table<string, table<string, true>>
  local consumers = {}
  for _, map in ipairs(maps) do
    -- Walked through `order`, not `ipairs(nodes)`. A consumer map arrives via
    -- `artifact.decode`, which **already rehydrates** — `nodes` is keyed by
    -- node id there, not an array, so `ipairs` over it yields nothing and
    -- every count comes back zero. Found exactly that way: 29 maps read, 0
    -- modules matched, against a hand count that said 107.
    for _, id in ipairs(map.ir.order or {}) do
      local node = map.ir.nodes[id]
      for _, ext in ipairs((node and node.requires_external) or {}) do
        if mods[ext] then
          consumers[ext] = consumers[ext] or {}
          -- A set: one consumer requiring the same module from twelve of its
          -- own files is one consumer, and counting files here would make the
          -- biggest project look like the broadest adoption.
          consumers[ext][map.name] = true
        end
      end
    end
  end

  local entries, counts = {}, { external = 0, internal = 0, unreferenced = 0 }
  local names = {}
  for module in pairs(mods) do
    names[#names + 1] = module
  end
  table.sort(names)

  for _, module in ipairs(names) do
    local who = {}
    for name in pairs(consumers[module] or {}) do
      who[#who + 1] = name
    end
    table.sort(who)

    local kind
    if #who > 0 then
      kind = "external"
    elseif internal[module] then
      kind = "internal"
    else
      kind = "unreferenced"
    end

    counts[kind] = counts[kind] + 1
    entries[#entries + 1] = { module = module, kind = kind, consumers = who }
  end

  return { entries = entries, counts = counts, maps = #maps }
end

---The index as report lines, most-used first within `external`.
---@param index Documentation.Consumers.Index
---@param title string
---@return string[]
function M.render(index, title)
  local out = {
    "# " .. title,
    "",
    ("Read %d consumer map(s)."):format(index.maps),
    "",
    ("- %d module(s) required by at least one consumer"):format(index.counts.external),
    ("- %d required only by this library itself"):format(index.counts.internal),
    ("- %d referenced by nobody, inside or out"):format(index.counts.unreferenced),
    "",
    "**`unreferenced` does not mean dead.** It means no consumer among the",
    "maps supplied here — a project not in the set, a map not regenerated",
    "since its last require was added, and a user who never committed a map",
    "are all invisible to this and all perfectly normal.",
    "",
  }

  local external = {}
  for _, e in ipairs(index.entries) do
    if e.kind == "external" then
      external[#external + 1] = e
    end
  end
  table.sort(external, function(a, b)
    if #a.consumers ~= #b.consumers then
      return #a.consumers > #b.consumers
    end
    return a.module < b.module
  end)

  if #external > 0 then
    out[#out + 1] = "## Required by consumers"
    out[#out + 1] = ""
    for _, e in ipairs(external) do
      out[#out + 1] = ("- `%s` — %d: %s"):format(
        e.module,
        #e.consumers,
        table.concat(e.consumers, ", ")
      )
    end
    out[#out + 1] = ""
  end

  for _, section in ipairs({
    { kind = "unreferenced", title = "## Referenced by nobody" },
    { kind = "internal", title = "## Used only inside this library" },
  }) do
    local list = {}
    for _, e in ipairs(index.entries) do
      if e.kind == section.kind then
        list[#list + 1] = "- `" .. e.module .. "`"
      end
    end
    if #list > 0 then
      out[#out + 1] = section.title
      out[#out + 1] = ""
      vim.list_extend(out, list)
      out[#out + 1] = ""
    end
  end

  return out
end

return M
