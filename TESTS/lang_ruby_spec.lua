-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/lang_ruby_spec.lua — documentation.core.lang.ruby
--
-- Skips when the ruby parser is not reachable; `DOCMAP_RUBY_PARSER` points at
-- one without installing it into a runtimepath.
--
-- Ruby's visibility is a *positional statement* — `private` is a method call
-- that changes the default for everything after it — which is the shape C++'s
-- access specifier had. Ruby adds two spellings C++ has no equivalent of, and
-- the fixture carries both: `private def foo` marks one definition, and
-- `private :foo` marks one **by name**, possibly long after it was written.
-- No other language here can change a declaration's visibility from
-- somewhere else in the file.

return function(H)
  local eq, ok = H.eq, H.ok

  local explicit = os.getenv("DOCMAP_RUBY_PARSER")
  local ok_add, has_rb
  if explicit and explicit ~= "" then
    ok_add, has_rb = pcall(vim.treesitter.language.add, "ruby", { path = explicit })
  else
    ok_add, has_rb = pcall(vim.treesitter.language.add, "ruby")
  end

  local rb = require("documentation.core.lang_registry").get("ruby")
  ok(rb ~= nil, "the ruby backend must be registered")

  -- ---------------------------------------------------------------------
  -- Contract answers, which hold with or without a grammar installed.
  -- ---------------------------------------------------------------------
  eq(rb.is_source("widget.rb"), true)
  eq(rb.is_source("Gemfile"), false, "a manifest is not a source file")
  eq(rb.module_tag, false, "no tag names a Ruby file's module")
  eq(
    rb.param_docs,
    false,
    "YARD's @param is a gem's convention, not the language's — RDoc ships with "
      .. "Ruby and has no per-parameter form at all"
  )

  if not (ok_add and has_rb) then
    ok(true, "lang.ruby: ruby parser not installed — skipping the rest")
    return
  end

  local function write(body)
    local file = H.tmpfile(".rb")
    local fw = assert(io.open(file, "w"))
    fw:write(body)
    fw:close()
    return file
  end

  local file = write(table.concat({
    "# frozen_string_literal: true",
    "",
    "require 'json'",
    "require_relative 'helpers'",
    "",
    "# A widget that does things.",
    "#",
    "# More detail here.",
    "module Acme",
    "  # The widget class.",
    "  class Widget",
    "    MAX = 10",
    "",
    "    attr_reader :name",
    "",
    "    # Adds two numbers.",
    "    #",
    "    # @param [Integer] x The first number.",
    "    # @param [Integer] y The second number.",
    "    # @return [Integer] Their sum.",
    "    def add(x, y)",
    "      x + y",
    "    end",
    "",
    "    # A class method.",
    "    def self.build(name)",
    "      new(name)",
    "    end",
    "",
    "    # Marked one definition at a time.",
    "    private def one_off(a)",
    "      a",
    "    end",
    "",
    "    # Public when written, private later by name.",
    "    def named_later",
    "      1",
    "    end",
    "    private :named_later",
    "",
    "    private",
    "",
    "    # Not published.",
    "    def helper",
    "      42",
    "    end",
    "",
    "    # A class method after `private` is still public.",
    "    def self.still_public",
    "      2",
    "    end",
    "",
    "    public",
    "",
    "    # Published again.",
    "    def visible_again",
    "      1",
    "    end",
    "",
    "    # @api private",
    "    def tagged_private",
    "      3",
    "    end",
    "  end",
    "end",
    "",
  }, "\n"))

  local header = rb.parse_header(file)
  eq(header.summary, "A widget that does things.", "the comment above the first module")
  ok(header.body:match("More detail"))
  eq(
    header.module,
    nil,
    "Ruby has no rule tying a file's name to what it defines — one file can "
      .. "open three classes in two modules"
  )

  local fns, _, requires, symbols = rb.scan_file(file)
  local by = {}
  for _, fn in ipairs(fns) do
    by[fn.name] = fn
  end

  -- ---------------------------------------------------------------------
  -- Ruby's own notation: `#` for an instance method, `.` for a class one.
  -- They are different methods and can share a name, so merging them under
  -- `::` — as C++ and Rust do — would lose that.
  -- ---------------------------------------------------------------------
  eq(by["Acme::Widget#add"] ~= nil, true, "an instance method")
  eq(by["Acme::Widget.build"] ~= nil, true, "and a class method, told apart")
  eq(by["Acme::Widget#add"].signature, "Acme::Widget#add(x, y)")

  -- ---------------------------------------------------------------------
  -- Positional visibility, and the two spellings around it.
  -- ---------------------------------------------------------------------
  eq(by["Acme::Widget#add"].internal, false, "before any `private`")
  eq(by["Acme::Widget#helper"].internal, true, "after a bare `private`")
  eq(by["Acme::Widget#visible_again"].internal, false, "and `public` changes it back")
  eq(
    by["Acme::Widget#one_off"].internal,
    true,
    "`private def foo` marks one definition without changing the default"
  )
  eq(
    by["Acme::Widget#named_later"].internal,
    true,
    "`private :foo` reaches back and changes a method written earlier — no "
      .. "other language here can do that"
  )
  eq(
    by["Acme::Widget.still_public"].internal,
    false,
    "`private` affects instance methods only: a class method after it is still public"
  )
  eq(
    by["Acme::Widget#tagged_private"].internal,
    true,
    "YARD's `@api private` is the authoring-convention layer, like PHP's @internal"
  )

  -- ---------------------------------------------------------------------
  -- YARD tags are parsed and shown even though they are not judged.
  -- ---------------------------------------------------------------------
  eq(#by["Acme::Widget#add"].params, 2, "parsed and shown")
  eq(by["Acme::Widget#add"].params[1].name, "x")
  eq(by["Acme::Widget#add"].params[1].type, "Integer", "`@param [Integer] x` puts the type first")
  eq(by["Acme::Widget#add"].params[1].desc, "The first number.")
  eq(#by["Acme::Widget#add"].returns, 1)
  eq(by["Acme::Widget#add"].returns[1].type, "Integer")

  -- ---------------------------------------------------------------------
  -- Requires: only `require_relative` names a file.
  -- ---------------------------------------------------------------------
  local mods = {}
  for _, r in ipairs(requires) do
    mods[r.module] = true
  end
  eq(mods["json"], true, "`require` searches the load path — recorded as written")
  eq(mods["./helpers"], true, "`require_relative` names the file beside this one")

  local sym = {}
  for _, s in ipairs(symbols) do
    sym[s.name] = s
  end
  eq(sym["Acme"].detail, "module")
  eq(sym["Acme::Widget"].detail, "class")
  eq(sym["Acme::Widget"].summary, "The widget class.")
  eq(sym["Acme::Widget::MAX"].kind, "constant")
  eq(sym["Acme::Widget#name"].detail, "attr_reader", "an attr_* generates a binding per symbol")

  -- A magic comment is not documentation: it sits where documentation sits
  -- and means something to the interpreter, like Go's `//go:build`.
  local magic = write(table.concat({
    "# frozen_string_literal: true",
    "class Bare",
    "end",
    "",
  }, "\n"))
  eq(rb.parse_header(magic).summary, "", "a magic comment documents nothing")

  local markers = require("documentation.core.markers")
  eq(#markers.scan_source("# TODO: finish this", rb), 1)
end
