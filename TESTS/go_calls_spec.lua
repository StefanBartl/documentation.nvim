-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/go_calls_spec.lua — Go call edges, and the package scope they need
--
-- Go is the fifth backend to emit call sites and the first outside Lua and
-- the ECMA family, which is why it gets a spec of its own rather than a
-- paragraph in `lang_go_spec.lua`: the new thing here is not the extractor
-- but `LangBackend.call_scope = "package"`, and that is a *resolver*
-- property, testable only over a whole tree.
--
-- **Why a checked-in tree and not a string fixture.** A Go package is a
-- directory, so every case worth testing is a statement about two files
-- sitting next to each other — which a snippet cannot express at all. The
-- tree is real, compiling Go on purpose, including its hardest case:
-- `widgets` and `widgets_test` are two packages in one directory, so one
-- name declared twice there is something the language permits rather than
-- something this fixture invented to be convenient.
--
-- Measured before it was written: on `aws/smithy-go`, 883 call edges, 397 of
-- them across files of one package. Package scope is not a corner of a Go
-- call graph; it is nearly half of it.

return function(H)
  local eq, ok = H.eq, H.ok

  local explicit = os.getenv("DOCMAP_GO_PARSER")
  local ok_add, has_go
  if explicit and explicit ~= "" then
    ok_add, has_go = pcall(vim.treesitter.language.add, "go", { path = explicit })
  else
    ok_add, has_go = pcall(vim.treesitter.language.add, "go")
  end

  -- Contract answers first: these hold with or without a grammar, and they
  -- are what every *other* part of the tool reads to decide whether a panel
  -- is empty because the project has no calls or because this build cannot
  -- see them.
  local go = require("documentation.core.lang_registry").get("go")
  ok(go ~= nil, "go: the backend must be registered")
  eq(go.emits_calls, true, "go: this backend returns call sites")
  eq(go.call_scope, "package", "go: an unqualified call resolves in the directory, not the file")

  local lua = require("documentation.core.lang_registry").get("lua")
  eq(
    lua.call_scope,
    nil,
    "lua: absent, and absent must keep meaning file scope — a bare helper() "
      .. "in Lua names something this file declares"
  )

  if not (ok_add and has_go) then
    ok(true, "go_calls: go parser not installed — skipping the tree")
    return
  end

  local root = (vim.fn.getcwd():gsub("\\", "/")) .. "/TESTS/fixtures/gocalls"
  ok(vim.fn.isdirectory(root) == 1, "go_calls: the fixture tree is checked in")

  local opts = require("documentation.config").build(root)
  eq(
    type(opts.source) == "table" and opts.source[1] or opts.source,
    ".",
    "go_calls: `go.mod` beside the sources means the module root is the source root"
  )

  local ir = require("documentation.core.scan").scan(opts)

  local calls = {}
  for _, e in ipairs(ir.edges or {}) do
    if e.kind == "call" then
      calls[e.from .. "#" .. tostring(e.from_fn)] = e
    end
  end

  -- The case the feature exists for. Nothing at this call site says `double`
  -- lives in helper.go; Go declares no `module_file`, so the two files are
  -- two IR nodes and a file-scoped resolver finds nothing at all.
  local use = calls["./widget.go#Use"]
  ok(use, "go_calls: an unqualified call to a sibling file resolves")
  eq(use.to, "./helper.go", "go_calls: ...to the sibling that declares it")
  eq(use.to_fn, "double")
  eq(
    use.confidence,
    "exact",
    "go_calls: package scope is a language guarantee, not the `calls_heuristic` guess"
  )

  -- Order matters as much as the lookup: this file's own declaration is the
  -- nearer answer and must still win, without the package index behind it
  -- turning the name ambiguous.
  local local_ = calls["./widget.go#Local"]
  ok(local_, "go_calls: a call to this file's own declaration still resolves")
  eq(local_.to, "./widget.go", "go_calls: ...to this file, not through the package index")
  eq(local_.to_fn, "same")

  -- Siblings, not descendants. `./inner` is a different package and a
  -- different scope, so `Deep` must reach the `double` beside it and never
  -- the one in the directory above — the two are deliberately given
  -- different bodies so a wrong edge is a wrong answer, not a tie.
  local deep = calls["./inner/deep.go#Deep"]
  ok(deep, "go_calls: a nested package resolves within itself")
  eq(deep.to, "./inner/other.go", "go_calls: ...to its own sibling file")
  eq(deep.to_fn, "double")

  -- A name two files of one directory declare is dropped rather than
  -- arbitrated. `shared` is in helper.go (package widgets) and again in
  -- widget_test.go (package widgets_test) — which real Go compiles, and
  -- which means the directory is not one scope. There is no honest pick, and
  -- a confident wrong edge is the failure `calls_heuristic` stays opt-in for.
  eq(
    calls["./widget.go#Shaky"],
    nil,
    "go_calls: an ambiguous name yields no edge — fewer edges beats a wrong one"
  )
end
