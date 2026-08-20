---@module 'documentation.core.calls'
--- Call-graph extraction: which function calls which, across the scanned tree.
--- The Caller/Callee half of the Doxygen-shaped picture, and the only stage
--- here that has to reason about names rather than just read them.
---
--- Two steps, deliberately split:
---
---   extract(root, src, defs)  syntax only — every call site, its raw callee
---                             text, and which top-level function encloses it.
---                             Runs inside `docmap.functions.scan_file`, on the
---                             treesitter tree that was parsed there anyway.
---   build(ir, opts)           resolution — turns that raw text into node ids
---                             and function names, using the require aliases
---                             `docmap.deps` collected.
---
--- The split exists because resolution is not a per-file question. `fs.read()`
--- only means something once you know that this file bound `fs` to
--- `lib.nvim.fs` and that some node in the map declares that module. A scanner
--- that tried to answer it file-by-file would either be wrong or would need
--- the whole IR passed into it, which is what `build` is.
---
--- ## What resolves, and what is thrown away
---
--- Four shapes resolve exactly, because each is a syntactic fact rather than
--- a guess:
---
---   fs.read(x)               `fs` is bound by `local fs = require("…fs")`
---   require("…fs").read(x)   the module path is in the call itself
---   M.helper(x)              `M` is a prefix this file's own functions use
---   helper(x)                a bare name matching a file-local `local function`
---
--- Everything else is dropped: `obj:method()` on an unknown receiver,
--- `vim.fs.dirname()` (outside the tree), `M[name]()` (not a name at all).
--- `opts.calls_heuristic` adds one guessed shape back — an unresolved bare
--- name matching exactly one function anywhere in the tree — and marks those
--- edges `confidence = "heuristic"` so the renderer can draw them as the
--- weaker claim they are. It is off by default, because a call graph that
--- confidently draws a wrong edge is worse than one that draws fewer.
---
--- Genuinely invisible to this: dynamic dispatch. `lib.nvim.require`'s lazy and
--- metatable strategies produce calls that appear nowhere in the source, and
--- callbacks handed to `vim.schedule` or stored in tables are calls whose
--- target is a value, not a name. Doxygen has the same blind spot in C++ for
--- the same reason. This is why no call-derived check is ever `error` severity.

local M = {}

-- `name:` covers identifier, dot_index_expression and method_index_expression
-- in one capture; splitting them into three patterns would only move the
-- discrimination from `resolve_callee` (where it is one string match) into the
-- query (where it is three near-identical clauses).
local CALL_QUERY = vim.treesitter.query.parse("lua", "(function_call name: (_) @callee) @call")

---Extract every call site from an already-parsed tree.
---
---`defs` comes from `docmap.functions`, which found the same file's top-level
---function definitions moments earlier; the row ranges are what attribute a
---call to a caller. A call outside any top-level function (module-level
---initialisation) gets `from_fn = nil` and is dropped by `build` — the
---interesting module-level call is `require`, and `docmap.deps` already
---models that as its own edge kind.
---@param root TSNode Root of the parsed Lua tree.
---@param src string Source text the tree was parsed from.
---@param defs { name: string, srow: integer, erow: integer }[] Top-level function ranges, 0-based rows.
---@return Documentation.RawCall[]
function M.extract(root, src, defs)
  local out = {}

  for id, node in CALL_QUERY:iter_captures(root, src) do
    if CALL_QUERY.captures[id] == "callee" then
      local srow = node:range()
      local callee = vim.treesitter.get_node_text(node, src)

      -- Multi-line callee expressions would carry a newline into the text and
      -- never match any name pattern; skipping them here keeps `resolve_callee`
      -- free of whitespace handling.
      if not callee:find("\n") then
        local from_fn
        for _, def in ipairs(defs) do
          -- Innermost wins: definitions are scanned top-level only, so ranges
          -- never nest, and the first containing one is the only one.
          if srow >= def.srow and srow <= def.erow then
            from_fn = def.name
            break
          end
        end
        out[#out + 1] = { callee = callee, from_fn = from_fn, line = srow + 1 }
      end
    end
  end

  return out
end

local IDENT_QUERY = vim.treesitter.query.parse("lua", "(identifier) @id")

---How often each identifier appears in the file, by name.
---
---Exists for one question the call graph cannot answer: a function passed as
---a *value* — `vim.system(cmd, on_exit)`, `table.sort(t, by_line)` — is used,
---but there is no call site naming it, so `extract` above sees nothing. A
---dead-code report built on call edges alone would flag every callback in the
---tree, which is precisely the kind of confident wrong answer that gets a
---check switched off.
---
---Counting occurrences is deliberately coarser than resolving them: a
---file-local `read` and an unrelated `x.read` both count, so the number can
---be too *high*. That errs toward calling something used, which is the safe
---direction for this question.
---@param root TSNode
---@param src string
---@return table<string, integer>
function M.identifier_counts(root, src)
  local counts = {}
  for id, node in IDENT_QUERY:iter_captures(root, src) do
    if IDENT_QUERY.captures[id] == "id" then
      local text = vim.treesitter.get_node_text(node, src)
      counts[text] = (counts[text] or 0) + 1
    end
  end
  return counts
end

---Last dot-separated segment of a declared function name: `M.scan_full` →
---`scan_full`. What a caller writing `docmap.scan_full(...)` actually names,
---since the callee's own `M` is a file-local convention the call site cannot
---see.
---@param name string
---@return string
local function bare(name)
  return name:match("([%w_]+)$") or name
end

---Build the lookup tables `resolve` needs for one node: its own functions by
---declared and bare name, and the prefixes its functions are declared on
---(`M` in `function M.foo()`), which is how a same-file `M.foo()` call is
---told apart from a call through a require alias that happens to be named M.
---@param node Documentation.Node
---@return table<string, string> by_name
---@return table<string, boolean> self_prefixes
local function index_functions(node)
  local by_name, prefixes = {}, {}
  for _, fn in ipairs(node.functions) do
    by_name[fn.name] = fn.name
    -- Declared name wins over bare name on collision: `M.read` and a
    -- file-local `read` in the same file are two functions, and the qualified
    -- call site is the unambiguous one.
    if by_name[bare(fn.name)] == nil then
      by_name[bare(fn.name)] = fn.name
    end
    local prefix = fn.name:match("^([%w_]+)%.")
    if prefix then
      prefixes[prefix] = true
    end
  end
  return by_name, prefixes
end

---Last dot-separated segment stays in `member` whole, deliberately: the
---roadmap example this exists for (`plenary.job.new`) is itself two dotted
---segments past the module, and splitting further would just have to be
---rejoined by every renderer that wants to show "what was actually called".
---@param acc table<string, table<string, integer>> Per-node accumulator, `acc[module][member or ""]`.
---@param module string
---@param member string?
local function record_external_call(acc, module, member)
  local by_member = acc[module]
  if not by_member then
    by_member = {}
    acc[module] = by_member
  end
  local key = member or ""
  by_member[key] = (by_member[key] or 0) + 1
end

---Which languages resolve an unqualified call in *package* scope.
---
---Asked of the registry rather than listed here, so a twenty-fourth backend
---that needs it is one field on that backend and nothing in this file. Cached
---per call to `build`, because the answer cannot change inside one scan and
---the lookup would otherwise run per node.
---@return table<string, boolean>
local function package_scoped_languages()
  local out = {}
  local registry = require("documentation.core.lang_registry")
  for _, entry in ipairs(registry.report()) do
    local backend = registry.get(entry.name)
    if backend and backend.call_scope == "package" then
      out[entry.name] = true
    end
  end
  return out
end

---For every node whose language resolves calls in package scope, the names
---its *siblings* declare — the other nodes under the same parent namespace.
---
---**Why this exists at all.** A Go package is a directory, and every `.go`
---file in it shares one scope: `double(n)` written in `widget.go` may name a
---function declared in `helper.go` next to it, with nothing at the call site
---qualifying it. Go declares no `module_file`, so those two files are two IR
---nodes — which means a file-scoped resolver misses the *majority* of a Go
---call graph rather than a margin of it. Measured on a three-file fixture
---before this was written: two of three call sites were exactly that shape.
---
---**Siblings, not descendants.** A directory below is a different package in
---Go and a different scope, so including it would invent edges the language
---does not allow. The parent namespace is exactly the package.
---
---**A name two siblings both declare is dropped, not arbitrated.** Real Go
---would not compile, so the case means the directory is not one package —
---`foo` beside `foo_test`, or a build-tagged variant — and there is no
---honest way to pick. Dropping matches what this module already does with
---every other ambiguity: fewer edges beats a confident wrong one.
---
---Only the *bare* name is indexed. A Go method is stored as `Widget.Go` and
---is never called that way — `w.Go(...)` names a variable, which nothing
---here can resolve without a receiver-type model — so indexing the
---qualified form would add a key no call site can produce.
---@param ir Documentation.IR
---@return table<string, table<string, { node: string, fn: string }>> by parent id
local function package_index(ir)
  local scoped = package_scoped_languages()
  if not next(scoped) then
    return {}
  end

  local out = {}
  local ambiguous = {}
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.language and scoped[node.language] and node.parent then
      local bucket = out[node.parent]
      if not bucket then
        bucket = {}
        out[node.parent] = bucket
        ambiguous[node.parent] = {}
      end
      for _, fn in ipairs(node.functions) do
        local b = bare(fn.name)
        if bucket[b] and bucket[b].node ~= id then
          ambiguous[node.parent][b] = true
        else
          bucket[b] = { node = id, fn = fn.name }
        end
      end
    end
  end

  for parent, names in pairs(ambiguous) do
    for name in pairs(names) do
      out[parent][name] = nil
    end
  end
  return out
end

---Resolve every node's `calls_raw` into `kind="call"` edges appended to
---`ir.edges`. Mutates `ir` in place; `deps.build` must have run first, since
---resolution reads the require aliases it collected.
---
---Also stamps `node.calls_external` — counted the same pass, over the same
---`aliases`/`inline_mod` shapes an internal call resolves through, just for
---the case `by_module` has no entry: not a second traversal, because an
---external call is exactly an internal one that failed the one lookup that
---makes it internal. See `core/deps.lua`'s own header for why the module
---string itself (not a node) is what represents "outside this map" — this
---is the same call, made about calls instead of requires.
---@param ir Documentation.IR
---@param opts Documentation.Opts?
---@return Documentation.Edge[] added
function M.build(ir, opts)
  opts = opts or {}
  local by_module = require("documentation.core.deps").module_index(ir)
  local by_path = require("documentation.core.deps").path_index(ir)
  ir.edges = ir.edges or {}

  -- Empty for a tree with no package-scoped language in it, which is every
  -- Lua and JavaScript repository — so this costs one `next()` there.
  local packages = package_index(ir)

  local index = {} ---@type table<string, { by_name: table<string, string>, prefixes: table<string, boolean> }>
  for _, id in ipairs(ir.order) do
    local by_name, prefixes = index_functions(ir.nodes[id])
    index[id] = { by_name = by_name, prefixes = prefixes }
  end

  -- Only built when the heuristic is on: a bare name is a usable hint exactly
  -- when the whole tree declares it once. Names owned by two modules are
  -- ambiguous, and an ambiguous guess is the failure mode this whole flag is
  -- opt-in to avoid, so a second declaration removes the entry rather than
  -- picking a winner.
  local unique_bare = {}
  if opts.calls_heuristic then
    local count = {}
    for _, id in ipairs(ir.order) do
      for _, fn in ipairs(ir.nodes[id].functions) do
        local b = bare(fn.name)
        count[b] = (count[b] or 0) + 1
        unique_bare[b] = { node = id, fn = fn.name }
      end
    end
    for b, n in pairs(count) do
      if n > 1 then
        unique_bare[b] = nil
      end
    end
  end

  local edges = {}
  local seen = {}

  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]

    local aliases = {}
    -- Bare names a named import bound into this file's scope, and the member
    -- each refers to. The shape `calls.lua` had no branch for: JS binds an
    -- imported function directly, so `helper()` looks exactly like a call to
    -- a file-local function and resolves to nothing without this.
    local imports = {}
    -- Every alias whose module `by_module` cannot place in this tree — the
    -- exact negative of `aliases` above, built from the same
    -- `node.requires_raw` pass. `deps.build` already decided these modules
    -- are external (they are what fills `node.requires_external`); this is
    -- the same decision, read again here because `deps.lua` keeps only the
    -- module string and throws the alias away once it has.
    local external_aliases = {}
    for _, req in ipairs(node.requires_raw or {}) do
      -- Same two-step resolution `deps.build` uses, and it must be the same
      -- or the call graph would disagree with the require graph about which
      -- module a specifier names.
      local target = by_module[req.module]
        or require("documentation.core.deps").resolve_relative(by_path, node.path, req.module)

      if req.alias then
        if target then
          aliases[req.alias] = { node = target, member = req.member }
        else
          external_aliases[req.alias] = req.module
        end
      end

      for localname, exported in pairs(req.names or {}) do
        if target then
          imports[localname] = { node = target, member = exported }
        else
          -- An import from outside the tree still says which member is
          -- used, which is finer than the bare "this module is required"
          -- `requires_external` records.
          imports[localname] = { external = req.module, member = exported }
        end
      end
    end

    ---@type table<string, table<string, integer>>
    local calls_external_acc = {}

    for _, call in ipairs(node.calls_raw or {}) do
      if call.from_fn then
        local to_id, to_fn, confidence

        -- `require("mod").fn(...)` — an inline require rather than a binding.
        -- Checked first because the callee text starts with the identifier
        -- `require`, which the alias branch below would otherwise try to look
        -- up as a local name. This shape is everywhere in this tree (it is how
        -- a lazy dependency is called without a top-level binding), and it is
        -- exact: the module path is right there in the source.
        local inline_mod, inline_fn =
          call.callee:match("^require%s*%(?%s*['\"]([%w%._%-]+)['\"]%s*%)?%s*%.([%w_%.]+)$")

        local head, rest = call.callee:match("^([%w_]+)%.([%w_%.]+)$")
        if inline_mod and by_module[inline_mod] then
          local target = by_module[inline_mod]
          to_fn = index[target].by_name[inline_fn] or index[target].by_name[bare(inline_fn)]
          to_id = to_fn and target or nil
          confidence = "exact"
        elseif inline_mod then
          record_external_call(calls_external_acc, inline_mod, inline_fn)
        elseif head and aliases[head] then
          local target = aliases[head].node
          to_fn = index[target].by_name[rest] or index[target].by_name[bare(rest)]
          to_id = to_fn and target or nil
          confidence = "exact"
        elseif head and external_aliases[head] then
          record_external_call(calls_external_acc, external_aliases[head], rest)
        elseif head and index[id].prefixes[head] then
          to_fn = index[id].by_name[call.callee] or index[id].by_name[bare(rest)]
          to_id = to_fn and id or nil
          confidence = "exact"
        elseif call.callee:match("^[%w_]+$") then
          -- A bare name is a file-local function first, then a named import,
          -- and only then the heuristic. That order is the point: a file that
          -- declares its own `helper` and also imports one means its own, and
          -- an import is an exact fact where the heuristic is a guess.
          to_fn = index[id].by_name[call.callee]
          local imported = imports[call.callee]
          -- Package scope sits between "this file" and "an import", and the
          -- order is the point. This file's own declaration still wins — a
          -- name declared here shadows nothing but is the nearer answer — and
          -- package scope is an *exact* fact where the heuristic below is a
          -- guess, so it must come before it. See `package_index`.
          local sibling = node.parent
            and packages[node.parent]
            and packages[node.parent][call.callee]
          if to_fn then
            to_id, confidence = id, "exact"
          elseif sibling then
            to_id, to_fn, confidence = sibling.node, sibling.fn, "exact"
          elseif imported and imported.node then
            local target = imported.node
            to_fn = index[target].by_name[imported.member]
              or index[target].by_name[bare(imported.member)]
            to_id = to_fn and target or nil
            confidence = "exact"
          elseif imported and imported.external then
            record_external_call(calls_external_acc, imported.external, imported.member)
          elseif unique_bare[call.callee] then
            to_id = unique_bare[call.callee].node
            to_fn = unique_bare[call.callee].fn
            confidence = "heuristic"
          end
        end

        -- Direct recursion is real but tells the reader nothing a self-loop
        -- on a diagram would not obscure.
        if to_id and to_fn and not (to_id == id and to_fn == call.from_fn) then
          local key = id .. "|" .. call.from_fn .. "|" .. to_id .. "|" .. to_fn
          if not seen[key] then
            seen[key] = true
            edges[#edges + 1] = {
              kind = "call",
              from = id,
              to = to_id,
              from_fn = call.from_fn,
              to_fn = to_fn,
              line = call.line,
              confidence = confidence,
            }
          end
        end
      end
    end

    -- Flattened and sorted here, once per node, rather than left as the
    -- nested accumulator table `record_external_call` built — a stable
    -- array is what every consumer (the Deps-view external box, `to_json`'s
    -- hand-picked node fields) actually wants, and table iteration order in
    -- Lua is unspecified, which `--check`'s byte-compare cannot tolerate.
    ---@type Documentation.ExternalCall[]
    local calls_external = {}
    for module, by_member in pairs(calls_external_acc) do
      for member, count in pairs(by_member) do
        calls_external[#calls_external + 1] =
          { module = module, member = member ~= "" and member or nil, count = count }
      end
    end
    table.sort(calls_external, function(a, b)
      if a.module ~= b.module then
        return a.module < b.module
      end
      return (a.member or "") < (b.member or "")
    end)
    node.calls_external = calls_external
  end

  -- Same reasoning as `deps.build`: each producer sorts its own block and
  -- appends, so `ir.edges` stays byte-deterministic without one comparator
  -- that has to understand every kind's optional fields.
  table.sort(edges, function(a, b)
    if a.from ~= b.from then
      return a.from < b.from
    end
    if a.from_fn ~= b.from_fn then
      return a.from_fn < b.from_fn
    end
    if a.to ~= b.to then
      return a.to < b.to
    end
    return a.to_fn < b.to_fn
  end)

  for _, e in ipairs(edges) do
    ir.edges[#ir.edges + 1] = e
  end

  return edges
end

return M
