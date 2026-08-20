-- TESTS/lang_rust_spec.lua — documentation.core.lang.rust
--
-- Skips when the rust parser is not reachable; `DOCMAP_RUST_PARSER` points at
-- one without installing it into a runtimepath.
--
-- Rust is the language Phase 0's last open item was written about — `mod x
-- { … }`, one file holding several modules — so the fixture has an inline
-- module in it, and the assertion is that its contents are qualified rather
-- than flattened into the file.
--
-- The fixture is written under a `src/` directory rather than into a bare
-- temp file, because the module path is *derived from the path*: that is what
-- lets `use crate::a::b` resolve to a node, and a test that skipped it would
-- be testing a different function than the one that runs.

return function(H)
  local eq, ok = H.eq, H.ok

  local explicit = os.getenv("DOCMAP_RUST_PARSER")
  local ok_add, has_rust
  if explicit and explicit ~= "" then
    ok_add, has_rust = pcall(vim.treesitter.language.add, "rust", { path = explicit })
  else
    ok_add, has_rust = pcall(vim.treesitter.language.add, "rust")
  end

  local rs = require("documentation.core.lang_registry").get("rust")
  ok(rs ~= nil, "the rust backend must be registered")

  -- ---------------------------------------------------------------------
  -- Contract answers, which hold with or without a grammar installed.
  -- ---------------------------------------------------------------------
  eq(rs.is_source("lib.rs"), true)
  eq(rs.is_source("Cargo.toml"), false, "a manifest is not a source file")
  eq(rs.module_tag, false, "a module path is the file's position, never a tag")
  eq(rs.module_file, "mod.rs", "the fourth directory-owns-a-module convention here")
  eq(
    rs.param_docs,
    false,
    "rustdoc has no tag vocabulary — `# Arguments` is a Markdown heading some "
      .. "projects write and most do not"
  )

  if not (ok_add and has_rust) then
    ok(true, "lang.rust: rust parser not installed — skipping the rest")
    return
  end

  -- A real `src/` directory, because `module_path_of` reads the path — and a
  -- named one, because the crate name comes from the directory holding
  -- `src/`.
  local base = vim.fn.tempname()
  local root = base .. "/mycrate"
  vim.fn.mkdir(root .. "/src/deep", "p")

  local function write(rel, body)
    local path = root .. "/" .. rel
    local fw = assert(io.open(path, "w"))
    fw:write(body)
    fw:close()
    return path
  end

  local file = write(
    "src/widgets.rs",
    table.concat({
      "//! The widgets module.",
      "//!",
      "//! More detail about it.",
      "",
      "use std::io;",
      "use crate::other::Thing;",
      "use super::sibling;",
      "",
      "mod split;",
      "",
      "/// How many.",
      "pub const MAX: usize = 10;",
      "",
      "static COUNTER: usize = 0;",
      "",
      "/// A widget.",
      "#[derive(Debug)]",
      "pub struct Widget {",
      "    pub name: String,",
      "}",
      "",
      "/// A trait.",
      "pub trait Doer {",
      "    /// Do it.",
      "    fn go(&self, n: usize) -> Result<(), io::Error>;",
      "}",
      "",
      "impl Widget {",
      "    /// Makes one.",
      "    pub fn new(name: String) -> Self {",
      "        Widget { name }",
      "    }",
      "",
      "    fn helper(&self) -> usize { 0 }",
      "",
      "    pub(crate) fn crate_only(&self) {}",
      "}",
      "",
      "/// Adds two numbers.",
      "pub fn add(x: i32, y: i32) -> i32 { x + y }",
      "",
      "fn private(z: i32) -> i32 { z }",
      "",
      "/// An inline module.",
      "pub mod inner {",
      "    /// Inside it.",
      "    pub fn nested(a: u8) {}",
      "}",
      "",
    }, "\n")
  )

  -- ---------------------------------------------------------------------
  -- `//!` is the file's doc and the module path comes from the path.
  -- ---------------------------------------------------------------------
  local header = rs.parse_header(file)
  eq(header.summary, "The widgets module.", "`//!` documents the file, as in Zig")
  ok(header.body:match("More detail"), "and the rest of the block is the body")
  eq(header.module, "mycrate::widgets", "derived from the position under src/")

  eq(
    rs.parse_header(write("src/lib.rs", "//! Root.\n")).module,
    "mycrate",
    "lib.rs is the crate root"
  )
  eq(
    rs.parse_header(write("src/deep/mod.rs", "//! Deep.\n")).module,
    "mycrate::deep",
    "mod.rs names its directory"
  )
  eq(
    rs.parse_header(write("src/deep/leaf.rs", "//! Leaf.\n")).module,
    "mycrate::deep::leaf",
    "and a file inside it is one level further down"
  )

  -- **The crate name rather than the literal `crate`, and a workspace is
  -- why.** Every member of a Cargo workspace has its own `crate::` root, so
  -- two members each holding a `builder` module would produce one module name
  -- for two different files — and a module index keyed on that string
  -- resolves one member's import to the other member's file. Measured on
  -- `clap-rs/clap`, which has three members.
  local other = base .. "/othercrate"
  vim.fn.mkdir(other .. "/src", "p")
  local ow = assert(io.open(other .. "/src/widgets.rs", "w"))
  ow:write("//! Another crate's widgets.\nuse crate::shared::Thing;\n")
  ow:close()
  eq(
    rs.parse_header(other .. "/src/widgets.rs").module,
    "othercrate::widgets",
    "the same file name in another member is another module"
  )
  local _, _, oreq = rs.scan_file(other .. "/src/widgets.rs")
  eq(
    oreq[1].module,
    "othercrate::shared",
    "and its `crate::` resolves against its own crate, not the neighbour's"
  )

  local fns, _, requires, symbols = rs.scan_file(file)
  local by = {}
  for _, fn in ipairs(fns) do
    by[fn.name] = fn
  end

  -- ---------------------------------------------------------------------
  -- Visibility: four values, one of them published.
  -- ---------------------------------------------------------------------
  eq(by["add"].internal, false, "`pub` is the crate's public surface")
  eq(by["private"].internal, true, "no modifier is private")
  eq(by["Widget::new"].internal, false)
  eq(by["Widget::helper"].internal, true)
  eq(
    by["Widget::crate_only"].internal,
    true,
    "`pub(crate)` is restricted, not published — from outside it answers like private"
  )
  eq(
    by["Doer::go"].internal,
    false,
    "a trait member carries no modifier of its own and is as visible as its "
      .. "trait — writing `pub` there is a compile error. The third time this "
      .. "tool has met the same construct, after C#'s and Go's interfaces"
  )

  -- ---------------------------------------------------------------------
  -- Owning scope, and the inline module Phase 0 named.
  -- ---------------------------------------------------------------------
  eq(by["Widget::new"] ~= nil, true, "an inherent method belongs to its type")
  eq(by["Widget::new"].signature, "Widget::new(name)", "&self is bound by the call, as in Python")
  eq(
    by["inner::nested"] ~= nil,
    true,
    "a function in an inline module is qualified, not flattened into the file"
  )
  eq(by["inner::nested"].summary, "Inside it.")

  -- The doc comment sits above an attribute, which sits above the item.
  local sym = {}
  for _, s in ipairs(symbols) do
    sym[s.name] = s
  end
  eq(
    sym["Widget"].summary,
    "A widget.",
    "`#[derive(…)]` between the doc comment and the item is stepped over, not treated as a wall"
  )
  eq(sym["MAX"].kind, "constant")
  eq(sym["COUNTER"].kind, "binding")
  eq(sym["Doer"].detail, "trait")
  eq(sym["inner"].detail, "mod", "and the inline module is itself a symbol")

  -- ---------------------------------------------------------------------
  -- `use` paths, resolved far enough to be edges.
  -- ---------------------------------------------------------------------
  local mods = {}
  for _, r in ipairs(requires) do
    mods[r.module] = true
  end
  eq(mods["std::io"], true, "an external crate, as written")
  eq(
    mods["mycrate::other"],
    true,
    "the trailing `Thing` is a type, not a module — capitalisation says so, "
      .. "and rustc's own lints enforce it"
  )
  eq(mods["mycrate::sibling"], true, "`super::` is rewritten against this file's own module path")
  eq(
    mods["mycrate::widgets::split"],
    true,
    "`mod split;` says the module lives in another file — one of the few Rust "
      .. "edges that names a file rather than a path through the module tree"
  )

  local markers = require("documentation.core.markers")
  eq(#markers.scan_source("// TODO: finish this", rs), 1)
end
