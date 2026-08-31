-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/docs_spec.lua — documentation.core.docs
--
-- Its own file rather than a block in docmap_spec.lua, for the reason that
-- file's own header gives: it already sits at Lua's 200-local ceiling.
--
-- The assertions below are shaped by what a first real run against this
-- repository actually produced, not by what the design expected. That run
-- reported 25 `doc-references-missing` findings of which 24 were false, and
-- resolved 194 references of which the most-cited was a local function
-- called `git` picking up documents that discuss the version-control tool.
-- Every exclusion tested here exists because of one of those, and each is
-- named in the case it guards.

return function(H)
  local eq, ok = H.eq, H.ok
  local docs = require("documentation.core.docs")

  -- A miniature IR, hand-built: these functions take an IR, not a tree, so a
  -- real scan would only make the fixtures harder to read.
  local ir = {
    order = { "n/root", "n/scan", "n/deep", "n/ns" },
    nodes = {
      ["n/root"] = {
        id = "n/root",
        module = "demo",
        path = "lua/demo",
        functions = { { name = "M.setup" }, { name = "write" } },
      },
      -- `parent` links are set because the prefix walk climbs them: a real
      -- IR always has them, and a fixture without them silently exercised a
      -- fallback path instead of the real one.
      ["n/scan"] = {
        id = "n/scan",
        module = "demo.core.scan",
        path = "lua/demo/core/scan.lua",
        parent = "n/ns",
        functions = { { name = "M.run" }, { name = "git" } },
      },
      ["n/deep"] = {
        id = "n/deep",
        module = "demo.core.deps",
        path = "lua/demo/core/deps.lua",
        parent = "n/ns",
        -- `write` also exists on n/root: a bare name owned twice.
        functions = { { name = "M.build" }, { name = "write" } },
      },
      -- A directory with no init.lua: no `module` tag of its own.
      ["n/ns"] = { id = "n/ns", path = "lua/demo/core", parent = "n/root", functions = {} },
    },
  }

  local idx = docs.build_index(ir)

  -- ---------------------------------------------------------------------
  -- The index
  -- ---------------------------------------------------------------------
  eq(idx.exact["demo.core.scan"].kind, "module", "docs: a module path indexes as a module")
  eq(idx.exact["demo.core.scan.run"].fn, "M.run", "docs: qualified module.bare form resolves")
  eq(idx.exact["M.run"].fn, "M.run", "docs: the declared name as written resolves")
  ok(
    idx.exact["demo.core"] ~= nil,
    "docs: a dotted prefix of a known module is itself known, so a namespace "
      .. "with no @module tag is not mistaken for a missing member of its parent"
  )
  eq(idx.bare["git"].fn, "git", "docs: a tree-unique bare name is available to the heuristic")
  eq(idx.bare["write"], nil, "docs: a bare name owned by two modules is owned by neither")

  -- A prefix must name the namespace itself, not one of its children. The
  -- first version resolved `demo.core` to whichever module under it
  -- `pairs()` happened to yield first — a different one per run, which made
  -- the byte-compared artifact permanently stale because regenerating never
  -- reproduced the previous file. Both halves are asserted: the right node,
  -- and the same node every time.
  eq(
    idx.exact["demo.core"].node,
    "n/ns",
    "docs: a namespace prefix resolves to the namespace node, not to a child module"
  )
  for _ = 1, 5 do
    eq(
      docs.build_index(ir).exact["demo.core"].node,
      "n/ns",
      "docs: ... and does so deterministically, run after run"
    )
  end

  -- ---------------------------------------------------------------------
  -- Resolution — qualified by default, bare only when asked
  -- ---------------------------------------------------------------------
  local r = docs.resolve(idx, "demo.core.scan.run")
  eq(r.confidence, "exact", "docs: a qualified reference is exact")
  eq(r.fn, "M.run", "docs: ... and names the right function")
  eq(docs.resolve(idx, "demo.core.deps").kind, "module", "docs: a module path resolves")

  -- The `git` case, which is why undotted mentions are gated: it is in the
  -- index under its exact declared name, and it is also an ordinary word.
  eq(
    docs.resolve(idx, "git"),
    nil,
    "docs: an undotted mention does not resolve by default, even on an exact index hit"
  )
  eq(
    docs.resolve(idx, "git", true).confidence,
    "heuristic",
    "docs: ... and is heuristic, never exact, when the heuristic is enabled"
  )
  eq(docs.resolve(idx, "write", true), nil, "docs: an ambiguous bare name stays unresolved")
  eq(docs.resolve(idx, "nothing.at.all"), nil, "docs: an unknown qualified name resolves to nil")

  -- ---------------------------------------------------------------------
  -- missing_member — the rule behind `doc-references-missing`
  -- ---------------------------------------------------------------------
  local mod, miss = docs.missing_member(idx, "demo.core.scan.gone")
  eq(mod, "demo.core.scan", "docs: a real module prefix with a dead member is reported")
  eq(miss, "gone", "docs: ... naming the member that is missing")

  eq(docs.missing_member(idx, "demo.core.scan.run"), nil, "docs: a live member is not reported")
  eq(docs.missing_member(idx, "vim.fn.expand"), nil, "docs: an unknown prefix is never reported")
  eq(docs.missing_member(idx, "git"), nil, "docs: a bare word is not a missing member")
  eq(
    docs.missing_member(idx, "demo.nvim"),
    nil,
    "docs: `x.nvim` is a plugin repository name, not a member access"
  )
  eq(
    docs.missing_member(idx, "demo.lua"),
    nil,
    "docs: `x.lua` is a bare filename, not a member access"
  )
  eq(
    docs.missing_member(idx, "demo.core.scan.lua"),
    nil,
    "docs: `x.lua` is excluded even when `x` is a deeper module path"
  )
  eq(
    docs.missing_member(idx, "demo.core.scan.init"),
    nil,
    "docs: `x.init` is the alternative spelling of module `x`'s own file, not a missing member"
  )
  eq(
    docs.missing_member(idx, "demo.*"),
    nil,
    "docs: a glob over a namespace is not a claim that `*` is a member"
  )
  eq(
    docs.missing_member(idx, "demo.core"),
    nil,
    "docs: a namespace is not a missing member of its own parent"
  )

  -- ---------------------------------------------------------------------
  -- Rename notes — a ledger naming what something *used to* be called
  -- ---------------------------------------------------------------------
  ok(
    docs.is_rename_note(idx, "`demo.old.name` → `demo.core.scan.run`, and so on", "demo.old.name"),
    "docs: an arrow pointing at something that resolves marks a rename note"
  )
  eq(
    docs.is_rename_note(idx, "`demo.old.name` → `demo.also.gone`", "demo.old.name"),
    false,
    "docs: an arrow pointing at something equally missing is not evidence of a rename"
  )
  eq(
    docs.is_rename_note(idx, "see `demo.old.name` for details", "demo.old.name"),
    false,
    "docs: a mention with no arrow at all is not a rename note"
  )

  -- ---------------------------------------------------------------------
  -- code_spans — what counts as a mention in Markdown
  -- ---------------------------------------------------------------------
  local spans = docs.code_spans(table.concat({
    "# Title",
    "Prose mentioning `demo.core.scan.run` inline.",
    "```lua",
    "local x = demo.core.scan.run()   -- a code sample, not a reference",
    "```",
    "And ``a `nested` span`` too.",
    "~~~",
    "fenced with tildes: `demo.core.deps.build`",
    "~~~",
    "Last: `demo.core.deps.build`.",
  }, "\n"))

  local texts, lines = {}, {}
  for _, s in ipairs(spans) do
    texts[#texts + 1] = s.text
    lines[s.text] = s.line
  end

  ok(vim.tbl_contains(texts, "demo.core.scan.run"), "docs: an inline code span is a mention")
  eq(lines["demo.core.scan.run"], 2, "docs: ... reported at its own line")
  eq(
    vim.tbl_contains(texts, "local x = demo.core.scan.run()   -- a code sample, not a reference"),
    false,
    "docs: a fenced block is a code sample, and contributes no mentions"
  )
  ok(vim.tbl_contains(texts, "a `nested` span"), "docs: a double-backtick span is read as one span")
  eq(
    lines["demo.core.deps.build"],
    10,
    "docs: a tilde-fenced block is skipped too, so the last mention is the one outside it"
  )

  -- ---------------------------------------------------------------------
  -- corpus — what gets read at all
  -- ---------------------------------------------------------------------
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp .. "/docs/map", "p")
  vim.fn.mkdir(tmp .. "/.hidden", "p")
  vim.fn.mkdir(tmp .. "/node_modules", "p")
  local function put(rel, body)
    local fd = assert(io.open(tmp .. "/" .. rel, "w"))
    fd:write(body)
    fd:close()
  end
  put("README.md", "# Readme\nSee `demo.core.scan.run` and `demo.core.scan.gone`.\n")
  put("docs/map/overview.md", "# Generated\n`demo.core.scan.run`\n")
  put(".hidden/secret.md", "# Hidden\n`demo.core.scan.run`\n")
  put("node_modules/dep.md", "# Dep\n`demo.core.scan.run`\n")
  put("notes.txt", "not markdown: `demo.core.scan.run`\n")

  local corpus = docs.corpus({ root = tmp, out_dir = "docs/map" })
  eq(#corpus, 1, "docs: only real Markdown outside out_dir/hidden/node_modules is read")
  eq(corpus[1], "README.md", "docs: ... and that is the README")

  -- End to end over that corpus.
  local result = docs.resolve_all(ir, { root = tmp, out_dir = "docs/map" })
  eq(#result.files, 1, "docs: one file in the corpus")
  eq(result.files[1].title, "Readme", "docs: the title comes from the first heading")
  eq(result.files[1].refs, 1, "docs: one of its two mentions resolved")

  local key = "n/scan#M.run"
  ok(result.refs[key] ~= nil, "docs: the resolved mention is filed under nodeId#fnName")
  eq(result.refs[key][1].doc, "README.md", "docs: ... naming the document")
  eq(result.refs[key][1].line, 2, "docs: ... and the line")

  eq(#result.missing, 1, "docs: the unresolvable member is reported once")
  eq(result.missing[1].missing, "gone", "docs: ... naming what is missing")
  eq(result.missing[1].node, "n/scan", "docs: ... and the node to attribute it to")

  vim.fn.delete(tmp, "rf")
end
