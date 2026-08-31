---@module 'documentation.core.doccoverage'
--- Documentation coverage (R4): one number instead of three scattered
--- findings. `missing-summary`, `undocumented-param` and
--- `param-name-mismatch` each answer "is this one thing wrong", which is
--- right for `--check` and wrong for "how documented is this tree, and did
--- that number move since last time" — the question `diff.lua` already
--- answers for the require graph and the API surface, and this is the same
--- idea for documentation completeness.
---
--- A function counts as documented when it has a non-empty summary and its
--- declared parameters are fully and correctly named in `@param` lines —
--- exactly the two conditions `missing-summary`/`undocumented-param`/
--- `param-name-mismatch` already check per-function, reused here rather than
--- reimplemented so the aggregate can never quietly disagree with the
--- findings a reader already sees. `@return` is deliberately not part of the
--- definition: unlike a parameter, a function's raw signature carries no
--- count of what it returns, so there is no structural fact to check
--- against — only "did the author write an @return line", which
--- `missing-summary`-style nagging already covers badly enough without a
--- coverage number pretending it is more precise than that.
---
--- `@internal` functions are excluded, the same as all three findings this
--- builds on: an internal function's documentation bar is the author's own,
--- and folding it into a "published API" coverage number would make the
--- number answer a question nobody asked.

local M = {}

---Whether `language`'s backend has a per-parameter documentation
---convention at all.
---
---**Not every language does, and judging one that does not by one that does
---produces a wrong number rather than a low one.** LuaCATS, JSDoc, Javadoc
---and Doxygen all name parameters individually; Zig documents a declaration
---with a `///` block and has no `@param`, and an assembly label has no
---parameter list to name. Before this existed, every Zig function in a tree
---scored undocumented forever however carefully it was written — which the
---single tree-wide average hid and `M.by_language` made impossible to miss.
---
---The same shape as `module_tag = false`: a backend states that its language
---has no such concept, and the checks stop reporting the absence of
---something that cannot be present. Absent/`nil` means "yes it has one", the
---conservative default that preserves the behaviour every backend written
---before this had.
---@param language string? From `Documentation.Node.language`; `nil` for a namespace.
---@return boolean
function M.language_documents_params(language)
  if not language then
    return true
  end
  local backend = require("documentation.core.lang_registry").get(language)
  return not backend or backend.param_docs ~= false
end

---True when `fn`'s declared parameters are fully and correctly documented:
---same count, same names at each position — exactly what
---`undocumented-param` and `param-name-mismatch` each check one half of.
---
---Vacuously true for a language with no per-parameter convention, which is
---the honest answer rather than a lenient one: there is no set of parameter
---documentation this function could have written that would satisfy a rule
---its language does not have.
---@param fn Documentation.FunctionInfo
---@param language string? The node's language. Omitted, the strict rule applies.
---@return boolean
function M.params_documented(fn, language)
  if not M.language_documents_params(language) then
    return true
  end
  local check = require("documentation.core.check")
  local declared = check.declared_param_names(fn)

  local doc_params = fn.params
  -- Same colon-method `self` exception `param-name-mismatch` needs: Lua's
  -- implicit sugar means `self` never appears in the raw signature text,
  -- but documenting it explicitly is legitimate LuaCATS style.
  if fn.name:find(":") and doc_params[1] and doc_params[1].name == "self" then
    local shifted = {}
    for i = 2, #doc_params do
      shifted[#shifted + 1] = doc_params[i]
    end
    doc_params = shifted
  end

  local declared_count = 0
  for _, token in ipairs(declared) do
    if token ~= "..." then
      declared_count = declared_count + 1
    end
  end
  if declared_count > #doc_params then
    return false
  end

  for i = 1, math.min(#declared, #doc_params) do
    if declared[i] ~= "..." and declared[i] ~= doc_params[i].name then
      return false
    end
  end
  return true
end

---True when `fn` has both a non-empty summary and fully, correctly
---documented parameters — the whole definition of "documented" this module
---uses, in one place, so `M.resolve` (which stamps `fn.documented` into the
---IR for the Analysis tab) and `M.summary` (the aggregate CLI/badge number)
---can never quietly disagree about a single function.
---@param fn Documentation.FunctionInfo
---@return boolean
---@param language string? The node's language, so a language with no
---per-parameter convention is judged on its summary alone.
function M.is_documented(fn, language)
  local has_summary = fn.summary ~= nil and fn.summary ~= ""
  return has_summary and M.params_documented(fn, language)
end

---Stamp `fn.documented` onto every non-`@internal` function in `ir` —
---`@internal` functions are left `false` rather than skipped, the same
---"always a real boolean, never a nil a reader has to guard" reasoning
---`fn.tested`'s default already follows. What the Analysis tab's
---Documentation panel reads to build a per-module breakdown without
---duplicating `M.is_documented`'s logic in JS.
---@param ir Documentation.IR
function M.resolve(ir)
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    for _, fn in ipairs(node.functions) do
      fn.documented = (not fn.internal) and M.is_documented(fn, node.language) or false
    end
  end
end

---Aggregate documentation coverage over `ir`: how many published (non-
---`@internal`) functions have both a summary and fully, correctly
---documented parameters.
---@param ir Documentation.IR
---@return integer documented
---@return integer total
function M.summary(ir)
  local documented, total = 0, 0
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    for _, fn in ipairs(node.functions) do
      if not fn.internal then
        total = total + 1
        if M.is_documented(fn, node.language) then
          documented = documented + 1
        end
      end
    end
  end
  return documented, total
end

---The same measure, split by the language each node was read with.
---
---**Why one average stopped being enough.** When this module was written the
---tree it measured was Lua. There are nine language backends now, and they do
---not set the same bar: Java's Javadoc has a tool behind it and its `@param`
---tags are parsed, while an assembly label has no parameter list at all and
---is documented by whatever comment sits above it. Averaging those produces a
---number that is true of no language in the tree — a repository at 60% might
---be 95% Lua and 5% C, and the single figure hides exactly the fact worth
---acting on.
---
---The average stays, and stays the headline: it is what the badge and
---`--check` compare, and one number is what a reader wants first. This is the
---second question, and it is only asked when the tree can answer it — a
---breakdown of one row is the average with extra words.
---
---Grouped by `node.language`, the field the walk already stamps from whichever
---backend claimed the file. A namespace has none and contributes nothing,
---which is correct rather than convenient: it holds no functions to count.
---
---**Two counts, because the bar is not the same in every language.** Eight
---of the twenty-three backends declare `param_docs = false`, so a function
---there is documented once it has a summary; the other fifteen also require
---every parameter. Reporting one percentage per language would put two
---different measures in one column and invite a comparison that means
---nothing.
---
---So each row carries both:
---
--- * `summarised` — has a non-empty summary. **Comparable across all
---   twenty-three**, because every language has the concept.
--- * `documented` — passes that language's own full bar, parameters
---   included where the language has them. Comparable across the fifteen
---   that judge parameters, and equal to `summarised` for the eight that do
---   not.
---
---`judges_params` says which of the two the row is, so a caller can render
---the difference rather than hiding it. Keeping them separate costs a field
---and answers both questions honestly; collapsing them would answer neither.
---@param ir Documentation.IR
---@return { language: string, documented: integer, summarised: integer, total: integer, judges_params: boolean }[] # Largest first, ties by name, so the order is deterministic across runs.
function M.by_language(ir)
  local acc = {}
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    local lang = node.language
    if lang then
      for _, fn in ipairs(node.functions) do
        if not fn.internal then
          local slot = acc[lang]
          if not slot then
            slot = {
              language = lang,
              documented = 0,
              summarised = 0,
              total = 0,
              judges_params = M.language_documents_params(lang),
            }
            acc[lang] = slot
          end
          slot.total = slot.total + 1
          if (fn.summary or "") ~= "" then
            slot.summarised = slot.summarised + 1
          end
          if M.is_documented(fn, lang) then
            slot.documented = slot.documented + 1
          end
        end
      end
    end
  end

  local out = {}
  for _, slot in pairs(acc) do
    out[#out + 1] = slot
  end
  -- Largest first because that is the order a reader scans, and by name on a
  -- tie because `pairs` order differs between runs of the same binary — which
  -- would make this line churn in a byte-deterministic artifact.
  table.sort(out, function(a, b)
    if a.total ~= b.total then
      return a.total > b.total
    end
    return a.language < b.language
  end)
  return out
end

---`M.summary(ir)` rendered as a shields.io-shaped SVG badge — what
---`opts.badge` writes to `coverage.svg`. Split out of `M.summary` so a
---caller that only wants the raw numbers (the CLI's printed line, a future
---Analysis-tab panel) never pulls in `render/badge.lua` for nothing.
---@param ir Documentation.IR
---@return string svg
function M.badge_svg(ir)
  local badge = require("documentation.core.render.badge")
  local documented, total = M.summary(ir)
  local pct = total > 0 and (100 * documented / total) or 0
  return badge.render("doc coverage", ("%.0f%%"):format(pct), badge.color_for(pct))
end

return M
