-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/lang_swift_spec.lua — documentation.core.lang.swift
--
-- Skips when the swift parser is not reachable; `DOCMAP_SWIFT_PARSER` points
-- at one without installing it into a runtimepath.
--
-- Swift brings two shapes nothing else here has. Its documentation is
-- **Markdown list items** — `- Parameter x:` rather than a tag — and its
-- default visibility is `internal`, meaning module-only, which is a fourth
-- answer to "what does an absent modifier mean" after C#'s private, Java's
-- package-private and Kotlin's and PHP's public.

return function(H)
  local eq, ok = H.eq, H.ok

  local explicit = os.getenv("DOCMAP_SWIFT_PARSER")
  local ok_add, has_sw
  if explicit and explicit ~= "" then
    ok_add, has_sw = pcall(vim.treesitter.language.add, "swift", { path = explicit })
  else
    ok_add, has_sw = pcall(vim.treesitter.language.add, "swift")
  end

  local sw = require("documentation.core.lang_registry").get("swift")
  ok(sw ~= nil, "the swift backend must be registered")

  eq(sw.is_source("Widget.swift"), true)
  eq(sw.is_source("Package.resolved"), false, "a manifest lock is not a source file")
  eq(sw.module_tag, false, "a Swift module is a build target, not anything written in a file")
  eq(sw.param_docs, true, "`- Parameter x:` is the language's own form, with DocC behind it")

  if not (ok_add and has_sw) then
    ok(true, "lang.swift: swift parser not installed — skipping the rest")
    return
  end

  local function write(body)
    local file = H.tmpfile(".swift")
    local fw = assert(io.open(file, "w"))
    fw:write(body)
    fw:close()
    return file
  end

  local file = write(table.concat({
    "// Copyright (c) Somebody.",
    "",
    "import Foundation",
    "import UIKit",
    "",
    "/// A widget that does things.",
    "///",
    "/// More detail here.",
    "public struct Widget {",
    "    /// How many.",
    "    public static let max = 10",
    "",
    "    private var count: Int = 0",
    "",
    "    /// Adds two numbers.",
    "    ///",
    "    /// - Parameter x: The first number.",
    "    /// - Parameter y: The second number,",
    "    ///   continued on a new line.",
    "    /// - Returns: Their sum.",
    "    public func add(x: Int, y: Int) -> Int {",
    "        return x + y",
    "    }",
    "",
    "    /// Not published.",
    "    private func helper() -> Int { 42 }",
    "",
    "    func moduleOnly() {}",
    "",
    "    fileprivate func fileOnly() {}",
    "",
    "    open func subclassable() {}",
    "}",
    "",
    "/// A protocol.",
    "public protocol Doer {",
    "    /// Do it.",
    "    func go(n: Int)",
    "}",
    "",
    "/// A free function.",
    "public func freeStanding(s: String) -> String { s }",
    "",
  }, "\n"))

  local header = sw.parse_header(file)
  eq(header.summary, "A widget that does things.", "the first type's `///` block")
  ok(header.body:match("More detail"))
  ok(
    not header.summary:match("Copyright"),
    "a license banner is a `//` comment and only `///` is documentation"
  )
  eq(header.module, nil, "there is no module name written anywhere in a Swift file")

  local fns, _, requires, symbols = sw.scan_file(file)
  local by = {}
  for _, fn in ipairs(fns) do
    by[fn.name] = fn
  end

  -- ---------------------------------------------------------------------
  -- Five visibilities, two published, and a default that is neither of the
  -- three answers this tool already had.
  -- ---------------------------------------------------------------------
  eq(by["Widget.add"].internal, false, "public is the module's surface")
  eq(by["Widget.subclassable"].internal, false, "and so is `open`")
  eq(by["Widget.helper"].internal, true, "private is not")
  eq(by["Widget.fileOnly"].internal, true, "nor is fileprivate")
  eq(
    by["Widget.moduleOnly"].internal,
    true,
    "**no modifier is `internal` in Swift** — module-only, a fourth answer "
      .. "after C#'s private, Java's package-private and Kotlin's public"
  )
  eq(
    by["Doer.go"].internal,
    false,
    "a protocol member is public and carries no modifier — the sixth language "
      .. "in a row to need this, after C#, Go, Rust, PHP and Kotlin"
  )

  -- ---------------------------------------------------------------------
  -- Documentation as Markdown bullets, which is a fourth shape after tags,
  -- prose-with-sections and XML markup.
  -- ---------------------------------------------------------------------
  eq(#by["Widget.add"].params, 2, "`- Parameter x:` is a bullet, not a tag")
  eq(by["Widget.add"].params[1].name, "x")
  eq(by["Widget.add"].params[1].desc, "The first number.")
  eq(
    by["Widget.add"].params[2].desc,
    "The second number, continued on a new line.",
    "Markdown wraps freely, so a description on two lines is ordinary and is joined"
  )
  eq(#by["Widget.add"].returns, 1)
  eq(by["Widget.add"].returns[1].desc, "Their sum.")

  -- The other spelling: `- Parameters:` opens an indented list.
  local grouped = write(table.concat({
    "/// Moves a thing.",
    "///",
    "/// - Parameters:",
    "///   - from: Where it starts.",
    "///   - to: Where it ends.",
    "/// - Returns: Whether it moved.",
    "public func move(from: Int, to: Int) -> Bool { true }",
    "",
  }, "\n"))
  local gfns = sw.scan_file(grouped)
  eq(#gfns[1].params, 2, "`- Parameters:` opens a list where each item is a parameter")
  eq(gfns[1].params[1].name, "from")
  eq(gfns[1].params[2].desc, "Where it ends.")
  eq(
    gfns[1].signature,
    "move(from, to)",
    "and the signature carries the *label*, which is what a caller writes and "
      .. "what the documentation names"
  )

  -- ---------------------------------------------------------------------
  -- Imports and symbols.
  -- ---------------------------------------------------------------------
  local mods = {}
  for _, r in ipairs(requires) do
    mods[r.module] = true
  end
  eq(mods["Foundation"], true)
  eq(
    mods["UIKit"],
    true,
    "every Swift import is external by construction — there is no import-by-path"
  )

  local sym = {}
  for _, s in ipairs(symbols) do
    sym[s.name] = s
  end
  eq(sym["Widget"].detail, "struct", "`struct` and `class` share a node type here")
  eq(sym["Doer"].detail, "protocol")
  eq(sym["Widget.max"].kind, "constant", "`let` is a constant, `var` a binding")
  eq(sym["Widget.max"].summary, "How many.")
  eq(sym["Widget.count"].kind, "binding")

  local markers = require("documentation.core.markers")
  eq(#markers.scan_source("// TODO: finish this", sw), 1)
end
