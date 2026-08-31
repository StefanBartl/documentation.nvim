-- TESTS/many_modules_spec.lua — the `file-holds-many-modules` check: one file
-- carrying several module identities, which the map keys on the file.
--
-- Built over a synthetic IR rather than a scanned fixture, on the precedent
-- check_overload_credit_spec.lua set. The languages this check is about are
-- Rust and Elixir, and a fixture in either would make these assertions
-- depend on a treesitter grammar that a plain local run does not have — the
-- question here is what the check does with `owner`/`owner_kind`, not
-- whether the backends set them, which lang_rust_spec.lua and
-- lang_elixir_spec.lua already own.
--
-- What these assertions protect, in order of how quietly each would break:
--
--   1. **A single module is not a finding.** Every Elixir function has an
--      owner — the backend says so in as many words — so a check counting
--      owners instead of identities would fire on every correct `.ex` file
--      in existence and be switched off the same afternoon.
--   2. **A test module is not an identity.** `#[cfg(test)] mod tests` is how
--      Rust is written, not a defect, and it sits in the file it tests by
--      design.
--   3. **A class is not a module.** Three classes in one file is ordinary
--      Python; only constructs that carry a *module* identity count.

return function(H)
  local eq, ok = H.eq, H.ok
  local check = require("documentation.core.check")
  local findings = require("documentation.core.findings")

  local opts = { root = "/fake", lua_root = "lua", extra_checks = {} }

  ---@param name string
  ---@param owner string?
  ---@param owner_kind string?
  local function fn(name, owner, owner_kind)
    return {
      name = name,
      signature = name .. "()",
      summary = "",
      body = "",
      line = 1,
      params = {},
      returns = {},
      see = {},
      overload = {},
      todo = {},
      bug = {},
      test = {},
      owner = owner,
      owner_kind = owner_kind,
    }
  end

  ---@param node table Overrides for the single node under test.
  local function make_ir(node)
    local base = {
      id = "a",
      kind = "module",
      name = "a",
      path = "a",
      source = "a/init.lua",
      module = nil,
      summary = "x",
      body = "",
      readme = "x.md",
      types = {},
      export = "table",
      parent = nil,
      depth = 0,
      children = {},
      functions = {},
    }
    return {
      meta = {
        title = "t",
        source = "lua",
        types_dir = "@types",
        branch = "main",
        schema = 1,
        counts = { module = 1, namespace = 0, file = 0 },
      },
      root = "a",
      order = { "a" },
      nodes = { a = vim.tbl_extend("force", base, node) },
      edges = {},
    }
  end

  ---The one `file-holds-many-modules` finding, or `nil`.
  ---@param node table
  ---@return Documentation.Finding?
  local function fired(node)
    local hit
    for _, f in ipairs(check.run(make_ir(node), opts)) do
      if f.check == "file-holds-many-modules" then
        ok(hit == nil, "many-modules: at most one finding per node")
        hit = f
      end
    end
    return hit
  end

  ---The same, for a case that must fire — so the assertions after it are
  ---not each one nil check.
  ---@param node table
  ---@param msg string
  ---@return Documentation.Finding finding
  ---@return table<string, any> params Its params, which every built-in check carries.
  local function must_fire(node, msg)
    local hit = fired(node)
    ok(hit, msg)
    assert(hit)
    return hit, assert(hit.params)
  end

  -- ---------------------------------------------------------------------
  -- Silent where the file is the module.
  -- ---------------------------------------------------------------------

  -- A Lua tree, which has no owning module construct at all.
  eq(
    fired({
      source = "lua/a/init.lua",
      module = "a",
      functions = { fn("M.one"), fn("M.two") },
    }),
    nil,
    "many-modules: free functions alone are the file's own surface"
  )

  -- One `defmodule` in one `.ex` file: the file *is* the module, and Elixir
  -- sets `owner_kind = "module"` on every function it holds.
  eq(
    fired({
      source = "lib/a.ex",
      module = "A",
      functions = { fn("A.one", "A", "module"), fn("A.two", "A", "module") },
    }),
    nil,
    "many-modules: a single defmodule is the file's identity, not a second one"
  )

  -- Three classes in one file is ordinary Python. A class is not a module:
  -- its methods belong to the file the same way a free function does.
  eq(
    fired({
      source = "src/a.py",
      functions = {
        fn("A.m", "A", "class"),
        fn("B.m", "B", "class"),
        fn("C.m", "C", "class"),
      },
    }),
    nil,
    "many-modules: classes are not module identities"
  )

  -- `mod x { … }` with nothing outside it: one identity in the file, even
  -- though it is written one level in.
  eq(
    fired({
      source = "src/lib.rs",
      functions = { fn("x::one", "x", "module") },
    }),
    nil,
    "many-modules: an inline module alone is one identity"
  )

  -- ---------------------------------------------------------------------
  -- Test modules do not count.
  -- ---------------------------------------------------------------------

  eq(
    fired({
      source = "src/lib.rs",
      functions = { fn("x::one", "x", "module"), fn("tests::t", "tests", "module") },
    }),
    nil,
    "many-modules: `mod tests` is not an identity of its own"
  )

  -- Qualified, because a scope name arrives with its enclosing path: the
  -- last segment is what decides.
  eq(
    fired({
      source = "src/lib.rs",
      functions = { fn("x::one", "x", "module"), fn("x::tests::t", "x::tests", "module") },
    }),
    nil,
    "many-modules: a nested `mod tests` is read off the last segment"
  )

  -- ---------------------------------------------------------------------
  -- Fires where the identities are genuinely several.
  -- ---------------------------------------------------------------------

  local three, three_p = must_fire({
    source = "lib/a.ex",
    name = "a",
    functions = {
      fn("A.one", "A", "module"),
      fn("B.one", "B", "module"),
      fn("C.one", "C", "module"),
    },
  }, "many-modules: three defmodules in one .ex file is the case this is for")
  eq(three.severity, "info", "many-modules: info — Elixir is written this way on purpose")
  eq(three_p.count, 3, "many-modules: counts the identities, not the functions")
  eq(three_p.modules, "A, B, C", "many-modules: names them in source order")
  eq(three_p.file, "lib/a.ex", "many-modules: reports the source file")
  eq(
    findings.format(three),
    "lib/a.ex holds 3 module identities the map cannot separate: A, B, C",
    "many-modules: renders through the catalog"
  )

  -- `mod x { … }` beside a free function: the file has a surface of its own
  -- *and* holds another module.
  local _, mixed = must_fire({
    source = "src/lib.rs",
    name = "lib",
    functions = { fn("one"), fn("x::one", "x", "module") },
  }, "many-modules: an inline module beside the file's own functions is two")
  eq(mixed.count, 2, "many-modules: the file's own identity counts as one")
  eq(mixed.modules, "lib, x", "many-modules: the file's identity is named first, from the node")

  -- The same, with the file's own surface written as an `impl` block rather
  -- than as free functions — owned, but not by a module.
  local _, impls = must_fire({
    source = "src/lib.rs",
    name = "lib",
    functions = { fn("Widget::new", "Widget", "impl"), fn("x::one", "x", "module") },
  }, "many-modules: an `impl` block is the file's own surface too")
  eq(impls.modules, "lib, x", "many-modules: `impl` members count toward the file")

  -- A declared `@module` is preferred over the node name for the file's own
  -- identity: that is the name a reader knows the file by, and the node name
  -- is only what is left when nothing declared one.
  local _, declared = must_fire({
    source = "src/lib.rs",
    name = "lib",
    module = "mycrate",
    functions = { fn("one"), fn("x::one", "x", "module") },
  }, "many-modules: fires the same with a declared module")
  eq(
    declared.modules,
    "mycrate, x",
    "many-modules: the declared @module names the file's own identity"
  )
end
