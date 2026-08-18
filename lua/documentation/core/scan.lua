---@module 'documentation.core.scan'
--- Filesystem walk + leading-comment-block parser producing the docmap IR.
---
--- Deliberately does **not** parse Lua. It reads only each file's leading
--- comment block — everything before the first non-comment line — which is
--- reliable because the `---@module` convention is uniform, and which costs
--- ~200 lines instead of a Lua front end. Anything needing real name
--- resolution (classes, fields, signatures) is left to `docmap.luals`, which
--- delegates to `lua-language-server --doc`.
---
--- The walk is generic: nothing here knows about `lib.nvim` specifically, so
--- another plugin can point it at its own tree via `opts.root`/`opts.source`.

local M = {}

local uv = vim.uv

-- This is the only backend-aware line in this file, and it names a
-- registry, never a specific backend — `core/lang.lua` requiring THIS
-- module back (deferred, inside its own functions) is fine, but this file
-- requiring `core/lang/lua.lua` directly was tried first and correctly
-- caught by the `documentation.core` -> `documentation.core.lang` layer
-- rule: that is exactly the coupling the registry exists to prevent, and
-- `core/lang_registry.lua`'s own `KNOWN_BACKENDS` list is where that
-- self-registration require now lives instead.
local lang_registry = require("documentation.core.lang_registry")

---Directories the walk never descends into, and the same list
---`core/lang/ecma.lua` consults when deciding whether a candidate directory
---is evidence of its own language.
---
---Only ever mattered once `source` could be something other than
---`lua/<plugin>`. A Neovim plugin's source root contains none of these, so
---the walk got away without a list for as long as Lua was the only backend;
---a JavaScript project whose `source` resolves to `src` or to the repository
---root does not, and a `node_modules` with forty thousand files in it is
---both unusably slow to walk and wrong to report as the project's own code.
---
---Vendored dependencies and generated output, deliberately in one list
---because the walk does not care which applies. **Not** a general ignore
---mechanism: `.gitignore` is not read, because a repository can quite
---reasonably ignore a directory this map should still describe.
---@type table<string, true>
M.VENDOR_DIRS = {
  ["node_modules"] = true,
  ["vendor"] = true,
  ["bower_components"] = true,
  ["target"] = true,
  ["dist"] = true,
  ["build"] = true,
  ["out"] = true,
  [".next"] = true,
  [".nuxt"] = true,
  [".svelte-kit"] = true,
  ["__pycache__"] = true,
  [".venv"] = true,
  ["venv"] = true,
  [".git"] = true,
  [".deps"] = true,
  [".claude"] = true,
}

---Normalize to forward slashes; every path in the IR is stored this way so
---the artifact is byte-identical regardless of which OS generated it.
---@param p string
---@return string
local function slash(p)
  return (p:gsub("\\", "/"))
end

---Strip a trailing separator.
---@param p string
---@return string
local function chomp(p)
  return (p:gsub("/+$", ""))
end

---@param path string
---@return boolean
local function is_dir(path)
  local st = uv.fs_stat(path)
  return st ~= nil and st.type == "directory"
end

---@param path string
---@return boolean
local function is_file(path)
  local st = uv.fs_stat(path)
  return st ~= nil and st.type == "file"
end

---Read a file's first `limit` lines without slurping the whole thing.
---@param path string
---@param limit integer
---@return string[]
local function head_lines(path, limit)
  local out = {}
  local fd = io.open(path, "r")
  if not fd then
    return out
  end
  for line in fd:lines() do
    out[#out + 1] = line
    if #out >= limit then
      break
    end
  end
  fd:close()
  return out
end

---Split a prose blob into a one-sentence summary and the remaining body.
---
---The summary is what lands in tree rows and generated tables, so it is
---capped: a "sentence" that runs past `max` characters is almost always a
---module that never wrote a real summary line, and truncating it produces a
---better table than letting one row swallow the layout.
---
---Exported (not local) so `docmap.functions` can apply the same summary-line
---logic to a function's doc-comment prose instead of duplicating it.
---@param prose string
---@return string summary
---@return string body
function M.split_summary(prose)
  if prose == "" then
    return "", ""
  end

  -- First blank-line-delimited paragraph is the summary candidate.
  local first_para, rest = prose:match("^(.-)\n%s*\n(.*)$")
  if not first_para then
    first_para, rest = prose, ""
  end

  local flat = first_para:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")

  -- Prefer a real sentence boundary: ". " not preceded by a single capital
  -- (crude initials guard) and not inside `code`.
  local sentence = flat:match("^(.-[%.!?])%s")
  local summary = sentence or flat

  local max = 160
  if #summary > max then
    summary = summary:sub(1, max - 1):gsub("%s+%S*$", "") .. "…"
  end

  local body = rest
  if sentence and #sentence < #flat then
    body = flat:sub(#sentence + 1):gsub("^%s+", "") .. (rest ~= "" and ("\n\n" .. rest) or "")
  end

  return summary, (body:gsub("^%s+", ""):gsub("%s+$", ""))
end

---Parse the leading comment block of a Lua file.
---@param path string
---@return { module: string?, summary: string, body: string, tags: table<string, string> }
function M.parse_header(path)
  local lines = head_lines(path, 200)

  local module_path, meta
  local prose = {}
  local tags = {}
  local seen_module = false

  for _, line in ipairs(lines) do
    -- Stop at the first line that is not a comment and not blank: the header
    -- block is over and everything past it is code.
    if not line:match("^%s*%-%-") and line:match("%S") then
      break
    end

    local mod = line:match("^%-%-%-@module%s+['\"]([^'\"]+)['\"]")
    if mod then
      module_path = mod
      seen_module = true
    elseif line:match("^%-%-%-@meta") then
      meta = true
    else
      -- A tagged annotation ends the prose block for our purposes; we only
      -- want the free text that documents the module itself.
      local tag, value = line:match("^%-%-%-@(%a+)%s*(.*)$")
      if tag then
        if value ~= "" and tags[tag] == nil then
          tags[tag] = value
        end
      else
        local text = line:match("^%s*%-%-%-?%s?(.*)$")
        if text and seen_module then
          prose[#prose + 1] = text
        end
      end
    end
  end

  -- `@brief`/`@description` exist in a handful of files as a competing
  -- convention; treat them as prose so those modules are not blank on the map.
  local blob = table.concat(prose, "\n")
  if blob:match("^%s*$") then
    blob = tags.brief or tags.description or ""
  end

  local summary, body = M.split_summary(blob)
  return { module = module_path, summary = summary, body = body, tags = tags, meta = meta }
end

---Classify a module's export shape from its tail.
---@param path string
---@return "function"|"table"|"other"|"none"
local function export_shape(path)
  local fd = io.open(path, "r")
  if not fd then
    return "none"
  end
  local last
  for line in fd:lines() do
    if line:match("^return%s") or line:match("^return$") then
      last = line
    end
  end
  fd:close()

  if not last then
    return "none"
  end
  if last:match("^return%s+function") then
    return "function"
  end
  if last:match("^return%s*{") then
    return "table"
  end
  if last:match("^return%s+%u?%w*%s*$") then
    return "table"
  end
  return "other"
end

---List entries of `dir`, sorted, so generated output is deterministic.
---@param dir string
---@return { name: string, type: string }[]
local function entries(dir)
  local out = {}
  local iter = vim.fs.dir(dir)
  if not iter then
    return out
  end
  for name, type_ in iter do
    out[#out + 1] = { name = name, type = type_ }
  end
  table.sort(out, function(a, b)
    if (a.type == "directory") ~= (b.type == "directory") then
      return a.type == "directory"
    end
    return a.name < b.name
  end)
  return out
end

---Cheap line count for a file the walk does not otherwise read — currently
---only `@types/` members, which carry no functions and so never go through
---`docmap.functions` (which counts its own lines from the source it already
---has in memory).
---@param path string
---@return integer
local function count_lines(path)
  local n = 0
  local fd = io.open(path, "r")
  if not fd then
    return 0
  end
  for _ in fd:lines() do
    n = n + 1
  end
  fd:close()
  return n
end

---An empty tally, so every node starts from the same shape and the
---aggregation below can add without presence checks.
---@return Documentation.Stats
local function zero_stats()
  return {
    modules = 0,
    namespaces = 0,
    files_lua = 0,
    files_md = 0,
    files_other = 0,
    lines = 0,
    functions = 0,
    symbols = 0,
    types = 0,
  }
end

---@param opts Documentation.Opts
---@return Documentation.IR
function M.scan(opts)
  local root = chomp(slash(opts.root))
  -- `opts.source` is one directory or several. One is the overwhelmingly
  -- common case and stays exactly what it was; several exist because a
  -- repository can hold two languages in two places (`lua/` beside `src/`,
  -- or C's `src/` beside `include/`), and a single starting directory means
  -- the walk never *sees* the other one -- not skips it, never visits it,
  -- and says nothing about it either. See `docs/ROADMAP/IDEAS/MULTILANG.md`
  -- Stage 1 for the measurement that forced this.
  local sources = {}
  for _, entry in ipairs(type(opts.source) == "table" and opts.source or { opts.source or "lua" }) do
    sources[#sources + 1] = chomp(slash(entry))
  end
  local types_dir = opts.types_dir or "@types"

  -- Resolved once per scan, not threaded through every language backend's
  -- shared `scan_file(path)` signature — that interface is common to five
  -- backends (`lua`/`js`/`ts`/`tsx`/`ecma`) and adding a parameter to it for
  -- one policy value would touch all five for something that only ever
  -- needs to be current *before* the walk below starts, never per file.
  -- Safe against leaking one repo's override into a later scan of a
  -- different one in the same process (`:DocBrowse` bouncing between repos,
  -- multiple `:DocMap` calls in one session): every `M.scan` explicitly
  -- resets it, so a scan with no `opts.snippet_max_lines` always gets the
  -- real default back, never a previous call's override.
  require("documentation.core.snippet").MAX_LINES = opts.snippet_max_lines
    or require("documentation.core.snippet").DEFAULT_MAX_LINES

  -- Same reasoning, same reset discipline: `core/bindings.lua`'s wrapper
  -- table is caller policy that only has to be current before the walk, and
  -- a scan with no `opts.bindings` must get the real (empty) default back
  -- rather than whatever repo was scanned last in this process.
  require("documentation.core.bindings").WRAPPERS = (opts.bindings and opts.bindings.wrappers)
    or require("documentation.core.bindings").DEFAULT_WRAPPERS

  for _, src in ipairs(sources) do
    assert(is_dir(root .. "/" .. src), "docmap: source directory not found: " .. root .. "/" .. src)
  end

  local index = {} ---@type table<string, Documentation.Node>
  local order = {} ---@type string[]
  local counts = { module = 0, namespace = 0, file = 0 }

  ---Bound on the second traversal below. Generous enough never to stop early
  ---on a real repository, small enough that a home directory picked by mistake
  ---does not turn a scan into a filesystem crawl — the same reasoning
  ---`docmap-desktop`'s own language counter uses for the same shape of walk.
  local OUTSIDE_MAX_FILES = 20000

  ---Extensions seen inside the scanned roots that no backend claimed.
  ---@type table<string, integer>
  local unclaimed = {}

  ---Files each backend *did* read, by backend name. What tells a language
  ---that is merely partly outside the source roots (`scripts/` next to
  ---`lua/`, normal and intentional) from one that is *entirely* outside
  ---them — which is the real gap and the only one worth a line on every run.
  ---@type table<string, integer>
  local claimed = {}

  ---Build one node from a directory.
  ---@param abs string
  ---@param rel string Path relative to `root`
  ---@param parent_id string?
  ---@param depth integer
  ---@return string id
  local function walk_dir(abs, rel, parent_id, depth)
    local id = rel
    local name = rel:match("([^/]+)$") or opts.title or rel

    -- The first registered backend whose `module_file` exists here owns this
    -- directory. Only Lua is registered today (`core/lang/lua.lua`), so this
    -- is exactly the `init.lua` check it replaces — see
    -- `docs/ROADMAP/IDEAS/MULTILANG.md` Phase 0 for why the walk asks the registry
    -- instead of assuming there is only ever one answer.
    local module_backend, module_abs
    for _, backend in ipairs(lang_registry.all()) do
      if backend.module_file then
        local candidate = abs .. "/" .. backend.module_file
        if is_file(candidate) then
          module_backend, module_abs = backend, candidate
          break
        end
      end
    end
    local has_init = module_backend ~= nil
    if module_backend then
      claimed[module_backend.name] = (claimed[module_backend.name] or 0) + 1
    end
    local header = module_backend and module_backend.parse_header(module_abs) or nil

    -- `@types/` is an attribute of its module, not a node of its own: a
    -- module's types belong to it, and promoting them to siblings doubles the
    -- tree for no navigational gain.
    local type_files = {}
    local abs_types = abs .. "/" .. types_dir
    if is_dir(abs_types) then
      for _, e in ipairs(entries(abs_types)) do
        if e.type == "file" and e.name:match("%.lua$") then
          type_files[#type_files + 1] = rel .. "/" .. types_dir .. "/" .. e.name
        end
      end
    end

    local readme = is_file(abs .. "/README.md") and (rel .. "/README.md") or nil

    local kind = has_init and "module" or "namespace"
    counts[kind] = counts[kind] + 1

    local fns, calls, requires, syms, plugins, endpoints, loc, binds = {}, {}, {}, {}, {}, {}, 0, {}
    if module_backend then
      fns, calls, requires, syms, plugins, endpoints, loc, binds =
        module_backend.scan_file(module_abs)
    end

    -- Own tally for this directory: what sits directly in it, plus its
    -- `@types/` members, which are files of this module rather than nodes of
    -- their own and would otherwise be counted nowhere.
    local own = zero_stats()
    own[kind == "module" and "modules" or "namespaces"] = 1
    own.functions = #fns
    own.symbols = #syms
    if has_init then
      own.files_lua = 1
      own.lines = loc
    end
    for _, t in ipairs(type_files) do
      own.files_lua = own.files_lua + 1
      own.lines = own.lines + count_lines(root .. "/" .. t)
    end

    -- Listed once and reused by both the tally and the child walk below: an
    -- earlier version called `entries(abs)` twice per directory, which is a
    -- second full directory read for every one of ~150 directories.
    local dir_entries = entries(abs)
    for _, e in ipairs(dir_entries) do
      if e.type ~= "directory" and not e.name:match("%.lua$") then
        if e.name:lower():match("%.md$") then
          own.files_md = own.files_md + 1
        else
          own.files_other = own.files_other + 1
        end
      end
    end

    ---@type Documentation.Node
    local node = {
      id = id,
      kind = kind,
      name = name,
      path = rel,
      source = module_backend and (rel .. "/" .. module_backend.module_file) or nil,
      module = header and header.module or nil,
      summary = header and header.summary or "",
      body = header and header.body or "",
      readme = readme,
      types = type_files,
      export = module_backend and export_shape(module_abs) or nil,
      parent = parent_id,
      depth = depth,
      children = {},
      functions = fns,
      symbols = syms,
      plugins = plugins,
      endpoints = endpoints,
      bindings = binds,
      stats = own,
      requires = {},
      required_by = {},
      requires_external = {},
      requires_raw = requires,
      calls_raw = calls,
    }

    index[id] = node
    order[#order + 1] = id

    for _, e in ipairs(dir_entries) do
      local child_abs = abs .. "/" .. e.name
      local child_rel = rel .. "/" .. e.name
      -- Looked up once per entry rather than in the branch condition below:
      -- a second call cannot prove to the type checker it would return the
      -- same table, and calling a registry lookup twice per file is waste
      -- besides.
      local leaf_backend = e.type ~= "directory" and lang_registry.for_file(e.name) or nil

      if e.type == "directory" then
        if e.name ~= types_dir and not M.VENDOR_DIRS[e.name] then
          node.children[#node.children + 1] = walk_dir(child_abs, child_rel, id, depth + 1)
        end
      elseif e.type ~= "directory" and not leaf_backend then
        -- Counted, not ignored. A file no backend claims is the ordinary
        -- case for a README or a lockfile and the *interesting* case for a
        -- `.py` in a tree this build cannot read -- and the two are
        -- indistinguishable unless someone counts. Keyed by extension so
        -- the report can name what it was.
        local ext = e.name:match("%.([%w]+)$")
        if ext then
          ext = ext:lower()
          unclaimed[ext] = (unclaimed[ext] or 0) + 1
        end
      elseif leaf_backend and e.name ~= (module_backend and module_backend.module_file) then
        -- Helper files are real, documented units and stay visible as leaves
        -- rather than being folded into the parent's detail pane. The
        -- exclusion above is what keeps the file that already became this
        -- directory's own `source` (this backend's `module_file`) from also
        -- appearing a second time as its own leaf.
        local h = leaf_backend.parse_header(child_abs)
        counts.file = counts.file + 1
        claimed[leaf_backend.name] = (claimed[leaf_backend.name] or 0) + 1
        local leaf_fns, leaf_calls, leaf_requires, leaf_syms, leaf_plugins, leaf_endpoints, leaf_loc, leaf_binds =
          leaf_backend.scan_file(child_abs)
        local leaf_stats = zero_stats()
        leaf_stats.files_lua = 1
        leaf_stats.lines = leaf_loc
        leaf_stats.functions = #leaf_fns
        leaf_stats.symbols = #leaf_syms
        ---@type Documentation.Node
        local leaf = {
          id = child_rel,
          kind = "file",
          name = e.name,
          path = child_rel,
          source = child_rel,
          module = h.module,
          summary = h.summary,
          body = h.body,
          readme = nil,
          types = {},
          export = export_shape(child_abs),
          parent = id,
          depth = depth + 1,
          children = {},
          functions = leaf_fns,
          symbols = leaf_syms,
          plugins = leaf_plugins,
          endpoints = leaf_endpoints,
          bindings = leaf_binds,
          stats = leaf_stats,
          requires = {},
          required_by = {},
          requires_external = {},
          requires_raw = leaf_requires,
          calls_raw = leaf_calls,
        }
        index[child_rel] = leaf
        order[#order + 1] = child_rel
        node.children[#node.children + 1] = child_rel
      end
    end

    return id
  end

  -- One source root is still one tree, byte-for-byte as before: no synthetic
  -- node, no extra depth, the module itself is the root of the map. The
  -- alternative -- always wrapping, for uniformity -- would put a
  -- meaningless "repository" node above every existing map and shift every
  -- node id's depth by one, which is a breaking change to buy tidiness in a
  -- branch most trees never take.
  local root_id
  if #sources == 1 then
    root_id = walk_dir(root .. "/" .. sources[1], sources[1], nil, 0)
  else
    -- Several roots need something above them, because `ir.root` is one id
    -- and every consumer reads it as one: the tree view renders from it, the
    -- hierarchy centres on it, `check.lua` exempts it. Giving them a real
    -- parent is cheaper and more honest than teaching a dozen consumers that
    -- "the root" is sometimes a list -- and the parent is not invented, it
    -- is the repository directory these subtrees actually sit in.
    root_id = "."
    counts.namespace = counts.namespace + 1
    ---@type Documentation.Node
    index[root_id] = {
      id = root_id,
      kind = "namespace",
      name = opts.title or (root:match("([^/]+)$") or root),
      path = root_id,
      -- No `source`/`module`/`functions`: this directory is not a module and
      -- claiming otherwise would put a node in the map that answers to
      -- nothing on disk. What it does carry is the repository's own README,
      -- which is real and is the one thing a reader landing here wants.
      summary = "",
      body = "",
      readme = is_file(root .. "/README.md") and "README.md" or nil,
      types = {},
      parent = nil,
      depth = 0,
      children = {},
      functions = {},
      symbols = {},
      plugins = {},
      endpoints = {},
      bindings = {},
      stats = (function()
        local z = zero_stats()
        z.namespaces = 1
        return z
      end)(),
      requires = {},
      required_by = {},
      requires_external = {},
      calls_external = {},
      requires_raw = {},
      calls_raw = {},
    }
    -- Pushed before the walk so the reverse-`order` stats rollup below still
    -- sees every child after its parent, which is the invariant that makes
    -- that loop a valid post-order.
    order[#order + 1] = root_id
    for _, src in ipairs(sources) do
      index[root_id].children[#index[root_id].children + 1] =
        walk_dir(root .. "/" .. src, src, root_id, 1)
    end
  end
  index[root_id].name = opts.title or index[root_id].name

  -- What a backend could have read but never got the chance to.
  --
  -- The failure this closes was found twice in one session, the same shape
  -- both times: a map that looks healthy and is missing half its subject.
  -- `source` bounds the walk, which is the whole point of it — but a
  -- `tools/` directory of TypeScript sitting outside every source root is
  -- invisible today, and invisible is the one thing this map must not be
  -- about its own coverage.
  --
  -- A second traversal rather than a wider first one, deliberately: the walk
  -- builds nodes and must not build them for files outside the map's stated
  -- scope. This one builds nothing, counts by backend, and stops early.
  ---@type table<string, integer>
  local outside = {}
  do
    local seen = 0
    local stack = { { abs = root, rel = "" } }
    while #stack > 0 and seen < OUTSIDE_MAX_FILES do
      local cur = table.remove(stack)
      for _, e in ipairs(entries(cur.abs)) do
        local child_rel = cur.rel == "" and e.name or (cur.rel .. "/" .. e.name)
        if e.type == "directory" then
          -- Skipped when it is a source root or inside one: those files are
          -- in the map already, and counting them here would report the
          -- whole tree as missing from itself.
          local inside = false
          for _, src in ipairs(sources) do
            if
              src == "."
              or child_rel == src
              or src:sub(1, #child_rel + 1) == (child_rel .. "/")
              or child_rel:sub(1, #src + 1) == (src .. "/")
            then
              inside = true
              break
            end
          end
          if not inside and not M.VENDOR_DIRS[e.name] and e.name ~= types_dir then
            stack[#stack + 1] = { abs = cur.abs .. "/" .. e.name, rel = child_rel }
          end
        else
          seen = seen + 1
          local backend = lang_registry.for_file(e.name)
          if backend then
            outside[backend.name] = (outside[backend.name] or 0) + 1
          end
        end
      end
    end
  end

  ---@type Documentation.IR
  local ir = {
    meta = {
      title = opts.title or (#sources == 1 and sources[1] or index[root_id].name),
      -- Stays a string, always: nothing reads it, and a field that is
      -- sometimes a string and sometimes a list is worse than one that is
      -- always the honest single answer -- with several roots the scan
      -- really did start at the repository directory.
      source = #sources == 1 and sources[1] or root_id,
      -- Emitted only when there is more than one, so a single-root map is
      -- byte-identical to the maps every existing user already has. Its
      -- absence is not ambiguous: it means `source` alone describes the
      -- scan, which is exactly what it did before this field existed.
      sources = #sources > 1 and sources or nil,
      -- Emitted only when non-empty, so a tree with nothing to report is
      -- byte-identical to the maps generated before this existed. Absence
      -- means "nothing was missed", which is the common and the good case.
      unclaimed = next(unclaimed) and unclaimed or nil,
      outside = next(outside) and outside or nil,
      -- Kept beside `outside` so a consumer can tell "this language is
      -- partly outside the roots" (ordinary: a scripts/ next to lua/) from
      -- "this language is entirely outside them" (the real gap). The CLI
      -- prints only the second; the artifact carries both.
      claimed = next(claimed) and claimed or nil,
      types_dir = types_dir,
      repo_url = opts.repo_url,
      branch = opts.branch or "main",
      schema = 2,
      counts = counts,
    },
    root = root_id,
    order = order,
    nodes = index,
    edges = {},
  }

  -- Both graph stages run here rather than in `scan_full`, unlike the LuaLS
  -- merge: they need no external tool, they cost only in-memory resolution
  -- over data the walk already collected, and running them here means every
  -- caller of `scan()` — checks, renderers, a live handle — sees the same
  -- fully-formed IR instead of some seeing a half-built one. Order matters:
  -- call resolution reads the require aliases `deps` indexes.
  require("documentation.core.deps").build(ir)
  require("documentation.core.calls").build(ir, opts)

  -- Roll the per-directory tallies up the tree. Reverse `order` is a valid
  -- post-order here because `walk_dir` appends a node before descending into
  -- it, so every child sits after its parent — walking backwards means a node
  -- is only ever added to its parent once its own subtree is complete.
  for i = #order, 1, -1 do
    local node = index[order[i]]
    local parent = node.parent and index[node.parent]
    if parent then
      for key, value in pairs(node.stats) do
        parent.stats[key] = parent.stats[key] + value
      end
    end
  end

  return ir
end

return M
