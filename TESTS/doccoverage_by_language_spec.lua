-- TESTS/doccoverage_by_language_spec.lua — `doccoverage.by_language`
--
-- The split the single average stopped being able to carry. When
-- `doccoverage.lua` was written the tree it measured was Lua; there are nine
-- language backends now and they do not set the same bar, so an average
-- across them can be true of no language in the tree.
--
-- Built on hand-made IR tables rather than on a scan: this function is pure —
-- an IR in, a table out — and testing it through a real parse would make it
-- depend on grammars CI does not install, for no extra confidence about the
-- grouping, which is the only thing here that could be wrong.

return function(H)
  local eq, ok = H.eq, H.ok

  local dc = require("documentation.core.doccoverage")

  ---One function, documented or not. `signature` is not decoration:
  ---`params_documented` reads the declared parameter list out of it, so a
  ---fixture without one raises rather than counting as undocumented.
  local function fn(name, summary, internal)
    return {
      name = name,
      signature = name .. "()",
      summary = summary or "",
      params = {},
      internal = internal or false,
    }
  end

  local function ir_of(nodes)
    local ir = { order = {}, nodes = {} }
    for _, entry in ipairs(nodes) do
      ir.order[#ir.order + 1] = entry[1]
      ir.nodes[entry[1]] = { language = entry[2], functions = entry[3] }
    end
    return ir
  end

  -- -------------------------------------------------------------------
  -- The grouping itself.
  -- -------------------------------------------------------------------
  local ir = ir_of({
    { "a.lua", "lua", { fn("a", "Does a."), fn("b") } },
    { "b.lua", "lua", { fn("c", "Does c.") } },
    { "c.zig", "zig", { fn("d", "Does d.") } },
  })
  local per = dc.by_language(ir)
  eq(#per, 2, "two languages in the tree")

  local by = {}
  for _, row in ipairs(per) do
    by[row.language] = row
  end
  eq(by.lua.total, 3)
  eq(by.lua.documented, 2)
  eq(by.zig.total, 1)
  eq(by.zig.documented, 1)

  -- The total across the rows must equal the headline, or the two numbers on
  -- one screen disagree — which is the failure a breakdown is most likely to
  -- introduce and the least likely to be noticed.
  local documented, total = dc.summary(ir)
  local sum_d, sum_t = 0, 0
  for _, row in ipairs(per) do
    sum_d = sum_d + row.documented
    sum_t = sum_t + row.total
  end
  eq(sum_t, total, "the rows must add up to the headline's denominator")
  eq(sum_d, documented, "and to its numerator")

  -- -------------------------------------------------------------------
  -- Order: largest first, ties by name. Deterministic because `pairs` is
  -- not, and this reaches a byte-deterministic artifact.
  -- -------------------------------------------------------------------
  eq(per[1].language, "lua", "the larger language comes first")

  local tied = dc.by_language(ir_of({
    { "x.zig", "zig", { fn("x", "Doc.") } },
    { "y.c", "c", { fn("y", "Doc.") } },
    { "z.java", "java", { fn("z", "Doc.") } },
  }))
  eq(tied[1].language, "c", "equal counts break the tie by name")
  eq(tied[2].language, "java")
  eq(tied[3].language, "zig")
  local again = dc.by_language(ir_of({
    { "x.zig", "zig", { fn("x", "Doc.") } },
    { "y.c", "c", { fn("y", "Doc.") } },
    { "z.java", "java", { fn("z", "Doc.") } },
  }))
  eq(again[1].language, tied[1].language, "and the order is stable across calls")

  -- -------------------------------------------------------------------
  -- What does not count, and why each one is right rather than convenient.
  -- -------------------------------------------------------------------
  local mixed = dc.by_language(ir_of({
    -- A namespace has no language and no functions. Counting it as a
    -- language would invent a row for a directory.
    { "dir", nil, {} },
    -- `@internal` is out of the published surface, the same rule `summary`
    -- applies — an internal function's documentation bar is the author's.
    { "p.lua", "lua", { fn("pub", "Doc."), fn("priv", "", true) } },
  }))
  eq(#mixed, 1, "a namespace is not a language")
  eq(mixed[1].total, 1, "an @internal function is not part of the published surface")

  eq(#dc.by_language(ir_of({})), 0, "an empty tree has no rows, not a zero row")

  -- A single-language tree still answers; it is the *caller* that decides a
  -- one-row breakdown is not worth printing, and that decision belongs where
  -- the printing is rather than here.
  local one = dc.by_language(ir_of({ { "a.lua", "lua", { fn("a", "Doc.") } } }))
  eq(#one, 1, "one language answers with one row — suppressing it is the caller's call")

  -- -------------------------------------------------------------------
  -- The unfairness this breakdown exposed, and the fix for it.
  --
  -- Building `by_language` against a real mixed tree produced `zig 0/2` for
  -- a file whose one documented function was documented — because the
  -- measure demanded `@param` lines from a language that has no `@param`.
  -- Every Zig function scored undocumented forever, and the tree-wide
  -- average had been hiding it. `param_docs = false` is the same shape as
  -- `module_tag = false`: the language says it has no such concept, and the
  -- measure stops judging it by one.
  -- -------------------------------------------------------------------
  eq(dc.language_documents_params("lua"), true, "LuaCATS names parameters individually")
  eq(dc.language_documents_params("zig"), false, "Zig documents a declaration, not its parameters")
  eq(dc.language_documents_params("asm"), false, "a label has no parameter list to name")
  eq(
    dc.language_documents_params(nil),
    true,
    "a namespace is judged by the strict rule, not exempted"
  )
  eq(
    dc.language_documents_params("nosuchlanguage"),
    true,
    "an unknown language keeps the strict rule — an exemption must be declared, never assumed"
  )

  -- A Zig-shaped function: a summary, declared parameters in the signature,
  -- and no `params` because the language has no form to put them in.
  local zig_fn = {
    name = "add",
    signature = "add(a: i32, b: i32)",
    summary = "Adds two numbers.",
    params = {},
    internal = false,
  }
  eq(dc.is_documented(zig_fn, "zig"), true, "judged on its summary, which is all Zig offers")
  eq(
    dc.is_documented(zig_fn, "lua"),
    false,
    "and the strict rule still applies where the convention exists — the exemption is per language, not a general softening"
  )

  ok(true, "doccoverage.by_language")
end
