-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/lang_dart_spec.lua — documentation.core.lang.dart
--
-- Skips when the dart parser is not reachable; `DOCMAP_DART_PARSER` points at
-- one without installing it into a runtimepath.
--
-- Dart is the one language here where the leading underscore is a **fact**:
-- Lua, the ECMA family and Python all use `_name` as a convention nothing
-- enforces, and Dart's compiler makes it genuinely unreachable outside the
-- library. So its visibility sits beside Go's capitalisation rather than
-- beside Python's habit.
--
-- The fixture carries an abstract class on purpose. An abstract method has
-- no body, so it parses as a `declaration` wrapping a `function_signature`
-- rather than as a `method_signature` — and reading that node as a field
-- dropped every member of the one construct whose whole content is its
-- members.

return function(H)
  local eq, ok = H.eq, H.ok

  local explicit = os.getenv("DOCMAP_DART_PARSER")
  local ok_add, has_dt
  if explicit and explicit ~= "" then
    ok_add, has_dt = pcall(vim.treesitter.language.add, "dart", { path = explicit })
  else
    ok_add, has_dt = pcall(vim.treesitter.language.add, "dart")
  end

  local dt = require("documentation.core.lang_registry").get("dart")
  ok(dt ~= nil, "the dart backend must be registered")

  eq(dt.is_source("widget.dart"), true)
  eq(dt.is_source("pubspec.yaml"), false, "a manifest is not a source file")
  eq(dt.module_tag, false, "a Dart library is its file")
  eq(
    dt.param_docs,
    false,
    "dartdoc refers to a parameter as `[x]` inside Markdown prose — a "
      .. "cross-reference, not a slot, so there is nothing to match"
  )

  if not (ok_add and has_dt) then
    ok(true, "lang.dart: dart parser not installed — skipping the rest")
    return
  end

  local function write(body)
    local file = H.tmpfile(".dart")
    local fw = assert(io.open(file, "w"))
    fw:write(body)
    fw:close()
    return file
  end

  local file = write(table.concat({
    "// Copyright (c) Somebody.",
    "",
    "import 'dart:io';",
    "import 'package:http/http.dart' as http;",
    "import 'helpers.dart';",
    "",
    "/// How many.",
    "const int maxCount = 10;",
    "",
    "/// A widget that does things.",
    "///",
    "/// More detail here.",
    "class Widget {",
    "  /// The name.",
    "  final String name;",
    "",
    "  int _count = 0;",
    "",
    "  /// Builds one.",
    "  Widget(this.name);",
    "",
    "  /// Adds two numbers.",
    "  int add(int x, int y) => x + y;",
    "",
    "  /// Not published.",
    "  int _helper() => 42;",
    "",
    "  /// Takes named and optional parameters.",
    "  void configure(int a, {int? b, String c = 'x'}) {}",
    "}",
    "",
    "/// An abstract class.",
    "abstract class Doer {",
    "  /// Do it.",
    "  void go(int n);",
    "}",
    "",
    "/// A top-level function.",
    "String freeStanding(String s) => s;",
    "",
    "void _privateTopLevel() {}",
    "",
  }, "\n"))

  local header = dt.parse_header(file)
  eq(header.summary, "A widget that does things.", "the first type's `///` block")
  ok(header.body:match("More detail"))
  ok(
    not header.summary:match("Copyright"),
    "the grammar calls a `//` line `comment` and a `///` line "
      .. "`documentation_comment`, so the banner is skipped without a rule"
  )

  local fns, _, requires, symbols = dt.scan_file(file)
  local by = {}
  for _, fn in ipairs(fns) do
    by[fn.name] = fn
  end

  -- ---------------------------------------------------------------------
  -- Visibility, which the compiler enforces.
  -- ---------------------------------------------------------------------
  eq(by["Widget.add"].internal, false)
  eq(
    by["Widget._helper"].internal,
    true,
    "`_name` is library-private and genuinely unreachable — a fact, not a request"
  )
  eq(by["_privateTopLevel"].internal, true, "and it applies at the top level too")
  eq(
    by["Doer.go"].internal,
    false,
    "an abstract method is a `declaration` wrapping a `function_signature`, "
      .. "not a `method_signature` — reading it as a field dropped every "
      .. "member of every abstract class"
  )
  eq(by["Doer.go"].summary, "Do it.")
  eq(by["Widget.Widget"] ~= nil, true, "and a constructor is a function too")
  eq(by["Widget.Widget"].summary, "Builds one.")

  -- Dart uses `{named}` and `[optional]` parameter groups heavily; missing
  -- them would drop most of Flutter's parameters.
  eq(
    by["Widget.configure"].signature,
    "Widget.configure(a, b, c)",
    "named and optional groups nest one level deeper and are still parameters"
  )

  -- ---------------------------------------------------------------------
  -- Imports: only a relative one names a file in this tree.
  -- ---------------------------------------------------------------------
  local mods = {}
  for _, r in ipairs(requires) do
    mods[r.module] = true
  end
  eq(mods["dart:io"], true, "the SDK, as written")
  eq(mods["package:http/http.dart"], true, "a pub package, as written")
  eq(mods["./helpers.dart"], true, "and a relative import is the file beside this one")

  local sym = {}
  for _, s in ipairs(symbols) do
    sym[s.name] = s
  end
  eq(sym["maxCount"].kind, "constant", "a top-level `const`, from a flat parse")
  eq(sym["maxCount"].summary, "How many.")
  eq(sym["Widget"].detail, "class")
  eq(sym["Doer"].detail, "abstract class", "`abstract` is read from the text, not the node name")
  eq(sym["Widget.name"].kind, "constant", "`final` is a constant")
  eq(sym["Widget.name"].summary, "The name.")
  eq(sym["Widget._count"].kind, "binding")

  local markers = require("documentation.core.markers")
  eq(#markers.scan_source("// TODO: finish this", dt), 1)
end
