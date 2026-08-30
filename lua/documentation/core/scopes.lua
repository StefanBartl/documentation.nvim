---@module 'documentation.core.scopes'
--- Owning scopes: which class, `impl` block, trait, receiver type or inline
--- module a function belongs to, and the grouping that follows from it.
---
--- ## Why the IR needed a field and not a better string
---
--- Every backend that has an owner already knew it — Python's
--- `record_function(node, owner)`, Rust's `impl` walk, Go's receiver type —
--- and every one of them spent it on the display name: `Class.method`,
--- `Widget::new`, `Doer::go`. That is the right name, and it was never the
--- whole fact. A dotted name cannot be read backwards:
---
---   * `Class.helper` written at module scope and `helper` written inside
---     `class Class` produce the identical `name`. "Which methods does this
---     class have" answered by string-prefix match gets the first one wrong,
---     and gets it wrong silently.
---   * Lua's own `function M.foo()` is dotted for a reason that has nothing
---     to do with ownership — `M` is the module table. A prefix match over a
---     mixed tree groups by punctuation, not by structure.
---   * Ruby writes `Class#method` for instance methods and `Class.method`
---     for singleton ones, PHP and Rust write `::`. A consumer matching
---     prefixes has to know all four separators to ask one question.
---
--- So `Documentation.FunctionInfo` carries `owner` and `owner_kind`, set at
--- the one place the parse tree still exists, and this module is the single
--- reader that turns them into groups.
---
--- ## Derived, never serialised
---
--- `Documentation.ScopeInfo` is not an IR field and does not appear in
--- `module_map.json`. It is exactly the grouping of data the artifact
--- already carries, and `duplicates` — the one derived table that *is*
--- serialised — states its own reason for being the exception: the page has
--- no parse tree to recompute `fn.shape` with. It has `fn.owner` right
--- there, and does this same grouping in JavaScript. A second copy would
--- only be one more thing that can disagree with itself.
---
--- ## What a scope is not
---
--- A scope is not a node. It has no summary, no coverage, no edges and no
--- id — a Rust `mod x { … }` grouped here is still read as part of its file,
--- which is the honest state of the "one file, many modules" question. What
--- this closes is attribution: the members are attributed to the thing that
--- owns them instead of lying side by side with their neighbours.

local M = {}

---Group functions by their owning scope, in first-appearance order.
---
---Free functions — everything with no `owner` — are not represented: they
---belong to the module, which is the node itself and already has a place to
---be listed. A caller rendering both sections wants `M.split`.
---
---@param fns Documentation.FunctionInfo[]?
---@return Documentation.ScopeInfo[] scopes In the order their first member appears in `fns`, which is source order for every backend.
function M.group(fns)
  ---@type Documentation.ScopeInfo[]
  local scopes = {}
  local by_name = {}

  for _, fn in ipairs(fns or {}) do
    -- Both or neither: a backend that sets one without the other has a bug,
    -- and treating a half-set pair as an owner would invent a scope of kind
    -- `nil` that no consumer can render.
    if fn.owner and fn.owner_kind then
      local scope = by_name[fn.owner]
      if not scope then
        scope = { name = fn.owner, kind = fn.owner_kind, functions = {} }
        by_name[fn.owner] = scope
        scopes[#scopes + 1] = scope
      end
      scope.functions[#scope.functions + 1] = fn
    end
  end

  return scopes
end

---The same split a module view needs: what the module itself declares, and
---what its scopes own.
---
---@param fns Documentation.FunctionInfo[]?
---@return Documentation.FunctionInfo[] free Functions with no owner, in source order.
---@return Documentation.ScopeInfo[] scopes As `M.group`.
function M.split(fns)
  local free = {}
  for _, fn in ipairs(fns or {}) do
    if not (fn.owner and fn.owner_kind) then
      free[#free + 1] = fn
    end
  end
  return free, M.group(fns)
end

---Every scope in the tree, node by node.
---
---@param ir Documentation.IR
---@return { node: Documentation.Node, scope: Documentation.ScopeInfo }[] entries Node order, then scope order within a node.
function M.all(ir)
  local out = {}
  for _, id in ipairs(ir.order or {}) do
    local node = ir.nodes[id]
    if node then
      for _, scope in ipairs(M.group(node.functions)) do
        out[#out + 1] = { node = node, scope = scope }
      end
    end
  end
  return out
end

---One line for a report: "3 scopes owning 12 of 15 functions".
---
---Says nothing at all for a tree whose languages have no owning construct —
---a Lua repository would otherwise carry a permanent "0 scopes" line that
---is true, useless, and reads like something is missing.
---
---@param ir Documentation.IR
---@return string? line `nil` when the tree has no owning scope anywhere.
function M.summary(ir)
  local scopes, owned, total = 0, 0, 0
  for _, id in ipairs(ir.order or {}) do
    local node = ir.nodes[id]
    if node then
      total = total + #(node.functions or {})
      for _, scope in ipairs(M.group(node.functions)) do
        scopes = scopes + 1
        owned = owned + #scope.functions
      end
    end
  end
  if scopes == 0 then
    return nil
  end
  return ("%d scope%s owning %d of %d functions"):format(
    scopes,
    scopes == 1 and "" or "s",
    owned,
    total
  )
end

return M
