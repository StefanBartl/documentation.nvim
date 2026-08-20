-- TESTS/lang_kotlin_spec.lua — documentation.core.lang.kotlin
--
-- Skips when the kotlin parser is not reachable; `DOCMAP_KOTLIN_PARSER`
-- points at one without installing it into a runtimepath.
--
-- Kotlin is the third answer this tool has met to the question "what does an
-- absent visibility modifier mean". C# says private, Java says
-- package-private, Kotlin says **public** — and most Kotlin declares no
-- modifier at all, so getting it wrong would report an entire codebase as
-- unpublished.

return function(H)
  local eq, ok = H.eq, H.ok

  local explicit = os.getenv("DOCMAP_KOTLIN_PARSER")
  local ok_add, has_kt
  if explicit and explicit ~= "" then
    ok_add, has_kt = pcall(vim.treesitter.language.add, "kotlin", { path = explicit })
  else
    ok_add, has_kt = pcall(vim.treesitter.language.add, "kotlin")
  end

  local kt = require("documentation.core.lang_registry").get("kotlin")
  ok(kt ~= nil, "the kotlin backend must be registered")

  eq(kt.is_source("Widget.kt"), true)
  eq(kt.is_source("build.gradle.kts"), true, "a Kotlin script is a Kotlin source file")
  eq(kt.is_source("build.gradle"), false, "a Groovy build file is not")
  eq(kt.module_tag, false, "a package declaration is a language construct, not a doc tag")
  eq(kt.param_docs, true, "KDoc's @param names each one, as Javadoc's does")

  if not (ok_add and has_kt) then
    ok(true, "lang.kotlin: kotlin parser not installed — skipping the rest")
    return
  end

  -- Written to a *named* file rather than to `H.tmpfile`, because the module
  -- name is package plus file stem — a temp name would make the assertion
  -- about `41.kt`.
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local function write(name, body)
    local file = dir .. "/" .. name
    local fw = assert(io.open(file, "w"))
    fw:write(body)
    fw:close()
    return file
  end

  local file = write(
    "Widget.kt",
    table.concat({
      "// Copyright (c) Somebody.",
      "",
      "package acme.widgets",
      "",
      "import java.io.File",
      "import acme.other.Thing as Alias",
      "",
      "/** How many. */",
      "const val MAX = 10",
      "",
      "/**",
      " * A widget that does things.",
      " *",
      " * @property name The name.",
      " */",
      "class Widget(val name: String) {",
      "    private var count: Int = 0",
      "",
      "    /**",
      "     * Adds two numbers.",
      "     *",
      "     * @param x The first number.",
      "     * @param y The second number,",
      "     *   continued on a new line.",
      "     * @return Their sum.",
      "     */",
      "    fun add(x: Int, y: Int): Int = x + y",
      "",
      "    /** Not published. */",
      "    private fun helper(): Int = 42",
      "",
      "    internal fun moduleOnly() {}",
      "",
      "    protected fun guarded() {}",
      "}",
      "",
      "/** An interface. */",
      "interface Doer {",
      "    /** Do it. */",
      "    fun go(n: Int)",
      "}",
      "",
      "/** A top-level function. */",
      "fun freeStanding(s: String): String = s",
      "",
    }, "\n")
  )

  -- ---------------------------------------------------------------------
  -- The header. A *type* is preferred over a property, because a file that
  -- opens with `const val MAX = 10` would otherwise take "How many." as its
  -- summary — true of the constant and silent about the file.
  -- ---------------------------------------------------------------------
  local header = kt.parse_header(file)
  eq(header.module, "acme.widgets.Widget", "package plus file stem, the shape java.lua established")
  eq(
    header.summary,
    "A widget that does things.",
    "the first *type*, not the first declaration — a top-level constant above "
      .. "the class is the common case in Kotlin, not a corner"
  )
  ok(
    not header.summary:match("Copyright"),
    "a license banner is a `//` comment and only `/**` is documentation"
  )

  local fns, _, requires, symbols = kt.scan_file(file)
  local by = {}
  for _, fn in ipairs(fns) do
    by[fn.name] = fn
  end

  -- ---------------------------------------------------------------------
  -- Four visibilities, and the default that is neither C#'s nor Java's.
  -- ---------------------------------------------------------------------
  eq(
    by["Widget.add"].internal,
    false,
    "**no modifier is public in Kotlin** — C# says private and Java says "
      .. "package-private for the same silence"
  )
  eq(by["Widget.helper"].internal, true, "explicitly private")
  eq(by["Widget.guarded"].internal, true, "protected is not published")
  eq(
    by["Widget.moduleOnly"].internal,
    true,
    "`internal` is this compilation module — from outside it answers like private, "
      .. "the same collapse Java's protected and Rust's pub(crate) get"
  )
  eq(
    by["Doer.go"].internal,
    false,
    "an interface member with no modifier is public — the fifth language to "
      .. "need this, after C#, Go, Rust and PHP"
  )
  eq(by["freeStanding"].internal, false, "and a top-level function is public by default too")

  -- ---------------------------------------------------------------------
  -- KDoc, including the tag no other language here has.
  -- ---------------------------------------------------------------------
  eq(#by["Widget.add"].params, 2)
  eq(by["Widget.add"].params[1].name, "x")
  eq(by["Widget.add"].params[1].desc, "The first number.")
  eq(
    by["Widget.add"].params[2].desc,
    "The second number, continued on a new line.",
    "a description continued on the next line is joined"
  )
  eq(#by["Widget.add"].returns, 1)
  eq(by["Widget.add"].signature, "Widget.add(x, y)")

  -- `@property` documents a constructor parameter that is also a property.
  -- In a `data class` that is the only place the fields are described, so
  -- reading it as anything but a parameter would leave every data class
  -- undocumented.
  local data = write(
    "Point.kt",
    table.concat({
      "package acme",
      "",
      "/**",
      " * A point.",
      " *",
      " * @property x The horizontal one.",
      " * @property y The vertical one.",
      " */",
      "data class Point(val x: Int, val y: Int)",
      "",
    }, "\n")
  )
  local _, _, _, dsym = kt.scan_file(data)
  local ds = {}
  for _, s in ipairs(dsym) do
    ds[s.name] = s
  end
  eq(ds["Point"].summary, "A point.")
  eq(ds["Point.x"] ~= nil, true, "a primary-constructor `val` is a property")
  eq(ds["Point.y"] ~= nil, true)

  -- ---------------------------------------------------------------------
  -- Imports and symbols.
  -- ---------------------------------------------------------------------
  local mods = {}
  for _, r in ipairs(requires) do
    mods[r.module] = true
  end
  eq(mods["java.io.File"], true)
  eq(mods["acme.other.Thing"], true, "an alias names the same declaration")

  local sym = {}
  for _, s in ipairs(symbols) do
    sym[s.name] = s
  end
  eq(sym["MAX"].kind, "constant", "`const val` is a constant, a plain `var` a binding")
  eq(sym["MAX"].summary, "How many.")
  eq(sym["Widget"].detail, "class")
  eq(sym["Doer"].detail, "interface", "`interface` and `class` share a node type here")
  eq(sym["Widget.count"].kind, "binding")
  eq(sym["Widget.name"] ~= nil, true, "and the constructor's `val name` is one too")

  local markers = require("documentation.core.markers")
  eq(#markers.scan_source("// TODO: finish this", kt), 1)
end
