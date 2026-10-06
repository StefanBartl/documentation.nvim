---@module 'documentation.testing'
--- Which specs does a change touch, and what do the specs say about the map.
---
--- The provider side of the affected-selection contract (version 1, see
--- `docs/testing-contract.md`). A test runner hands in a list of changed files
--- and gets back the spec files that cover them, how fresh the graph behind
--- the answer is, and, explicitly, everything the graph could NOT tell it:
--- changed files outside the map, changed modules no spec covers, specs it
--- cannot place. An unknown is never reported as "unaffected".
---
--- The runner is not required and neither is this plugin on its side: this
--- module never requires a test runner (soft dependency, LUA-05); a runner
--- that finds this module absent falls back to running everything.
---
--- ## The chain
---
---   changed file -> graph node (`path` / `source` of the map)
---                -> the node and its transitive dependents (`deps.impact`)
---                -> spec files that require any of them
---
--- A spec covers a module when it requires it, or requires a module that
--- loads it. Specs are the files `<tests_dir>/**/*_spec.lua` (default `TESTS`)
--- plus an optional per-repository list (`spec_roots`).
---
--- ## Cross-repository
---
--- With a directory of sibling checkouts (`consumers`, the option the
--- `consumer-require-missing` check already uses) the same question is asked of
--- every consumer whose committed map is readable: a consumer module that
--- requires an affected module is affected, and so are its dependents and the
--- consumer's specs that cover them. A checkout without a usable map is listed
--- as `measured = false`: not measured is not the same as not affected.
---
--- ## The map side
---
--- `spec_state` answers the opposite question for the map: which modules have
--- specs, and how did the last run of them end. It reads the run result only
--- as untrusted data (`testing.status`).

local gitq = require("documentation.testing.git")
local specs_mod = require("documentation.testing.specs")

local M = {}

---Version of the answer's shape; bumped only for an incompatible change.
M.CONTRACT_VERSION = 1
---Most changed paths one call accepts.
M.MAX_CHANGED = 50000
---Most direct spec paths kept per node in `spec_state` (the count stays exact).
M.MAX_SPECS_PER_NODE = 50
---Largest module map read (a bigger file is reported, not read).
M.MAX_MAP_BYTES = 64 * 1024 * 1024

-- Changed files that cannot change what a spec observes of this code.
local IGNORABLE_EXT = {
  md = true,
  markdown = true,
  txt = true,
  rst = true,
  adoc = true,
  svg = true,
  png = true,
  jpg = true,
  jpeg = true,
  gif = true,
  ico = true,
  webp = true,
  pdf = true,
  html = true,
  css = true,
  lock = true,
}
local IGNORABLE_NAMES = {
  LICENSE = true,
  [".gitignore"] = true,
  [".gitattributes"] = true,
  [".editorconfig"] = true,
  [".stylua.toml"] = true,
  ["stylua.toml"] = true,
  [".luacheckrc"] = true,
}
-- Machine output of this very plugin: regenerating it is not a code change.
local function is_ignorable(rel, map_rel)
  local map_dir = map_rel:match("^(.*)/[^/]*$") or ""
  if rel == map_rel or (map_dir ~= "" and rel:sub(1, #map_dir + 1) == map_dir .. "/") then
    return true
  end
  local name = rel:match("([^/]+)$") or rel
  if IGNORABLE_NAMES[name] then
    return true
  end
  local ext = name:match("%.([%w]+)$")
  return ext ~= nil and IGNORABLE_EXT[ext:lower()] == true
end

-- ------------------------------------------------------------------ paths

---Repository root spelled with forward slashes, no trailing slash.
---@param root any
---@return string|nil
local function norm_root(root)
  if type(root) ~= "string" or root == "" or root:find("[%z\1-\31]") then
    return nil
  end
  local s = root:gsub("\\", "/"):gsub("(.)/+$", "%1")
  return s
end

---@param a string
---@param b string
---@return boolean
local function same_path(a, b)
  local ok_a, ka = pcall(require("lib.nvim.fs.normkey"), a, { realpath = true })
  local ok_b, kb = pcall(require("lib.nvim.fs.normkey"), b, { realpath = true })
  if ok_a and ok_b then
    return ka == kb
  end
  return a == b
end

---Turn what the caller listed into repository-relative, normalised paths.
---@param root string
---@param list any[]
---@return string[] paths Unique, sorted.
---@return Documentation.Testing.Gap[] invalid
local function normalize_changed(root, list)
  local out, seen, invalid = {}, {}, {}
  local root_lower = root:lower()
  for _, raw in ipairs(list) do
    local rel
    if type(raw) == "string" and #raw <= 1000 and not raw:find("[%z\1-\31]") then
      local p = raw:gsub("\\", "/")
      local absolute = p:sub(1, 1) == "/" or p:match("^%a:") ~= nil
      if absolute then
        -- Compared case-insensitively on a drive path (Windows), exactly on a
        -- POSIX one: `C:/x` and `c:/x` are the same place, `/X` and `/x` not.
        local drive = p:match("^%a:") ~= nil
        local head = drive and p:sub(1, #root):lower() or p:sub(1, #root)
        local want = drive and root_lower or root
        if head == want and p:sub(#root + 1, #root + 1) == "/" then
          rel = specs_mod.clean_rel(p:sub(#root + 2))
        end
      else
        rel = specs_mod.clean_rel(p)
      end
    end
    if rel then
      if not seen[rel] then
        seen[rel] = true
        out[#out + 1] = rel
      end
    else
      invalid[#invalid + 1] = {
        kind = "invalid_path",
        message = ("changed entry refused (not a path inside the repository): %s"):format(
          type(raw) == "string" and vim.inspect(raw:sub(1, 80)) or type(raw)
        ),
      }
    end
  end
  table.sort(out)
  return out, invalid
end

-- ------------------------------------------------------------------ the map

---Make an untrusted decoded map safe to walk: node tables only, the three
---edge lists are arrays of strings.
---@param ir table
local function sanitize(ir)
  local order, nodes = {}, {}
  for _, id in ipairs(ir.order or {}) do
    local n = type(id) == "string" and ir.nodes[id] or nil
    if type(n) == "table" then
      for _, key in ipairs({ "requires", "required_by", "requires_external" }) do
        local clean = {}
        if type(n[key]) == "table" then
          for _, v in ipairs(n[key]) do
            if type(v) == "string" then
              clean[#clean + 1] = v
            end
          end
        end
        n[key] = clean
      end
      for _, key in ipairs({ "path", "source", "module" }) do
        if type(n[key]) ~= "string" then
          n[key] = nil
        end
      end
      n.id = id
      nodes[id] = n
      order[#order + 1] = id
    end
  end
  ir.nodes, ir.order = nodes, order
end

---@param abs string
---@return string|nil text
---@return string|nil err
local function read_map_text(abs)
  local uv = vim.uv or vim.loop
  local st = uv.fs_stat(abs)
  if not st or st.type ~= "file" then
    return nil, "absent"
  end
  if st.size > M.MAX_MAP_BYTES then
    return nil, ("larger than %d bytes"):format(M.MAX_MAP_BYTES)
  end
  local text = require("lib.nvim.fs.read")(abs)
  if not text then
    return nil, "cannot be read"
  end
  return text, nil
end

---The repository's own options for the keys this module reads.
---@param root string
---@return table
local function repo_options(root)
  local ok, cfg = pcall(function()
    return require("documentation.config.file").load(root)
  end)
  if ok and type(cfg) == "table" then
    return cfg
  end
  return {}
end

---@param opts table Caller options.
---@param cfg table Repo options.
---@param key string
---@return any
local function pick(opts, cfg, key)
  if opts[key] ~= nil then
    return opts[key]
  end
  return cfg[key]
end

---Load and sanitise a repository's committed map.
---@param root string
---@param out_dir any
---@return Documentation.IR|nil ir
---@return string|nil err
---@return string map_rel
---@return string map_abs
local function load_ir(root, out_dir)
  local safe = require("documentation.core.safe_out_dir")(out_dir or "docs/map") or "docs/map"
  local map_rel = safe .. "/module_map.json"
  local map_abs = root .. "/" .. map_rel
  local text, why = read_map_text(map_abs)
  if not text then
    return nil,
      why == "absent" and ("no module map at %s: generate it with :DocMap first"):format(map_rel)
        or ("module map %s %s"):format(map_rel, why),
      map_rel,
      map_abs
  end
  local ir, err = require("documentation.core.artifact").decode(text)
  if not ir then
    return nil, ("module map %s is not usable: %s"):format(map_rel, tostring(err)), map_rel, map_abs
  end
  sanitize(ir)
  return ir, nil, map_rel, map_abs
end

-- ------------------------------------------------------------------ coverage

---@class Documentation.Testing.Index
---@field spec_nodes table<string, table<string, true>> spec -> directly required node ids
---@field unplaced table<string, string> spec -> reason
---@field infos Documentation.Testing.SpecInfo[]

---Resolve what every spec requires against the graph.
---@param ir Documentation.IR
---@param infos Documentation.Testing.SpecInfo[]
---@return Documentation.Testing.Index
local function index_specs(ir, infos)
  local deps = require("documentation.core.deps")
  local by_module = deps.module_index(ir)
  local spec_nodes, unplaced = {}, {}
  for _, info in ipairs(infos) do
    local set = {}
    for _, m in ipairs(info.modules) do
      local id = by_module[m]
      if id then
        set[id] = true
      end
    end
    for _, prefix in ipairs(info.prefixes) do
      for module, id in pairs(by_module) do
        if module:sub(1, #prefix) == prefix then
          set[id] = true
        end
      end
    end
    spec_nodes[info.path] = set
    if info.unreadable then
      unplaced[info.path] = "unreadable"
    elseif info.dynamic then
      unplaced[info.path] = "dynamic_require"
    elseif next(set) == nil then
      unplaced[info.path] = "no_graph_module"
    end
  end
  return { spec_nodes = spec_nodes, unplaced = unplaced, infos = infos }
end

---For every node: the specs that require it directly and the ones that reach it
---only through the graph (a spec covers what it loads, transitively).
---@param ir Documentation.IR
---@param idx Documentation.Testing.Index
---@return table<string, table<string, true>> direct node -> set of specs
---@return table<string, table<string, true>> reached node -> set of specs (includes direct)
local function coverage(ir, idx)
  local direct, reached = {}, {}
  for spec, set in pairs(idx.spec_nodes) do
    local seen, queue, qi = {}, {}, 1
    for id in pairs(set) do
      direct[id] = direct[id] or {}
      direct[id][spec] = true
      seen[id] = true
      queue[#queue + 1] = id
    end
    while qi <= #queue do
      local cur = queue[qi]
      qi = qi + 1
      reached[cur] = reached[cur] or {}
      reached[cur][spec] = true
      for _, nxt in ipairs((ir.nodes[cur] or {}).requires or {}) do
        if not seen[nxt] and ir.nodes[nxt] then
          seen[nxt] = true
          queue[#queue + 1] = nxt
        end
      end
    end
  end
  return direct, reached
end

---@param set table<string, true>|nil
---@return string[]
local function sorted_keys(set)
  local out = {}
  for k in pairs(set or {}) do
    out[#out + 1] = k
  end
  table.sort(out)
  return out
end

---Read every discovered spec file.
---@param root string
---@param list string[]
---@return Documentation.Testing.SpecInfo[]
local function read_specs(root, list)
  local infos = {}
  for _, rel in ipairs(list) do
    infos[#infos + 1] = specs_mod.read(root, rel)
  end
  return infos
end

---The part of a map a selection depends on, as one comparable string: which
---nodes exist, where their sources are, and who requires whom. Titles,
---summaries and every other piece of documentation are left out on purpose: a
---map that differs only there answers "which specs does this change touch"
---exactly as a fresh one would.
---@param ir Documentation.IR
---@return string
local function graph_signature(ir)
  local out = {}
  for _, id in ipairs(ir.order) do
    local n = ir.nodes[id]
    out[#out + 1] = table.concat({
      id,
      n.path or "",
      n.source or "",
      n.module or "",
      table.concat(n.requires or {}, ","),
      table.concat(n.required_by or {}, ","),
      table.concat(n.requires_external or {}, ","),
    }, "\t")
  end
  return table.concat(out, "\n")
end

---Whether the committed map describes the same graph as a scan of the tree as
---it is now. The exact answer to "is the map stale", where git can only say
---"code was committed after the map": a change that does not alter the graph
---(a function body, a comment) leaves the map file unchanged and so never gets
---a newer commit of its own.
---
---Costs a full scan, so it runs only when the caller asks for it (`verify`) and
---git already called the map stale.
---@param root string
---@param ir Documentation.IR The committed map, already sanitised.
---@return boolean same
local function matches_fresh_scan(root, ir)
  local ok, same = pcall(function()
    local built = require("documentation.config").build(root, { spec_state = false })
    local fresh = require("documentation").scan_full(built)
    return graph_signature(fresh) == graph_signature(ir)
  end)
  return ok and same == true
end

-- ------------------------------------------------------------------ cross repo

---A directory that can be a Lua consumer at all: it has a `lua/` tree. A
---checkout of anything else (notes, a website) is not a consumer and is not
---listed as one that failed to be measured.
---@param cand string
---@return boolean
local function looks_like_checkout(cand)
  local uv = vim.uv or vim.loop
  local st = uv.fs_stat(cand .. "/lua")
  return st ~= nil and st.type == "directory"
end

---What a consumer's specs make of a change in this repository.
---@param root string
---@param affected_modules table<string, true> Module paths of the changed modules and their dependents.
---@param consumers_dir any
---@return Documentation.Testing.CrossRepo[]
---@return string|nil note
local function cross_repo(root, affected_modules, consumers_dir)
  local uv = vim.uv or vim.loop
  if consumers_dir == nil then
    return {}, nil
  end
  local dir = norm_root(consumers_dir)
  if not dir or vim.fn.isdirectory(dir) == 0 then
    return {}, "the consumers directory does not exist: no consumer was looked at"
  end
  local entries, count = {}, 0
  for name, kind in vim.fs.dir(dir) do
    count = count + 1
    if count > 500 then
      break
    end
    local cand = dir .. "/" .. name
    local st = (kind == "directory" or kind == "link") and uv.fs_stat(cand) or nil
    if name:sub(1, 1) ~= "." and st and st.type == "directory" and not same_path(cand, root) then
      local repo = { repo = name }
      local cfg = repo_options(cand)
      local ir, err, map_rel, map_abs = load_ir(cand, cfg.out_dir)
      if not ir then
        if looks_like_checkout(cand) then
          repo.measured = false
          repo.reason = err and err:match("absent") and "no committed module map"
            or ("the module map is not usable: " .. tostring(err))
          if err and err:find("no module map at", 1, true) then
            repo.reason = "no committed module map"
          end
          entries[#entries + 1] = repo
        end
      else
        local ok, res = pcall(function()
          local deps = require("documentation.core.deps")
          local hit, hit_set = {}, {}
          for _, id in ipairs(ir.order) do
            for _, ext in ipairs(ir.nodes[id].requires_external) do
              if affected_modules[ext] and not hit_set[id] then
                hit_set[id] = true
                hit[#hit + 1] = id
              end
            end
          end
          local affected = {}
          for _, id in ipairs(hit) do
            affected[id] = true
            for _, dep in ipairs((deps.impact(ir, id))) do
              affected[dep] = true
            end
          end

          local list = specs_mod.discover(cand, cfg.tests_dir, cfg.spec_roots)
          local infos = read_specs(cand, list)
          local idx = index_specs(ir, infos)
          local selected, unplaced = {}, {}
          for _, info in ipairs(infos) do
            local direct_hit = false
            for _, m in ipairs(info.modules) do
              if affected_modules[m] then
                direct_hit = true
              end
            end
            for _, p in ipairs(info.prefixes) do
              for m in pairs(affected_modules) do
                if m:sub(1, #p) == p then
                  direct_hit = true
                end
              end
            end
            local via_graph = false
            for id in pairs(idx.spec_nodes[info.path]) do
              if affected[id] then
                via_graph = true
              end
            end
            if direct_hit or via_graph then
              selected[#selected + 1] = info.path
            end
            if idx.unplaced[info.path] and not (direct_hit or via_graph) then
              unplaced[#unplaced + 1] = info.path
            end
          end
          return {
            hit = hit,
            affected = affected,
            selected = selected,
            unplaced = unplaced,
          }
        end)
        if not ok then
          repo.measured = false
          repo.reason = "the module map is malformed"
          entries[#entries + 1] = repo
        elseif #res.hit > 0 or #res.selected > 0 then
          local fresh = require("documentation.testing.freshness").assess(
            cand,
            map_rel,
            map_abs,
            ir.meta,
            cfg.lua_root
          )
          table.sort(res.selected)
          table.sort(res.unplaced)
          repo.measured = true
          repo.stale = fresh.stale
          repo.specs = res.selected
          repo.unplaced_specs = res.unplaced
          repo.modules = sorted_keys(res.affected)
          repo.uncovered = #res.selected == 0
          entries[#entries + 1] = repo
        end
      end
    end
  end
  table.sort(entries, function(a, b)
    return a.repo < b.repo
  end)
  return entries, nil
end

-- ------------------------------------------------------------------ public

---Which specs does this change touch?
---
---Options: `root` (required), `changed` (list of files, repository-relative or
---absolute inside the root), `since` (a git revision: the files changed
---between it and the working tree are added), `spec_roots`, `tests_dir`,
---`out_dir`, `consumers`, `verify`. Anything not given is read from the
---repository's own `.docmap.json`.
---
---`verify = true` settles a "stale" verdict exactly instead of by git history:
---when git says the code is newer than the map, the tree is scanned and the
---map is accepted when its graph equals the scan's (`graph.verified`).
---It costs a full scan, so it is off unless asked for.
---
---Returns `nil, err` only when no answer is possible at all (bad options, no
---map). Every weaker situation is an answer that says so (`graph.stale`,
---`gaps`, `complete = false`).
---@param opts { root: string, changed?: string[], since?: string, spec_roots?: string[], tests_dir?: string, out_dir?: string, consumers?: string, verify?: boolean }
---@return Documentation.Testing.Result|nil result
---@return string|nil err
function M.affected_specs(opts)
  if type(opts) ~= "table" then
    return nil, "affected_specs: opts must be a table"
  end
  local root = norm_root(opts.root)
  if not root or vim.fn.isdirectory(root) == 0 then
    return nil, "affected_specs: opts.root must be an existing directory"
  end
  if opts.changed ~= nil and type(opts.changed) ~= "table" then
    return nil, "affected_specs: opts.changed must be a list of paths"
  end

  local raw = {}
  for _, p in ipairs(opts.changed or {}) do
    raw[#raw + 1] = p
  end
  if opts.since ~= nil then
    if not gitq.valid_rev(opts.since) then
      return nil, "affected_specs: opts.since is not a valid revision"
    end
    local files = gitq.changed_since(root, opts.since)
    if not files then
      return nil, ("affected_specs: git could not list the changes since %s"):format(opts.since)
    end
    vim.list_extend(raw, files)
  end
  if #raw > M.MAX_CHANGED then
    return nil, ("affected_specs: more than %d changed files: run everything"):format(M.MAX_CHANGED)
  end

  local cfg = repo_options(root)
  local ir, err, map_rel, map_abs = load_ir(root, pick(opts, cfg, "out_dir"))
  if not ir then
    return nil, err
  end

  local ok, result = pcall(function()
    local deps = require("documentation.core.deps")
    local freshness = require("documentation.testing.freshness")
    local graph = freshness.assess(root, map_rel, map_abs, ir.meta, pick(opts, cfg, "lua_root"))
    local gaps = graph.gaps

    if graph.stale and opts.verify == true and matches_fresh_scan(root, ir) then
      graph.stale = false
      graph.stale_reason = nil
      graph.verified = true
    end

    local changed, invalid = normalize_changed(root, raw)
    vim.list_extend(gaps, invalid)

    local tests_dir = pick(opts, cfg, "tests_dir")
    local spec_list, problems = specs_mod.discover(root, tests_dir, pick(opts, cfg, "spec_roots"))
    vim.list_extend(gaps, problems)
    local infos = read_specs(root, spec_list)
    local idx = index_specs(ir, infos)
    local direct, reached = coverage(ir, idx)
    local is_spec = {}
    for _, s in ipairs(spec_list) do
      is_spec[s] = true
    end
    local tests_rel = specs_mod.clean_rel(tests_dir or "TESTS") or "TESTS"

    local by_path = deps.path_index(ir)
    local selected, ignored = {}, {}
    local changed_nodes, role = {}, {}
    for _, rel in ipairs(changed) do
      local id = by_path[rel]
      if is_spec[rel] then
        selected[rel] = true
      elseif id then
        if not role[id] then
          role[id] = "changed"
          changed_nodes[#changed_nodes + 1] = id
        end
      elseif is_ignorable(rel, map_rel) then
        ignored[#ignored + 1] = rel
      elseif rel == tests_rel or rel:sub(1, #tests_rel + 1) == tests_rel .. "/" then
        gaps[#gaps + 1] = {
          kind = "test_support_changed",
          path = rel,
          message = "a file under the spec directory that is not a spec changed: any spec may use it",
        }
      else
        gaps[#gaps + 1] = {
          kind = "changed_not_in_graph",
          path = rel,
          message = "the changed file is not in the module map: its dependents are unknown",
        }
      end
    end

    local affected_modules = {}
    for _, id in ipairs(changed_nodes) do
      for _, dep in ipairs((deps.impact(ir, id))) do
        if not role[dep] then
          role[dep] = "dependent"
        end
      end
    end

    local modules = {}
    local ids = {}
    for id in pairs(role) do
      ids[#ids + 1] = id
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
      local node = ir.nodes[id]
      local covering = sorted_keys(reached[id])
      for _, s in ipairs(covering) do
        selected[s] = true
      end
      if node.module then
        affected_modules[node.module] = true
      end
      modules[#modules + 1] = {
        id = id,
        module = node.module,
        path = node.path or id,
        role = role[id],
        specs = covering,
      }
      if role[id] == "changed" and node.module and #covering == 0 then
        gaps[#gaps + 1] = {
          kind = "changed_module_without_spec",
          path = node.source or node.path,
          module = node.module,
          message = ("no spec requires %s or anything that loads it"):format(node.module),
        }
      end
    end
    -- `direct` is only needed by `spec_state`; kept here to document that the
    -- two views share one coverage computation.
    local _ = direct

    local unplaced = {}
    for _, spec in ipairs(spec_list) do
      local reason = idx.unplaced[spec]
      if reason then
        unplaced[#unplaced + 1] = spec
        gaps[#gaps + 1] = {
          kind = reason == "unreadable" and "spec_unreadable" or "spec_unplaced",
          path = spec,
          reason = reason,
          message = reason == "dynamic_require"
              and "the spec requires a module by a computed name: it can depend on anything"
            or reason == "unreadable" and "the spec file could not be read"
            or "none of the modules the spec requires is in the module map",
        }
      end
    end

    local cross, cross_note = cross_repo(root, affected_modules, pick(opts, cfg, "consumers"))
    local blocking = false
    for _, g in ipairs(gaps) do
      if
        g.kind == "changed_not_in_graph"
        or g.kind == "test_support_changed"
        or g.kind == "invalid_path"
        or g.kind == "spec_unreadable"
        or g.kind == "invalid_spec_root"
      then
        blocking = true
      end
    end
    if cross_note then
      graph.cross_repo_note = cross_note
    end

    table.sort(ignored)
    return {
      version = M.CONTRACT_VERSION,
      specs = sorted_keys(selected),
      modules = modules,
      unplaced_specs = unplaced,
      ignored = ignored,
      complete = (not graph.stale) and not blocking,
      graph = graph,
      cross_repo = cross,
    }
  end)
  if not ok then
    return nil, "affected_specs: the module map could not be analysed: " .. tostring(result)
  end
  return result, nil
end

---Which modules have specs, and how did the last run of them end?
---
---Pass the live `ir` when the map is being generated (no git, no map read);
---without one the committed map is loaded. `status_file` (a Result-IR or a
---run history) and `state_dir` locate the last run; both optional.
---@param opts { root: string, ir?: Documentation.IR, spec_roots?: string[], tests_dir?: string, out_dir?: string, status_file?: string, state_dir?: string }
---@return Documentation.Testing.SpecState|nil state
---@return string|nil err
function M.spec_state(opts)
  if type(opts) ~= "table" then
    return nil, "spec_state: opts must be a table"
  end
  local root = norm_root(opts.root)
  if not root or vim.fn.isdirectory(root) == 0 then
    return nil, "spec_state: opts.root must be an existing directory"
  end
  local cfg = repo_options(root)
  local ir = opts.ir
  local graph
  if ir == nil then
    local err, map_rel, map_abs
    ir, err, map_rel, map_abs = load_ir(root, pick(opts, cfg, "out_dir"))
    if not ir then
      return nil, err
    end
    graph = require("documentation.testing.freshness").assess(
      root,
      map_rel,
      map_abs,
      ir.meta,
      pick(opts, cfg, "lua_root")
    )
  end

  local ok, state = pcall(function()
    local list =
      specs_mod.discover(root, pick(opts, cfg, "tests_dir"), pick(opts, cfg, "spec_roots"))
    local infos = read_specs(root, list)
    local idx = index_specs(ir, infos)
    local direct, reached = coverage(ir, idx)

    local status_mod = require("documentation.testing.status")
    local status =
      status_mod.read(root, { status_file = opts.status_file, state_dir = opts.state_dir })
    local by_spec = {}
    for spec in pairs(idx.spec_nodes) do
      by_spec[spec] = status.by_spec[spec]
    end

    local nodes = {}
    local totals = { modules = 0, with_specs = 0, indirect_only = 0, without_specs = 0 }
    for _, id in ipairs(ir.order) do
      local node = ir.nodes[id]
      if node.module then
        local d = sorted_keys(direct[id])
        local r = reached[id] or {}
        local indirect = 0
        for s in pairs(r) do
          if not (direct[id] or {})[s] then
            indirect = indirect + 1
          end
        end
        local last
        for _, s in ipairs(d) do
          if by_spec[s] then
            last = status_mod.worse(last, by_spec[s])
          end
        end
        local kept = d
        if #d > M.MAX_SPECS_PER_NODE then
          kept = vim.list_slice(d, 1, M.MAX_SPECS_PER_NODE)
        end
        nodes[id] = {
          specs = kept,
          spec_count = #d,
          indirect_count = indirect,
          last_status = last,
        }
        totals.modules = totals.modules + 1
        if #d > 0 then
          totals.with_specs = totals.with_specs + 1
        elseif indirect > 0 then
          totals.indirect_only = totals.indirect_only + 1
        else
          totals.without_specs = totals.without_specs + 1
        end
      end
    end

    return {
      version = M.CONTRACT_VERSION,
      nodes = nodes,
      totals = totals,
      status = { source = status.source and "present" or nil, kind = status.kind, ts = status.ts },
      notes = status.notes,
      graph = graph,
    }
  end)
  if not ok then
    return nil, "spec_state: the module map could not be analysed: " .. tostring(state)
  end
  return state, nil
end

return M
