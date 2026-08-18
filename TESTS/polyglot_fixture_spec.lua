-- TESTS/polyglot_fixture_spec.lua — a real mixed tree, checked in
--
-- MULTILANG.md stage 3.7 asks for real per-language sample trees rather than
-- hand-written snippets, and gives the reason: `core/plugins.lua` passed nine
-- fixtures and then produced 235 false positives against one real config.
--
-- This is the *polyglot* one, and it is the case that would have caught the
-- worst failure this pipeline has had. `config.detect_source` returned "lua"
-- for every tree it did not recognise, so a JavaScript project died on
-- `source directory not found` — for months, while the engine could read
-- JS/TS the whole time. A checked-in tree with Lua beside JS/TS turns that
-- from something a person has to think to try into something CI runs.
--
-- `TESTS/fixtures/polyglot/` is a tree, not a snippet: it has two source
-- roots, a helper file beside a module, a file outside every root, and an
-- extension no backend claims — each of which is a separate thing the scan
-- has to get right, and none of which a string fixture exercises.

return function(H)
  local eq, ok = H.eq, H.ok

  local root = (vim.fn.getcwd():gsub("\\", "/")) .. "/TESTS/fixtures/polyglot"
  ok(vim.fn.isdirectory(root) == 1, "polyglot: the fixture tree is checked in")

  local opts = require("documentation.config").build(root)

  -- The failure this fixture exists for. Before source detection asked the
  -- backends, this came back as the single string "lua" and the scan died.
  -- Joined through a local rather than `table.concat(opts.source, …)`
  -- directly: the field is `string|string[]`, and a spec that only compiles
  -- for the list case would stop type-checking the day someone passes a
  -- plain string.
  local detected = type(opts.source) == "table" and table.concat(opts.source, " + ")
    or tostring(opts.source)
  eq(detected, "lua/pgl + src", "polyglot: both source roots are detected, Lua's and the ECMA one")

  local ir = require("documentation.core.scan").scan(opts)

  -- Several roots need a parent, and it is the repository directory they
  -- share rather than an invented node.
  eq(ir.root, ".", "polyglot: several roots get a synthetic parent")
  eq(
    table.concat(ir.meta.sources or {}, " + "),
    "lua/pgl + src",
    "polyglot: the artifact records every root walked"
  )

  local by_id = {}
  for _, id in ipairs(ir.order) do
    by_id[id] = ir.nodes[id]
  end

  ok(by_id["lua/pgl"] ~= nil, "polyglot: the Lua module is in the map")
  ok(by_id["src/util.js"] ~= nil, "polyglot: ... and the JavaScript file")
  ok(by_id["src/parse.ts"] ~= nil, "polyglot: ... and the TypeScript file")

  -- The half that used to vanish silently: a mixed tree mapped one source
  -- root and said nothing about the other.
  eq(by_id["lua/pgl"].language, "lua", "polyglot: the Lua module records its language")
  eq(by_id["src/util.js"].language, "js", "polyglot: ... the JS file records its own")
  eq(by_id["src/parse.ts"].language, "ts", "polyglot: ... and the TS file its own")

  -- A namespace has no module file of any language, and guessing one from
  -- its children would make a directory holding both look like whichever
  -- child came first.
  eq(by_id["."].language, nil, "polyglot: the synthetic root claims no language")

  -- Coverage honesty, both directions. `tools/build.ts` sits outside every
  -- source root; `NOTES.md` sits inside one and belongs to no backend.
  eq(
    ir.meta.outside and ir.meta.outside.ts,
    1,
    "polyglot: a readable file outside every source root is counted"
  )
  eq(
    ir.meta.unclaimed and ir.meta.unclaimed.md,
    1,
    "polyglot: an unclaimed extension inside the roots is counted"
  )
  -- `ts` contributed nodes, so this is "partly outside", not "a language
  -- absent from the map" — which is exactly the distinction that keeps the
  -- CLI quiet here.
  ok(
    ir.meta.claimed and ir.meta.claimed.ts and ir.meta.claimed.ts > 0,
    "polyglot: ... and that language is also claimed, so the report stays quiet"
  )

  -- Function-level facts need the ECMA parser, which CI does not install.
  -- Asserted when it happens to be there, skipped honestly when not — the
  -- same split `lang_js_spec.lua` uses.
  local names = {}
  for _, id in ipairs(ir.order) do
    for _, fn in ipairs(by_id[id].functions or {}) do
      names[fn.name] = true
    end
  end
  ok(names["M.polyglot_fixture_add"], "polyglot: the Lua module's function is extracted")

  local ok_js, has_js = pcall(vim.treesitter.language.add, "javascript")
  if ok_js and has_js then
    ok(names["polyglotFixtureJoin"], "polyglot: the JS function is extracted too")
  else
    ok(true, "polyglot: javascript parser not installed — function-level JS assertions skipped")
  end
end
