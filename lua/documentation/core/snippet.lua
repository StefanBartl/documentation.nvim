---@module 'documentation.core.snippet'
--- Bounded source-code snippets: a function's own body, capped to a fixed
--- line count. `docs/ecosystem.md`'s §3.5 two-tier split for hover previews —
--- signature and a bounded snippet always available offline; a full file is
--- an enhancement that needs `serve`. This is the second tier.
---
--- Shared between `functions.lua` (Lua) and `core/lang/ecma.lua` (JS/TS/TSX)
--- rather than duplicated in each: the bounding rule (how many lines, what
--- happens past the cap) is a policy decision, not a per-language fact —
--- both backends already have `src` and a 0-based row range in scope at the
--- exact point they build a `Documentation.FunctionInfo`, so this only needs
--- those two things, never a treesitter node.

local M = {}

---The real default, never mutated — `M.scan`'s own header explains why a
---fixed default has to exist separately from the currently-active
---`M.MAX_LINES` below: a scan with no `opts.snippet_max_lines` has to be
---able to get back to this value even after a previous scan (a different
---repo, a different `opts`) overrode `M.MAX_LINES` for itself.
M.DEFAULT_MAX_LINES = 40

---Lines kept per function before the rest becomes a count — the same shape
---`docs.lua`'s `REFS_PER_ENTITY` caps a reference list, for the same reason:
---this ships in an artifact already measured at 750KB+ (`docs/ecosystem.md`
---§1), and one large function is not entitled to blow that up on its own.
---
---Overridable per scan via `opts.snippet_max_lines` — `core/scan.lua`'s
---`M.scan` resolves it into this field once, before any file is scanned;
---nothing past that point reads `opts` directly.
M.MAX_LINES = M.DEFAULT_MAX_LINES

---One function's own source, bounded to `M.MAX_LINES` lines.
---@param src string Whole-file source text.
---@param srow integer 0-based first row of the function's span.
---@param erow integer 0-based last row of the function's span (inclusive).
---@return string? snippet `nil` for an empty/invalid span — a real absence, not an empty string pretending to be one.
---@return integer omitted Lines cut off past the cap; `0` when nothing was.
function M.extract(src, srow, erow)
  if erow < srow then
    return nil, 0
  end
  local lines = vim.split(src, "\n", { plain = true })
  local first = srow + 1
  if first > #lines then
    return nil, 0
  end
  local last = math.min(erow + 1, #lines)
  local capped_last = math.min(last, first + M.MAX_LINES - 1)

  local out = {}
  for i = first, capped_last do
    out[#out + 1] = lines[i]
  end

  local total = last - first + 1
  local kept = capped_last - first + 1
  return table.concat(out, "\n"), total - kept
end

return M
