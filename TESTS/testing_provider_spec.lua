-- Test code: a nil from a fixture read or a decode must crash the spec and name
-- it; the nil guards LuaLS asks for would hide the failure being tested.
---@diagnostic disable: need-check-nil, undefined-field, param-type-mismatch, assign-type-mismatch
-- TESTS/testing_provider_spec.lua -- documentation.testing (the affected-selection provider)
--
-- A real project is generated with `documentation.generate` (so the contract
-- is checked against what `core/deps.lua` really writes, not against a map
-- the spec made up), committed with git, and queried:
--
--   p.a  <-  p.b  <-  p.c        c requires b requires a
--   p.d                          nothing requires it, and no spec requires it
--
--   TESTS/b_spec.lua    requires p.b
--   TESTS/c_spec.lua    requires p.c
--   TESTS/dyn_spec.lua  requires a module by a computed name
--   TESTS/none_spec.lua requires nothing of the project
--
-- Each case below is a way the answer can be wrong in the dangerous direction
-- (a spec left out): stale graph, unknown file, uncovered module, a spec the
-- graph cannot place, a consumer that was never measured, hostile input.

return function(H)
  local eq, ok = H.eq, H.ok
  local testing = require("documentation.testing")

  local function write(path, text)
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    local fd = assert(io.open(path, "wb"))
    fd:write(text)
    fd:close()
  end

  local function git(root, ...)
    local res = vim
      .system({
        "git",
        "-C",
        root,
        "-c",
        "user.email=t@example.test",
        "-c",
        "user.name=t",
        "-c",
        "commit.gpgsign=false",
        ...,
      }, { text = true })
      :wait()
    assert(res.code == 0, "git failed: " .. tostring(res.stderr))
    return vim.trim(res.stdout or "")
  end

  local function commit_all(root, msg)
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", msg)
    return git(root, "rev-parse", "HEAD")
  end

  local made = {}
  local function tmpdir()
    local d = vim.fn.tempname():gsub("\\", "/")
    vim.fn.mkdir(d, "p")
    made[#made + 1] = d
    return d
  end

  local function module_file(root, name, requires)
    local lines =
      { ("---@module 'p.%s'"):format(name), ("--- Module %s of the fixture."):format(name) }
    lines[#lines + 1] = "local M = {}"
    for _, r in ipairs(requires or {}) do
      lines[#lines + 1] = ("local _ = require('%s')"):format(r)
    end
    lines[#lines + 1] = "return M"
    write(root .. "/lua/p/" .. name .. ".lua", table.concat(lines, "\n") .. "\n")
  end

  ---The project; returns its root. `generate` writes docs/map; everything is committed.
  local function project()
    local root = tmpdir() .. "/p"
    write(root .. "/lua/p/init.lua", "---@module 'p'\n--- The fixture.\nreturn {}\n")
    module_file(root, "a")
    module_file(root, "b", { "p.a" })
    module_file(root, "c", { "p.b" })
    module_file(root, "d")
    write(root .. "/TESTS/b_spec.lua", "local b = require('p.b')\nreturn function() end\n")
    write(root .. "/TESTS/c_spec.lua", "local c = require('p.c')\nreturn function() end\n")
    write(
      root .. "/TESTS/dyn_spec.lua",
      "local name = 'a'\nlocal m = require(name)\nreturn function() end\n"
    )
    write(root .. "/TESTS/none_spec.lua", "return function() end\n")
    write(root .. "/TESTS/fixtures/x_spec.lua", "local a = require('p.a')\n")
    write(root .. "/README.md", "# p\n")
    git(root, "init", "-q")
    local documentation = require("documentation")
    documentation.generate({ root = root, source = "lua/p", title = "p", luals = false })
    commit_all(root, "init")
    return root
  end

  local function gap_kinds(res)
    local kinds = {}
    for _, g in ipairs(res.graph.gaps) do
      kinds[g.kind] = (kinds[g.kind] or 0) + 1
    end
    return kinds
  end

  local function list(t)
    return table.concat(t, ",")
  end

  -- ------------------------------------------------ the chain: file -> dependents -> specs
  local root = project()

  local res, err = testing.affected_specs({ root = root, changed = { "lua/p/a.lua" } })
  ok(res, "affected_specs answers: " .. tostring(err))
  eq(res.version, 1, "the answer carries the contract version")
  eq(
    list(res.specs),
    "TESTS/b_spec.lua,TESTS/c_spec.lua",
    "a change in a selects the specs of b and c"
  )
  local roles = {}
  for _, m in ipairs(res.modules) do
    roles[m.module] = m.role
  end
  eq(roles["p.a"], "changed", "the changed module is marked changed")
  eq(roles["p.b"], "dependent", "its direct dependent is a dependent")
  eq(roles["p.c"], "dependent", "its transitive dependent is a dependent")
  eq(roles["p.d"], nil, "an unrelated module is not affected")
  eq(
    list(res.unplaced_specs),
    "TESTS/dyn_spec.lua,TESTS/none_spec.lua",
    "specs the graph cannot place are listed, never silently dropped"
  )
  local kinds = gap_kinds(res)
  eq(kinds.spec_unplaced, 2, "both unplaced specs are gaps")
  local reasons = {}
  for _, g in ipairs(res.graph.gaps) do
    if g.kind == "spec_unplaced" then
      reasons[g.path] = g.reason
    end
  end
  eq(reasons["TESTS/dyn_spec.lua"], "dynamic_require", "a computed require is named as such")
  eq(reasons["TESTS/none_spec.lua"], "no_graph_module", "a spec outside the graph is named as such")
  eq(res.complete, true, "a fresh graph without a blocking gap is complete")
  ok(
    res.graph.generated_at and res.graph.generated_at:match("^%d%d%d%d%-%d%d%-%d%dT"),
    "generated_at is ISO"
  )
  ok(res.graph.commit and #res.graph.commit == 40, "the map's commit is reported")
  eq(res.graph.commit, res.graph.head, "map and code were committed together: same commit")
  eq(res.graph.stale, false, "fresh graph is not stale")

  -- A mid-chain change selects only what covers it: b's own spec and c's.
  local mid = testing.affected_specs({ root = root, changed = { "lua/p/b.lua" } })
  eq(list(mid.specs), "TESTS/b_spec.lua,TESTS/c_spec.lua", "a change in b selects b and c specs")
  local leaf = testing.affected_specs({ root = root, changed = { "lua/p/c.lua" } })
  eq(list(leaf.specs), "TESTS/c_spec.lua", "a change in c selects only c's spec, not a's or b's")

  -- Absolute paths inside the root, backslashes and ./ spellings are the same file.
  local spelled = testing.affected_specs({
    root = root,
    changed = { root .. "/lua/p/c.lua", ".\\lua\\p\\c.lua" },
  })
  eq(list(spelled.specs), "TESTS/c_spec.lua", "absolute and backslash spellings resolve")
  eq(#spelled.modules, 1, "...to one module, not two")

  -- A changed spec runs itself; fixtures are not specs.
  local own = testing.affected_specs({ root = root, changed = { "TESTS/none_spec.lua" } })
  eq(list(own.specs), "TESTS/none_spec.lua", "a changed spec selects itself")
  local fx = testing.affected_specs({ root = root, changed = { "lua/p/a.lua" } })
  for _, s in ipairs(fx.specs) do
    ok(not s:find("fixtures", 1, true), "a spec-shaped file under fixtures/ is never selected")
  end

  -- ------------------------------------------------ gaps
  local gap = testing.affected_specs({ root = root, changed = { "lua/p/d.lua" } })
  eq(#gap.specs, 0, "a module nobody tests selects nothing...")
  eq(gap_kinds(gap).changed_module_without_spec, 1, "...and says so explicitly")
  local gd
  for _, g in ipairs(gap.graph.gaps) do
    if g.kind == "changed_module_without_spec" then
      gd = g
    end
  end
  eq(gd.module, "p.d", "the gap names the module")

  local unknown = testing.affected_specs({ root = root, changed = { "lua/p/brand_new.lua" } })
  eq(gap_kinds(unknown).changed_not_in_graph, 1, "a changed file outside the map is a gap")
  eq(unknown.complete, false, "...and the selection is not complete")

  local support = testing.affected_specs({ root = root, changed = { "TESTS/harness.lua" } })
  eq(
    gap_kinds(support).test_support_changed,
    1,
    "a changed test helper is a gap: any spec may use it"
  )
  eq(support.complete, false, "...and the selection is not complete")

  local docs = testing.affected_specs({
    root = root,
    changed = { "README.md", "docs/map/module_map.json", "docs/map/index.html" },
  })
  eq(
    list(docs.ignored),
    "README.md,docs/map/index.html,docs/map/module_map.json",
    "docs and generated files are ignored"
  )
  eq(#docs.specs, 0, "...and select nothing")
  eq(docs.complete, true, "...without making the answer incomplete")

  -- ------------------------------------------------ freshness
  write(
    root .. "/lua/p/a.lua",
    "---@module 'p.a'\n--- Module a, edited.\nlocal M = {}\nM.x = 1\nreturn M\n"
  )
  local dirty = testing.affected_specs({ root = root, changed = { "lua/p/a.lua" } })
  eq(dirty.graph.dirty, true, "uncommitted source changes are reported")
  eq(dirty.graph.stale, false, "...but they do not make a committed map stale")
  local code_sha = commit_all(root, "edit a")
  local stale = testing.affected_specs({ root = root, changed = { "lua/p/a.lua" } })
  eq(stale.graph.stale, true, "code committed after the map makes the graph stale")
  ok(
    stale.graph.stale_reason and stale.graph.stale_reason:find(code_sha:sub(1, 12), 1, true),
    "the reason names the commit"
  )
  eq(stale.complete, false, "a stale graph is never complete")
  eq(
    list(stale.specs),
    "TESTS/b_spec.lua,TESTS/c_spec.lua",
    "a stale graph still answers, it just says so"
  )
  ok(stale.graph.commit ~= stale.graph.head, "map commit and HEAD differ")

  -- verify: the edit added a symbol but no require edge, so the graph of the old
  -- map is still the graph of the tree: a rescan settles "stale" exactly.
  local verified = testing.affected_specs({
    root = root,
    changed = { "lua/p/a.lua" },
    verify = true,
  })
  eq(verified.graph.stale, false, "verify: a map whose graph equals a fresh scan is not stale")
  eq(verified.graph.verified, true, "...and is marked verified")
  eq(verified.complete, true, "...so the answer is complete")
  eq(stale.graph.verified, nil, "without verify the stale answer is not marked")

  -- a new require edge changes the graph: the old map no longer describes it.
  module_file(root, "d", { "p.a" })
  commit_all(root, "d requires a")
  local drifted = testing.affected_specs({
    root = root,
    changed = { "lua/p/a.lua" },
    verify = true,
  })
  eq(drifted.graph.stale, true, "verify: a map that differs from a fresh scan stays stale")
  eq(drifted.graph.verified, nil, "...and is not marked verified")
  require("documentation").generate({ root = root, source = "lua/p", title = "p", luals = false })
  local map_path = root .. "/docs/map/module_map.json"
  local fd = assert(io.open(map_path, "rb"))
  local map_text = fd:read("*a")
  fd:close()
  write(map_path, map_text .. "\n")
  commit_all(root, "map rewritten")
  local again = testing.affected_specs({ root = root, changed = { "lua/p/a.lua" } })
  eq(again.graph.stale, false, "a map committed after the code is fresh again")
  eq(again.complete, true, "...and the answer is complete again")

  -- Outside git the age cannot be established: stale, with the reason.
  local nogit = tmpdir() .. "/q"
  write(nogit .. "/lua/p/a.lua", "---@module 'p.a'\n--- A.\nreturn {}\n")
  require("documentation").generate({ root = nogit, source = "lua/p", title = "q", luals = false })
  local ng = testing.affected_specs({ root = nogit, changed = { "lua/p/a.lua" } })
  eq(ng.graph.stale, true, "no git: the graph is reported stale, never fresh")
  ok(ng.graph.stale_reason:find("no git", 1, true), "...with the reason")
  ok(ng.graph.generated_at, "...and still a generated_at from the file")

  -- ------------------------------------------------ since
  local since_root = project()
  write(
    since_root .. "/lua/p/c.lua",
    "---@module 'p.c'\n--- c edited.\nlocal b = require('p.b')\nreturn {}\n"
  )
  write(since_root .. "/lua/p/untracked.lua", "return {}\n")
  local sres = testing.affected_specs({ root = since_root, since = "HEAD" })
  ok(sres, "since=HEAD answers")
  eq(list(sres.specs), "TESTS/c_spec.lua", "since lists the modified file")
  eq(gap_kinds(sres).changed_not_in_graph, 1, "...and the untracked file, which is not in the map")
  local bad, bad_err = testing.affected_specs({ root = since_root, since = "--output=/tmp/x" })
  eq(bad, nil, "an option-shaped revision is refused")
  ok(bad_err:find("valid revision", 1, true), "...with a reason")
  eq(
    (testing.affected_specs({ root = since_root, since = "no such ref" })),
    nil,
    "whitespace is refused"
  )
  local missing = testing.affected_specs({ root = since_root, since = "definitely-not-a-ref" })
  eq(missing, nil, "an unknown revision is an error, not an empty selection")

  -- ------------------------------------------------ hostile input
  local hostile = testing.affected_specs({
    root = root,
    changed = {
      "../../etc/passwd",
      "/etc/passwd",
      "C:/Windows/system32/x.lua",
      "lua/p/a.lua\0evil",
      "lua/../../x",
      42,
      {},
      "",
      string.rep("a/", 800) .. "x.lua",
    },
    spec_roots = { "../outside", "/abs", 7, "nonexistent_dir" },
  })
  ok(hostile, "hostile entries do not make the call fail")
  eq(gap_kinds(hostile).invalid_path, 9, "every hostile changed entry is refused and reported")
  eq(gap_kinds(hostile).invalid_spec_root, 4, "every bad spec root is refused and reported")
  eq(hostile.complete, false, "refused input makes the answer incomplete")
  eq(
    (testing.affected_specs({ root = root, changed = "lua/p/a.lua" })),
    nil,
    "changed must be a list"
  )
  eq((testing.affected_specs({ root = root .. "/nope", changed = {} })), nil, "root must exist")
  eq((testing.affected_specs(nil)), nil, "opts must be a table")

  local many = {}
  for i = 1, testing.MAX_CHANGED + 1 do
    many[i] = "f" .. i
  end
  local capped, cap_err = testing.affected_specs({ root = root, changed = many })
  eq(capped, nil, "an absurd change list is refused: run everything")
  ok(cap_err:find("run everything", 1, true), "...saying so")

  -- spec_roots: an explicit extra directory and a single file are honoured
  write(root .. "/extra/e_spec.lua", "local a = require('p.a')\n")
  write(root .. "/extra/sub/notaspec.lua", "local a = require('p.a')\n")
  write(root .. "/one.lua", "local a = require('p.d')\n")
  local extra = testing.affected_specs({
    root = root,
    changed = { "lua/p/a.lua", "lua/p/d.lua" },
    spec_roots = { "extra", "one.lua" },
  })
  eq(
    list(extra.specs),
    "TESTS/b_spec.lua,TESTS/c_spec.lua,extra/e_spec.lua,one.lua",
    "spec_roots add a directory (only *_spec.lua) and an explicit file"
  )

  -- ------------------------------------------------ hostile map
  local function with_map(text)
    local r = tmpdir() .. "/m"
    write(r .. "/docs/map/module_map.json", text)
    write(r .. "/TESTS/a_spec.lua", "local a = require('x.a')\n")
    return r
  end

  local nomap = tmpdir() .. "/none"
  vim.fn.mkdir(nomap, "p")
  local r1, e1 = testing.affected_specs({ root = nomap, changed = { "a.lua" } })
  eq(r1, nil, "no map: no answer")
  ok(e1:find("no module map", 1, true), "...and the error says to generate it")

  local r2, e2 = testing.affected_specs({ root = with_map("not json {"), changed = { "a.lua" } })
  eq(r2, nil, "a corrupt map: no answer")
  ok(e2:find("not usable", 1, true), "...saying the map is not usable")

  local garbage = vim.json.encode({
    meta = { source = { "../../x", 5, "-rf" } },
    nodes = {
      {
        id = "lua/x/a.lua",
        path = "lua/x/a.lua",
        module = "x.a",
        requires = "oops",
        required_by = { 1, {}, "lua/x/b.lua" },
      },
      {
        id = "lua/x/b.lua",
        path = "lua/x/b.lua",
        module = "x.b",
        requires = { "lua/x/a.lua", false },
        required_by = { "lua/x/a.lua" },
      },
      "not a node",
      { id = 7 },
    },
  })
  local hroot = with_map(garbage)
  local r3, e3 = testing.affected_specs({ root = hroot, changed = { "lua/x/a.lua" } })
  ok(r3, "a map with malformed nodes is sanitised, not fatal: " .. tostring(e3))
  eq(list(r3.specs), "TESTS/a_spec.lua", "...and still answers from what is well-formed")
  -- cyclic required_by must terminate
  eq(r3.graph.stale, true, "an untracked map of a non-repository is stale")

  -- ------------------------------------------------ cross repository
  local base = tmpdir()
  local lib = base .. "/lib"
  write(lib .. "/lua/l/x.lua", "---@module 'l.x'\n--- x.\nreturn {}\n")
  write(
    lib .. "/lua/l/y.lua",
    "---@module 'l.y'\n--- y, requires x.\nlocal x = require('l.x')\nreturn {}\n"
  )
  write(lib .. "/TESTS/x_spec.lua", "local x = require('l.x')\n")
  git(lib, "init", "-q")
  require("documentation").generate({ root = lib, source = "lua/l", title = "lib", luals = false })
  commit_all(lib, "lib")

  -- measured consumer: one module requires l.y, one spec covers that module, one requires l.x directly
  local c1 = base .. "/consumer1"
  write(
    c1 .. "/lua/c1/mod.lua",
    "---@module 'c1.mod'\n--- m.\nlocal y = require('l.y')\nreturn {}\n"
  )
  write(
    c1 .. "/lua/c1/top.lua",
    "---@module 'c1.top'\n--- t.\nlocal m = require('c1.mod')\nreturn {}\n"
  )
  write(c1 .. "/lua/c1/other.lua", "---@module 'c1.other'\n--- o.\nreturn {}\n")
  write(c1 .. "/TESTS/top_spec.lua", "local t = require('c1.top')\n")
  write(c1 .. "/TESTS/direct_spec.lua", "local x = require('l.x')\n")
  write(c1 .. "/TESTS/other_spec.lua", "local o = require('c1.other')\n")
  git(c1, "init", "-q")
  require("documentation").generate({ root = c1, source = "lua/c1", title = "c1", luals = false })
  commit_all(c1, "c1")

  -- uncovered consumer: affected, no spec
  local c2 = base .. "/consumer2"
  write(c2 .. "/lua/c2/m.lua", "---@module 'c2.m'\n--- m.\nlocal x = require('l.x')\nreturn {}\n")
  git(c2, "init", "-q")
  require("documentation").generate({ root = c2, source = "lua/c2", title = "c2", luals = false })
  commit_all(c2, "c2")

  -- not measured: a Lua checkout without a map, one with a corrupt map
  write(base .. "/nomap/lua/n/a.lua", "return {}\n")
  write(base .. "/corrupt/lua/n/a.lua", "return {}\n")
  write(base .. "/corrupt/docs/map/module_map.json", "{ not json")
  -- not a Lua checkout at all, a hidden directory, a plain file: not listed
  write(base .. "/notes/readme.txt", "x")
  write(base .. "/.hidden/lua/a.lua", "x")
  write(base .. "/loose.txt", "x")
  -- a measured consumer that does not use the library: not listed
  write(base .. "/innocent/lua/i/a.lua", "---@module 'i.a'\n--- i.\nreturn {}\n")
  require("documentation").generate({
    root = base .. "/innocent",
    source = "lua/i",
    title = "i",
    luals = false,
  })

  local cross =
    testing.affected_specs({ root = lib, changed = { "lua/l/x.lua" }, consumers = base })
  local by_repo = {}
  for _, c in ipairs(cross.cross_repo) do
    by_repo[c.repo] = c
  end
  eq(by_repo.consumer1.measured, true, "a consumer with a map is measured")
  eq(
    list(by_repo.consumer1.specs),
    "TESTS/direct_spec.lua,TESTS/top_spec.lua",
    "consumer specs: through the graph (top -> mod -> l.y -> l.x) and by a direct require; the unrelated spec is left out"
  )
  eq(by_repo.consumer1.uncovered, false, "a covered consumer is not uncovered")
  eq(by_repo.consumer2.measured, true, "a second consumer is measured")
  eq(by_repo.consumer2.uncovered, true, "an affected consumer without a covering spec says so")
  eq(by_repo.nomap.measured, false, "a Lua checkout without a map is NOT MEASURED, not unaffected")
  eq(by_repo.nomap.reason, "no committed module map", "...with the reason")
  eq(by_repo.corrupt.measured, false, "a corrupt consumer map is not measured")
  ok(by_repo.corrupt.reason:find("not usable", 1, true), "...saying why")
  eq(by_repo.notes, nil, "a directory that is not a Lua checkout is not listed")
  eq(by_repo[".hidden"], nil, "a hidden directory is not listed")
  eq(by_repo.innocent, nil, "a measured consumer that does not use the change is not listed")
  eq(by_repo.lib, nil, "the repository itself is not its own consumer")
  eq(cross.specs[1], "TESTS/x_spec.lua", "the local specs are still answered")

  local no_dir = testing.affected_specs({ root = lib, changed = { "lua/l/x.lua" } })
  eq(#no_dir.cross_repo, 0, "without a consumers directory there is no cross-repo section")
  local bad_dir = testing.affected_specs({
    root = lib,
    changed = { "lua/l/x.lua" },
    consumers = base .. "/missing",
  })
  eq(#bad_dir.cross_repo, 0, "a missing consumers directory yields nothing...")
  ok(bad_dir.graph.cross_repo_note, "...and a note that nothing was looked at")

  -- ------------------------------------------------ spec_state and status
  local state, serr = testing.spec_state({ root = root })
  ok(state, "spec_state answers: " .. tostring(serr))
  eq(state.nodes["lua/p/a.lua"].spec_count, 0, "a is required by no spec directly")
  eq(
    state.nodes["lua/p/a.lua"].indirect_count,
    2,
    "...but b's and c's specs reach it through the graph"
  )
  eq(state.nodes["lua/p/b.lua"].spec_count, 1, "b has its own spec")
  eq(list(state.nodes["lua/p/b.lua"].specs), "TESTS/b_spec.lua", "...named")
  eq(
    state.nodes["lua/p/d.lua"].spec_count + state.nodes["lua/p/d.lua"].indirect_count,
    0,
    "d has none at all"
  )
  eq(state.totals.without_specs >= 1, true, "the totals count a module without any spec")
  eq(state.nodes["lua/p/b.lua"].last_status, nil, "no status known without a run result")

  local result_ir = vim.json.encode({
    schema_version = 1,
    run = {},
    summary = {},
    cases = {
      { id = "x", file = "TESTS/b_spec.lua", status = "pass" },
      { id = "y", file = "TESTS/b_spec.lua", status = "fail" },
      { id = "z", file = "TESTS/c_spec.lua", status = "pass" },
      { id = "w", file = "TESTS/c_spec.lua", status = "bogus" },
      { id = "v", file = "../../etc/passwd", status = "fail" },
      { id = "u", file = "TESTS/b_spec.lua\n::error::x", status = "crash" },
      "junk",
    },
  })
  write(root .. "/last.json", result_ir)
  local with = testing.spec_state({ root = root, status_file = root .. "/last.json" })
  eq(with.nodes["lua/p/b.lua"].last_status, "fail", "the worst case status represents the spec")
  eq(
    with.nodes["lua/p/c.lua"].last_status,
    "pass",
    "an unknown status word is ignored, not trusted"
  )
  eq(with.status.kind, "result-ir", "the kind of the source is reported")
  eq(with.nodes["lua/p/d.lua"].last_status, nil, "a module without specs has no status")
  ok(
    not vim.json.encode(with):find("etc/passwd", 1, true),
    "no foreign path from the file reaches the answer"
  )

  local history = vim.json.encode({
    v = 1,
    run = "r1",
    ts = 1700000000,
    summary = {},
    failed = { "TESTS/c_spec.lua::a::b", 5 },
  })
  write(root .. "/runs.jsonl", "garbage line\n" .. history .. "\n")
  local hist = testing.spec_state({ root = root, status_file = root .. "/runs.jsonl" })
  eq(hist.status.kind, "history", "a run history is understood")
  eq(hist.nodes["lua/p/c.lua"].last_status, "fail", "a remembered failure marks its spec file")
  eq(
    hist.nodes["lua/p/b.lua"].last_status,
    nil,
    "a file with no recorded failure stays unknown, not passed"
  )
  ok(#hist.notes > 0, "the unusable line is reported")

  write(root .. "/big.json", string.rep("x", 4 * 1024 * 1024 + 10))
  local big = testing.spec_state({ root = root, status_file = root .. "/big.json" })
  eq(big.nodes["lua/p/b.lua"].last_status, nil, "an oversized status file is ignored")
  ok(big.notes[1] and big.notes[1]:find("larger", 1, true), "...with a note")
  write(root .. "/wrong.json", vim.json.encode({ schema_version = 99, cases = {} }))
  local wrong = testing.spec_state({ root = root, status_file = root .. "/wrong.json" })
  ok(
    wrong.notes[1]:find("unknown result schema", 1, true),
    "an unknown schema version is ignored with a note"
  )
  local gone = testing.spec_state({ root = root, status_file = root .. "/does-not-exist.json" })
  ok(gone.notes[1]:find("not found", 1, true), "a missing status file is a note, not an error")
  local weird = testing.spec_state({ root = root, status_file = 42 })
  ok(weird, "a non-string status_file does not break the answer")

  -- the standard history location is derived from the project like testing.nvim does
  local status = require("documentation.testing.status")
  local hdir = status.history_dir(root, "/state")
  ok(
    hdir:match("^/state/testing/p%-%x%x%x%x%x%x%x%x%x%x%x%x$"),
    "history dir: <state>/testing/<name>-<12 hex>"
  )

  -- ------------------------------------------------ the map: opt-in rendering
  local function files(opts)
    local r = tmpdir() .. "/g"
    write(r .. "/lua/g/init.lua", "---@module 'g'\n--- G.\nreturn {}\n")
    write(r .. "/lua/g/used/init.lua", "---@module 'g.used'\n--- Used.\nreturn {}\n")
    write(r .. "/lua/g/bare/init.lua", "---@module 'g.bare'\n--- Bare.\nreturn {}\n")
    write(r .. "/TESTS/used_spec.lua", "local u = require('g.used')\n")
    local o = vim.tbl_extend(
      "force",
      { root = r, source = "lua/g", title = "g", luals = false },
      opts or {}
    )
    require("documentation").generate(o)
    local function read(p)
      local f = assert(io.open(r .. "/docs/map/" .. p, "rb"))
      local t = f:read("*a")
      f:close()
      return t
    end
    return {
      json = read("module_map.json"),
      html = read("index.html"),
      md = read("overview.md"),
      root = r,
    }
  end

  local off = files()
  local off2 = files({ spec_state = false })
  eq(off.md, off2.md, "spec_state=false changes nothing in the markdown")
  eq(off.html:find('"spec_state"', 1, true), nil, "...nor the page's data")
  ok(
    off.md:find("| Module | Description | Fns | Docs |", 1, true),
    "the table header is the old one"
  )
  ok(not off.md:find("Specs", 1, true), "no Specs column without the option")

  local on = files({ spec_state = true })
  eq(on.json, off.json, "module_map.json never carries spec state (it must stay deterministic)")
  ok(
    on.md:find("| Module | Description | Fns | Docs | Specs |", 1, true),
    "the markdown gets a Specs column"
  )
  ok(
    on.md:find("`g.used`", 1, true) and on.md:find("1 spec", 1, true),
    "a module with a spec says so"
  )
  ok(on.md:find("no specs", 1, true), "a module without any spec says so")
  ok(on.html:find('"spec_state"', 1, true), "the page carries the data")
  ok(on.html:find("no specs", 1, true), "...and the renderer for the detail panel")
  -- the embedded JSON must not be able to close its script block
  local hostile_state = vim.json.encode({ x = "</script><script>alert(1)</script>" })
  ok(hostile_state:find("<", 1, true), "sanity: the probe string contains markup")
  eq(on.html:find("</script><script>alert", 1, true), nil, "the page holds no injected script")

  -- The generated page's own script still parses: a syntax slip in the added
  -- detail-panel code would blank the whole page. Needs `node`, which every CI
  -- runner image ships; a machine without it fails here on purpose.
  ok(vim.fn.executable("node") == 1, "node is required for the page syntax check")
  local biggest = ""
  for body in on.html:gmatch("<script>(.-)</script>") do
    if #body > #biggest then
      biggest = body
    end
  end
  ok(#biggest > 10000, "the page's main script was found")
  local js = tmpdir() .. "/page.js"
  write(js, biggest)
  if vim.fn.executable("node") == 1 then
    local check = vim.system({ "node", "--check", js }, { text = true }):wait()
    eq(check.code, 0, "the page script has valid syntax: " .. tostring(check.stderr))
  end

  -- ------------------------------------------------ the spec scanner
  local specs = require("documentation.testing.specs")
  local mods, prefixes, dynamic = specs.scan_text([[
local a = require("x.a")
local b = require 'x.b'
local ok, c = pcall(require, "x.c")
-- local d = require("x.commented")
local e = require("x.dialect." .. name)
]])
  eq(list(mods), "x.a,x.b,x.c", "literal requires, all three spellings, comments ignored")
  eq(list(prefixes), "x.dialect.", "a computed name yields its literal prefix")
  eq(dynamic, false, "a prefix is not a dynamic require")
  local _, _, dyn1 = specs.scan_text("local m = require(name)\n")
  eq(dyn1, true, "require(variable) is dynamic")
  local _, _, dyn2 = specs.scan_text("local ok, m = pcall(require, name)\n")
  eq(dyn2, true, "pcall(require, variable) is dynamic")
  local _, _, dyn3 = specs.scan_text("-- require(name)\nlocal a = require('x')\n")
  eq(dyn3, false, "a commented-out dynamic require does not count")

  eq(specs.clean_rel("./a//b/../c"), "a/c", "clean_rel resolves . and ..")
  eq(specs.clean_rel("../a"), nil, "clean_rel refuses a climb out")
  eq(specs.clean_rel("a/../../b"), nil, "clean_rel refuses a late climb out")
  eq(specs.clean_rel("C:/a"), nil, "clean_rel refuses a drive path")
  eq(specs.clean_rel("/a"), nil, "clean_rel refuses an absolute path")
  eq(specs.clean_rel("a\0b"), nil, "clean_rel refuses a NUL byte")

  local gitq = require("documentation.testing.git")
  eq(gitq.valid_rev("HEAD~3"), true, "a plain revision is accepted")
  eq(gitq.valid_rev("origin/main@{1}"), true, "a reflog revision is accepted")
  eq(gitq.valid_rev("--upload-pack=x"), false, "an option-shaped revision is refused")
  eq(gitq.valid_rev("a b"), false, "whitespace is refused")
  eq(gitq.valid_rev("a..b"), false, "a range is refused")
  eq(gitq.valid_rev(string.rep("a", 201)), false, "an overlong revision is refused")

  local fresh_mod = require("documentation.testing.freshness")
  eq(
    list(fresh_mod.source_pathspecs({ source = { "lua/x", "../y", "-z", "/abs", 5, "C:/w" } })),
    "lua,lua/x",
    "hostile source entries of a map never become pathspecs"
  )

  -- ------------------------------------------------ the documented schema matches the answer
  local repo_root = (debug.getinfo(1, "S").source:sub(2):match("(.*)[/]TESTS[/]")) or "."
  local sf = assert(io.open(repo_root .. "/docs/affected-specs.schema.json", "rb"))
  local schema = vim.json.decode(sf:read("*a"))
  sf:close()
  ---@param value table
  ---@param props table<string, table>
  ---@param what string
  local function within(value, props, what)
    for k in pairs(value) do
      ok(props[k] ~= nil, ("%s: field %q is not in the schema"):format(what, k))
    end
  end
  local sample = { res, hostile, cross, gap, unknown, support, stale }
  for _, answer in ipairs(sample) do
    within(answer, schema.properties, "answer")
    eq(answer.version, schema.properties.version.const, "the answer's version is the schema's")
    for _, k in ipairs(schema.required) do
      ok(answer[k] ~= nil, ("answer: required field %q is present"):format(k))
    end
    within(answer.graph, schema.definitions.graph.properties, "graph")
    local kinds_ok = {}
    for _, kind in ipairs(schema.definitions.gap.properties.kind.enum) do
      kinds_ok[kind] = true
    end
    for _, g in ipairs(answer.graph.gaps) do
      ok(kinds_ok[g.kind], ("gap kind %q is documented"):format(g.kind))
      within(g, schema.definitions.gap.properties, "gap")
    end
    for _, m in ipairs(answer.modules) do
      within(m, schema.properties.modules.items.properties, "module")
    end
    for _, c in ipairs(answer.cross_repo) do
      within(c, schema.definitions.consumer.properties, "cross_repo entry")
    end
  end

  for _, d in ipairs(made) do
    vim.fn.delete(d, "rf")
  end
end
