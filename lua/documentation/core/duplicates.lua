---@module 'documentation.core.duplicates'
--- Copy-paste detection: functions whose *structure* is identical, grouped.
--- PMD's CPD, over the same IR every other Analysis tool reads.
---
--- The pattern this is aimed at is specific to a utility tree. Two modules
--- that each grew their own `read(path)` do not fail a check, do not fail a
--- test, and do not show up in any of the graphs — the require graph says
--- nothing, because the whole point is that neither one requires the other.
--- It is the one shape of drift the rest of this plugin is structurally blind
--- to.
---
--- ## What "identical" means here
---
--- The comparison is on `fn.shape`, computed in
--- [`functions.lua`](functions.lua) during the scan: a hash of the treesitter
--- node *types* over the function's whole subtree, never their text. So two
--- functions differing only in identifier and literal names match, which is
--- the entire point — a copy-paste gets renamed on the way in, and a detector
--- that only found byte-identical bodies would find the one case nobody ships.
---
--- The blind spots are worth stating, because they are the reason this is a
--- ranking and not a check:
---
---   * **A single edited line breaks the match.** This finds copies, not
---     near-copies. Real clone detectors slide a window over a token stream to
---     find the longest common run; that is a genuinely more expensive
---     algorithm, and exact-shape matching is what earns its cost on the first
---     pass. If the answer here is consistently empty on a tree that clearly
---     has duplication, *that* is the argument for the sliding window — not
---     an assumption up front.
---   * **The other direction is not an error either.** Two functions can
---     legitimately share a shape and share nothing else: `M.min` and `M.max`
---     over the same fold, two adapters around different APIs with the same
---     five lines of plumbing. This is why the result is a panel, not a
---     finding: `--check` must never fail on it.
---
--- ## Size floor
---
--- Below `MIN_SIZE` nodes a shared shape means nothing — every one-line
--- accessor in a tree is `return self.x`, and reporting those buries the
--- findings that matter under dozens that do not. Measured on this repository:
--- no floor reports 5 groups, a floor of 40 reports 2, and both of those two
--- are real. The number is the point where trivia stops and structure starts,
--- and it is a constant rather than an option because a knob nobody knows how
--- to set is worse than a documented default.

local M = {}

---Node-count floor below which a shared shape is not evidence of anything.
---@type integer
M.MIN_SIZE = 40

---One group of structurally identical functions.
---@class Documentation.Duplicates.Group
---@field shape string The fingerprint they share.
---@field size integer Node count of the shared shape.
---@field members Documentation.Duplicates.Member[] At least two, sorted by node id then function name.

---@class Documentation.Duplicates.Member
---@field node string Node id the function is declared in.
---@field module string? The node's declared `@module`, when it has one.
---@field name string Qualified function name, e.g. "M.read".
---@field signature string
---@field line integer

---@class Documentation.Duplicates.Result
---@field groups Documentation.Duplicates.Group[] Largest group first, then by shape size, then by fingerprint.
---@field functions integer How many functions sit in some group.
---@field considered integer How many functions were large enough to compare at all.
---@field min_size integer The floor that was applied, so a reader can tell "nothing found" from "nothing looked at".

---Group every function in `ir` by structural shape.
---
---Pure: an IR in, a table out — the same shape as `coverage`/`doccoverage`
---and, like them, no filesystem and no git. The work that could not be pure
---already happened during the scan, where the parse tree existed.
---@param ir Documentation.IR
---@param min_size integer? Override `M.MIN_SIZE`; the spec uses it, callers should not need to.
---@return Documentation.Duplicates.Result
function M.resolve(ir, min_size)
  local floor = min_size or M.MIN_SIZE
  local by_shape = {}
  local considered = 0

  for _, id in ipairs(ir.order or {}) do
    local node = ir.nodes[id]
    for _, fn in ipairs((node and node.functions) or {}) do
      -- An artifact written before `shape` existed simply has none. Skipping
      -- rather than erroring is the same tolerance `diff.lua` extends to
      -- older schema versions: this tool is not the right place to discover
      -- that a committed map is a few versions old.
      if fn.shape and (fn.shape_size or 0) >= floor then
        considered = considered + 1
        local g = by_shape[fn.shape]
        if not g then
          g = { shape = fn.shape, size = fn.shape_size, members = {} }
          by_shape[fn.shape] = g
        end
        g.members[#g.members + 1] = {
          node = id,
          module = node.module,
          name = fn.name,
          signature = fn.signature,
          line = fn.line,
        }
      end
    end
  end

  local groups, in_groups = {}, 0
  for _, g in pairs(by_shape) do
    if #g.members > 1 then
      table.sort(g.members, function(a, b)
        if a.node ~= b.node then
          return a.node < b.node
        end
        return a.name < b.name
      end)
      groups[#groups + 1] = g
      in_groups = in_groups + #g.members
    end
  end

  -- Deterministic to the last tie-break, because this feeds a committed
  -- artifact: `pairs` order above is unspecified, so anything not fully
  -- ordered here would produce byte-different output on two runs over an
  -- unchanged tree and make `--check` report the map as stale immediately
  -- after generating it.
  table.sort(groups, function(a, b)
    if #a.members ~= #b.members then
      return #a.members > #b.members
    end
    if a.size ~= b.size then
      return a.size > b.size
    end
    return a.shape < b.shape
  end)

  return { groups = groups, functions = in_groups, considered = considered, min_size = floor }
end

---One line for a report: "2 groups, 5 functions".
---@param result Documentation.Duplicates.Result
---@return string
function M.summary(result)
  if #result.groups == 0 then
    return ("no structural duplicates among %d functions of %d+ nodes"):format(
      result.considered,
      result.min_size
    )
  end
  return ("%d duplicate group%s covering %d functions"):format(
    #result.groups,
    #result.groups == 1 and "" or "s",
    result.functions
  )
end

return M
