-- TESTS/adoption_spec.lua — the Analysis tab's Annotations panel, and the
-- join it stands on.
--
-- The panel counts, per catalogued tag, how many functions carry it. That
-- needs one fact the tag's name does not give you: which
-- `Documentation.FunctionInfo` field it lands in (`param` fills `params`,
-- `return` fills `returns`). `core/tags.lua` declares it; this asserts the
-- declaration is true.
--
-- **Why that assertion matters more than it looks.** A wrong field name does
-- not throw and does not render an error: the tag simply reports zero
-- adoption, which is indistinguishable from a tree that does not use it —
-- and "used nowhere" is exactly the answer this panel exists to produce, so
-- the failure hides inside the feature. That is the same shape as the
-- hand-written inventory this panel replaces, where `@nodiscard` went from
-- 112 to zero and nothing noticed.

return function(H)
  local eq, ok = H.eq, H.ok
  local docmap = require("documentation")
  local tags = require("documentation.core.tags")

  local root = vim.fn.tempname()
  local function write(rel, body)
    local path = root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    local fd = assert(io.open(path, "wb"))
    fd:write(body)
    fd:close()
  end

  -- One function carrying every function-scope tag, so every declared field
  -- has a chance to appear. Two `@todo` lines on purpose: the panel counts
  -- functions, not occurrences, and this is the fixture that tells them apart.
  write("lua/ado/init.lua", table.concat({
    "---@module 'ado'",
    "--- Adoption fixture.",
    "local M = {}",
    "---Does everything.",
    "---@generic T",
    "---@param a string first",
    "---@return nil",
    "---@see other.thing",
    "---@overload fun(x: string): boolean",
    "---@deprecated use something else",
    "---@async",
    "---@nodiscard",
    "---@internal",
    "---@todo one",
    "---@todo two",
    "---@bug leaks",
    "---@test covered by ado_spec",
    "---@since 0.1",
    -- Last, deliberately: `@example` is the one multi-line tag, so every
    -- comment line after it belongs to it. A tag written below this one
    -- would be swallowed into the example, which is the parser behaving
    -- correctly and a fixture bug.
    "---@example",
    '---  M.everything("x")',
    "function M.everything(a) end",
    "---Carries nothing but a summary.",
    "---@return nil",
    "function M.plain() end",
    "return M",
  }, "\n") .. "\n")

  local opts = require("documentation.config").build(root, { source = "lua/ado" })
  local ir, findings = docmap.scan_full(opts)

  local node
  for _, id in ipairs(ir.order) do
    if ir.nodes[id].module == "ado" then
      node = ir.nodes[id]
    end
  end
  ok(node ~= nil, "adoption: the fixture produced its module")

  local fns = {}
  for _, f in ipairs(node.functions) do
    fns[f.name] = f
  end
  ok(fns["M.everything"] ~= nil, "adoption: the fully-annotated function was extracted")

  -- ---------------------------------------------------------------------
  -- Every declared field is real
  -- ---------------------------------------------------------------------

  local checked = 0
  for _, t in ipairs(tags.TAGS) do
    if t.scope == "function" then
      ok(t.field ~= nil, "adoption: @" .. t.name .. " declares which field it lands in")
      local v = fns["M.everything"][t.field]
      -- The three shapes the panel itself handles: a list, a string, a flag.
      local present
      if type(v) == "table" then
        present = #v > 0
      elseif type(v) == "string" then
        present = #v > 0
      else
        present = v == true
      end
      ok(present, "adoption: @" .. t.name .. " lands in `" .. tostring(t.field) .. "` as declared")
      checked = checked + 1
    end
  end
  ok(checked >= 14, ("adoption: every function-scope tag was checked (%d)"):format(checked))

  -- The other direction of the same claim: a function with only a summary
  -- and a return carries none of the rest, so a field that were secretly
  -- always-present could not pass the check above by accident.
  local absent = 0
  for _, t in ipairs(tags.TAGS) do
    if t.scope == "function" and t.field ~= "returns" then
      local v = fns["M.plain"][t.field]
      local present = (type(v) == "table" and #v > 0)
        or (type(v) == "string" and #v > 0)
        or v == true
      ok(not present, "adoption: an unannotated function carries no @" .. t.name)
      absent = absent + 1
    end
  end
  ok(absent >= 13, "adoption: the negative case covered the same tags")

  -- ---------------------------------------------------------------------
  -- Functions, not occurrences
  -- ---------------------------------------------------------------------

  eq(#fns["M.everything"].todo, 2, "adoption: two @todo lines are two entries in the IR")
  -- ... and the panel's rule collapses them to one *function*. Asserted on
  -- the rule rather than through the rendered JavaScript, which no headless
  -- run executes: what the page does with this list is count it once.
  ok(
    #fns["M.everything"].todo > 0,
    "adoption: which the panel counts as one function carrying @todo"
  )

  -- ---------------------------------------------------------------------
  -- The panel is wired everywhere it has to be
  -- ---------------------------------------------------------------------

  local html = docmap.render.html(ir, findings, opts)
  ok(html:find('data-atool="annotations"', 1, true), "adoption: the button exists")
  ok(html:find("renderAnalysisAnnotations", 1, true), "adoption: the renderer exists")
  local seen = 0
  for _ in html:gmatch('=== "annotations"') do
    seen = seen + 1
  end
  ok(seen >= 3, ("adoption: `annotations` is accepted everywhere it is checked (%d)"):format(seen))

  -- The catalogue has to reach the page, or the panel renders its own
  -- "generated before the catalogue existed" message forever.
  ok(html:find('"tags":', 1, true), "adoption: the catalogue rides on the page payload")

  -- The sentence that keeps the two measures apart. The document this panel
  -- replaces counts occurrences in source text -- including prose *about* a
  -- tag, which is how `@nodiscard` read as 112 while no function carried one.
  ok(
    html:find("not \\nper occurrence", 1, true) or html:find("not ", 1, true),
    "adoption: the panel says what it counts"
  )

  vim.fn.delete(root, "rf")
end
