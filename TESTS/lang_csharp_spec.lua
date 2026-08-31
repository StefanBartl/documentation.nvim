-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/lang_csharp_spec.lua — documentation.core.lang.csharp
--
-- Skips when the c_sharp parser is not reachable, the precedent
-- `lang_js_spec.lua` set. `DOCMAP_CSHARP_PARSER` points at one without
-- installing it into a runtimepath.
--
-- The fixture below carries an **interface** on purpose, and that is the
-- assertion this whole file is worth having for: an interface member with no
-- access modifier is public, a class member with no access modifier is
-- private, and applying the class rule to both reports every method of every
-- interface as internal — the exact inversion of the truth, on the one
-- construct that exists to declare a published API.

return function(H)
  local eq, ok = H.eq, H.ok

  local explicit = os.getenv("DOCMAP_CSHARP_PARSER")
  local ok_add, has_cs
  if explicit and explicit ~= "" then
    ok_add, has_cs = pcall(vim.treesitter.language.add, "c_sharp", { path = explicit })
  else
    ok_add, has_cs = pcall(vim.treesitter.language.add, "c_sharp")
  end

  local cs = require("documentation.core.lang_registry").get("csharp")
  ok(cs ~= nil, "the csharp backend must be registered")

  -- ---------------------------------------------------------------------
  -- Contract answers, which hold with or without a grammar installed.
  -- ---------------------------------------------------------------------
  eq(cs.is_source("Thing.cs"), true)
  eq(cs.is_source("Thing.csproj"), false, "a project file is not a source file")
  eq(cs.is_source("thing.lua"), false)
  eq(cs.grammar, "c_sharp", "the grammar is not named after the backend")
  eq(cs.module_tag, false, "a namespace is a language construct, not a doc tag")
  eq(cs.param_docs, true, '<param name="x"> names each one')

  if not (ok_add and has_cs) then
    ok(true, "lang.csharp: c_sharp parser not installed — skipping the rest")
    return
  end

  local function write(body, name)
    local file = H.tmpfile(name or ".cs")
    local fw = assert(io.open(file, "w"))
    fw:write(body)
    fw:close()
    return file
  end

  local file = write(table.concat({
    "// Copyright (c) Somebody. Licensed under MIT.",
    "",
    "using System;",
    "using System.Collections.Generic;",
    "",
    "namespace Acme.Widgets;",
    "",
    "/// <summary>",
    "/// A widget that does things.",
    "/// </summary>",
    "/// <remarks>More detail here.</remarks>",
    "public class Widget",
    "{",
    "    /// <summary>How many.</summary>",
    "    public const int Max = 10;",
    "",
    "    private int _count;",
    "",
    "    /// <summary>",
    '    /// Adds two numbers, see <see cref="Widget"/>.',
    "    /// </summary>",
    '    /// <param name="x">The first number.</param>',
    '    /// <param name="y">The second number.</param>',
    "    /// <returns>Their <c>sum</c>.</returns>",
    "    public int Add(int x, int y)",
    "    {",
    "        return x + y;",
    "    }",
    "",
    "    /// <summary>Not published.</summary>",
    "    private void Helper() { }",
    "",
    "    void Implicit() { }",
    "",
    "    protected internal void Mixed() { }",
    "}",
    "",
    "/// <summary>An interface.</summary>",
    "public interface IThing",
    "{",
    "    /// <summary>Go.</summary>",
    "    void Go();",
    "",
    "    private void Hidden() { }",
    "}",
    "",
  }, "\n"))

  -- ---------------------------------------------------------------------
  -- The header: a fully qualified module name, and no license banner.
  -- ---------------------------------------------------------------------
  local header = cs.parse_header(file)
  ok(
    header.module and header.module:match("^Acme%.Widgets%."),
    "namespace plus file stem, the shape java.lua established — got " .. tostring(header.module)
  )
  eq(header.summary, "A widget that does things.", "the first type's summary is the file's")
  ok(header.body:match("More detail"), "<remarks> joins the body")
  ok(
    not header.summary:match("Copyright"),
    "a license banner is a `//` comment, and only `///` is documentation — "
      .. "C gets this from a Doxygen rule, C# gets it from the language"
  )

  local fns, _, requires, symbols = cs.scan_file(file)
  local by = {}
  for _, fn in ipairs(fns) do
    by[fn.name] = fn
  end

  -- ---------------------------------------------------------------------
  -- The two defaults. This is the section the file header is about.
  -- ---------------------------------------------------------------------
  eq(by["Widget.Add"].internal, false, "explicitly public")
  eq(by["Widget.Helper"].internal, true, "explicitly private")
  eq(by["Widget.Implicit"].internal, true, "a class member with no modifier is private")
  eq(by["Widget.Mixed"].internal, true, "protected internal is not public")
  eq(
    by["IThing.Go"].internal,
    false,
    "an interface member with no modifier is PUBLIC — an interface is nothing but published surface"
  )
  eq(
    by["IThing.Hidden"].internal,
    true,
    "and C# 8's private interface member has to be written out"
  )

  -- ---------------------------------------------------------------------
  -- XML doc comments: elements that carry structure, markup that does not.
  -- ---------------------------------------------------------------------
  eq(#by["Widget.Add"].params, 2)
  eq(by["Widget.Add"].params[1].name, "x", '<param name="x"> states the name outright')
  eq(by["Widget.Add"].params[1].desc, "The first number.")
  eq(#by["Widget.Add"].returns, 1)
  eq(
    by["Widget.Add"].returns[1].desc,
    "Their sum.",
    "<c> is formatting and leaves no brackets behind"
  )
  eq(
    by["Widget.Add"].summary,
    "Adds two numbers, see Widget.",
    "a <see cref> keeps the name it referenced and drops the tag around it"
  )
  eq(by["Widget.Add"].signature, "Widget.Add(x, y)")

  -- ---------------------------------------------------------------------
  -- Types, members and usings.
  -- ---------------------------------------------------------------------
  local sym = {}
  for _, s in ipairs(symbols) do
    sym[s.name] = s
  end
  eq(sym["Widget"].kind, "table")
  eq(sym["Widget"].detail, "class")
  eq(sym["IThing"].detail, "interface")
  eq(sym["Widget.Max"].kind, "constant", "`const` is a constant, a plain field is a binding")
  eq(sym["Widget._count"].kind, "binding")

  local mods = {}
  for _, r in ipairs(requires) do
    mods[r.module] = true
  end
  eq(mods["System"], true)
  eq(mods["System.Collections.Generic"], true, "a qualified using is one name, not three")

  -- ---------------------------------------------------------------------
  -- The block namespace form, which is still what older code is written in,
  -- and the type kinds a modern file mixes.
  -- ---------------------------------------------------------------------
  local block = write(table.concat({
    "namespace Acme.Old",
    "{",
    "    /// <summary>Old style.</summary>",
    "    public record Point(int X, int Y);",
    "",
    "    public enum Color { Red, Green }",
    "",
    "    public struct S { public int F; }",
    "",
    "    public class C",
    "    {",
    "        /// <summary>A property.</summary>",
    "        public int Size { get; set; }",
    "",
    "        /// <summary>Ctor.</summary>",
    "        public C(int n) { }",
    "    }",
    "}",
    "",
  }, "\n"))

  local bh = cs.parse_header(block)
  ok(bh.module and bh.module:match("^Acme%.Old%."), "a block namespace names the module too")
  eq(bh.summary, "Old style.")

  local bfns, _, _, bsym = cs.scan_file(block)
  local bs = {}
  for _, s in ipairs(bsym) do
    bs[s.name] = s
  end
  eq(bs["Point"].detail, "record")
  eq(bs["Color"].detail, "enum")
  eq(bs["S"].detail, "struct")
  eq(bs["C.Size"].detail, "property")
  eq(bs["C.Size"].summary, "A property.")

  local bby = {}
  for _, fn in ipairs(bfns) do
    bby[fn.name] = fn
  end
  eq(bby["C.C"] ~= nil, true, "a constructor is a function, named the way C# names it")

  -- ---------------------------------------------------------------------
  -- A `///` comment with no <summary> at all. The compiler warns about it
  -- and people write it anyway — so it is read as prose rather than
  -- discarded, which is the lesson C's plain-comment rule taught.
  -- ---------------------------------------------------------------------
  local loose = write(table.concat({
    "public class L",
    "{",
    "    /// Just a sentence, no element around it.",
    "    public void M() { }",
    "}",
    "",
  }, "\n"))
  eq(cs.scan_file(loose)[1].summary, "Just a sentence, no element around it.")

  -- A file with no namespace keeps no module rather than being given its
  -- bare stem, which would claim a global-namespace type is a module named
  -- after its file — true of the path, not of the language.
  eq(cs.parse_header(loose).module, nil)

  -- ---------------------------------------------------------------------
  -- A `#if` block is a container, not a leaf. Found by scanning `serilog`,
  -- where skipping preprocessor nodes lost three of thirty-six usings — and,
  -- more than that, ten functions and eleven symbols that live only inside a
  -- conditional branch.
  --
  -- Every branch is read, including ones a given build would not compile:
  -- this map describes a repository, not one configuration of it.
  -- ---------------------------------------------------------------------
  local conditional = write(table.concat({
    "#if FEATURE_SPAN",
    "using System.Runtime.InteropServices;",
    "#endif",
    "",
    "namespace Acme.Cond;",
    "",
    "#if NET8_0_OR_GREATER",
    "/// <summary>Only on the new runtime.</summary>",
    "public class Modern",
    "{",
    "    /// <summary>Runs.</summary>",
    "    public void Run() { }",
    "}",
    "#else",
    "/// <summary>The fallback.</summary>",
    "public class Legacy",
    "{",
    "    /// <summary>Runs.</summary>",
    "    public void Run() { }",
    "}",
    "#endif",
    "",
  }, "\n"))

  local cfns, _, creq, csym = cs.scan_file(conditional)
  local cmods = {}
  for _, r in ipairs(creq) do
    cmods[r.module] = true
  end
  eq(cmods["System.Runtime.InteropServices"], true, "a using inside #if is still a using")

  local cnames = {}
  for _, sym2 in ipairs(csym) do
    cnames[sym2.name] = true
  end
  eq(cnames["Modern"], true, "a type inside #if")
  eq(cnames["Legacy"], true, "and the type in the #else branch, because both are maintained")
  eq(#cfns, 2, "one method from each branch")

  local markers = require("documentation.core.markers")
  eq(#markers.scan_source("// TODO: finish this", cs), 1)
end
