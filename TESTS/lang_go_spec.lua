-- TESTS/lang_go_spec.lua — documentation.core.lang.go
--
-- Skips when the go parser is not reachable; `DOCMAP_GO_PARSER` points at one
-- without installing it into a runtimepath.
--
-- Go is here for two properties nothing else in this tool has. Its visibility
-- is a fact about *spelling* the compiler enforces, which makes it the only
-- backend that needs no keyword, tag or export list to answer. And godoc has
-- no tag vocabulary at all — no `@param`, nothing — which makes Go the third
-- `param_docs = false` language and the first for that reason: it has
-- parameters and documents them nowhere.

return function(H)
  local eq, ok = H.eq, H.ok

  local explicit = os.getenv("DOCMAP_GO_PARSER")
  local ok_add, has_go
  if explicit and explicit ~= "" then
    ok_add, has_go = pcall(vim.treesitter.language.add, "go", { path = explicit })
  else
    ok_add, has_go = pcall(vim.treesitter.language.add, "go")
  end

  local go = require("documentation.core.lang_registry").get("go")
  ok(go ~= nil, "the go backend must be registered")

  -- ---------------------------------------------------------------------
  -- Contract answers, which hold with or without a grammar installed.
  -- ---------------------------------------------------------------------
  eq(go.is_source("main.go"), true)
  eq(go.is_source("main_test.go"), true, "Go puts tests beside the code by design")
  eq(go.is_source("go.mod"), false, "a build file is not a source file")
  eq(go.module_tag, false, "a package is a directory; the path is the identity")
  eq(
    go.param_docs,
    false,
    "godoc has no per-parameter form — judging Go by one would report every "
      .. "well-documented Go project as undocumented"
  )

  if not (ok_add and has_go) then
    ok(true, "lang.go: go parser not installed — skipping the rest")
    return
  end

  local function write(body)
    local file = H.tmpfile(".go")
    local fw = assert(io.open(file, "w"))
    fw:write(body)
    fw:close()
    return file
  end

  local file = write(table.concat({
    "// Package widgets does things.",
    "//",
    "// More detail about the package.",
    "package widgets",
    "",
    "import (",
    '\t"fmt"',
    '\t"github.com/acme/other"',
    '\talias "github.com/acme/aliased"',
    '\t_ "github.com/acme/blank"',
    ")",
    "",
    "// Max is how many.",
    "const Max = 10",
    "",
    "var counter int",
    "",
    "// Widget is a thing.",
    "type Widget struct {",
    "\tName string",
    "}",
    "",
    "// Thinger is an interface.",
    "type Thinger interface {",
    "\t// Go does it.",
    "\tGo(n int) error",
    "\thidden()",
    "}",
    "",
    "// Add adds two numbers and returns their sum.",
    "func Add(x, y int) int {",
    "\treturn x + y",
    "}",
    "",
    "func unexported(z int) int {",
    "\treturn z",
    "}",
    "",
    "// Run runs the widget.",
    "func (w *Widget) Run(n int) error {",
    "\tfmt.Println(alias.Y, other.X)",
    "\treturn nil",
    "}",
    "",
    "func (w Widget) hidden() {}",
    "",
  }, "\n"))

  -- ---------------------------------------------------------------------
  -- The package comment is Go's only file-level documentation, and there is
  -- deliberately no module name — see the backend's `parse_header`.
  -- ---------------------------------------------------------------------
  local header = go.parse_header(file)
  eq(header.summary, "Package widgets does things.")
  ok(header.body:match("More detail"), "the rest of the package comment is the body")
  eq(
    header.module,
    nil,
    "a Go package is a directory: every file in it declares the same package, "
      .. "so the package name is not a unique module name"
  )

  local fns, _, requires, symbols = go.scan_file(file)
  local by = {}
  for _, fn in ipairs(fns) do
    by[fn.name] = fn
  end

  -- ---------------------------------------------------------------------
  -- Visibility is capitalisation, and the compiler enforces it.
  -- ---------------------------------------------------------------------
  eq(by["Add"].internal, false, "upper case is exported — the whole of Go's visibility system")
  eq(by["unexported"].internal, true)
  eq(by["Widget.Run"].internal, false)
  eq(
    by["Widget.hidden"].internal,
    true,
    "the method's own name decides, not its receiver's — an exported type "
      .. "routinely carries unexported methods"
  )

  -- ---------------------------------------------------------------------
  -- An interface's methods are its whole content. They are `method_elem`
  -- nodes with no body and no receiver, so they are not reached by the
  -- function branch — and an interface listed as a bare symbol would show
  -- its name and nothing it promises. The lesson C# taught by getting the
  -- same construct backwards.
  -- ---------------------------------------------------------------------
  eq(by["Thinger.Go"] ~= nil, true, "an interface method is an entity")
  eq(by["Thinger.Go"].summary, "Go does it.")
  eq(by["Thinger.Go"].signature, "Thinger.Go(n)")
  eq(by["Thinger.hidden"].internal, true, "and capitalisation decides there too")

  -- `x, y int` is one declaration with two names — a shape no other language
  -- here has.
  eq(by["Add"].signature, "Add(x, y)")

  -- ---------------------------------------------------------------------
  -- Imports: recorded as written, aliases and blank imports included.
  -- ---------------------------------------------------------------------
  local mods = {}
  for _, r in ipairs(requires) do
    mods[r.module] = true
  end
  eq(mods["fmt"], true)
  eq(mods["github.com/acme/other"], true)
  eq(mods["github.com/acme/aliased"], true, "an alias names the same package")
  eq(mods["github.com/acme/blank"], true, "a blank import is still a dependency")

  local sym = {}
  for _, s in ipairs(symbols) do
    sym[s.name] = s
  end
  eq(sym["Max"].kind, "constant")
  eq(sym["Max"].summary, "Max is how many.")
  eq(sym["counter"].kind, "binding")
  eq(sym["Widget"].detail, "struct")
  eq(sym["Thinger"].detail, "interface")

  -- ---------------------------------------------------------------------
  -- A directive comment is not prose. `//go:build` and `//go:generate` sit
  -- exactly where documentation sits and mean something to a tool rather
  -- than to a reader — keeping them would make the summary of many files a
  -- build constraint.
  -- ---------------------------------------------------------------------
  local directives = write(table.concat({
    "//go:build linux",
    "",
    "// Package only builds on Linux.",
    "package only",
    "",
    "//go:generate stringer -type=Kind",
    "// Kind is a kind.",
    "type Kind int",
    "",
    "//go:noinline",
    "func Bare() {}",
    "",
  }, "\n"))

  eq(go.parse_header(directives).summary, "Package only builds on Linux.")
  local dfns, _, _, dsym = go.scan_file(directives)
  local dby = {}
  for _, s in ipairs(dsym) do
    dby[s.name] = s
  end
  eq(
    dby["Kind"].summary,
    "Kind is a kind.",
    "the directive above the prose is dropped, not the prose"
  )
  eq(dfns[1].summary, "", "and a declaration with only a directive above it is undocumented")

  -- ---------------------------------------------------------------------
  -- Nothing in a `_test.go` file is published API — a compiler fact, not a
  -- convention: `go build` excludes those files from the importable package
  -- entirely. Without this, Go's own naming requirement for tests
  -- (`TestXxx`, `BenchmarkXxx`, `ExampleXxx`, all necessarily capitalised)
  -- makes every test function look exported.
  --
  -- Measured against `spf13/cobra`, because the size of the distortion is
  -- the argument: 184 exported functions in the sources and 289 more in the
  -- tests, so the published surface read two and a half times its real size,
  -- and coverage averaged 38% for a library whose sources are at 75%.
  -- ---------------------------------------------------------------------
  local testfile = H.tmpfile("_test.go")
  local tw = assert(io.open(testfile, "w"))
  tw:write(table.concat({
    "package widgets",
    "",
    "// TestAdd checks Add.",
    "func TestAdd(t *testing.T) {}",
    "",
    "// Helper is capitalised but still not API.",
    "func Helper() {}",
    "",
  }, "\n"))
  tw:close()

  local tfns = go.scan_file(testfile)
  local tby = {}
  for _, fn in ipairs(tfns) do
    tby[fn.name] = fn
  end
  eq(tby["TestAdd"].internal, true, "a test function is not published API")
  eq(
    tby["Helper"].internal,
    true,
    "and neither is a capitalised helper beside it — the file is excluded "
      .. "from the package, so spelling cannot make it reachable"
  )
  eq(#tfns, 2, "they stay in the map: Go puts tests beside the code by design")
  eq(tby["TestAdd"].summary, "TestAdd checks Add.", "and they keep their documentation")

  local markers = require("documentation.core.markers")
  eq(#markers.scan_source("// TODO: finish this", go), 1)
end
