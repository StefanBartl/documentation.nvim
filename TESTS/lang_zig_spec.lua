-- TESTS/lang_zig_spec.lua — documentation.core.lang.zig
--
-- Skips when the zig treesitter parser is not reachable, the same precedent
-- `lang_js_spec.lua` sets and for the same reason: CI does not install a
-- grammar this repository does not vendor. The assertions below were run
-- against a real parse during development, with a grammar built from
-- `tree-sitter-grammars/tree-sitter-zig` for that purpose, and they run
-- again wherever the parser happens to be present.
--
-- `DOCMAP_ZIG_PARSER` is honoured so the grammar can be pointed at without
-- installing it into a runtimepath — which is how it was verified here, and
-- is the difference between this spec being skippable and being unrunnable.

return function(H)
  local eq, ok = H.eq, H.ok

  -- `pcall` alone is not enough: `language.add` returns a falsy value rather
  -- than erroring when it cannot find the parser, so the pcall reports
  -- success even when nothing was added.
  local explicit = os.getenv("DOCMAP_ZIG_PARSER")
  local ok_add, has_zig
  if explicit and explicit ~= "" then
    ok_add, has_zig = pcall(vim.treesitter.language.add, "zig", { path = explicit })
  else
    ok_add, has_zig = pcall(vim.treesitter.language.add, "zig")
  end
  if not (ok_add and has_zig) then
    ok(true, "lang.zig: zig parser not installed — skipping (see this file's header)")
    return
  end

  local zig = require("documentation.core.lang_registry").get("zig")
  ok(zig ~= nil, "the zig backend must be registered")

  local fixture = H.tmpfile(".zig")
  local fw = assert(io.open(fixture, "w"))
  fw:write(table.concat({
    "//! A module of two things.",
    "//! Second line of the module doc.",
    "",
    'const std = @import("std");',
    'const helper = @import("helper.zig");',
    "",
    "/// Add two numbers.",
    "/// Returns their sum.",
    "pub fn add(a: i32, b: i32) i32 {",
    "    return a + b;",
    "}",
    "",
    "fn private(x: u8) void {",
    "    _ = x;",
    "}",
    "",
    "pub const Thing = struct {",
    "    /// A method on Thing.",
    "    pub fn go(self: *Thing) void {",
    "        _ = self;",
    "    }",
    "};",
    "",
  }, "\n"))
  fw:close()

  -- ---------------------------------------------------------------------
  -- `//!` is the file's own documentation — a language feature here, not a
  -- comment convention, which is why this needs no tag to look for.
  -- ---------------------------------------------------------------------
  local header = zig.parse_header(fixture)
  eq(header.summary, "A module of two things.")
  eq(header.module, nil, "Zig has no module tag: the path is the identity")
  ok(header.body:find("Second line", 1, true) ~= nil, "the rest of the block survives")

  local fns, _, requires, symbols, _, _, lines = zig.scan_file(fixture)

  eq(lines, 22)
  eq(#fns, 3, "both top-level functions and the one inside the struct")

  local by = {}
  for _, f in ipairs(fns) do
    by[f.name] = f
  end

  -- ---------------------------------------------------------------------
  -- `///` documents the declaration below it. The block is the *run* of
  -- lines immediately above, which is why comments are read positionally
  -- rather than off the declaration node.
  -- ---------------------------------------------------------------------
  eq(by.add.summary, "Add two numbers.")
  ok(by.add.body:find("Returns their sum.", 1, true) ~= nil, "the whole block, not the first line")
  eq(by.add.signature, "add(a: i32, b: i32)")
  eq(by.add.line, 9)

  -- ---------------------------------------------------------------------
  -- Visibility is a fact from the grammar, not an inference from a leading
  -- underscore — the thing every other language in this tool has to guess.
  -- ---------------------------------------------------------------------
  eq(by.add.internal, false, "pub fn is exported")
  eq(by.private.internal, true, "bare fn is not")
  eq(by.private.summary, "", "an undocumented function has no summary rather than a wrong one")

  eq(by.go.internal, false, "pub inside a struct is still pub")
  eq(by.go.summary, "A method on Thing.")

  -- ---------------------------------------------------------------------
  -- `@import` is the require edge, and both shapes appear: a package name
  -- and a file path. Only the second can resolve inside this tree, which is
  -- a distinction `deps.lua` already draws — this backend's job is to
  -- report both and decide neither.
  -- ---------------------------------------------------------------------
  local mods = {}
  for _, r in ipairs(requires) do
    mods[r.module] = r.line
  end
  eq(mods["std"], 4)
  eq(mods["helper.zig"], 5)

  -- ---------------------------------------------------------------------
  -- The contract fields that decide how the rest of the engine treats this
  -- backend. Asserted here rather than left to `backend_contract_spec`,
  -- which checks that they *exist* and not that they are right.
  -- ---------------------------------------------------------------------
  eq(zig.module_tag, false, "no tag can be missing when the path is the identity")
  eq(zig.module_file, nil, "Zig has no directory-owns-a-module convention")
  eq(zig.grammar, "zig")
  eq(zig.is_source("build.zig"), true)
  eq(zig.is_source("README.md"), false)
  eq(#zig.block_comments, 0, "Zig has no block comment, deliberately")

  -- ---------------------------------------------------------------------
  -- Module-scope symbols, added 2026-08-20 because the parity audit found
  -- Zig among four backends that reported none at all -- invisible from
  -- inside any one language, obvious in a table across all of them.
  -- ---------------------------------------------------------------------
  do
    local sym = {}
    for _, s2 in ipairs(symbols) do
      sym[s2.name] = s2
    end

    ok(sym.Thing ~= nil, "a top-level `pub const` is a symbol")
    eq(sym.Thing.kind, "constant", "`const` is the constant, `var` the binding")

    -- The two `@import` bindings are dependencies, and the require edges
    -- above already carry them. Reporting them here as well would be one
    -- fact in two places -- the same line `core/symbols.lua` draws for
    -- Lua's own `local fs = require(...)`.
    eq(sym.std, nil, "an @import binding is a dependency, not a symbol")
    eq(sym.helper, nil, "both of them")

    -- Module scope only: `_ = x` inside `private` and `_ = self` inside
    -- `go` are statements, not declarations, but a `const` inside a
    -- function body would be the real test of the anchor -- so it is worth
    -- stating that nothing from inside a body appears.
    for _, s2 in ipairs(symbols) do
      ok(s2.name == "Thing", "only the module-scope declaration is reported, found " .. s2.name)
    end
  end
end
