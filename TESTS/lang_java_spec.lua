-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/lang_java_spec.lua — documentation.core.lang.java
--
-- Skips when the java treesitter parser is not reachable, the same
-- precedent `lang_js_spec.lua` and `lang_zig_spec.lua` set and for the same
-- reason: CI does not install a grammar this repository does not vendor.
-- Every assertion below was run against a real parse during development,
-- with a grammar built from `tree-sitter/tree-sitter-java`.
--
-- `DOCMAP_JAVA_PARSER` is honoured so the grammar can be pointed at without
-- installing it into a runtimepath — which is how it was verified here, and
-- is the difference between this spec being skippable and being unrunnable.

return function(H)
  local eq, ok = H.eq, H.ok

  -- `pcall` alone is not enough: `language.add` returns a falsy value rather
  -- than erroring when it cannot find the parser, so the pcall reports
  -- success even when nothing was added.
  local explicit = os.getenv("DOCMAP_JAVA_PARSER")
  local ok_add, has_java
  if explicit and explicit ~= "" then
    ok_add, has_java = pcall(vim.treesitter.language.add, "java", { path = explicit })
  else
    ok_add, has_java = pcall(vim.treesitter.language.add, "java")
  end
  if not (ok_add and has_java) then
    ok(true, "lang.java: java parser not installed — skipping (see this file's header)")
    return
  end

  local java = require("documentation.core.lang_registry").get("java")
  ok(java ~= nil, "the java backend must be registered")

  local fixture = H.tmpfile(".java")
  -- Deliberately named `Greeter.java`: the module name is the package plus
  -- the *file's* stem, so a fixture whose name does not matter would let a
  -- wrong implementation pass by reading the class name instead.
  fixture = fixture:gsub("[^/\\]+%.java$", "Greeter.java")
  local fw = assert(io.open(fixture, "w"))
  fw:write(table.concat({
    "package com.example.app;",
    "",
    "import java.util.List;",
    "import static java.util.Collections.emptyList;",
    "",
    "/**",
    " * Greets people.",
    " * More about greeting.",
    " */",
    "public class Greeter {",
    "",
    "    /**",
    "     * Greet one person.",
    "     *",
    "     * @param name who to greet, which may be",
    "     *             longer than one line",
    "     * @return the greeting",
    "     * @deprecated use greetAll instead",
    "     */",
    "    @Override",
    "    public String greet(String name) {",
    '        return "hi " + name;',
    "    }",
    "",
    "    private int count(List<String> xs) {",
    "        return xs.size();",
    "    }",
    "",
    "    protected void log() {",
    "    }",
    "",
    "    public Greeter() {",
    "    }",
    "}",
    "",
  }, "\n"))
  fw:close()

  -- ---------------------------------------------------------------------
  -- Java states its own identity, so the header reports a real fully
  -- qualified name rather than a path-derived guess.
  -- ---------------------------------------------------------------------
  local header = java.parse_header(fixture)
  eq(header.module, "com.example.app.Greeter")
  eq(header.summary, "Greets people.")
  ok(
    header.body:find("More about greeting.", 1, true) ~= nil,
    "the whole block, not the first line"
  )

  local fns, _, requires, _, _, _, lines = java.scan_file(fixture)

  eq(lines, 34)
  eq(#fns, 4, "three methods and the constructor")

  local by = {}
  for _, f in ipairs(fns) do
    by[f.name] = f
  end

  -- ---------------------------------------------------------------------
  -- Methods are qualified by their owning type; a constructor is not, since
  -- it is already named after it.
  -- ---------------------------------------------------------------------
  ok(by["Greeter.greet"] ~= nil, "a method carries its type")
  ok(by["Greeter"] ~= nil, "a constructor does not become Greeter.Greeter")

  local greet = by["Greeter.greet"]
  eq(greet.summary, "Greet one person.")
  eq(greet.signature, "greet(String name)")
  -- The annotation, not the `public` keyword: `@Override` is part of the
  -- declaration's own `modifiers` node, so the grammar says the declaration
  -- begins there. Asserted as measured rather than as assumed — a line
  -- number that points one line above what a reader calls the declaration
  -- is still inside it, and the alternative is second-guessing the parser.
  eq(greet.line, 20, "the declaration including its annotations, not the Javadoc above it")

  -- ---------------------------------------------------------------------
  -- The block tags are a contract, not prose: a parameter's description
  -- comes from `@param` and continues across lines, exactly as Javadoc has
  -- allowed for decades.
  -- ---------------------------------------------------------------------
  eq(#greet.params, 1)
  eq(greet.params[1].name, "name")
  eq(greet.params[1].desc, "who to greet, which may be longer than one line")
  eq(#greet.returns, 1)
  eq(greet.returns[1].desc, "the greeting")
  eq(greet.deprecated, "use greetAll instead")
  ok(greet.body:find("@param", 1, true) == nil, "tags are parsed out of the prose, not left in it")

  -- ---------------------------------------------------------------------
  -- Visibility is four-valued in Java and two-valued here: `public` is the
  -- published surface and the other three are not. Read off the grammar's
  -- `modifiers` node, never from the text.
  -- ---------------------------------------------------------------------
  eq(greet.internal, false, "public is the published surface")
  eq(by["Greeter.count"].internal, true, "private is not")
  eq(by["Greeter.log"].internal, true, "protected is not published either")
  eq(
    by["Greeter.count"].summary,
    "",
    "an undocumented method has no summary rather than a wrong one"
  )

  -- ---------------------------------------------------------------------
  -- `import` is the require edge, and a static import is recorded by the
  -- type that owns the member — the edge is between files, and a member is
  -- not one.
  -- ---------------------------------------------------------------------
  local mods = {}
  for _, r in ipairs(requires) do
    mods[r.module] = r.line
  end
  eq(mods["java.util.List"], 3)
  eq(mods["java.util.Collections"], 4, "a static import names its owning type")

  -- ---------------------------------------------------------------------
  -- The contract fields that decide how the rest of the engine treats this
  -- backend. Asserted here rather than left to `backend_contract_spec`,
  -- which checks that they exist and not that they are right.
  -- ---------------------------------------------------------------------
  eq(java.module_tag, false, "a package declaration is a language feature, not a doc tag")
  eq(java.module_file, nil, "a directory is a package, which is a namespace and not a module")
  eq(java.grammar, "java")
  eq(java.is_source("Thing.java"), true)
  eq(java.is_source("README.md"), false)
  eq(#java.block_comments, 1, "Javadoc is a block comment, and markers.lua needs to know it")

  -- ---------------------------------------------------------------------
  -- Module-scope symbols, added 2026-08-20. Java was one of four backends
  -- the parity audit found reporting none at all, which no single language
  -- makes visible.
  --
  -- **A Java field is the module-scope binding**, because Java has no
  -- module scope: everything lives in a type. A second fixture rather than
  -- fields added to `Greeter.java`, so the line count and function
  -- assertions above keep meaning what they were written to mean.
  -- ---------------------------------------------------------------------
  do
    local f2 = H.tmpfile(".java"):gsub("[^/\\]+%.java$", "Config.java")
    local fh = assert(io.open(f2, "w"))
    fh:write(table.concat({
      "package com.example.app;",
      "",
      "public class Config {",
      "    /** How many at once. */",
      "    public static final int MAX = 10;",
      "",
      "    private String name;",
      "",
      "    public int count = 0;",
      "",
      "    public static class Inner {",
      "        static final int MAX = 3;",
      "    }",
      "}",
      "",
    }, "\n"))
    fh:close()

    local _, _, _, symbols = java.scan_file(f2)
    local fields = {}
    for _, s2 in ipairs(symbols) do
      fields[s2.name] = s2
    end

    -- Qualified with the owning type, for the reason the methods above are:
    -- `Config.MAX` and `Config.Inner.MAX` are two fields that share a
    -- spelling, and one name for both would lose the distinction.
    ok(fields["Config.MAX"] ~= nil, "a field is qualified by the type that holds it")
    ok(fields["Inner.MAX"] ~= nil, "including one in an inner class, qualified by its nearest type")
    eq(fields["Config.MAX"].summary, "How many at once.", "the Javadoc is parsed, not shown raw")

    -- `static final` is the constant, and it is the language's own
    -- distinction rather than a guess: a non-final field can be reassigned,
    -- and a `final` instance field is per-object state. Neither is what
    -- "constant" means in the other twenty-two backends.
    eq(fields["Config.MAX"].kind, "constant")
    eq(fields["Config.name"].kind, "binding", "private, but not a constant")
    eq(fields["Config.count"].kind, "binding", "public and mutable is still a binding")
  end
end
