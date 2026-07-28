---@module 'documentation.churn'
--- Churn hotspots: modules that are both **frequently changed** and
--- **complex**. Adam Tornhill's signal from *Your Code as a Crime Scene*, over
--- this plugin's own IR.
---
--- The argument for the product rather than either factor is that neither
--- factor alone is actionable. A module edited fifty times that is five lines
--- of constants is not a problem, it is a config file. A three-hundred-point
--- parser nobody has touched in two years is not a problem either — it is
--- finished. What costs real time is the intersection: complicated code that
--- keeps having to change, where every edit is expensive and there will be
--- another one next week. That is a refactoring priority, and it is invisible
--- from either metric on its own.
---
--- **The product is a scalarization, and it has the weakness every
--- scalarization has**: a large enough value on one axis outranks a moderate
--- value on both. A module edited ninety times that is genuinely two lines
--- will still climb past one edited five times at complexity 15. Tornhill's
--- own presentation is a *scatter plot* and the answer is the top-right
--- quadrant, which has no such failure mode — but it is also not a ranking,
--- and a quickfix list is a ranking. Kept because both columns ship on every
--- row: when the order looks wrong, the two numbers next to it say why
--- immediately. Normalising the axes first would fix the ordering and cost
--- exactly that, since a normalised score means nothing on its own.
---
--- ## Why this is a command and not an Analysis panel
---
--- It needs `git log`, and git data cannot enter the committed artifact.
--- `--check` byte-compares committed output against freshly-generated output,
--- so a map carrying history invalidates itself the moment it is committed —
--- there is no fixed point. Exactly why the History tab is not a tab. The
--- other four Analysis tools are pure `ir -> result`; this one is not, and the
--- roadmap listing it beside code duplication as the same kind of work was
--- simply wrong.
---
--- So it lands where `:DocMap impact` already lives: live-computed into the
--- quickfix list, nothing written, no artifact involved.
---
--- ## Pure
---
--- Counting commits is git's job and belongs in `command.lua`, the same split
--- `history.lua` follows. What is here takes a plain `path -> commits` table
--- and an IR, and returns a ranking — which is what lets the scoring be
--- driven from a headless spec with no repository at all.

local M = {}

---One ranked module.
---@class Documentation.Churn.Entry
---@field node string Node id.
---@field module string? Declared `@module`, when it has one.
---@field source string? Repo-relative source path — what the commit count was counted against.
---@field commits integer Commits touching this module's source in the range.
---@field complexity integer Summed cyclomatic complexity of its documented functions.
---@field score integer `commits * complexity`.
---@field hottest string? Signature of its single most complex function — where to actually start reading.

---@class Documentation.Churn.Result
---@field entries Documentation.Churn.Entry[] Highest score first; ties by commits, then node id.
---@field commits integer Distinct commits seen in the range.
---@field unmatched integer Files that changed but back no scanned module — deleted files, docs, CI config.

---Summed complexity of a node's own functions, and the worst single one.
---
---Summed rather than averaged, deliberately. An average asks "how bad is the
---typical function here", which is not the question — a module carrying one
---200-point monster and nine trivial helpers has a real problem that an
---average divides away to nothing. `hottest` is carried alongside because the
---sum says which module and never which function, and "start here" is the
---only useful next step from a ranking like this.
---@param node Documentation.Node
---@return integer total
---@return string? hottest
local function complexity_of(node)
  local total, worst, worst_name = 0, -1, nil
  for _, fn in ipairs(node.functions or {}) do
    local c = fn.complexity or 1
    total = total + c
    if c > worst then
      worst, worst_name = c, fn.signature or fn.name
    end
  end
  return total, worst_name
end

---Rank modules by churn × complexity.
---
---`counts` is keyed by **repo-relative source path** with forward slashes,
---which is what `node.source` already is — matching on the path rather than
---on a module name is what makes this work for files git renamed, deleted or
---never scanned: they simply do not match, and are counted in `unmatched`
---rather than silently dropped. A number with no idea how much it ignored is
---worse than no number.
---@param counts table<string, integer> Repo-relative path -> commits touching it.
---@param ir Documentation.IR
---@param total_commits integer? Distinct commits in the range, for the report.
---@return Documentation.Churn.Result
function M.rank(counts, ir, total_commits)
  local by_source = {}
  for _, id in ipairs(ir.order or {}) do
    local node = ir.nodes[id]
    if node and node.source then
      by_source[node.source] = id
    end
  end

  local entries, matched = {}, {}
  local unmatched = 0
  for path, n in pairs(counts or {}) do
    local id = by_source[path]
    if id then
      matched[id] = (matched[id] or 0) + n
    else
      unmatched = unmatched + 1
    end
  end

  for id, commits in pairs(matched) do
    local node = ir.nodes[id]
    local complexity, hottest = complexity_of(node)
    -- A module with no documented functions has no complexity to multiply, so
    -- it would score zero however often it changed. Dropped rather than listed
    -- at the bottom: a ranking of refactoring risk that ends in a run of
    -- zeroes reads as if the tail were low-risk, when it is really unmeasured.
    if complexity > 0 then
      entries[#entries + 1] = {
        node = id,
        module = node.module,
        source = node.source,
        commits = commits,
        complexity = complexity,
        score = commits * complexity,
        hottest = hottest,
      }
    end
  end

  table.sort(entries, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    if a.commits ~= b.commits then
      return a.commits > b.commits
    end
    return a.node < b.node
  end)

  return { entries = entries, commits = total_commits or 0, unmatched = unmatched }
end

---Quickfix rows for a ranking, in order.
---@param result Documentation.Churn.Result
---@param root string Absolute repository root.
---@return table[]
function M.quickfix_items(result, root)
  local items = {}
  for i, e in ipairs(result.entries) do
    items[i] = {
      filename = root .. "/" .. (e.source or ""),
      lnum = 1,
      text = ("%s · %d commits × complexity %d = %d%s"):format(
        e.module or e.node,
        e.commits,
        e.complexity,
        e.score,
        e.hottest and ("  · hottest: " .. e.hottest) or ""
      ),
    }
  end
  return items
end

return M
