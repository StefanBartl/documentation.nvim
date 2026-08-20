-- TESTS/lang_cfamily_spec.lua — documentation.core.lang.c / .cpp
--
-- Skips per language when that treesitter parser is not reachable, the same
-- precedent `lang_js_spec.lua`, `lang_zig_spec.lua` and `lang_java_spec.lua`
-- set: CI does not install grammars this repository does not vendor. Every
-- assertion below was run against a real parse during development, with
-- grammars built from `tree-sitter/tree-sitter-c` and
-- `tree-sitter/tree-sitter-cpp`.
--
-- `DOCMAP_C_PARSER` and `DOCMAP_CPP_PARSER` point at grammars without
-- installing them into a runtimepath — which is how this was verified, and
-- is the difference between skippable and unrunnable.

return function(H)
  local eq, ok = H.eq, H.ok

  ---`pcall` alone is not enough: `language.add` returns a falsy value rather
  ---than erroring when it cannot find the parser, so the pcall reports
  ---success even when nothing was added.
  ---@param lang string
  ---@param env string
  ---@return boolean
  local function have(lang, env)
    local explicit = os.getenv(env)
    local ok_add, added
    if explicit and explicit ~= "" then
      ok_add, added = pcall(vim.treesitter.language.add, lang, { path = explicit })
    else
      ok_add, added = pcall(vim.treesitter.language.add, lang)
    end
    return ok_add and added and true or false
  end

  local registry = require("documentation.core.lang_registry")
  ok(registry.get("c") ~= nil, "the c backend must be registered")
  ok(registry.get("cpp") ~= nil, "the cpp backend must be registered")

  -- -------------------------------------------------------------------
  -- Contract answers, which hold with or without a grammar installed.
  -- -------------------------------------------------------------------
  local c = registry.get("c")
  local cpp = registry.get("cpp")
  eq(c.module_tag, false, "the preprocessor works on paths, so no tag can be missing")
  eq(c.module_file, nil, "C has no directory-owns-a-module convention")
  eq(c.is_source("util.h"), true, "a header is a source file this backend claims")
  eq(c.is_source("util.c"), true)
  eq(c.is_source("util.cpp"), false, "a .cpp belongs to the other registration")
  eq(cpp.is_source("thing.hpp"), true)
  eq(cpp.is_source("thing.h"), false, "a .h is claimed once, by c.lua — see its header")
  eq(#c.block_comments, 1, "/* */, which markers.lua needs to know about")

  -- =====================================================================
  -- C
  -- =====================================================================
  if not have("c", "DOCMAP_C_PARSER") then
    ok(true, "lang.c: c parser not installed — skipping (see this file's header)")
  else
    -- ------------------------------------------------------------------
    -- A source file: definitions are the functions, and a forward
    -- declaration is a duplicate of the body below it rather than a second
    -- function.
    -- ------------------------------------------------------------------
    local cfile = H.tmpfile(".c")
    local fw = assert(io.open(cfile, "w"))
    fw:write(table.concat({
      "#include <stdio.h>",
      '#include "util.h"',
      "",
      "int add(int a, int b);",
      "",
      "/**",
      " * @brief Add two numbers.",
      " * @param a the first",
      " *          addend",
      " * @return their sum",
      " */",
      "int add(int a, int b) {",
      "  return a + b;",
      "}",
      "",
      "/// A helper nobody outside this file may call.",
      "static void helper(void) {",
      "}",
      "",
    }, "\n"))
    fw:close()

    local fns, _, requires, _, _, _, lines = c.scan_file(cfile)

    -- 18 lines of source; the trailing empty entry is the final newline,
    -- not a nineteenth line.
    eq(lines, 18)
    eq(#fns, 2, "the prototype is not a second function in a .c file")

    local by = {}
    for _, f in ipairs(fns) do
      by[f.name] = f
    end

    eq(by.add.summary, "Add two numbers.", "@brief outranks the first sentence")
    eq(by.add.signature, "add(int a, int b)")
    eq(by.add.line, 12, "the definition, not the prototype above it")
    eq(#by.add.params, 1)
    eq(by.add.params[1].name, "a")
    eq(by.add.params[1].desc, "the first addend", "a tag continues across lines")
    eq(by.add.returns[1].desc, "their sum")

    -- `static` is the whole of C's visibility system, and it is exactly
    -- what `internal` records.
    eq(by.add.internal, false)
    eq(by.helper.internal, true, "static means this translation unit only")
    eq(by.helper.summary, "A helper nobody outside this file may call.", "/// is a doc block too")

    local mods = {}
    for _, r in ipairs(requires) do
      mods[r.module] = r.line
    end
    eq(
      mods["stdio.h"],
      1,
      "a system include is recorded; whether it resolves is deps.lua's question"
    )
    eq(mods["util.h"], 2)

    -- ------------------------------------------------------------------
    -- A header: the prototypes *are* the published surface. This is the
    -- declaration-vs-definition decision `MULTILANG.md` Phase 5 named, and
    -- the reason it is made per file rather than per function.
    -- ------------------------------------------------------------------
    local hfile = H.tmpfile(".h")
    local hw = assert(io.open(hfile, "w"))
    hw:write(table.concat({
      "/** Two numbers, added. */",
      "",
      "/// Add two numbers.",
      "int add(int a, int b);",
      "",
      "/// Multiply two numbers.",
      "int mul(int a, int b);",
      "",
    }, "\n"))
    hw:close()

    local hfns = c.scan_file(hfile)
    eq(#hfns, 2, "a header's prototypes are its functions, or the file reads as empty")
    local hby = {}
    for _, f in ipairs(hfns) do
      hby[f.name] = f
    end
    eq(hby.add.summary, "Add two numbers.")
    eq(hby.mul.line, 7)
    eq(hby.add.internal, false, "a header prototype is published by definition")

    local header = c.parse_header(hfile)
    eq(header.module, nil, "the path is the identity")
    eq(header.summary, "Two numbers, added.")

    -- ------------------------------------------------------------------
    -- Plain comments, which is where real C lives. Doxygen recognises only
    -- `/**`, `/*!`, `///` and `//!`; `antirez/sds` — 1328 lines, 45
    -- functions, nearly all of them commented — uses none of them, and the
    -- Doxygen-only rule found zero summaries in it. So a comment directly
    -- above a declaration documents it whatever its punctuation.
    --
    -- Two things must survive that: a license banner must not become the
    -- file's summary, and commented-out code must not become a function's.
    -- ------------------------------------------------------------------
    local plain = H.tmpfile(".c")
    local pw = assert(io.open(plain, "w"))
    pw:write(table.concat({
      "/* Copyright (c) 2026, somebody. All rights reserved. */",
      "",
      "/* Trim the string in place. */",
      "void trim(char *s) {",
      "}",
      "",
      "/* int old_trim(char *s) {",
      "     return 0;",
      "   } */",
      "void retrim(char *s) {",
      "}",
      "",
    }, "\n"))
    pw:close()

    local pfns = c.scan_file(plain)
    local pby = {}
    for _, f in ipairs(pfns) do
      pby[f.name] = f
    end
    eq(pby.trim.summary, "Trim the string in place.", "a plain block is documentation")
    eq(pby.retrim.summary, "", "commented-out code is not documentation")

    local pheader = c.parse_header(plain)
    eq(
      pheader.summary,
      "",
      "a license banner is not a file summary — the header rule wants Doxygen style"
    )
  end

  -- =====================================================================
  -- C++
  -- =====================================================================
  if not have("cpp", "DOCMAP_CPP_PARSER") then
    ok(true, "lang.cpp: cpp parser not installed — skipping (see this file's header)")
  else
    local hppfile = H.tmpfile(".hpp")
    local hw = assert(io.open(hppfile, "w"))
    hw:write(table.concat({
      "#include <vector>",
      "",
      "namespace app {",
      "",
      "class Thing {",
      "public:",
      "  /// Do the thing.",
      "  void go(int n);",
      "",
      "private:",
      "  /// Not for callers.",
      "  int check(int n);",
      "};",
      "",
      "struct Plain {",
      "  /// Structs start public.",
      "  int size(void);",
      "};",
      "",
      "}",
      "",
    }, "\n"))
    hw:close()

    local fns = cpp.scan_file(hppfile)
    local by = {}
    for _, f in ipairs(fns) do
      by[f.name] = f
    end

    eq(by.go ~= nil, true, "a member declaration in a header is a function")
    eq(by.go.summary, "Do the thing.")

    -- ------------------------------------------------------------------
    -- Access is positional in C++: everything after `private:` is private
    -- until the next specifier, a `class` starts private and a `struct`
    -- starts public. There is nothing on the member node to read, which is
    -- why this is tracked while walking.
    -- ------------------------------------------------------------------
    eq(by.go.internal, false, "after public:")
    eq(by.check.internal, true, "after private:")
    eq(by.size.internal, false, "a struct starts public")

    -- ------------------------------------------------------------------
    -- An out-of-line definition writes its own qualified name, so nothing
    -- has to be reconstructed from the enclosing scope.
    -- ------------------------------------------------------------------
    local cppfile = H.tmpfile(".cpp")
    local cw = assert(io.open(cppfile, "w"))
    cw:write(table.concat({
      '#include "thing.hpp"',
      "",
      "namespace app {",
      "",
      "/// Do the thing, at last.",
      "void Thing::go(int n) {",
      "}",
      "",
      "}",
      "",
    }, "\n"))
    cw:close()

    local dfns, _, drequires = cpp.scan_file(cppfile)
    eq(#dfns, 1)
    eq(dfns[1].name, "Thing::go", "the written name, not a reconstructed one")
    eq(dfns[1].summary, "Do the thing, at last.")
    eq(drequires[1].module, "thing.hpp")
  end

  -- ---------------------------------------------------------------------
  -- Module-scope symbols, added 2026-08-20. C and C++ were two of the four
  -- backends the parity audit found reporting none at all.
  --
  -- `#define` is here because it is *the* C idiom for a threshold: leaving
  -- it out would mean the one thing every C project uses for a constant is
  -- the one thing the Index tab cannot show.
  -- ---------------------------------------------------------------------
  do
    local f = H.tmpfile(".c")
    local fh = assert(io.open(f, "w"))
    fh:write(table.concat({
      "#define MAX_ITEMS 64",
      "",
      "/** How many are cached. */",
      "static const int CACHE = 10;",
      "",
      "static int counter;",
      "",
      "typedef struct { int x; } Point;",
      "",
      "/** Adds. */",
      "int add(int a, int b) { return a + b; }",
      "",
    }, "\n"))
    fh:close()

    local fns, _, _, symbols = c.scan_file(f)
    local by = {}
    for _, s2 in ipairs(symbols) do
      by[s2.name] = s2
    end

    eq(by.MAX_ITEMS ~= nil, true, "a #define is the C constant")
    eq(by.MAX_ITEMS.kind, "constant")
    eq(by.CACHE.kind, "constant", "`const` is what makes it one, not `static`")
    eq(by.CACHE.summary, "How many are cached.")
    eq(by.counter.kind, "binding", "no const, so a binding")
    eq(by.Point ~= nil, true, "a typedef is a named shape")
    eq(by.Point.kind, "table", "the same word go.lua uses for its own types")

    -- **A function is never also a symbol.** The same line
    -- `core/symbols.lua` draws when it refuses to report
    -- `M.foo = function(...)` in both places.
    eq(by.add, nil, "a function is reported once, as a function")
    ok(#fns >= 1, "and it is reported")

    -- The defect the field work exposed: three lines of slack reached past
    -- one declaration to the next, so `counter` inherited `CACHE`'s comment.
    -- A doc block documents one declaration.
    eq(by.counter.summary, "", "a doc block belongs to one declaration, not to the next one too")
  end
end
