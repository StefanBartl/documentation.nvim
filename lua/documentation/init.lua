---@module 'documentation'
--- documentation.nvim: generated module map. Scans an annotated Lua tree,
--- builds an intermediate representation, checks it for documentation drift,
--- and renders it.
---
--- Nothing here is tied to one repository — `opts.root`/`opts.source` point it
--- at any tree whose files carry `---@module`, so a plugin generates its own
--- map with the same code. Nothing below hardcodes a module prefix, a
--- directory layout or a repo URL. (It grew inside `lib.nvim` as
--- `lib.nvim.docmap`; extracting it changed the module path and the command
--- names, not the pipeline.)
---
--- Pipeline:
---   scan       → Documentation.IR          (filesystem walk + header parse)
---   luals      → merges into the IR     (opt-in: @class/@alias detail, type edges)
---   check      → Documentation.Finding[]   (drift between docs and reality)
---   render     → html / mermaid / markdown / json
---
--- The IR is the contract between the halves: renderers never touch the
--- filesystem, and the scanner never knows what will be drawn.
---
--- Two ways to drive the pipeline:
---   generate(opts)  — one-shot: scan, check, render, write to opts.out_dir.
---                      What :DocMap and the CI/hook CLI use.
---   install(opts)   — live: keeps a scanned IR in memory, optionally
---                      rescanning on save, with subscribers. What another
---                      plugin's source code reaches for instead of parsing
---                      module_map.json off disk.
---
--- `M.cli` is the `--check`/`--full` entry point `scripts/gen_map.lua` and
--- `scripts/hooks/pre-commit` both call through — see cli.lua.
---
--- Usage:
---   require("documentation").setup({})            -- register :DocMap/:DocBrowse
---   require("documentation").generate({
---     root = "/path/to/repo",
---     source = "lua/myplugin",
---     title = "myplugin.nvim",
---     repo_url = "https://github.com/user/repo",
---   })
---
--- See @types/init.lua for Documentation.*.

require("documentation.@types")

local scan = require("documentation.core.scan")
local check = require("documentation.core.check")
local mkdirp = require("lib.nvim.fs.mkdirp")
local json = require("documentation.core.json")

local M = {}

M.scan = scan.scan
M.parse_header = scan.parse_header
M.check = check.run
M.tally = check.tally

---Reject a malformed options table at the published boundary.
---
---Only here, not on every function in the tree. Inside the pipeline LuaLS
---already catches a wrong argument from the annotations, and asserts on 270
---internal functions would be noise that never fires. What LuaLS cannot see is
---a caller *outside* this repository — a plugin passing its own table, a
---script, a `:lua` line — and there the difference is between a message that
---names the mistake and an "attempt to index a nil value" three frames deep in
---a scanner.
---@param opts any
---@param where string Function name, for the message.
---@raises string When `opts` is not a table with a non-empty string `root`.
local function assert_opts(opts, where)
  assert(type(opts) == "table", where .. ": opts must be a table, got " .. type(opts))
  assert(
    type(opts.root) == "string" and opts.root ~= "",
    where .. ": opts.root is required (absolute path to the repository root)"
  )
end

---`scan()` + optional LuaLS merge (`opts.luals`) + `check()`, in one call.
---The shared step `generate()` and `install()`'s rescan both build on, so the
---enrichment wiring exists in exactly one place rather than being repeated at
---every entry point that needs a fully-formed IR.
---@param opts Documentation.Opts
---@return Documentation.IR
---@return Documentation.Finding[]
---@raises string When `opts.root` is missing, or `opts.source` names a directory that does not exist (from `scan`).
function M.scan_full(opts)
  assert_opts(opts, "documentation.scan_full")

  -- Instrumentation, off unless `opts.debug`. Attached to the IR rather than
  -- returned as a third value: every caller of `scan_full` would otherwise
  -- have to thread a value it mostly ignores, and `install()`'s rescan would
  -- have to invent somewhere to put it. `ir.timing` is read by
  -- `bindings/usrcmds/generate.lua` and by nothing on the render path — it is
  -- deliberately **not** serialised into the artifact, because a duration is
  -- different on every machine and `--check` byte-compares.
  local timing = require("documentation.core.timing")
  local t = timing.new(opts.debug)

  local ir = timing.measure(t, "scan", function()
    return M.scan(opts)
  end)
  ir.timing = t
  ir.edges = ir.edges or {}

  -- Always runs, even with no opts.tag_files: `tagfiles.resolve` sets
  -- `ir.tag_links = {}` unconditionally, so the field's presence (vs. the
  -- LuaLS-enrichment fields, which stay nil when never run) is not itself a
  -- signal — checking `next(opts.tag_files or {})` is what a caller wanting
  -- to know "was this configured" should do.
  timing.measure(t, "tagfiles", function()
    require("documentation.core.tagfiles").resolve(ir, opts)
  end)

  -- Must run after tagfiles above: it extends the same ir.tag_links table
  -- and deliberately never overwrites an entry tagfiles already set — see
  -- core/external_repos.lua's own header for why a local project's own map
  -- wins over a guessed GitHub URL for the same module. Same "always runs,
  -- no-op when unconfigured" shape as tagfiles.
  timing.measure(t, "external_repos", function()
    require("documentation.core.external_repos").resolve(ir, opts)
  end)

  -- Same reasoning: cheap, local, no reason to gate behind a flag. A
  -- missing opts.tests_dir just leaves every fn.tested false, same as a
  -- tree with no tag_files leaves every requires_external unresolved.
  timing.measure(t, "coverage", function()
    require("documentation.core.coverage").resolve(ir, opts)
  end)

  -- Same reasoning again: `fn.documented` is what the Analysis tab's
  -- Documentation panel reads to build a per-module breakdown without
  -- reimplementing `doccoverage.is_documented` in JS.
  timing.measure(t, "doccoverage", function()
    require("documentation.core.doccoverage").resolve(ir)
  end)

  -- Grouped here rather than in JS, unlike the fan-in/fan-out panel: that one
  -- aggregates data already serialised, this one groups by `fn.shape`, which
  -- only `functions.lua` can produce because only the scan holds the parse
  -- tree. Cheap — one pass and a sort over what is already in memory.
  ir.duplicates = timing.measure(t, "duplicates", function()
    return require("documentation.core.duplicates").resolve(ir)
  end)

  -- The prose half of the same tree: which `.md` file mentions which module
  -- or function. Runs unconditionally for the same reason coverage and
  -- doccoverage do — it is local, cheap, and a tree with no documentation
  -- files simply produces an empty corpus, which is a real answer rather
  -- than a missing one.
  timing.measure(t, "docs", function()
    require("documentation.core.docs").resolve_all(ir, opts)
  end)

  -- This repo's own `lib.nvim.deps` manifest, as declared — never as probed.
  -- Runs unconditionally, same reasoning as `docs` above: one file read (two
  -- at most), and a repo with neither `docs/install.json` nor
  -- `docs/INSTALL.md` simply leaves `ir.tools` nil, same as `ir.quicks`
  -- leaving fields nil is itself a real answer. Presence on this host is
  -- deliberately never resolved here — see `core/tools.lua`'s header for why
  -- that would break `--check`.
  ir.tools = timing.measure(t, "tools", function()
    return require("documentation.core.tools").resolve(opts.root)
  end)

  -- This repo's own docs/FEATURES/ folder, same posture as docs/tools above:
  -- one directory listing plus a handful of file reads, a repo with none
  -- simply leaves ir.features nil. See core/features.lua and
  -- docs/FEATURES_FORMAT.md.
  ir.features = timing.measure(t, "features", function()
    return require("documentation.core.features").resolve(opts.root)
  end)

  -- The hand-verified ledger, same posture as `features`/`tools` above: a
  -- directory listing plus a few file reads, and a repo without one simply
  -- leaves `ir.checklist` nil. Only the *ledger* is resolved here — the
  -- "changed since verified" verdict needs git and would make the committed
  -- artifact invalidate itself, so it is computed live by `:DocMap checklist`
  -- and the serve tier instead. See core/checklist.lua.
  ir.checklist = timing.measure(t, "checklist", function()
    return require("documentation.core.checklist").resolve(opts.root)
  end)

  local luals_err
  if opts.luals then
    local luals = require("documentation.core.luals")
    local doc_json, err =
      luals.run(opts.root, opts.source or "lua", { timeout_ms = opts.luals_timeout_ms })
    if doc_json then
      luals.merge(ir, doc_json, opts.source or "lua")
    else
      -- Enrichment failing is not a reason to fail the whole scan — everything
      -- scan() produced is still valid. Surface it as a finding instead of
      -- letting it vanish silently.
      luals_err = err
    end
  end

  local findings = timing.measure(t, "check", function()
    return M.check(ir, opts)
  end)
  if luals_err then
    table.insert(findings, 1, {
      severity = "info",
      check = "luals-unavailable",
      node = nil,
      message = "opts.luals was set but enrichment did not run: " .. tostring(luals_err),
    })
  end

  -- Last, and it has to be: alone among the derived tables, this one reads the
  -- *findings* as well as the IR — "the map has drifted" is one of the
  -- verdicts, and drift is not knowable until `check` has run. Attached to the
  -- IR rather than returned as a third value, for the same reason `timing` is:
  -- every caller would otherwise thread a value most of them ignore, and
  -- `install()`'s rescan would need somewhere to put it.
  ir.quicks = timing.measure(t, "quicks", function()
    return require("documentation.core.quicks").compute(ir, findings, opts)
  end)

  return ir, findings
end

--- The editor-side map navigator (`:DocBrowse`). Lazily required: it pulls in
--- `lib.nvim.ui.kit`, which nothing on the generate/check path needs.
M.browse = setmetatable({}, {
  __index = function(_, k)
    return require("documentation.editor.browse")[k]
  end,
})

--- Structural diff between two maps. Lazily required: pure, and nothing on
--- the generate/check path needs it.
M.diff = setmetatable({}, {
  __index = function(_, k)
    return require("documentation.core.diff")[k]
  end,
})

--- The `--check`/`--full` CLI entry point, as a callable module rather than a
--- script — see cli.lua. Lazily required: only the CLI wrapper and hooks need
--- it, not `:DocMap` or `install()`.
M.cli = setmetatable({}, {
  __index = function(_, k)
    return require("documentation.core.cli")[k]
  end,
})

--- Where a diff radiates to: changed lines -> functions -> callers. Lazily
--- required for the same reason as `diff`: pure, and nothing on the
--- generate/check path needs it.
M.history = setmetatable({}, {
  __index = function(_, k)
    return require("documentation.core.history")[k]
  end,
})

--- `generate()` for a *list* of projects, one real headless Neovim
--- subprocess per project — see editor/generate_all.lua's own header for
--- why a subprocess and why no usercmd is registered here. Lazily
--- required: nothing on the single-project generate/check/install path
--- needs it.
M.generate_all = setmetatable({}, {
  __index = function(_, k)
    return require("documentation.editor.generate_all")[k]
  end,
})

M.render = {
  html = function(...)
    return require("documentation.core.render.html")(...)
  end,
  mermaid = function(...)
    return require("documentation.core.render.mermaid")(...)
  end,
  mermaid_deps = function(...)
    return require("documentation.core.render.mermaid").render_deps(...)
  end,
  markdown = function(...)
    return require("documentation.core.render.markdown")(...)
  end,
  mdview = function(...)
    return require("documentation.core.render.mdview")(...)
  end,
  dot = function(...)
    return require("documentation.core.render.dot")(...)
  end,
  badge = function(...)
    return require("documentation.core.render.badge").render(...)
  end,
}

---Serialize the IR deterministically: nodes in `ir.order`, object keys in a
---fixed sequence, and every nested value through `docmap.json` rather than
---`vim.json.encode`, whose key order is unspecified.
---@param ir Documentation.IR
---@return string
function M.to_json(ir)
  local out = {}
  local function put(s)
    out[#out + 1] = s
  end
  local function str(s)
    return json.encode(s or "")
  end

  put('{\n  "meta": ')
  put(json.encode(ir.meta))
  put(',\n  "root": ' .. str(ir.root))
  put(',\n  "nodes": [\n')

  for i, id in ipairs(ir.order) do
    local n = ir.nodes[id]
    local fields = {
      '"id": ' .. str(n.id),
      '"kind": ' .. str(n.kind),
      '"name": ' .. str(n.name),
      '"path": ' .. str(n.path),
      -- Added with schema 3. Found missing here by measurement, not by
      -- reading: the scan set it on every node and the artifact reported
      -- `null` for all hundred of them, because this field list and
      -- `Documentation.Node` are maintained separately by hand. That is the
      -- fifth time this exact trap has caught a field (see
      -- `core/render/html.lua`'s own payload comment for the previous four)
      -- and it is what `IDEAS.md` section 9's payload-contract test exists
      -- to end.
      '"language": ' .. (n.language and str(n.language) or "null"),
      '"source": ' .. (n.source and str(n.source) or "null"),
      '"module": ' .. (n.module and str(n.module) or "null"),
      '"summary": ' .. str(n.summary),
      '"body": ' .. str(n.body),
      '"readme": ' .. (n.readme and str(n.readme) or "null"),
      '"types": ' .. json.encode(n.types),
      '"types_detail": ' .. (n.types_detail and json.encode(n.types_detail) or "null"),
      '"functions": ' .. json.encode(n.functions),
      '"plugins": ' .. json.encode(n.plugins),
      -- Emitted unconditionally, like `plugins` above rather than like the
      -- `#x > 0 and ... or "[]"` fields below: a cold consumer has to be able
      -- to tell "this artifact predates bindings extraction" from "this tree
      -- registers none", and an always-present key is the only thing that
      -- distinguishes them. `bindings_explorer.source` in the author's own
      -- config relies on exactly that difference to report a stale artifact
      -- instead of silently claiming zero bindings.
      '"bindings": ' .. json.encode(n.bindings or {}),
      -- The sixth field this list has been caught missing, and the first
      -- found by measuring rather than by someone opening the page: the
      -- scanner has extracted route registrations since `core/endpoints.lua`
      -- shipped, the *page* shows them (it encodes node tables wholesale),
      -- and `module_map.json` carried none -- so `--check` could not see
      -- endpoint drift at all, and every consumer reading the artifact
      -- rather than the page saw a tree with no routes in it. Emitted
      -- unconditionally for the same reason `bindings` above is.
      '"endpoints": ' .. json.encode(n.endpoints or {}),
      '"export": ' .. (n.export and str(n.export) or "null"),
      '"parent": ' .. (n.parent and str(n.parent) or "null"),
      '"depth": ' .. tostring(n.depth),
      '"children": ' .. (#n.children > 0 and json.encode(n.children) or "[]"),
      -- The unresolved `requires_raw`/`calls_raw` stay out of the artifact on
      -- purpose: they are scratch input to the graph stages, already fully
      -- represented by `ir.edges`, and serializing them would roughly double
      -- the file to say the same thing twice.
      '"requires": ' .. (#n.requires > 0 and json.encode(n.requires) or "[]"),
      '"required_by": ' .. (#n.required_by > 0 and json.encode(n.required_by) or "[]"),
      '"requires_external": '
        .. (#n.requires_external > 0 and json.encode(n.requires_external) or "[]"),
      -- Same "empty array, not left off" rule as requires_external right
      -- above it, for the same reason: this is a per-node field the
      -- generated page's own Deps view reads directly, and an absent key
      -- reads as "never computed" where an empty array correctly reads as
      -- "computed, nothing found".
      '"calls_external": ' .. (#n.calls_external > 0 and json.encode(n.calls_external) or "[]"),
      '"symbols": ' .. json.encode(n.symbols),
      '"stats": ' .. json.encode(n.stats),
    }
    put("    {" .. table.concat(fields, ", ") .. "}")
    put(i < #ir.order and ",\n" or "\n")
  end

  put('  ],\n  "edges": ')
  put(json.encode(ir.edges or {}))
  put(',\n  "tag_links": ')
  put(json.encode(ir.tag_links or {}))
  -- Derived, and carried anyway: the grouping needs `fn.shape`, which exists
  -- only while the parse tree does, so a page reading the artifact could not
  -- redo it. Same reason `stats` is serialised rather than recomputed in JS.
  put(',\n  "duplicates": ')
  put(json.encode(ir.duplicates or { groups = {}, functions = 0, considered = 0, min_size = 0 }))
  -- Carried for the same reason `duplicates` is: the page has no filesystem
  -- to re-read `.md` files from, so a reference index it could rebuild
  -- itself does not exist. Bounded at the source — `docs.lua` caps both the
  -- stored context length and the references kept per entity — rather than
  -- trimmed here, so what the check reasons about and what the page shows
  -- are the same data.
  put(',\n  "docs": ')
  put(json.encode(ir.docs or { files = {}, refs = {}, missing = {} }))
  -- Carried rather than left for a consumer to recompute, and here the reason
  -- is not "the page cannot rebuild it" — it could — but that `quicks` reads
  -- the *findings*, which this artifact does not carry. Recomputed from
  -- `module_map.json` alone it would silently lose the drift verdicts and
  -- report a cleaner tree than the one that was scanned.
  put(',\n  "quicks": ')
  put(json.encode(ir.quicks or { good = {}, bad = {}, total_good = 0, total_bad = 0 }))
  -- Unlike duplicates/docs/quicks above, `nil` here is not "scan_full didn't
  -- run yet" — it is the real, common answer "this repo ships no
  -- lib.nvim.deps manifest" / "no docs/FEATURES/ folder", and `json.encode`
  -- turns a bare Lua `nil` into JSON `null` on its own, which is exactly
  -- the falsy value the Tools/Features renderers already check for. No
  -- default-shape fallback, unlike the three above, because there is no
  -- "ran but found nothing" shape to distinguish from "did not run" here —
  -- both core/tools.lua and core/features.lua always run, unconditionally.
  put(',\n  "tools": ')
  put(json.encode(ir.tools))
  put(',\n  "features": ')
  put(json.encode(ir.features))
  -- Same shape and same reasoning as tools/features directly above. Only the
  -- ledger is serialized — every staleness field is deliberately absent,
  -- because it is derived from `git log` and a byte-compared artifact cannot
  -- carry git data without invalidating itself. See core/checklist.lua.
  put(',\n  "checklist": ')
  put(json.encode(ir.checklist))
  put("\n}\n")
  return table.concat(out)
end

---Write `content` to `path`, creating parent directories.
---@param path string
---@param content string
---@return boolean ok
---@return string? err
local function write(path, content)
  local ok, err = mkdirp(vim.fs.dirname(path))
  if not ok then
    return false, err
  end
  local fd, ferr = io.open(path, "wb")
  if not fd then
    return false, ferr
  end
  fd:write(content)
  fd:close()
  return true
end

---Render and write `module_map.json`/`index.html`/`overview.md` into
---`opts.out_dir` for an already-scanned `ir`/`findings` pair. Split out of
---`generate()` so a caller that already has a fresh IR (e.g. `:DocMap full`,
---which scans through a registry handle to also update its cached IR) does
---not have to scan a second time just to get the artifacts written.
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
---@param opts Documentation.Opts
---@return string[] written Repo-relative paths of the files written
---@raises string When `opts.root` is missing, or a file under `opts.out_dir` cannot be written.
function M.write_artifacts(ir, findings, opts)
  assert_opts(opts, "documentation.write_artifacts")
  assert(
    type(ir) == "table" and type(ir.order) == "table",
    "documentation.write_artifacts: ir must be a scanned Documentation.IR"
  )
  local root = opts.root:gsub("\\", "/"):gsub("/+$", "")
  local out_dir = opts.out_dir or "docs/map"
  local written = {}

  local artifacts = {
    ["module_map.json"] = M.to_json(ir),
    ["index.html"] = M.render.html(ir, findings, opts),
    ["overview.md"] = M.render.markdown(ir, findings, opts),
  }
  if opts.badge then
    artifacts["coverage.svg"] = require("documentation.core.doccoverage").badge_svg(ir)
  end

  for name, content in pairs(artifacts) do
    local rel = out_dir .. "/" .. name
    local ok, err = write(root .. "/" .. rel, content)
    if not ok then
      error(("docmap: cannot write %s: %s"):format(rel, tostring(err)))
    end
    written[#written + 1] = rel
  end

  table.sort(written)
  return written
end

---Writes `overview.pdf` via pdfport.nvim (github.com/StefanBartl/
---pdfport.nvim, optional dependency, soft-required) -- byte-for-byte the
---same content `overview.md` gets, just handed to pdfport as text instead of
---read back from disk. Unlike `write_artifacts`, this is asynchronous
---(pdfport's markdown producer shells out to pandoc) and reports through
---`callback` rather than a return value, so it is not folded into
---`write_artifacts`'s synchronous `written` list -- call it separately, after
---`write_artifacts`, when `opts.pdf` is set (see `bindings/usrcmds/generate.lua`).
---@param ir Documentation.IR
---@param findings Documentation.Finding[]
---@param opts Documentation.Opts
---@param callback fun(ok: boolean, path_or_err: string) `path_or_err` is the
---repo-relative written path on success, an error message otherwise.
---@return nil
function M.write_pdf_artifact(ir, findings, opts, callback)
  local pdfport = require("documentation.core.soft_require").probe("pdfport")
  if not pdfport or type(pdfport.create) ~= "function" then
    callback(false, "pdfport.nvim not installed -- PDF export unavailable")
    return
  end
  if type(pdfport.can_create) ~= "function" or not pdfport.can_create("markdown") then
    callback(false, "pdfport.nvim has no available markdown producer (needs pandoc + a PDF engine)")
    return
  end

  assert_opts(opts, "documentation.write_pdf_artifact")
  local root = opts.root:gsub("\\", "/"):gsub("/+$", "")
  local out_dir = opts.out_dir or "docs/map"
  local rel = out_dir .. "/overview.pdf"

  pdfport.create({
    text = M.render.markdown(ir, findings, opts),
    from = "markdown",
    output = root .. "/" .. rel,
    on_conflict = "overwrite",
    __callback = function(result)
      if result.status == "ok" then
        callback(true, rel)
      else
        callback(false, result.error or "pdfport export failed")
      end
    end,
  })
end

---Scan, check and render everything into `opts.out_dir`.
---@param opts Documentation.Opts
---@return Documentation.IR
---@return Documentation.Finding[]
---@return string[] written Repo-relative paths of the files written
---@raises string When `opts.root` is missing, `opts.source` does not exist, or an artifact cannot be written.
function M.generate(opts)
  assert_opts(opts, "documentation.generate")
  local ir, findings = M.scan_full(opts)
  local written = M.write_artifacts(ir, findings, opts)
  return ir, findings, written
end

---Install a live handle: a scanned IR kept in memory, optionally rescanned on
---save, with `on_change` subscribers. See `lua/documentation/registry.lua`
---for the collision reason this is a separate module from `command.lua`
---rather than `install()` auto-registering a usercmd itself.
---@param opts Documentation.Opts
---@return Documentation.Handle
---@raises string When `opts.root` is missing — `registry.install` asserts it too, and does so before it can key a handle on a bad root.
function M.install(opts)
  assert_opts(opts, "documentation.install")
  return require("documentation.editor.registry").install(opts)
end

---Tear down a handle from `install()`. Accepts the handle itself or its root
---path. Idempotent: uninstalling twice is a no-op, not an error.
---@param handle_or_root Documentation.Handle|string
---@return boolean uninstalled
function M.uninstall(handle_or_root)
  return require("documentation.editor.registry").uninstall(handle_or_root)
end

---Plugin entry point: register `:DocMap`/`:DocBrowse` for `opts` (defaults
---filled in by `documentation.config`, which resolves the tree from the
---current working directory).
---
---A thin alias for `documentation.bindings.usrcmds.setup` rather than a second
---wiring path — `require("documentation")` on its own still creates no command,
---so a plugin embedding the pipeline is never forced to also take the commands.
---@param opts Documentation.Opts?
---@return Documentation.Handle
function M.setup(opts)
  return require("documentation.bindings.usrcmds").setup(opts)
end

return M
