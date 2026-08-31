-- The fixtures below carry only the fields `scopes.summary` reads; a full IR
-- and a full node per case would be noise rather than coverage.
---@diagnostic disable: missing-fields
-- TESTS/scopes_spec.lua — documentation.core.scopes
--
-- No grammar needed, deliberately. The two backend specs that *do* need one
-- (`lang_python_spec.lua`, `lang_rust_spec.lua`) assert that the owner comes
-- out of a real parse correctly; this file asserts what the shared grouping
-- does with it, which is the half every one of the twenty-three backends
-- shares and the half that has to hold on a CI host with no parsers at all.
--
-- The interesting assertions are the negative ones. Grouping by owner has an
-- obvious cheap alternative — match the prefix of `fn.name` — and the whole
-- reason the IR grew a field is that the cheap version is wrong in cases
-- that occur in real trees. Those cases are here.

return function(H)
  local eq, ok = H.eq, H.ok

  local scopes = require("documentation.core.scopes")

  ---One `Documentation.FunctionInfo`, cut down to what this module reads.
  ---@param name string
  ---@param owner string?
  ---@param kind string?
  local function fn(name, owner, kind)
    return { name = name, owner = owner, owner_kind = kind }
  end

  -- ---------------------------------------------------------------------
  -- Grouping, and the order it keeps.
  -- ---------------------------------------------------------------------
  local fns = {
    fn("helper"),
    fn("Widget.build", "Widget", "class"),
    fn("Gadget.build", "Gadget", "class"),
    fn("Widget.reset", "Widget", "class"),
    fn("main"),
  }

  local free, groups = scopes.split(fns)
  eq(#free, 2, "two functions belong to the module itself")
  eq(free[1].name, "helper")
  eq(free[2].name, "main")

  eq(#groups, 2)
  eq(groups[1].name, "Widget", "first appearance decides the order, not the alphabet")
  eq(groups[2].name, "Gadget")
  eq(#groups[1].functions, 2, "a scope collects members that are not adjacent in the file")
  eq(groups[1].functions[1].name, "Widget.build")
  eq(groups[1].functions[2].name, "Widget.reset")
  eq(groups[1].kind, "class")

  -- **The case a prefix match gets wrong.** A module-level function named
  -- after a class is not a method of it — and the two are indistinguishable
  -- by name alone, which is why the owner is a field.
  local mixed = scopes.group({
    fn("Widget.helper"),
    fn("Widget.build", "Widget", "class"),
  })
  eq(#mixed, 1)
  eq(#mixed[1].functions, 1, "only the one that says it is owned")
  eq(mixed[1].functions[1].name, "Widget.build")

  -- **Lua's own shape must not group.** `function M.foo()` is dotted because
  -- `M` is the module table, which is the node — a prefix match would invent
  -- a scope called `M` in every Lua file in every tree.
  local lua_like = scopes.group({ fn("M.scan"), fn("M.generate"), fn("M.check") })
  eq(#lua_like, 0, "no backend set an owner, so there is no scope")

  -- A half-set pair is a backend bug, not a scope of unknown kind.
  eq(#scopes.group({ fn("Thing.go", "Thing", nil) }), 0, "an owner with no kind is not a scope")
  eq(#scopes.group({ fn("go", nil, "class") }), 0, "and a kind with no owner is not either")

  eq(#scopes.group(nil), 0, "a node with no functions at all")

  -- ---------------------------------------------------------------------
  -- Over a whole IR.
  -- ---------------------------------------------------------------------
  local ir = {
    order = { "a", "b", "gone" },
    nodes = {
      a = { id = "a", functions = fns },
      b = { id = "b", functions = { fn("Doer::go", "Doer", "trait") } },
    },
  }

  local all = scopes.all(ir)
  eq(#all, 3, "two scopes in the first node, one in the second")
  eq(all[1].node.id, "a")
  eq(all[3].scope.name, "Doer")
  eq(all[3].scope.kind, "trait")

  eq(
    scopes.summary(ir),
    "3 scopes owning 4 of 6 functions",
    "the counts are over owned functions, not over scopes' members plus the free ones twice"
  )

  -- **Silent rather than zero.** A Lua or C tree has no owning construct at
  -- all, and a permanent "0 scopes" line would read as a missing feature
  -- rather than as an absent language construct.
  eq(
    scopes.summary({ order = { "a" }, nodes = { a = { functions = { fn("M.scan") } } } }),
    nil,
    "a tree with no owner anywhere says nothing"
  )

  ok(true, "scopes: grouping, the two shapes a prefix match gets wrong, and the IR-wide rollup")
end
