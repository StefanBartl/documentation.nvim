---@module 'documentation.core.docs'
--- The documentation corpus: which prose file mentions which module or
--- function, and which mentions no longer resolve to anything.
---
--- Everything else in this plugin reads *source* — annotations in comments,
--- next to the code they describe. This reads the other half: the `.md` files
--- that describe the same tree from the outside. Until this existed, a
--- documentation file was known to the map as a path (`node.readme`) and a
--- counter (`stats.files_md`); nothing had ever opened one.
---
--- ## What counts as a mention
---
--- **Inline code spans only** — `` `documentation.core.scan` ``. Not prose
--- words, not fenced code blocks. Both exclusions are load-bearing:
---
--- - A fenced block is a *code sample*. Every identifier in it would match
---   something, and a reference index where `local`, `opts` and `return` are
---   "mentions" is noise wearing data's clothes.
--- - A bare prose word that happens to share a name with a function
---   (`write`, `check`, `run`, `open` — all real functions in this tree) is
---   the same problem one step quieter. Backticks are the author *marking*
---   the word as an identifier, which is the only signal available here that
---   does not require understanding English.
---
--- ## What a mention resolves to, and the confidence it carries
---
--- The same discipline `calls.lua` applies to a callee and
--- `lib.nvim.telemetry` applies to a wrapped key, for the same reason — a
--- confident wrong answer is worse than a missing one:
---
---   `documentation.core.scan`          module path        -> exact
---   `documentation.core.scan.scan_full` qualified function -> exact
---   `M.scan_full`                       declared name      -> exact
---   `scan_full`                         bare, unique in tree -> heuristic
---   `write`                             bare, several owners -> NO MATCH
---   `anything else`                                          -> NO MATCH
---
--- A bare name owned by more than one module resolves to nothing at all
--- rather than to a guess, and is not reported as ambiguous either — the
--- author of a doc writing `` `read` `` was not necessarily naming a
--- function in this tree, and treating that as a reference this index simply
--- failed to place would overstate what is known.
---
--- ## The one drift this can see
---
--- `doc-references-missing`. A code span whose **longest dotted prefix is a
--- real module** but whose remainder names nothing in it — `` `documentation.
--- core.scan.parse_headr` `` — was unambiguously meant to name something
--- here, and does not. That is a documentation file describing a function
--- that has been renamed or removed: dead code's mirror image, in prose.
---
--- Deliberately narrow. A dotted name with *no* known module prefix
--- (`vim.fn.expand`, `some.config.value`, a filename) is not flagged: it
--- could be anything, and a check that fires on every third-party API name
--- in a document is a check that gets switched off. A plugin repository name
--- (`something.nvim`), a bare filename (`something.lua`), the ".init"
--- spelling of a module (`something.init`, same file `require("something")`
--- loads), a glob over a namespace (`something.*`) and the left-hand side of
--- a documented rename are excluded for the same reason — each was a real
--- false positive on a real repository's own documents before it was
--- excluded, not a hypothetical one.
---
--- ## The limit that has no fix
---
--- A document *quoting* a dead reference to explain it reads exactly like a
--- document *making* one. Markdown has no marker for "this identifier is the
--- subject of the sentence, not a pointer", and inventing one (a magic
--- comment, an ignore directive) would be asking every reader to learn a
--- convention so that a checker can stay quiet. This is known to bite
--- release notes and migration guides; the honest workaround is to write
--- about a removed name without putting it in backticks. Found the moment
--- this shipped: `docs/ROADMAP/FEATURES.md`'s own entry for this feature
--- tripped it, quoting the very reference the check had just caught.

local M = {}

local collect_recursive = require("lib.nvim.fs.collect_recursive")

--- Longest stored context around a mention. Bounded because this ships in a
--- byte-deterministic artifact that is already 750 KB — see
--- `docs/ECOSYSTEM.md` on why file contents are not embedded wholesale.
local CONTEXT_MAX = 120

--- References kept per entity before the rest become a count. A function
--- mentioned 200 times in one changelog does not need 200 rows to make its
--- point, and the artifact should not carry them.
local REFS_PER_ENTITY = 20

---Strip a leading `M.`-style table prefix: `M.scan_full` -> `scan_full`.
---
---This tree's universal convention is `local M = {}`, so a leading
---capitalized identifier plus a dot is the table, not part of the function's
---own name. Identical to the transformation `check_see_targets` has always
---applied — shared here so the two cannot drift apart.
---@param name string
---@return string
function M.bare_name(name)
  return (name:gsub("^%u[%w_]*%.", ""))
end

---Resolve a relative markdown link against the directory of the file that
---wrote it, returning a repo-relative path.
---
---**Two callers, one answer, and the second one is why this moved here.**
---`check.lua`'s `dead-readme-link` has resolved links this way since it
---shipped; `render/markdown.lua` needs the identical resolution to *rebase*
---a link that travels out of its own directory. Two copies of a path walk
---would be exactly the drift this plugin exists to report.
---
---Lives in `docs.lua` rather than staying in `check.lua` because it is
---knowledge about markdown links, which is what this module already owns
---(`corpus`, `code_spans`) — not knowledge about checking.
---@param base_dir string Repo-relative directory of the linking file, no trailing slash.
---@param target string The link target as written.
---@return string
function M.resolve_link(base_dir, target)
  local joined = base_dir .. "/" .. target
  local parts, stack = {}, {}
  for seg in joined:gmatch("[^/]+") do
    parts[#parts + 1] = seg
  end
  for _, seg in ipairs(parts) do
    if seg == ".." then
      table.remove(stack)
    elseif seg ~= "." then
      stack[#stack + 1] = seg
    end
  end
  return table.concat(stack, "/")
end

---Build the name -> entity index this module resolves against.
---
---One index, three callers' worth of questions: "is this a known name"
---(`check_see_targets`), "what does this name refer to" (doc references),
---and "does this module own a function called X" (`doc-references-missing`).
---Built once from the IR rather than once per caller — the alternative is
---several near-identical loops that answer the same question slightly
---differently, which is the drift this plugin exists to find.
---@param ir Documentation.IR
---@return Documentation.Docs.Index
function M.build_index(ir)
  ---@type Documentation.Docs.Index
  local idx = { exact = {}, bare = {}, modules = {}, fns_by_module = {} }
  local bare_count = {}

  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]

    if node.module then
      idx.exact[node.module] = { kind = "module", node = id }
      idx.modules[node.module] = id
      idx.fns_by_module[node.module] = {}
    end

    for _, fn in ipairs(node.functions or {}) do
      local bare = M.bare_name(fn.name)
      -- The declared name as written, e.g. "M.scan_full".
      idx.exact[fn.name] = { kind = "function", node = id, fn = fn.name }
      if node.module then
        -- The qualified form a reader would actually write.
        idx.exact[node.module .. "." .. bare] = { kind = "function", node = id, fn = fn.name }
        idx.fns_by_module[node.module][bare] = fn.name
      end
      bare_count[bare] = (bare_count[bare] or 0) + 1
      idx.bare[bare] = { kind = "function", node = id, fn = fn.name }
    end
  end

  -- Every dotted prefix of a known module is itself a real part of this tree
  -- — `documentation.editor` is a directory that owns `documentation.editor.
  -- serve`, even though it has no `init.lua` and therefore no `@module` tag
  -- of its own to be indexed by. Registering the prefixes is what keeps
  -- `doc-references-missing` from reporting a namespace as a missing member
  -- of its own parent.
  --
  -- Two properties this loop has to have, both learned the hard way:
  --
  -- 1. **Deterministic.** An earlier version iterated `pairs(idx.modules)`,
  --    so `documentation.core` resolved to whichever module under it the
  --    hash order happened to yield first — a *different one per run*. The
  --    artifact is byte-compared by `--check`, so that made the map
  --    permanently stale: regenerating produced a different file every time
  --    and the gate could never pass. `ir.order` is the deterministic walk
  --    order, and iterating it fixes the output.
  -- 2. **Pointing somewhere true.** Stripping one segment off a module name
  --    and climbing one `parent` link move together, so `documentation.core`
  --    resolves to the actual `lua/documentation/core` namespace node rather
  --    than to an arbitrary child of it. A prefix is a real place in this
  --    tree; the index should name that place.
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.module then
      local name = node.module
      local owner = node.parent
      while true do
        local shorter = name:match("^(.*)%.[^.]+$")
        if not shorter then
          break
        end
        name = shorter
        if not idx.exact[name] then
          idx.exact[name] = { kind = "module", node = owner or id }
        end
        owner = owner and ir.nodes[owner] and ir.nodes[owner].parent or nil
      end
    end
  end

  -- A bare name owned twice is owned by nobody, as far as this index is
  -- concerned. Removing the entry is the point: leaving one of the two would
  -- be picking a winner, which is exactly the guess this declines to make.
  for name, n in pairs(bare_count) do
    if n > 1 then
      idx.bare[name] = nil
    end
  end

  return idx
end

---Resolve one code-span mention.
---
---`heuristic` enables the bare-name path and is **off by default**, the same
---posture (and for the same reason) as `opts.calls_heuristic`. Measured on
---this repository before it was made opt-in: 74 of 194 resolved references
---came from bare names, and the names doing the matching were `write`,
---`open`, `scan`, `add` and `esc` — every one of them a *file-local* helper,
---and every one of them also an ordinary English word a document uses in
---backticks without naming a function at all. A reference index that
---confidently claims `` `open` `` in prose means
---`editor/browse#M.open` is worse than one that says nothing.
---@param idx Documentation.Docs.Index
---@param text string
---@param heuristic boolean? Allow bare, tree-unique names to resolve. Default false.
---@return Documentation.Docs.Target|nil
function M.resolve(idx, text, heuristic)
  local hit = idx.exact[text]
  -- A mention with no dot in it is not a *qualified* reference, even when it
  -- matches the index exactly — and it matches surprisingly often, because a
  -- file-local `local function git(...)` is indexed under the bare name
  -- `git`. Measured here: `git` collected 6 references from documents
  -- discussing the version-control tool. `esc`, `add` and `write` behave the
  -- same way. So an undotted mention takes the heuristic path regardless of
  -- which index it came from — the strictness belongs here rather than in
  -- the index, which `check_see_targets` needs complete.
  if hit and text:find(".", 1, true) then
    return { kind = hit.kind, node = hit.node, fn = hit.fn, confidence = "exact" }
  end
  -- An undotted mention is answered from `idx.bare` and never from
  -- `idx.exact`, even though the latter would often have an entry for it.
  -- `idx.exact` keys a file-local `local function write` under the bare name
  -- `write`, last writer winning, so two modules owning that name leaves one
  -- arbitrary survivor — exactly the ambiguity `idx.bare` was deduplicated
  -- to remove. Reading the deduplicated index here is what makes "owned by
  -- two modules" resolve to nothing rather than to a coin flip.
  if heuristic and text:match("^[%w_]+$") then
    local b = idx.bare[text]
    if b then
      return { kind = b.kind, node = b.node, fn = b.fn, confidence = "heuristic" }
    end
  end
  return nil
end

---Was this dotted mention unambiguously meant to name something in this
---tree, and fails to? Returns the owning module path plus the unresolved
---remainder, or nil.
---
---"Unambiguously meant" is the whole weight of this function: it requires
---the *longest dotted prefix* of the mention to be a real module in this
---map. `documentation.core.scan.gone` qualifies; `vim.fn.expand` does not,
---and neither does a bare word.
---@param idx Documentation.Docs.Index
---@param text string
---@return string|nil module_path
---@return string|nil missing
function M.missing_member(idx, text)
  if not text:find(".", 1, true) then
    return nil
  end
  if idx.exact[text] then
    return nil
  end
  -- `documentation.nvim`, `lib.nvim`, `mdview.nvim` — a Neovim *plugin* name,
  -- which is a repository, not a member access. Measured on this repository:
  -- before this exclusion, "module `documentation` has no member `nvim`" was
  -- the single largest source of findings, 10 of 25. The convention is as
  -- reliable as the `use*` hook convention `ecma.lua` already reads.
  if text:match("%.nvim$") then
    return nil
  end
  -- `chadrc.lua`, `options.lua` -- a bare *filename*, not a member access.
  -- The same shape as `.nvim$` above and found the same way: a config repo's
  -- own docs name a top-level file this way constantly (`` `chadrc.lua` ``,
  -- never `require("chadrc.lua")`), and every module whose name happens to
  -- also be a real file (`chadrc`, `options`, `machine`, `autocmds`, ...)
  -- turned every one of those mentions into a false "has no member 'lua'".
  -- Measured on a real config repo: 26 of 44 `doc-references-missing`
  -- findings, the single largest bucket, all of this exact shape.
  if text:match("%.lua$") then
    return nil
  end
  -- `bindings.mappings.init`, `config.neotree.init` -- naming a module's
  -- init.lua explicitly. `require("x.init")` and `require("x")` load the
  -- same file, so a doc pointing at the ".init" form is not naming a
  -- missing member, it is the ordinary alternative spelling of the module
  -- itself -- the same shape as `.nvim$`/`.lua$` above.
  if text:match("%.init$") then
    return nil
  end

  local best_mod, best_rest
  local pos = 0
  while true do
    local dot = text:find(".", pos + 1, true)
    if not dot then
      break
    end
    local prefix = text:sub(1, dot - 1)
    if idx.modules[prefix] then
      best_mod, best_rest = prefix, text:sub(dot + 1)
    end
    pos = dot
  end

  if not best_mod then
    return nil
  end
  -- A remainder that is itself dotted (`mod.a.b`) is a nested reference this
  -- map has no model for — not a missing member of `mod`, so not reported.
  -- It must also *look* like something that could have been a function:
  -- `documentation.*` in prose is a glob over the namespace, not a claim
  -- that `documentation` exports a member named `*`.
  if best_rest == "" or best_rest:find(".", 1, true) then
    return nil
  end
  if not best_rest:match("^[%a_][%w_]*$") then
    return nil
  end
  if (idx.fns_by_module[best_mod] or {})[best_rest] then
    return nil
  end
  return best_mod, best_rest
end

---Extract every inline code span from Markdown, with its line number.
---
---Fenced blocks are skipped wholesale (see this module's header). The fence
---test accepts ``` and ~~~ with any info string, and closes on the first
---fence of the same character — good enough for real documents and, more to
---the point, wrong only in the safe direction: an unclosed fence swallows
---the rest of the file rather than emitting a burst of code-sample matches.
---Is this mention the left-hand side of a documented rename?
---
---A ledger entry writes `` `old.name` → `new.name` `` — the old name is
---*supposed* to be gone, and reporting it as a stale reference reports the
---document for being correct. Measured on this repository, this was 2 of
---`doc-references-missing`'s 3 findings before the rule existed.
---
---Narrow on purpose, in two ways. The arrow must separate this mention from
---**another code span on the same line**, and that right-hand span must
---itself **resolve** — an arrow pointing at something this map does not
---know is not evidence of a rename, just an arrow. A document that renames
---a thing into something equally missing is therefore still reported, which
---is the correct answer.
---@param idx Documentation.Docs.Index
---@param line string The full source line the mention sits on.
---@param text string The mention.
---@param heuristic boolean?
---@return boolean
function M.is_rename_note(idx, line, text, heuristic)
  local esc_text = text:gsub("(%W)", "%%%1")
  for arrow in ("→ -> ⇒ =>"):gmatch("%S+") do
    local rhs =
      line:match("`" .. esc_text .. "`%s*" .. arrow:gsub("(%W)", "%%%1") .. "%s*`([^`]+)`")
    if rhs and M.resolve(idx, vim.trim(rhs), heuristic) then
      return true
    end
  end
  return false
end

---@param content string
---@return { text: string, line: integer, context: string }[]
function M.code_spans(content)
  local out = {}
  local fence = nil
  local lineno = 0

  for line in (content .. "\n"):gmatch("([^\n]*)\n") do
    lineno = lineno + 1
    local f = line:match("^%s*(```+)") or line:match("^%s*(~~~+)")
    if fence then
      if f and f:sub(1, 1) == fence:sub(1, 1) and #f >= #fence then
        fence = nil
      end
    elseif f then
      fence = f
    else
      -- Double-backtick spans first, so ``a `b` c`` is one span rather than
      -- two mismatched ones. The inner pattern is `.-` and not `[^`]+`
      -- precisely because carrying backticks is the entire reason CommonMark
      -- offers the doubled form — an inner-backtick-excluding class can
      -- never match the case this branch exists for.
      for span in line:gmatch("``(.-)``") do
        local t = vim.trim(span)
        if t ~= "" then
          out[#out + 1] = { text = t, line = lineno, context = line }
        end
      end
      local stripped = line:gsub("``.-``", "")
      for span in stripped:gmatch("`([^`]+)`") do
        local t = vim.trim(span)
        if t ~= "" then
          out[#out + 1] = { text = t, line = lineno, context = line }
        end
      end
    end
  end

  return out
end

---@param s string
---@return string
local function condense(s)
  local flat = s:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
  if #flat > CONTEXT_MAX then
    flat = flat:sub(1, CONTEXT_MAX - 1) .. "…"
  end
  return flat
end

---Every Markdown file in the tree, repo-relative and sorted.
---
---`out_dir` is excluded and that is not optional: the generated map contains
---an `overview.md` naming every module and function in the tree, so
---including it would make every entity "documented" by the very artifact
---this is trying to enrich. Dot-directories, `node_modules` and `.deps` are
---excluded as the ordinary noise they are.
---@param opts Documentation.Opts
---@return string[] repo-relative paths
function M.corpus(opts)
  local root = opts.root:gsub("\\", "/"):gsub("/+$", "")
  local out_dir = (opts.out_dir or "docs/map"):gsub("^/+", ""):gsub("/+$", "")
  local out_abs = root .. "/" .. out_dir

  local files = collect_recursive.files(root, {
    ignore = function(abs, is_dir)
      local p = abs:gsub("\\", "/")
      if is_dir then
        if p == out_abs then
          return true
        end
        local name = p:match("([^/]+)$") or ""
        return name:sub(1, 1) == "." or name == "node_modules"
      end
      return false
    end,
  })

  local rel = {}
  for _, abs in ipairs(files) do
    local p = abs:gsub("\\", "/")
    if p:lower():match("%.md$") and p:sub(1, #root + 1) == root .. "/" then
      rel[#rel + 1] = p:sub(#root + 2)
    end
  end
  table.sort(rel)
  return rel
end

---Scan the corpus, resolve every mention, and attach the result to `ir`.
---
---Mutates `ir` in place, like every other resolver in `scan_full`'s chain.
---Sets `ir.docs` unconditionally — an empty corpus is a real answer ("this
---tree has no prose documentation"), distinct from the field being absent.
---@param ir Documentation.IR
---@param opts Documentation.Opts
---@return Documentation.Docs.Result
function M.resolve_all(ir, opts)
  local root = opts.root:gsub("\\", "/"):gsub("/+$", "")
  local idx = M.build_index(ir)

  local files, refs, missing = {}, {}, {}
  local overflow = {}

  for _, rel in ipairs(M.corpus(opts)) do
    local fd = io.open(root .. "/" .. rel, "r")
    if fd then
      local content = fd:read("*a")
      fd:close()

      local title = content:match("^%s*#%s+([^\n]+)") or rel:match("([^/]+)$")
      local n_refs = 0

      for _, span in ipairs(M.code_spans(content)) do
        local target = M.resolve(idx, span.text, opts.docs_heuristic)
        if target then
          local key = target.kind == "module" and target.node or (target.node .. "#" .. target.fn)
          local list = refs[key]
          if not list then
            list = {}
            refs[key] = list
          end
          n_refs = n_refs + 1
          if #list < REFS_PER_ENTITY then
            list[#list + 1] = {
              doc = rel,
              line = span.line,
              text = span.text,
              context = condense(span.context),
              confidence = target.confidence,
            }
          else
            overflow[key] = (overflow[key] or 0) + 1
          end
        else
          local mod, miss = M.missing_member(idx, span.text)
          if mod and M.is_rename_note(idx, span.context, span.text, opts.docs_heuristic) then
            mod = nil
          end
          if mod then
            missing[#missing + 1] = {
              doc = rel,
              line = span.line,
              text = span.text,
              module = mod,
              -- The owning module's node, so a finding can be attributed to
              -- it without the caller rebuilding the index to look it up.
              node = idx.modules[mod],
              missing = miss,
            }
          end
        end
      end

      files[#files + 1] = { path = rel, title = vim.trim(title or rel), refs = n_refs }
    end
  end

  -- Deterministic in every direction: the artifact is byte-compared.
  for key, list in pairs(refs) do
    table.sort(list, function(a, b)
      if a.doc ~= b.doc then
        return a.doc < b.doc
      end
      return a.line < b.line
    end)
    if overflow[key] then
      list.more = overflow[key]
    end
  end
  table.sort(missing, function(a, b)
    if a.doc ~= b.doc then
      return a.doc < b.doc
    end
    if a.line ~= b.line then
      return a.line < b.line
    end
    return a.text < b.text
  end)

  ir.docs = { files = files, refs = refs, missing = missing }
  return ir.docs
end

return M
