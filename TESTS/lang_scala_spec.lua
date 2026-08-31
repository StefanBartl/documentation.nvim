-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/lang_scala_spec.lua — documentation.core.lang.scala
--
-- Skips when the scala parser is not reachable; `DOCMAP_SCALA_PARSER` points
-- at one without installing it into a runtimepath.
--
-- Scala is the only language here besides Rust with **qualified visibility**:
-- `private[widgets]` is private to a named scope rather than absolutely,
-- which is `pub(crate)` read from the other end. And Scala has no `public`
-- keyword at all, so the rule must be written as *not private and not
-- protected* — asking for a keyword that does not exist would report every
-- codebase as unpublished.

return function(H)
  local eq, ok = H.eq, H.ok

  local explicit = os.getenv("DOCMAP_SCALA_PARSER")
  local ok_add, has_sc
  if explicit and explicit ~= "" then
    ok_add, has_sc = pcall(vim.treesitter.language.add, "scala", { path = explicit })
  else
    ok_add, has_sc = pcall(vim.treesitter.language.add, "scala")
  end

  local sc = require("documentation.core.lang_registry").get("scala")
  ok(sc ~= nil, "the scala backend must be registered")

  eq(sc.is_source("Widget.scala"), true)
  eq(sc.is_source("build.sbt"), false, "a build file is not a source file")
  eq(sc.module_tag, false, "a package clause is a language construct, not a doc tag")
  eq(sc.param_docs, true, "Scaladoc's @param names each one, as Javadoc's does")

  if not (ok_add and has_sc) then
    ok(true, "lang.scala: scala parser not installed — skipping the rest")
    return
  end

  -- Written to a *named* file: the module name is package plus file stem.
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
    "Widget.scala",
    table.concat({
      "// Copyright (c) Somebody.",
      "",
      "package acme.widgets",
      "",
      "import java.io.File",
      "import acme.other.{Thing, Other}",
      "",
      "/** How many. */",
      "val MaxCount = 10",
      "",
      "/**",
      " * A widget that does things.",
      " *",
      " * @param name The name.",
      " */",
      "class Widget(val name: String) {",
      "  private var count: Int = 0",
      "",
      "  /**",
      "   * Adds two numbers.",
      "   *",
      "   * @tparam T The element type.",
      "   * @param x The first number.",
      "   * @param y The second number,",
      "   *   continued on a new line.",
      "   * @return Their sum.",
      "   */",
      "  def add(x: Int, y: Int): Int = x + y",
      "",
      "  /** Not published. */",
      "  private def helper(): Int = 42",
      "",
      "  private[widgets] def packageOnly(): Unit = ()",
      "",
      "  protected def guarded(): Unit = ()",
      "}",
      "",
      "/** A trait. */",
      "trait Doer {",
      "  /** Do it. */",
      "  def go(n: Int): Unit",
      "}",
      "",
      "/** A companion object. */",
      "object Widget {",
      "  /** Builds one. */",
      "  def apply(name: String): Widget = new Widget(name)",
      "}",
      "",
    }, "\n")
  )

  local header = sc.parse_header(file)
  eq(header.module, "acme.widgets.Widget", "package plus file stem")
  eq(
    header.summary,
    "A widget that does things.",
    "the first *type*, not the first definition — a top-level `val` above the "
      .. "class is ordinary in Scala too, the rule Kotlin's fixture forced"
  )
  ok(not header.summary:match("Copyright"), "a `//` banner is not a Scaladoc block")

  local fns, _, requires, symbols = sc.scan_file(file)
  local by = {}
  for _, fn in ipairs(fns) do
    by[fn.name] = fn
  end

  -- ---------------------------------------------------------------------
  -- Visibility, including the qualified form only Rust has anything like.
  -- ---------------------------------------------------------------------
  eq(
    by["Widget.add"].internal,
    false,
    "**Scala has no `public` keyword at all** — the rule is written as *not "
      .. "private and not protected*, or every codebase would read as unpublished"
  )
  eq(by["Widget.helper"].internal, true, "explicitly private")
  eq(by["Widget.guarded"].internal, true, "protected is not published")
  eq(
    by["Widget.packageOnly"].internal,
    true,
    "`private[widgets]` is private to a named scope — Rust's `pub(crate)` read "
      .. "from the other end, and from outside a restriction is a restriction"
  )
  eq(
    by["Doer.go"].internal,
    false,
    "a trait member carries no modifier and is public — the seventh language "
      .. "in a row to need this, after C#, Go, Rust, PHP, Kotlin and Swift"
  )

  -- ---------------------------------------------------------------------
  -- Scaladoc, including the tag that documents a *type* parameter.
  -- ---------------------------------------------------------------------
  eq(
    #by["Widget.add"].params,
    3,
    "`@tparam` documents a type parameter and is read as a parameter — a Scala "
      .. "generic is declared and documented exactly like a value parameter"
  )
  eq(by["Widget.add"].params[1].name, "T", "the type parameter comes first, as written")
  eq(by["Widget.add"].params[2].name, "x")
  eq(
    by["Widget.add"].params[3].desc,
    "The second number, continued on a new line.",
    "a description continued on the next line is joined"
  )
  eq(#by["Widget.add"].returns, 1)
  eq(by["Widget.add"].signature, "Widget.add(x, y)", "the signature carries the value parameters")

  -- ---------------------------------------------------------------------
  -- Imports, symbols, and the companion object.
  -- ---------------------------------------------------------------------
  local mods = {}
  for _, r in ipairs(requires) do
    mods[r.module] = true
  end
  eq(mods["java.io.File"], true)
  eq(
    mods["acme.other"],
    true,
    "`import a.b.{C, D}` is one edge to `a.b` — the same reduction Rust's " .. "use-list needed"
  )

  local seen = {}
  for _, s in ipairs(symbols) do
    seen[s.name .. "/" .. s.detail] = s
    seen[s.name] = s
  end
  eq(seen["MaxCount"] and seen["MaxCount"].kind, "constant", "a top-level val is a constant")
  eq(seen["MaxCount"].summary, "How many.")
  eq(seen["Doer/trait"] ~= nil, true, "a trait")
  eq(
    seen["Widget/class"] ~= nil and seen["Widget/object"] ~= nil,
    true,
    "**a class and its companion object are two different entities sharing one "
      .. "name**, and both are recorded — merging them would lose the one Scala "
      .. "construct that deliberately reuses a name"
  )
  eq(seen["Widget.name"] ~= nil, true, "a constructor parameter is a field")

  local markers = require("documentation.core.markers")
  eq(#markers.scan_source("// TODO: finish this", sc), 1)
end
