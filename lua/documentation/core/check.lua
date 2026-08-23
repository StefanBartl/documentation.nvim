---@module 'documentation.core.check'
--- Drift checks over a docmap IR.
---
--- This is the half of docmap that earns its keep. A rendered map is a nice
--- artifact; a map that *fails* when documentation and reality diverge is a
--- test. Every check here corresponds to a defect class actually observed in
--- the tree it was written against — most sharply `lib.find_root`, which was
--- declared on the aggregate `Lib` class but wired into none of the export
--- strategies, so the published type was simply false and stayed that way
--- until it was found by accident.
---
--- Checks are pluggable: the generic ones below make no assumption beyond
--- "annotated Lua tree", and anything repo-specific (aggregator wiring, for
--- instance) is passed in through `opts.extra_checks` so another plugin can
--- reuse this file without inheriting another repository's conventions.

local M = {}

local uv = vim.uv
local docs = require("documentation.core.docs")

---Record a finding.
---
---`params` rather than a rendered sentence: the text is produced at the
---edge that shows it, by `core/findings.lua`. See that module's header for
---why — in one line, a sentence built here cannot be reordered for a
---language that puts its pieces in a different order.
---
---Nothing here validates that the catalog has a key for `check`. That is
---`findings_spec.lua`'s job, because a scan must not die over a missing
---string, and an unknown key still renders visibly rather than blank.
---@param list Documentation.Finding[]
---@param severity Documentation.Severity
---@param check string
---@param node_id string?
---@param params table<string, any> Values for the catalog template. `variant` selects a sub-template.
local function add(list, severity, check, node_id, params)
  list[#list + 1] = { severity = severity, check = check, node = node_id, params = params }
end

---Derive the module path a file *should* declare from where it lives.
---
---Exported because it is also the only sane way to name a **namespace**: a
---directory without `init.lua` declares no `@module` at all, but
---`lua/lib/nvim/fs` is still "lib.nvim.fs" to anyone typing it — and those
---directories are exactly the aggregation points a dependency graph is asked
---about. Deriving it in a second place would be a drift risk.
---@param path string Repo-relative, forward slashes
---@param lua_root string
---@return string|nil
function M.expected_module(path, lua_root)
  local prefix = lua_root .. "/"
  if path:sub(1, #prefix) ~= prefix then
    return nil
  end
  local rest = path:sub(#prefix + 1)
  rest = rest:gsub("%.lua$", ""):gsub("/init$", "")
  return (rest:gsub("/", "."))
end

--- Whether this node's language backend uses a `@module`-tag-shaped
--- authoring convention worth checking the absence of. Lua does — a Lua
--- module's canonical dotted name cannot be recovered from its file path
--- alone in general, which is the entire reason `expected_module`/
--- `module-path-mismatch` exist. A language whose module identity already
--- *is* its file path (JS/TS's ESM imports resolve by path, not by an
--- internal tag) has nothing to be missing, and firing an error-severity
--- finding on every such file would be a real regression the moment a
--- second backend without the convention exists — not a hypothetical one.
---
--- Read through the registry, never a specific backend: the same rule
--- `layer-violation` enforces everywhere else in `core`.
---@param node Documentation.Node
---@return boolean
local function wants_module_tag(node)
  if not node.source then
    return true
  end
  local backend = require("documentation.core.lang_registry").for_file(
    node.source:match("([^/]+)$") or node.source
  )
  -- No backend found (or one that never states an opinion): preserve
  -- today's behavior rather than silently waive the check on an unknown
  -- shape of node.
  return not backend or backend.module_tag ~= false
end

--- Every module and helper file should say what it is in one sentence — that
--- sentence is what the map, the README tables and the vimdoc all render.
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
local function check_summaries(ir, findings)
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.kind ~= "namespace" then
      if wants_module_tag(node) and not node.module then
        add(findings, "error", "missing-module-tag", id, { file = node.source or id })
      elseif node.summary == "" then
        add(findings, "warn", "missing-summary", id, { file = node.source or id })
      end
    end
  end
end

--- A copy-pasted module header that still names its origin is invisible in
--- review and actively misleading in the map.
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
---@param opts Documentation.Opts
local function check_module_paths(ir, findings, opts)
  local lua_root = opts.lua_root or "lua"
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.module and node.source then
      local want = M.expected_module(node.source, lua_root)
      if want and want ~= node.module then
        add(
          findings,
          "error",
          "module-path-mismatch",
          id,
          { file = node.source, declared = node.module, expected = want }
        )
      end
    end
  end
end

--- Not every module needs a README, but the absence should be a decision
--- rather than an oversight, so this is reported at `info`.
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
local function check_readmes(ir, findings)
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.kind == "module" and not node.readme then
      add(findings, "info", "missing-readme", id, { path = node.path })
    end
  end
end

--- Resolve a markdown link `target` relative to `base_dir` (repo-relative,
--- no trailing slash), walking `..`/`.` segments. Shared by both passes
--- below: a module README and a bare `docs/` file resolve their own
--- relative links identically, only `base_dir` differs, and it is always
--- the linking file's own directory — verified against every `node.readme`
--- in this repo's own map, never a mismatch.
---
--- **Moved to `docs.resolve_link` 2026-08-20**, when `render/markdown.lua`
--- turned out to need the same walk to rebase a summary's links into the
--- artifact directory. Two copies of a path resolver is the drift this
--- plugin reports in other people's trees.
local resolve_relative_link = docs.resolve_link

--- Blank out fenced code blocks and inline code spans, so link-shaped text
--- inside an example (this repo's own `` `[text](url)` `` in
--- `FEATURES_FORMAT.md`, describing markdown link syntax rather than
--- linking anywhere) is never mistaken for a real link. Mirrors
--- `docs.code_spans`'s own fence/double-backtick handling, but blanks
--- rather than extracts, and preserves line structure (irrelevant here,
--- since callers only re-scan the result for links, but cheap to keep).
---@param content string
---@return string
local function strip_code(content)
  local out = {}
  local fence = nil
  for line in (content .. "\n"):gmatch("([^\n]*)\n") do
    local f = line:match("^%s*(```+)") or line:match("^%s*(~~~+)")
    if fence then
      if f and f:sub(1, 1) == fence:sub(1, 1) and #f >= #fence then
        fence = nil
      end
      out[#out + 1] = ""
    elseif f then
      fence = f
      out[#out + 1] = ""
    else
      out[#out + 1] = line:gsub("``.-``", ""):gsub("`[^`]+`", "")
    end
  end
  return table.concat(out, "\n")
end

--- Relative links in any repo markdown file, checked against the tree.
---
--- Two passes over the same idea: a module README (`node.readme`, attached
--- to a scanned node) and every other `.md` file in the repository
--- (`docs.corpus(opts)`, already built for `doc-references-missing` and
--- reused here rather than walking the tree a second time). A moved module
--- or a docs reorganisation silently leaves 404s behind in either — this
--- checked only the first half until now.
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
---@param opts Documentation.Opts
local function check_readme_links(ir, findings, opts)
  local root = opts.root:gsub("\\", "/"):gsub("/+$", "")
  local checked = {}

  local function check_file(rel_path, node_id)
    checked[rel_path] = true
    local fd = io.open(root .. "/" .. rel_path, "r")
    if not fd then
      return
    end
    local content = strip_code(fd:read("*a"))
    fd:close()
    local base_dir = rel_path:match("(.*)/[^/]+$") or ""
    local seen = {}
    for target in content:gmatch("%]%(([^)#]+)%)") do
      if not target:match("^%a+://") and not target:match("^#") and not seen[target] then
        seen[target] = true
        local resolved = resolve_relative_link(base_dir, target)
        if not uv.fs_stat(root .. "/" .. resolved) then
          add(findings, "warn", "dead-readme-link", node_id, { file = rel_path, target = target })
        end
      end
    end
  end

  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.readme then
      check_file(node.readme, id)
    end
  end

  for _, rel_path in ipairs(docs.corpus(opts)) do
    if not checked[rel_path] then
      check_file(rel_path, rel_path)
    end
  end
end

--- Prose describing a function that is no longer there.
---
--- Dead code's mirror image, and the one drift in this plugin's whole
--- catalogue that lives outside the source tree entirely: every other check
--- reads annotations sitting next to the code they describe, where a rename
--- at least moves them both in one diff. A `.md` file has no such coupling —
--- it goes stale silently, and nothing but a reader ever notices.
---
--- Reads `ir.docs.missing`, which `docs.lua` fills during `scan_full`. The
--- rule there is deliberately narrow (the mention's longest dotted prefix
--- must be a real module in this map), so this fires on
--- `documentation.core.scan.parse_headr` and stays quiet on `vim.fn.expand`
--- — see that module's header.
---
--- `warn`, matching `dead-see-target` and `dead-readme-link`: a stale
--- reference is a real defect a reader will hit, but it breaks nothing at
--- runtime, so it is not an error.
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
local function check_doc_references(ir, findings)
  for _, m in ipairs((ir.docs or {}).missing or {}) do
    add(
      findings,
      "warn",
      "doc-references-missing",
      m.node,
      { doc = m.doc, line = m.line, text = m.text, module = m.module, missing = m.missing }
    )
  end
end

--- A malformed `docs/install.json`/`docs/INSTALL.md` entry — missing `bin`,
--- empty `why`, no `pkg` map — fails validation in `lib.nvim.deps.spec`
--- silently as far as this plugin is concerned: the entry is simply dropped
--- from `ir.tools.tools`, and nothing before this check ever looked at
--- `ir.tools.errors`. Surfacing it here is what makes a typo'd manifest
--- visible instead of a tool quietly never showing up in the Tools panel.
---
--- `node` is nil on every finding here, same as `luals-unavailable` in
--- `init.lua`: a manifest error belongs to the repo, not to any one scanned
--- module.
---
--- `warn`, matching `doc-references-missing`: a real defect a reader (or
--- `:Lib deps show`) will hit, but nothing at runtime breaks from it.
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
local function check_tools_spec(ir, findings)
  for _, e in ipairs((ir.tools or {}).errors or {}) do
    add(
      findings,
      "warn",
      "tools-spec-invalid",
      nil,
      { source = ir.tools.source, index = e.index, reason = e.message }
    )
  end
end

--- A `require` reaching into another project, checked against that
--- project's own artifact.
---
--- **The mirror of `consumer-require-missing`, from the other side.** That
--- check asks "does a project under `opts.consumers` require something this
--- library no longer declares"; this one asks the same question of *this*
--- tree's own dependencies, using `opts.tag_files` — and between them the
--- two directions of one cross-repository edge are both covered. Neither
--- needs any new extraction: both artifacts already exist.
---
--- **Only `tag_files`, never `external_repos`.** Both resolvers fill
--- `ir.tag_links`, and only one of them is authoritative: a tag file is
--- another checkout's *generated map*, which can say a module is not in it,
--- while `external_repos` is a declared GitHub repo whose URL is often an
--- unverified guess about the path shape. Reading a miss out of the second
--- would be reporting a broken dependency on the strength of a guessed
--- link. This reads `ir.tag_audit`, which `tagfiles.lua` fills and
--- `external_repos.lua` never touches.
---
--- **`tag-file-unavailable` is not an error path — it is the normal one
--- here,** and it exists so this check cannot report a clean bill it did
--- not earn. Every plugin in this ecosystem but `documentation.nvim` itself
--- gitignores `docs/map/`, with a reason worth respecting: a committed map
--- is stale the moment anything it describes changes, nothing but this
--- repository's CI gates that, and across these plugins it came to ~40 MB
--- of artifacts nobody asked for. So the map a tag file points at exists on
--- the author's disk and in no clone — which makes this a local check by
--- nature, and makes silence about it the one unacceptable outcome.
---
--- **Both severities match their mirrors.** A miss is `warn`, like
--- `consumer-require-missing`, and its message carries the same second
--- reading, because the same two explanations always fit: either the
--- require is broken now, or the map it was checked against predates a
--- rename the dependency has already followed. An unreadable tag file is
--- `info`, like `luals-unavailable` — a thing that did not run is not a
--- defect in the tree.
---
--- Measured across this ecosystem before being written: 18 external
--- requires under `lib` from `documentation.nvim` and 23 from
--- `runtime-analysis.nvim`, all 41 resolving against `lib.nvim`'s own map.
--- Zero findings, which is what a healthy ecosystem should produce — so
--- the proof this works is the positive control in its spec, not its
--- silence.
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
local function check_tag_requires(ir, findings)
  local audit = ir.tag_audit
  if not audit then
    return
  end

  for _, miss in ipairs(audit.missing) do
    add(
      findings,
      "warn",
      "tag-require-missing",
      miss.nodes[1],
      { module = miss.module, who = table.concat(miss.nodes, ", "), prefix = miss.prefix }
    )
  end

  for _, gap in ipairs(audit.unavailable) do
    add(findings, "info", "tag-file-unavailable", nil, { prefix = gap.prefix, dir = gap.dir })
  end
end

--- A module that exists on disk but is required by nothing above it was
--- either written and never wired up, or orphaned by a refactor.
---
--- Reads `node.required_by`, which `docmap.deps` fills during the scan. An
--- earlier version re-read every source file here to collect `require` strings
--- into one flat set — which answered this one question and discarded the
--- thing that made a dependency graph possible, namely *which* file each
--- require came from. Same answer now, from data that also draws the Deps
--- view, at no I/O.
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
local function check_orphans(ir, findings)
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.module and node.kind ~= "namespace" and id ~= ir.root then
      -- A module may legitimately be reached only through the aggregator's
      -- string map rather than a literal require, so this stays at `info`.
      if #(node.required_by or {}) == 0 then
        add(findings, "info", "unreferenced-module", id, { module = node.module })
      end
    end
  end
end

--- A `@class` or `@alias` that is declared, documented, and pointed at by
--- nothing. `unreferenced-module` one level down, and structurally the same
--- check: a name the tree carries but no longer uses.
---
--- **Only runs when LuaLS enrichment did.** `node.types_detail` is `nil`
--- when it did not and `{}` when it ran and found nothing, and that
--- distinction is the whole reason this can stay silent instead of
--- reporting every type in the tree as an orphan on a plain `:DocMap`.
---
--- **What counts as a reference, and why it is a token match.** Every
--- `.lua` file the map covers — each node's own source and its `@types`
--- files — is read once and split into dotted-identifier tokens; a type is
--- referenced if its full name is one of them. Tokens rather than a
--- substring search, because the first version of this used
--- `line:find(name)` and `Lib.Fs.Read` was then "referenced" by every
--- mention of `Lib.Fs.ReadAsync`. Measured on lib.nvim, that one difference
--- hid four real orphans.
---
--- **The corpus is the mapped tree, and that was measured rather than
--- assumed.** Two candidates were rejected by counting: adding the test
--- tree changed the result on neither lib.nvim nor runtime-analysis.nvim
--- (0 types referenced only from a spec), and no type in lib.nvim was
--- referenced only from a `.lua` file outside the map — 52 such files,
--- 0 references.
---
--- A type's own declaration line is not a use, but the rest of that line
--- is: `---@class Child : Parent` is the only place `Parent` may ever be
--- named, and dropping the whole line would have made every base class an
--- orphan.
---
--- `info`, matching `unreferenced-module` for the same reason: a published
--- type may legitimately be referenced only by a *consumer* annotating
--- against this library, which is outside anything this tree can see. Real
--- on the tree it was measured against — 24 in lib.nvim, one in
--- runtime-analysis.nvim, all four spot-checked by hand and none a false
--- positive — but not a failure.
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
---@param opts Documentation.Opts
local function check_orphaned_types(ir, findings, opts)
  local root = opts.root:gsub("\\", "/"):gsub("/+$", "")

  ---Every declared type, and the node that owns it.
  local declared = {} ---@type table<string, { node: string, info: Documentation.TypeInfo }>
  local ran = false
  for _, id in ipairs(ir.order) do
    local detail = ir.nodes[id].types_detail
    if detail then
      ran = true
      for _, t in ipairs(detail) do
        declared[t.name] = { node = id, info = t }
      end
    end
  end
  if not ran or not next(declared) then
    return
  end

  local files, seen_file = {}, {}
  local function want(rel)
    if rel and not seen_file[rel] then
      seen_file[rel] = true
      files[#files + 1] = rel
    end
  end
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    want(node.source)
    for _, t in ipairs(node.types or {}) do
      want(t)
    end
  end

  local referenced = {}
  for _, rel in ipairs(files) do
    local fd = io.open(root .. "/" .. rel, "rb")
    if fd then
      for line in fd:lines() do
        local self_decl = line:match("^%s*%-%-%-@class%s+([%w_%.]+)")
          or line:match("^%s*%-%-%-@alias%s+([%w_%.]+)")
        for tok in line:gmatch("[%a_][%w_%.]*") do
          if tok ~= self_decl then
            referenced[tok] = true
          end
        end
      end
      fd:close()
    end
  end

  local names = {}
  for name in pairs(declared) do
    names[#names + 1] = name
  end
  table.sort(names)

  for _, name in ipairs(names) do
    if not referenced[name] then
      local entry = declared[name]
      add(
        findings,
        "info",
        "orphaned-class-alias",
        entry.node,
        { kind = entry.info.kind, name = name, file = entry.info.file }
      )
    end
  end
end

--- Everything one spec file has to say, in a single pattern set so the tree
--- is walked once instead of three times. Measured over this repo's 75 spec
--- files: one walk is ~45ms where three were ~126ms, against ~80ms of
--- parsing that has to happen either way.
---
--- `@bind` is used only to *count*: a name bound twice in one file is one
--- this check refuses to reason about. That is cheaper and more honest than
--- a scope model, and it is what answers the shadowing local measured in
--- runtime-analysis.nvim — a `local config = { host = … }` inside a test
--- body, in a file that also binds `local config = require(…)`.
---
--- **The require pattern is deliberately not anchored on `(chunk …)`.** It
--- was, and profiling caught what reading could not: the anchored version
--- matched *once* across all 75 spec files, because a spec in this ecosystem
--- is `return function(H) … end` and every require sits inside that
--- function. The check was therefore looking at almost nothing while
--- appearing to work. Following a binding across scopes is safe here only
--- because `@bind` counts it first.
local TEST_QUERY = vim.treesitter.query.parse(
  "lua",
  [[
  (variable_declaration (assignment_statement (variable_list (identifier) @bind)))
  (parameters (identifier) @bind)

  (variable_declaration
    (assignment_statement
      (variable_list (identifier) @alias)
      (expression_list
        (function_call
          name: (identifier) @req (#eq? @req "require")
          arguments: (arguments (string) @module)))))

  (dot_index_expression table: (identifier) @tbl field: (identifier) @field)
]]
)

---First node of a capture, across both `iter_matches` shapes.
---@param match table
---@param id integer?
---@return TSNode?
local function first(match, id)
  local v = id and match[id]
  if not v then
    return nil
  end
  return type(v) == "table" and v[1] or v
end

---One spec file: resolve its require-bound members against the tree.
---@param findings Documentation.Finding[]
---@param root string
---@param path string Absolute path of the spec file.
---@param idx Documentation.Docs.Index
---@param surface_of fun(module: string): { enumerable: boolean, members: table<string, boolean> }
local function check_one_test_file(findings, root, path, idx, surface_of)
  local fd = io.open(path, "rb")
  if not fd then
    return
  end
  local src = fd:read("*a")
  fd:close()

  local ok_parser, parser = pcall(vim.treesitter.get_string_parser, src, "lua")
  if not ok_parser then
    return
  end
  local ok_parse, trees = pcall(function()
    return parser:parse()
  end)
  if not ok_parse or not trees or not trees[1] then
    return
  end
  local tree_root = trees[1]:root()

  local cap = {}
  for id, name in ipairs(TEST_QUERY.captures) do
    cap[name] = id
  end

  local bound = {}
  local module_of = {}
  local members = {}

  for _, match in TEST_QUERY:iter_matches(tree_root, src) do
    local bind_node = first(match, cap.bind)
    if bind_node then
      local name = vim.treesitter.get_node_text(bind_node, src)
      bound[name] = (bound[name] or 0) + 1
    end

    local alias_node = first(match, cap.alias)
    local module_node = first(match, cap.module)
    if alias_node and module_node then
      local alias = vim.treesitter.get_node_text(alias_node, src)
      local module = vim.treesitter.get_node_text(module_node, src)
      module_of[alias] = (module:gsub("^['\"]", ""):gsub("['\"]$", ""))
    end

    local tbl_node = first(match, cap.tbl)
    local field_node = first(match, cap.field)
    if tbl_node and field_node then
      members[#members + 1] = {
        alias = vim.treesitter.get_node_text(tbl_node, src),
        field = vim.treesitter.get_node_text(field_node, src),
        row = select(1, tbl_node:range()),
      }
    end
  end

  if not next(module_of) then
    return
  end

  -- An `alias` bound by `local alias = require(…)` is itself a binding, so
  -- the ordinary case counts one. Anything above that is a name this file
  -- reuses, and the check says nothing about it.
  local rel = path:gsub("\\", "/"):gsub("^" .. vim.pesc(root .. "/"), "")
  local reported = {}
  for _, m in ipairs(members) do
    local module = module_of[m.alias]
    if module and bound[m.alias] == 1 then
      local surface = surface_of(module)
      local key = module .. "." .. m.field
      if surface.enumerable and not surface.members[m.field] and not reported[key] then
        reported[key] = true
        add(
          findings,
          "warn",
          "test-references-missing",
          idx.modules[module],
          { file = rel, line = m.row + 1, alias = m.alias, field = m.field, module = module }
        )
      end
    end
  end
end

--- A spec that names a function which no longer exists.
---
--- `doc-references-missing` for the test tree — the same drift class from
--- the other side. `coverage.lua` already maps specs to functions in one
--- direction (`fn.tested`); this is the reverse, and it is where a rename
--- rots most quietly, because a spec can keep passing while naming
--- something gone: `eq(mod.removed, nil)` asserts exactly what a deleted
--- function returns.
---
--- **The coarse technique `coverage.lua` uses would be useless here.** It
--- counts bare identifiers, which errs toward "tested" — the safe direction
--- when the answer only adds a badge. Reversed, that same coarseness would
--- report every local variable in a spec as a missing function. So this
--- resolves a *qualified* shape instead: a `local mod = require("...")`
--- binding, and a `mod.field` access through it.
---
--- **Three classes of false positive, each found by measuring against a
--- real repository rather than reasoned about, and each answered here:**
---
--- 1. **A module-scope re-export.** `M.safe_sha = require("…").safe_sha` is
---    a real member, but `symbols.lua` deliberately drops require bindings
---    (`deps` owns them) and `functions.lua` never saw a declaration. Four
---    findings in this repo, all wrong. Answered by also reading the
---    module's own module-scope assignments.
--- 2. **A surface assembled at runtime.** `lib/init.lua` is literally
---    `return require(require("lib.config").strategy_module())`, and
---    `fs/path/object.lua` returns a `class.new("Path")` result whose
---    `new` no static reader can see. Five findings in lib.nvim, all wrong.
---    Answered by staying silent on any module that does not end in a bare
---    `return <ident>` for an `<ident>` bound to a table constructor — if
---    the surface cannot be enumerated, the check has nothing to say about
---    it.
--- 3. **A shadowing local.** `local config = { host = … }` inside a test
---    body, where the file also has `local config = require(…)` at the top.
---    One finding in runtime-analysis.nvim, wrong. Answered without a scope
---    model: a name declared more than once in a file is skipped entirely,
---    which is the same "fewer findings beat a confident wrong one" trade
---    `calls_heuristic` and `unreferenced-module` already make.
---
--- After all three, the measurement is 0 findings across this repo (694
--- member accesses), lib.nvim (786) and runtime-analysis.nvim (560) — three
--- trees with no such drift in them, which is the result a healthy tree
--- should produce.
---
--- `warn`, matching `doc-references-missing`: a spec naming something gone
--- is a real defect, and usually one the spec's own run would not catch.
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
---@param opts Documentation.Opts
local function check_test_references(ir, findings, opts)
  local root = opts.root:gsub("\\", "/"):gsub("/+$", "")
  local tests_dir = root .. "/" .. (opts.tests_dir or "TESTS")

  local ok_files, files = pcall(function()
    return require("lib.nvim.fs.collect_recursive").files(tests_dir)
  end)
  if not ok_files or not files or #files == 0 then
    return
  end

  local idx = docs.build_index(ir)

  ---Module-scope members of `module` that no other stage records, plus
  ---whether its surface can be enumerated statically at all. One read per
  ---module, cached, and only for modules a spec actually names.
  ---@type table<string, { enumerable: boolean, members: table<string, boolean> }>
  local surface = {}
  local function surface_of(module)
    if surface[module] then
      return surface[module]
    end
    local id = idx.modules[module]
    local node = id and ir.nodes[id]
    local entry = { enumerable = false, members = {} }
    surface[module] = entry
    if not (node and node.source) then
      return entry
    end

    local lines = {}
    local fd = io.open(root .. "/" .. node.source, "r")
    if not fd then
      return entry
    end
    for line in fd:lines() do
      lines[#lines + 1] = line
    end
    fd:close()

    -- The exported table, and whether it is a plain one. A bare
    -- `return M` only: `return setmetatable(M, {...})` is how this tree
    -- adds a lazy `__index`, which is exactly a surface no static reader
    -- can enumerate, so it belongs with case 2 above rather than beside a
    -- literal table.
    local exported
    for i = #lines, 1, -1 do
      local name = lines[i]:match("^return%s+([%a_][%w_]*)%s*$")
      if name then
        exported = name
        break
      end
      if lines[i]:match("%S") and not lines[i]:match("^%s*%-%-") then
        break
      end
    end
    if not exported then
      return entry
    end
    local literal = false
    for _, line in ipairs(lines) do
      if line:match("^local%s+" .. exported .. "%s*=%s*{%s*}%s*$") then
        literal = true
        break
      end
    end
    if not literal then
      return entry
    end

    entry.enumerable = true
    for _, line in ipairs(lines) do
      local name = line:match("^%s*" .. exported .. "%.([%w_]+)%s*=")
        or line:match("^%s*function%s+" .. exported .. "[%.:]([%w_]+)%s*%(")
      if name then
        entry.members[name] = true
      end
    end
    for _, s in ipairs(node.symbols or {}) do
      entry.members[docs.bare_name(s.name)] = true
    end
    for member in pairs(idx.fns_by_module[module] or {}) do
      entry.members[member] = true
    end
    return entry
  end

  for _, path in ipairs(files) do
    if path:sub(-4) == ".lua" then
      check_one_test_file(findings, root, path, idx, surface_of)
    end
  end
end

--- Strongly connected components of the **load-time** require graph.
---
--- Exported because two callers need exactly this: the drift check below, and
--- `docmap.diff`, which reports cycles a change introduced. Duplicating
--- Tarjan for the second one would have been two implementations of the one
--- thing in this module most likely to be subtly wrong.
---
--- Deferred requires — `require(...)` inside a function body, the standard way
--- this tree breaks initialisation order on purpose — are excluded, which is
--- why this builds its own adjacency instead of reusing `node.requires`. Run
--- against lib.nvim without that exclusion, every cycle reported was a
--- deliberate lazy load: a check that only ever fires on intentional code is
--- one people learn to skim past, so it would have cost the real ones too.
---
--- Iterative rather than recursive: the graph is as deep as the tree is wide
--- and Lua's default C stack is not something to spend here.
---@param ir Documentation.IR
---@return string[][] components Each sorted, each with at least two members.
function M.require_cycles(ir)
  local adj = {}
  for _, id in ipairs(ir.order) do
    adj[id] = {}
  end
  for _, edge in ipairs(ir.edges or {}) do
    if edge.kind == "require" and not edge.deferred and adj[edge.from] then
      adj[edge.from][#adj[edge.from] + 1] = edge.to
    end
  end

  local components = {}
  local index, low, on_stack, idx = {}, {}, {}, 0
  local stack = {}

  for _, start in ipairs(ir.order) do
    if index[start] == nil then
      -- Each frame carries its own child cursor, which is what turns the
      -- recursive formulation into a loop without changing the algorithm.
      local frames = { { id = start, child = 1 } }

      while #frames > 0 do
        local frame = frames[#frames]
        local id = frame.id

        if frame.child == 1 then
          index[id], low[id] = idx, idx
          idx = idx + 1
          stack[#stack + 1] = id
          on_stack[id] = true
        end

        local children = adj[id] or {}
        local advanced = false

        while frame.child <= #children do
          local child = children[frame.child]
          frame.child = frame.child + 1
          if index[child] == nil then
            frames[#frames + 1] = { id = child, child = 1 }
            advanced = true
            break
          elseif on_stack[child] then
            low[id] = math.min(low[id], index[child])
          end
        end

        if not advanced then
          if low[id] == index[id] then
            local component = {}
            repeat
              local popped = table.remove(stack)
              on_stack[popped] = false
              component[#component + 1] = popped
            until popped == id
            if #component > 1 then
              table.sort(component)
              components[#components + 1] = component
            end
          end

          table.remove(frames)
          local parent = frames[#frames]
          if parent then
            low[parent.id] = math.min(low[parent.id], low[id])
          end
        end
      end
    end
  end

  table.sort(components, function(a, b)
    return a[1] < b[1]
  end)
  return components
end

--- A cycle among load-time requires is the one that actually breaks: two
--- modules that require each other at the top of the file get a
--- half-initialised table on the second one in, and the failure reads as
--- anything but a cycle. Reported at `warn`, so `--check` does not go red over
--- a deliberate one.
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
---Two places registering the same binding, where the second silently wins.
---
---The one check in this file that is meaningless for a plugin and valuable
---for a *config*. A Neovim config is where `<leader>ff` gets bound in
---`lua/bindings/mappings/telescope.lua` and again, months later, in
---`lua/plugins/fzf.lua` — after which one of them simply never fires, with
---nothing anywhere saying so. `:map <leader>ff` shows the winner and gives
---no hint that there was a loser.
---
---No new extraction: `core/bindings.lua` has collected `lhs`, `modes`,
---`buffer` and the registering line since it shipped. This is a check over
---data the artifact already carries.
---
---Three things it deliberately does not report, each of which would make it
---the noisy check nobody keeps enabled:
---
---  * **Buffer-local against global.** Shadowing a global map inside one
---    buffer is the mechanism, not a mistake — it is what `buffer = true` is
---    *for*. Only global-against-global is a conflict.
---  * **A non-literal `lhs`.** `bindings.lua` records `nil` rather than
---    guessing at `prefix .. "x"`, and two unknowns are not a known clash.
---  * **One call, several modes.** `vim.keymap.set({ "n", "v" }, ...)` is one
---    registration, and counting it twice would make every multi-mode map in
---    every config a finding.
---
---User commands are the same statement about a different namespace (two
---`nvim_create_user_command("Foo")` calls, the second wins), so they share
---this check rather than getting a near-identical second one.
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
local function check_binding_conflicts(ir, findings)
  ---Registration sites per key, plus the human name of what that key means.
  ---
  ---The description is carried rather than parsed back out of the key. An
  ---earlier draft packed mode and `lhs` into one string separated by NUL and
  ---unpacked it with `%z`, which works under LuaJIT and **does not exist** in
  ---PUC Lua 5.4 — the interpreter `standalone/` is built against. Two fields
  ---cost nothing and cannot break on a host this file never sees.
  ---@type table<string, { what: string, sites: { node: string, line: integer, callee: string }[] }>
  local seen = {}
  ---Key order, so the findings come out in `ir.order` and not in whatever
  ---order `pairs` feels like — the same determinism `--check` needs
  ---everywhere else.
  ---@type string[]
  local order = {}

  ---@param key string
  ---@param what string
  ---@param node_id string
  ---@param binding Documentation.BindingSpec
  local function record(key, what, node_id, binding)
    if not seen[key] then
      seen[key] = { what = what, sites = {} }
      order[#order + 1] = key
    end
    local sites = seen[key].sites
    sites[#sites + 1] = { node = node_id, line = binding.line, callee = binding.callee }
  end

  for _, id in ipairs(ir.order) do
    for _, b in ipairs(ir.nodes[id].bindings or {}) do
      if b.kind == "keymap" and b.lhs and not b.buffer then
        for _, mode in ipairs(b.modes) do
          record(
            ("keymap/%s/%s"):format(mode, b.lhs),
            ("keymap %s in mode %s"):format(b.lhs, mode),
            id,
            b
          )
        end
      elseif b.kind == "usercmd" and b.name then
        record(("usercmd/%s"):format(b.name), ("user command :%s"):format(b.name), id, b)
      end
    end
  end

  for _, key in ipairs(order) do
    local entry = seen[key]

    -- Distinct *sites*, not distinct records: one call declaring several
    -- modes is recorded once per mode, with the same node and line each
    -- time, and is one registration.
    local at_seen, sites = {}, {}
    for _, site in ipairs(entry.sites) do
      local at = ("%s:%d"):format(site.node, site.line)
      if not at_seen[at] then
        at_seen[at] = true
        sites[#sites + 1] = site
      end
    end

    if #sites > 1 then
      local where = {}
      for _, site in ipairs(sites) do
        where[#where + 1] = ("%s:%d (%s)"):format(site.node, site.line, site.callee)
      end
      -- Reported against the *last* site, because that is the one that wins:
      -- the finding lands on the file whose author is most likely looking at
      -- it, rather than on the one whose binding silently disappeared.
      add(
        findings,
        "warn",
        "binding-conflict",
        sites[#sites].node,
        { what = entry.what, count = #sites, where = table.concat(where, ", ") }
      )
    end
  end
end

---A `require` bound to a local name that is never mentioned again.
---
---The mirror of `require-not-declared`: that one finds a dependency the
---module uses without declaring, this one finds a dependency it declares
---without using. Left behind by a refactor that removed the last call, and
---invisible afterwards — the line still reads like a dependency, the module
---still loads it, and nothing anywhere says it is dead weight.
---
---**Only aliased requires.** `require("x")` with no binding is a load for
---its side effects, which is a real and deliberate pattern (registering a
---backend, installing a metatable), and there is no name to look for.
---Reporting those would mean reporting the one shape that cannot be wrong.
---
---**The reference count is deliberately coarse**, the same way
---`Documentation.FunctionInfo.local_refs` is and for the same reason: a
---mention inside a comment or a string counts as a use. Over-counting errs
---toward "used", which is the safe direction — a missed dead require costs
---a line nobody deletes, a false one costs trust in the check.
---
---Measured before it was written: 144 aliased requires in this repository,
---none unreferenced. A check that fires on a healthy tree is a check people
---turn off, so knowing the floor is zero here mattered more than knowing it
---works on a fixture.
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
---@param opts Documentation.Opts
local function check_unused_requires(ir, findings, opts)
  local read = require("lib.nvim.fs.read")
  local root = (tostring(opts.root):gsub("\\", "/"):gsub("/+$", ""))

  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    -- `requires_raw` is scan-internal and absent from a rehydrated artifact
    -- (see `to_json`'s own note on why it is not serialised), so this check
    -- runs on a live scan and quietly does nothing on anything else rather
    -- than reporting every require in a loaded map as unused.
    if node.source and node.requires_raw and #node.requires_raw > 0 then
      local content = read(root .. "/" .. node.source)
      if content then
        local lines = vim.split(content, "\n", { plain = true })
        for _, req in ipairs(node.requires_raw) do
          if req.alias then
            local uses = 0
            for i, line in ipairs(lines) do
              -- The requiring line itself is skipped: the binding occurrence
              -- is not a use of the binding.
              if i ~= req.line then
                local from = 1
                while true do
                  local a, b = line:find("[%a_][%w_]*", from)
                  if not a then
                    break
                  end
                  if line:sub(a, b) == req.alias then
                    uses = uses + 1
                  end
                  from = b + 1
                end
              end
            end
            if uses == 0 then
              add(
                findings,
                "info",
                "unused-require",
                id,
                { file = node.source, line = req.line, module = req.module, alias = req.alias }
              )
            end
          end
        end
      end
    end
  end
end

---An `@example` block that is not valid Lua.
---
---Extraction and rendering already existed — `functions.lua` collects the
---block, the annotation popup shows it — so this is one call to the
---interpreter's own parser over text already in the IR. An example that does
---not parse is documentation demonstrating something that cannot be typed.
---
---**Two attempts, not one.** An `@example` is as often a fragment as a
---chunk: `{ timeout = 5000 }` is a perfectly good illustration of an options
---table and not a valid statement. Parsed as a chunk first, then as an
---expression (`return (…)`), and only reported when both fail. Without the
---second attempt this check would fire on the most common shape of example
---there is, which is the definition of a check nobody keeps.
---
---**Honest about its evidence.** No tree in this ecosystem uses `@example` —
---measured before writing it: zero blocks in this repository, and none in
---the thirty-odd sibling plugins. So the false-positive question is settled
---against fixtures and reasoning, not against real usage, and this check has
---never fired on anything real. Recorded because "cheapest real check in the
---backlog" (`IDEAS.md` §1.2) was true about the cost and optimistic about
---the *real*.
---
---`loadstring or load`: the first exists under LuaJIT, the second under PUC
---Lua 5.4 with string support. `standalone/` runs the second.
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
local function check_examples(ir, findings)
  local loader = loadstring or load
  if not loader then
    return
  end
  for _, id in ipairs(ir.order) do
    for _, fn in ipairs(ir.nodes[id].functions or {}) do
      if fn.example and vim.trim(fn.example) ~= "" then
        local ok_chunk, err = loader(fn.example, "@example")
        if not ok_chunk then
          local ok_expr = loader("return (" .. fn.example .. "\n)", "@example")
          if not ok_expr then
            add(findings, "warn", "example-does-not-parse", id, {
              fn = fn.name,
              -- The chunk error, not the expression one: the reader wrote
              -- a statement far more often than a value, so that message
              -- points at what they meant.
              error = (tostring(err):gsub('^%[string "@example"%]:', "line ")),
            })
          end
        end
      end
    end
  end
end

---A consumer requires something under this library's namespace that this
---library does not have.
---
---The check half of `docs/ROADMAP/IDEAS/IDEAS.md` §1.7, and the *only* half
---that can honestly be a check.
---
---## Why the obvious one was not built
---
---"A module no consumer requires" is the finding this section invites, and it
---cannot be an assertion. `core/consumers.lua`'s own header says why: the
---number is a floor, not a fact — a project not in the set, a map not
---regenerated since its last require was added, and a user who never
---committed a map are all invisible and all normal. Against `lib.nvim` it
---would raise 33 findings today, nearly all of them wrong, and a check whose
---premise is "I may not have seen all your consumers" is a check nobody can
---act on. It stays a report, where the caveat can be read.
---
---This direction has no such problem. A consumer's map says, in writing,
---that it requires `lib.nvim.thing`; if the library has no such module, that
---is a positive claim about data that exists. Two explanations, both worth
---knowing and both named in the message: the consumer is broken right now, or
---its map predates a rename it has already followed in code.
---
---`warn`, not `error`. The stale-map explanation is real and common, and a
---library failing its own CI because a downstream project has not
---regenerated would make this the check people disable rather than the one
---they read.
---
---**Inert unless `opts.consumers` names a directory.** Most projects are not
---libraries with a knowable consumer set, and a check that silently reads
---whatever happens to sit beside a checkout would be guessing at the most
---important input it has.
---
---Measured before it shipped: 29 sibling maps, 0 broken references. A check
---that fires on a healthy ecosystem is a check people turn off, so knowing
---the floor is zero mattered more than knowing it works on a fixture.
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
---@param opts Documentation.Opts
local function check_consumer_requires(ir, findings, opts)
  local dir = opts.consumers
  if not dir or dir == "" then
    return
  end

  local consumers = require("documentation.core.consumers")
  local root = (tostring(opts.root):gsub("\\", "/"):gsub("/+$", ""))
  local maps = consumers.load((tostring(dir):gsub("\\", "/"):gsub("/+$", "")), root)
  if #maps == 0 then
    return
  end

  local namespaces = consumers.namespaces(ir)
  local mine = {}
  for _, id in ipairs(ir.order) do
    local module = ir.nodes[id].module
    if module then
      mine[module] = true
    end
  end

  ---@type table<string, string[]>
  local broken = {}
  local order = {}
  for _, map in ipairs(maps) do
    for _, id in ipairs(map.ir.order or {}) do
      local node = map.ir.nodes[id]
      for _, ext in ipairs((node and node.requires_external) or {}) do
        -- Only under a namespace this library owns. A consumer requiring
        -- `plenary.async` or `vim.fn` is not this library's business, and
        -- reporting every foreign require would bury the one that matters.
        local ns = ext:match("^([^.]+)") or ext
        if namespaces[ns] and not mine[ext] then
          if not broken[ext] then
            broken[ext] = {}
            order[#order + 1] = ext
          end
          local who = broken[ext]
          -- A set by construction: one consumer requiring the same missing
          -- module from six of its files is one broken consumer.
          local seen = false
          for _, name in ipairs(who) do
            if name == map.name then
              seen = true
              break
            end
          end
          if not seen then
            who[#who + 1] = map.name
          end
        end
      end
    end
  end

  table.sort(order)
  for _, module in ipairs(order) do
    local who = broken[module]
    table.sort(who)
    add(
      findings,
      "warn",
      "consumer-require-missing",
      nil,
      { module = module, who = table.concat(who, ", ") }
    )
  end
end

local function check_require_cycles(ir, findings)
  for _, component in ipairs(M.require_cycles(ir)) do
    local names = {}
    for _, member in ipairs(component) do
      names[#names + 1] = ir.nodes[member].module or member
    end
    local joined = table.concat(names, " → ")
    -- Reported once per member, not once per cycle: findings attach to a
    -- node, and a cycle with no node attached is unclickable in the HTML
    -- findings table and unjumpable in the quickfix list.
    for _, member in ipairs(component) do
      add(findings, "warn", "require-cycle", member, { count = #component, members = joined })
    end
  end
end

--- A `require()` of a module inside this tree's **own** namespace that no file
--- in the tree declares.
---
--- The gap this closes: an unresolvable require lands in `requires_external`,
--- which is the same place a genuine third-party dependency lands. That is
--- correct for `plenary.async` and silently wrong for
--- `documentation.brwose.trail` — a typo, a module that was renamed, or one
--- deleted while a caller kept requiring it. All three break at runtime, and
--- none of them look any different in the map from a dependency the scan was
--- never meant to cover.
---
--- Telling them apart on the **first path segment**: a require whose leading
--- segment matches one this tree declares as its own is a claim about this
--- tree, and this tree is exactly what the scan can be authoritative about.
--- `lib.nvim.fs` from a `documentation`-rooted tree is somebody else's
--- module and unknowable from here; `documentation.anything` is not.
---
--- Whole first segment, never a raw string prefix — `documentation` must not
--- match a `documentationx.util` that happens to start with the same letters.
---
--- The one false positive left is a project deliberately split across repos
--- under one namespace, and it already has an answer: `opts.tag_files` is the
--- declaration that a prefix lives in another project's map, so anything it
--- covers is skipped. Matched the same way `tagfiles.lua` matches it, because
--- two different notions of "covered by a tag file" would be a bug waiting to
--- be found by whoever configures one.
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
---@param opts Documentation.Opts
local function check_require_not_declared(ir, findings, opts)
  local own = {}
  for _, id in ipairs(ir.order) do
    local mod = ir.nodes[id].module
    if mod then
      own[mod:match("^[^.]+") or mod] = true
    end
  end
  if not next(own) then
    return
  end

  local tag_files = opts.tag_files or {}
  ---@param mod string
  ---@return boolean
  local function tagged(mod)
    for prefix in pairs(tag_files) do
      if mod == prefix or mod:sub(1, #prefix + 1) == prefix .. "." then
        return true
      end
    end
    return false
  end

  -- The same index `deps.build` resolved against, not a second walk deciding
  -- the same question — "does this module exist in the tree" must have one
  -- answer, or a require can be an edge and a finding at once.
  local by_module = require("documentation.core.deps").module_index(ir)

  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]

    -- `requires_raw` rather than `requires_external`, purely for the line
    -- numbers: a file can require the same missing module twice, and
    -- "somewhere in this file" is not an answer. It is available because
    -- checks run against the in-memory IR straight after the scan — it is
    -- deliberately not serialized into the artifact.
    local reported = {}
    for _, req in ipairs(node.requires_raw or {}) do
      local mod = req.module
      if
        own[mod:match("^[^.]+")]
        and mod ~= node.module
        and not by_module[mod]
        and not reported[mod]
        and not tagged(mod)
      then
        reported[mod] = true
        add(findings, "warn", "require-not-declared", id, { module = mod, line = req.line })
      end
    end
  end
end

--- Architectural layering, expressed as module-path prefixes: modules under
--- `rule.from` may not require modules under `rule.to`. Opt-in via
--- `opts.layers`, because a layering that is not declared cannot be violated —
--- there is no generic default that would be true of an arbitrary tree.
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
---@param opts Documentation.Opts
local function check_layers(ir, findings, opts)
  local rules = opts.layers or {}
  if #rules == 0 then
    return
  end

  ---Prefix match on module-path segments, not raw string prefix: `lib.vim`
  ---must match `lib.vim.buffer` and never `lib.vimx`.
  ---@param module string
  ---@param prefix string
  ---@return boolean
  local function under(module, prefix)
    return module == prefix or module:sub(1, #prefix + 1) == prefix .. "."
  end

  for _, edge in ipairs(ir.edges or {}) do
    if edge.kind == "require" then
      local from = ir.nodes[edge.from]
      local to = ir.nodes[edge.to]
      if from.module and to.module then
        for _, rule in ipairs(rules) do
          -- `from` must be outside `rule.to`'s own scope, not just inside
          -- `rule.from`'s — otherwise a rule like `{from="documentation.core",
          -- to="documentation.core.lang"}` also fires on `core.lang.js`
          -- requiring `core.lang.ecma`: both modules sit trivially "under"
          -- `documentation.core` by prefix, so without this exclusion every
          -- intra-`core.lang` require would be misread as the very
          -- core-into-lang boundary crossing the rule exists to catch, not
          -- an edge that stays inside `core.lang` the whole way.
          if
            under(from.module, rule.from)
            and not under(from.module, rule.to)
            and under(to.module, rule.to)
          then
            add(findings, "warn", "layer-violation", edge.from, {
              from = from.module,
              to = to.module,
              from_layer = rule.from,
              to_layer = rule.to,
              -- Carried as a value rather than a second template: the
              -- rule's `why` is the *caller's* prose, not this
              -- catalogue's, so it is never translatable and never
              -- belongs in the catalog.
              why = rule.why and (" — " .. rule.why) or "",
            })
          end
        end
      end
    end
  end
end

--- `@see` is only useful if its target actually resolves to something in the
--- map — same reasoning as `dead-readme-link` for README links. A target
--- resolves against a node's `module` path, a qualified `module.bare_name`,
--- or a function's raw declared name (e.g. "M.scan_full", as written).
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
local function check_see_targets(ir, findings)
  -- The same name -> entity index the documentation-reference resolver uses
  -- (`docs.build_index`), rather than a second loop building a boolean
  -- version of it here. Two answers to "what names does this tree export"
  -- would drift, and this plugin exists to notice that kind of thing.
  -- `idx.exact` holds exactly what this check used to collect: module
  -- paths, declared function names, and qualified `module.bare` forms.
  local known = require("documentation.core.docs").build_index(ir).exact

  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    for _, fn in ipairs(node.functions) do
      for _, target in ipairs(fn.see) do
        if not known[target] then
          add(findings, "warn", "dead-see-target", id, { fn = fn.name, target = target })
        end
      end
    end
  end
end

--- `---@type Foo` on a local table, when fields are LATER assigned onto
--- that same table, is a real LuaLS defect class rather than a style nit:
--- it produces `missing-fields` and "fields cannot be injected"
--- diagnostics on every one of those assignments, because `@type` tells
--- the language server "this value already has exactly this shape", and a
--- later `x.foo = ...` looks like an attempt to add a field the type never
--- declared. `---@class X : Foo` (optionally with a `@see` on the type
--- definition) is the annotation that actually means "this table's own
--- shape, which happens to satisfy `Foo`" — declaring it lets the table
--- keep growing fields instead of freezing it at the literal.
---
--- **Both halves are verified, not assumed — this took two real, wrong
--- attempts to get right, both against a real config, and both worth
--- keeping as the reason for the shape below:**
---
--- 1. A `---@type` line only counts when it is immediately adjacent to the
---    file's first real code line — `---@type` always applies to the
---    statement right after it. An earlier version of this check read
---    `scan.parse_header`'s `tags.type` (the first `@type` tag anywhere in
---    the leading comment run, however far from any code), and
---    misattributed an unrelated LOCAL variable's own, entirely correct
---    `@type` to the module whenever nothing but comments, blank lines or
---    a divider sat between the header prose and that local's declaration
---    (`config.neotest.init.icons`, an `@alias` block in between).
--- 2. Adjacency alone is not enough either — fixed second, after adjacency
---    was verified against real data and STILL fired on files where
---    nothing was ever assigned to the annotated local at all. The
---    previous version used `#node.functions` (does this FILE have any
---    functions anywhere) as a stand-in for "are fields assigned to THIS
---    local" — two unrelated questions. `autocmds.general.defaults` was
---    the case that exposed it: `AUTOCMDS_GENERAL_DEFAULTS` is a complete,
---    static `---@type` table, never touched again; the file's one
---    function lives on a SEPARATE `local M = {}` that merely returns it.
---    `@type` there was already correct, and converting it to `@class`
---    would have added a needless global type name for no real defect.
---    So this now greps the rest of the file for an actual assignment onto
---    that local's own name (`name.field = ...` or the `function
---    name.field(...)` sugar for the same thing) and fires only when at
---    least one is found — the exact shape the LuaLS diagnostic itself
---    requires to exist.
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
---@param opts Documentation.Opts
local function check_type_vs_class(ir, findings, opts)
  local root = opts.root:gsub("\\", "/"):gsub("/+$", "")

  ---The `@type` tag and the local name it annotates, read off the line
  ---immediately before the file's first real code line — nil unless that
  ---line is both a `---@type` tag AND the next line is a `local NAME = `
  ---assignment. Returns `nil` for a `---@type` on anything else (a
  ---parameter-typed local reused later, a scalar): only a table literal is
  ---even a candidate for the "fields injected later" defect this check
  ---exists for.
  ---@param path string
  ---@return string|nil declared_type
  ---@return string|nil local_name
  ---@return string[]|nil rest_of_file  # remaining lines, for the field-assignment scan below
  local function adjacent_type_tag(path)
    local fd = io.open(path, "r")
    if not fd then
      return nil, nil, nil
    end
    local prev
    local declared, name
    local rest = {}
    local in_header = true
    for line in fd:lines() do
      if in_header then
        if not line:match("^%s*%-%-") and line:match("%S") then
          in_header = false
          if prev then
            declared = prev:match("^%-%-%-@type%s+(.+)$")
          end
          if declared then
            name = line:match("^local%s+([%w_]+)%s*=%s*{")
            if not name then
              -- Not a table literal on that line -- nothing to check.
              declared = nil
            end
          end
        else
          prev = line
        end
      end
      if not in_header then
        rest[#rest + 1] = line
      end
    end
    fd:close()
    if not declared then
      return nil, nil, nil
    end
    return declared, name, rest
  end

  ---How many times `name` is assigned a field after its own declaration.
  ---@param name string
  ---@param lines string[]
  ---@return integer
  local function count_field_assignments(name, lines)
    local escaped = name:gsub("%p", "%%%0")
    local assign = "^%s*" .. escaped .. "%.[%w_]+%s*="
    local method = "^%s*function%s+" .. escaped .. "%.[%w_]+%s*%("
    local n = 0
    for _, line in ipairs(lines) do
      if line:match(assign) or line:match(method) then
        n = n + 1
      end
    end
    return n
  end

  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.source then
      local declared_type, name, rest = adjacent_type_tag(root .. "/" .. node.source)
      if declared_type and name and rest then
        local n = count_field_assignments(name, rest)
        if n > 0 then
          add(
            findings,
            "warn",
            "type-vs-class",
            id,
            { module = node.module or id, name = name, type = declared_type, count = n }
          )
        end
      end
    end
  end
end

--- Comma-split the raw signature parameter list into declared names, in
--- source order. `...` is kept as its own token (both checks below treat it
--- specially rather than dropping it silently) so a caller comparing
--- positions still sees a real entry there instead of the list quietly
--- shifting.
---
--- Exported (not `local`) because `doccoverage.lua` (R4) needs the same
--- "how many params does the signature actually declare" question
--- `undocumented-param` already answers, and duplicating the comma-split
--- would be a second place for the two to quietly disagree.
---@param fn Documentation.FunctionInfo
---@return string[]
function M.declared_param_names(fn)
  local inside = fn.signature:match("%((.-)%)")
  local names = {}
  if not inside or inside == "" then
    return names
  end
  for token in inside:gmatch("[^,]+") do
    token = vim.trim(token)
    if token ~= "" then
      names[#names + 1] = token
    end
  end
  return names
end

--- Text-based heuristic, not a real arity check: counts comma-separated
--- names in the raw signature parameter list and compares against the
--- number of `@param` lines. Deliberately `info`, not `warn`/`error` — a
--- complex signature (default-valued table unpacking, `...`) can make this
--- heuristic wrong, and it should never be the thing that fails `--check`.
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
local function check_undocumented_params(ir, findings)
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    -- A language with no per-parameter documentation convention cannot fail
    -- this check, and reporting it would be reporting the absence of
    -- something that cannot be present — the same reason `missing-module-tag`
    -- skips a language whose identity is its path. Zig documents a
    -- declaration with one `///` block; an assembly label has no parameter
    -- list to name at all.
    local params_documentable =
      require("documentation.core.doccoverage").language_documents_params(node.language)
    for _, fn in ipairs(node.functions) do
      -- `@internal` says this is implementation, not published surface, so
      -- the documentation bar is the author's own. Nagging about it is how a
      -- heuristic check earns its way onto someone's ignore list.
      if params_documentable and not fn.internal then
        local declared = 0
        for _, token in ipairs(M.declared_param_names(fn)) do
          if token ~= "..." then
            declared = declared + 1
          end
        end
        if declared > #fn.params then
          -- A function documented entirely through @overload — zero @param
          -- lines, its real parameter list living inside the fun(...)
          -- literals instead — is not undocumented; @overload is the
          -- alternative convention this check has to credit, not a gap in
          -- it. Skip only the exact case the false positive was in:
          -- no @param lines at all, and at least one overload whose own
          -- parsed params cover the declared count. A function that has
          -- *some* @param lines but still fewer than the signature
          -- declares is still a real finding, overloads or not.
          local covered_by_overload = false
          if #fn.params == 0 then
            for _, ov in ipairs(fn.overload) do
              if #ov.params >= declared then
                covered_by_overload = true
                break
              end
            end
          end
          if not covered_by_overload then
            add(
              findings,
              "info",
              "undocumented-param",
              id,
              { fn = fn.name, declared = declared, documented = #fn.params }
            )
          end
        end
      end
    end
  end
end

--- R5: `undocumented-param` only ever compares *counts*, so a renamed
--- parameter whose `@param` line was never updated — the signature says
--- `path`, the doc still says `file` — passes it silently as long as both
--- lists are the same length. This compares the *names* at each shared
--- position instead.
---
--- Positional, not set-based: Lua has no keyword arguments, so "the doc's
--- third `@param` describes the signature's third parameter" is the actual
--- contract a reader relies on, not "every doc name appears somewhere in the
--- signature" (which would happily accept two params silently swapped).
---
--- Deliberately `info`, same reasoning as `undocumented-param`: text-based,
--- can be wrong on a signature this heuristic does not really understand,
--- and must never be the thing that fails `--check`.
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
local function check_param_name_mismatch(ir, findings)
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    for _, fn in ipairs(node.functions) do
      if not fn.internal then
        local declared = M.declared_param_names(fn)
        local doc_params = fn.params
        -- A colon-declared method's own `self` is Lua's implicit sugar, so
        -- `declared_param_names` never sees it — but documenting it
        -- explicitly (`---@param self Foo`) is common and legitimate LuaCATS
        -- style, verified against this repo's own `Lru:get`/`Lru:put`.
        -- Left uncorrected, every such function would misreport every real
        -- parameter shifted one position early. Skipping the doc's leading
        -- `self` line realigns the comparison instead of guessing it away.
        if fn.name:find(":") and doc_params[1] and doc_params[1].name == "self" then
          local shifted = {}
          for i = 2, #doc_params do
            shifted[#shifted + 1] = doc_params[i]
          end
          doc_params = shifted
        end
        local n = math.min(#declared, #doc_params)
        for i = 1, n do
          local sig_name = declared[i]
          local doc_name = doc_params[i].name
          -- `...` has no name to compare a doc line against; the varargs
          -- shape is exactly what `@vararg`/a bare `...` @param already
          -- means, not a mismatch.
          if sig_name ~= "..." and sig_name ~= doc_name then
            add(
              findings,
              "info",
              "param-name-mismatch",
              id,
              { fn = fn.name, index = i, documented = doc_name, actual = sig_name }
            )
          end
        end
      end
    end
  end
end

--- Functions nothing appears to use.
---
--- The trap this check is built around, stated plainly: **a library consists
--- of functions with no internal caller by design.** That is what a library
--- is. A naive "no callers ⇒ dead" would report most of the published API of
--- any tree worth mapping, and be switched off the same day. So it fires in
--- two tiers.
---
--- Always on, because there the statement holds:
---   * a **file-local** function (`local function foo`) that its own file
---     never mentions again, and that no call edge reaches;
---   * an `@internal` function no call edge reaches — the tag is the author
---     saying this is not surface, so "nobody calls it" is a real finding.
---
--- Only with `opts.dead_code`, because there it is a question rather than an
--- answer: any other function with no caller in the tree.
---
--- Three things deliberately count as "used", each because it would otherwise
--- produce a confident wrong answer:
---   * `local_refs` — a function passed as a *value* (`vim.system(cmd,
---     on_exit)`) has no call site naming it, and flagging every callback in
---     the tree is exactly the failure this check must not have;
---   * a heuristic call edge, even though it is a guess — for *this* question
---     a guess that something is used is the safe direction;
---   * being someone's `@see` target, which is a documented relationship.
---
--- A colon-declared method (`function Lru:put()`) is qualified on a table
--- exactly as `M.foo` is, just spelled with `:` — not a private local.
--- Treating it as file-local would be doubly wrong: not only is it not
--- private, but `calls.lua`'s callee resolution has no case for method-call
--- syntax at all (`self:put(...)` never becomes a call edge, colon call
--- sites are structurally invisible to it), so every colon method in the
--- tree would be misreported as dead the moment its only callers use `:`.
--- Verified against this repo's own `Lru:get`/`Lru:put`
--- (`lua/lib/lua/memo/lru.lua`), which are the public API and are called
--- only from other files, only via `:` — an earlier name-shape heuristic
--- here (`"^%u[%w_]*%."`, requiring a literal dot) flagged both as dead by
--- default; run against this tree it produced 76 findings where checking the
--- declared name for `:` as well as `.` produces 0.
---
--- Never above `info`, and never a reason for `--check` to fail: dynamic
--- dispatch is invisible to the scanner (`lib.nvim.require`'s metatable and
--- lazy strategies call things that appear nowhere in the source), so a
--- confident verdict here is not available at any severity.
---Every function `key` (`id .. "#" .. fn.name`) this tree's own static
---analysis considers "used" — a real call edge, a `@see` reference, or a
---non-zero `local_refs` count (a function passed as a *value*, which never
---gets a call edge no matter how public its name is). Exactly the definition
---`check_dead_functions` below is built around, extracted so a second
---consumer — `documentation.core.telemetry_join`'s static x runtime join,
---ECOSYSTEM.md step 8 — reads the identical "has a static caller" set rather
---than a second, potentially-drifting reimplementation of it. See that
---check's own doc-comment for the full reasoning behind each of the three
---signals folded in here.
---@param ir Documentation.IR
---@return table<string, true> used key -> true for every function this analysis considers used
function M.used_keys(ir)
  local called = {}
  for _, e in ipairs(ir.edges or {}) do
    if e.kind == "call" and e.to and e.to_fn then
      called[e.to .. "#" .. e.to_fn] = true
    end
  end

  -- Anything a `@see` points at is documented as related, which is a use.
  local seen_by_see = {}
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    for _, fn in ipairs(node.functions) do
      for _, target in ipairs(fn.see or {}) do
        seen_by_see[target] = true
      end
    end
  end

  local used = {}
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    for _, fn in ipairs(node.functions) do
      local key = id .. "#" .. fn.name
      local bare = fn.name:match("([%w_]+)$") or fn.name
      if
        called[key]
        or seen_by_see[fn.name]
        or seen_by_see[bare]
        or (node.module and seen_by_see[node.module .. "." .. bare])
        or (fn.local_refs or 0) > 0
      then
        used[key] = true
      end
    end
  end
  return used
end

---@param ir Documentation.IR
---@param findings Documentation.Finding[]
---@param opts Documentation.Opts
local function check_dead_functions(ir, findings, opts)
  local used = M.used_keys(ir)

  -- ECOSYSTEM.md step 8: a runtime call is stronger evidence than this
  -- check's own static analysis can ever produce for the exact case it is
  -- weakest at — a callback bound as a value, or dynamic dispatch, both
  -- structurally invisible to a call-edge scan. `by_key` is `nil` whenever
  -- `runtime-analysis.nvim` is not installed or telemetry was never enabled
  -- for this tree, in which case every lookup below is simply absent and
  -- this check behaves exactly as it always has — telemetry only ever
  -- *suppresses* a finding here, never manufactures one, matching the design
  -- doc's own "never above info, never a reason for --check to fail" rule
  -- for this check applying equally to what evidence can silence it.
  local telemetry_join = require("documentation.core.telemetry_join")
  local namespace = telemetry_join.namespace(opts)
  local data = namespace and telemetry_join.load(namespace)
  local by_key = data and telemetry_join.by_key(ir, data)

  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    for _, fn in ipairs(node.functions) do
      local key = id .. "#" .. fn.name
      local file_local = not fn.name:find("[.:]")

      if not used[key] then
        local row = by_key and by_key[key]
        if row and row.calls > 0 then
          goto continue
        end

        -- Three genuinely different statements, so three catalog entries
        -- rather than one sentence with a clause spliced in. A translator
        -- needs to see them apart; a reader of this code does too.
        local variant
        if file_local then
          variant = "file-local"
        elseif fn.internal then
          variant = "internal"
        elseif opts.dead_code then
          variant = "no-caller"
        end

        if variant then
          add(findings, "info", "dead-function", id, { variant = variant, fn = fn.name })
        end
      end
      ::continue::
    end
  end
end

---Run every check and return findings sorted by severity.
---@param ir Documentation.IR
---@param opts Documentation.Opts
---@return Documentation.Finding[]
function M.run(ir, opts)
  local findings = {}

  check_summaries(ir, findings)
  check_examples(ir, findings)
  check_module_paths(ir, findings, opts)
  check_readmes(ir, findings)
  check_readme_links(ir, findings, opts)
  check_doc_references(ir, findings)
  check_tools_spec(ir, findings)
  check_orphans(ir, findings)
  check_tag_requires(ir, findings)
  check_orphaned_types(ir, findings, opts)
  check_test_references(ir, findings, opts)
  check_binding_conflicts(ir, findings)
  check_require_cycles(ir, findings)
  check_require_not_declared(ir, findings, opts)
  check_unused_requires(ir, findings, opts)
  check_consumer_requires(ir, findings, opts)
  check_layers(ir, findings, opts)
  check_see_targets(ir, findings)
  check_type_vs_class(ir, findings, opts)
  check_undocumented_params(ir, findings)
  check_param_name_mismatch(ir, findings)
  check_dead_functions(ir, findings, opts)

  for _, extra in ipairs(opts.extra_checks or {}) do
    for _, f in ipairs(extra(ir, opts) or {}) do
      findings[#findings + 1] = f
    end
  end

  -- `opts.checks` last, so it reaches `extra_checks` results too: a project
  -- that writes its own check has exactly the same reason to want it graded
  -- `info` on a branch as it has for any built-in one, and a policy that
  -- covered only the checks this repository ships would be arbitrary.
  --
  -- Before the sort, not after — the list is serialized in severity order
  -- and byte-compared by `--check`. See `core/check_policy.lua`.
  findings = require("documentation.core.check_policy").apply(findings, opts.checks)

  local rank = { error = 1, warn = 2, info = 3 }
  table.sort(findings, function(a, b)
    if rank[a.severity] ~= rank[b.severity] then
      return rank[a.severity] < rank[b.severity]
    end
    if a.check ~= b.check then
      return a.check < b.check
    end
    return (a.node or "") < (b.node or "")
  end)

  return findings
end

---Group findings by severity for reporting.
---@param findings Documentation.Finding[]
---@return table<Documentation.Severity, integer>
function M.tally(findings)
  local t = { error = 0, warn = 0, info = 0 }
  for _, f in ipairs(findings) do
    t[f.severity] = (t[f.severity] or 0) + 1
  end
  return t
end

return M
