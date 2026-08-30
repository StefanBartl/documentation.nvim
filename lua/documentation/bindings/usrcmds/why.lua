---@module 'documentation.bindings.usrcmds.why'
--- `:DocMap why <a> <b>` — how does A end up connected to B?
---
--- The question the Deps view can only be walked by hand to answer. The chains
--- go to the quickfix list rather than to a message, because every hop *is* a
--- location: the edge carries the line the `require` or the call is written on,
--- so each entry jumps straight to the line that creates that link. A message
--- would have been something to read; this is something to act on.
---
--- ## Two chains, because there are two questions
---
--- **Loads** walks `require` edges: *what pulls what in*. **Calls** walks
--- `call` edges: *what actually invokes what*, function by function. Those are
--- different chains between the same two modules, and the second is usually the
--- one a reader means when they ask why A and B are connected — but until the
--- call traversal existed, the question was silently answered with the other
--- one's answer, and nothing said so.
---
--- Both are reported, and the interesting cases are the ones where they
--- disagree:
---
---   * **Loads but never calls.** A pulls B in and nothing along the way
---     invokes it. A dead dependency, and it looks exactly like a live one in
---     the require graph alone.
---   * **Calls without a require path.** The static dependency graph
---     understates the connection — a deferred or dynamically-built require
---     that `deps` could not follow.
---
--- The call chain is function-precise (`core.check#run → core.docs#corpus`)
--- because the edges are; the require chain is module-to-module because that is
--- all a `require` says.

local list = require("lib.nvim.ui.list")

local M = {}

---@param ctx Documentation.Bindings.Ctx
---@param arg string Everything after "why" — "<from> <to>".
function M.run(ctx, arg)
  local a, b = vim.trim(arg or ""):match("^(%S+)%s+(%S+)$")
  if not a then
    ctx.notify.warn("Usage: :" .. ctx.command_name .. " why <from> <to>")
    return
  end

  local ir = ctx.handle.ir()
  local lua_root = ctx.cfg.lua_root or "lua"
  local from_id = ctx.find_node(ir, a, lua_root)
  local to_id = ctx.find_node(ir, b, lua_root)
  if not from_id or not to_id then
    ctx.notify.warn(("No module matching '%s' in the map."):format(from_id and b or a))
    return
  end

  local calls = require("documentation.core.calls")
  local chain = require("documentation.core.deps").path(ir, from_id, to_id)
  local call_chain = calls.path(ir, from_id, to_id)

  if chain and #chain == 0 then
    ctx.notify.info("Those are the same module.")
    return
  end
  if not chain and not call_chain then
    -- Both traversals failed, so this really is "not connected" rather than
    -- "connected in the way the other chain describes".
    ctx.notify.info(("%s does not reach %s at all — neither loads nor calls."):format(a, b))
    return
  end

  local items = {}
  local names = { ir.nodes[from_id].module or from_id }
  local lazy = false

  for _, e in ipairs(chain or {}) do
    local target = ir.nodes[e.to]
    names[#names + 1] = (target.module or e.to) .. (e.deferred and " (lazy)" or "")
    lazy = lazy or e.deferred == true
    items[#items + 1] = {
      filename = ctx.cfg.root .. "/" .. ((ir.nodes[e.from] or {}).source or e.from),
      lnum = e.line or 1,
      col = 1,
      text = ("loads:  %s → %s%s"):format(
        (ir.nodes[e.from] or {}).module or e.from,
        target.module or e.to,
        e.deferred and "  (lazy)" or ""
      ),
    }
  end

  ---@param id string
  ---@param fn string|nil
  ---@return string
  local function fn_label(id, fn)
    return ("%s#%s"):format((ir.nodes[id] or {}).module or id, fn or "?")
  end

  local call_names = {}
  for i, e in ipairs(call_chain or {}) do
    if i == 1 then
      call_names[1] = fn_label(e.from, e.from_fn)
    end
    call_names[#call_names + 1] = fn_label(e.to, e.to_fn)
    items[#items + 1] = {
      filename = ctx.cfg.root .. "/" .. ((ir.nodes[e.from] or {}).source or e.from),
      lnum = e.line or 1,
      col = 1,
      -- `~` for a heuristic hop, the same mark the Calls view already uses for
      -- the same fact, so one reader learns it once.
      text = ("calls:%s  %s → %s"):format(
        e.confidence == "heuristic" and " ~" or "  ",
        fn_label(e.from, e.from_fn),
        fn_label(e.to, e.to_fn)
      ),
    }
  end

  list.qf(items, ("docmap why: %s → %s"):format(a, b), { open = false })

  ---@type string[]
  local lines = {}
  if chain then
    lines[#lines + 1] = ("loads · %d hop%s%s:  %s"):format(
      #chain,
      #chain == 1 and "" or "s",
      -- A path that only exists through a deferred require does not run at load
      -- time, which is usually the difference between "has to go" and "is
      -- fine" — so it is said up front, not buried in the list.
      lazy and ", lazy somewhere" or ", all at load time",
      table.concat(names, " → ")
    )
  else
    -- Said out loud rather than left as an absent line: a call path with no
    -- require path means the static graph understates the connection, which is
    -- a finding about `deps`, not about these two modules.
    lines[#lines + 1] = "loads · no require path — the call below is reached some other way"
  end

  if call_chain and #call_chain > 0 then
    lines[#lines + 1] = ("calls · %d hop%s%s:  %s"):format(
      #call_chain,
      #call_chain == 1 and "" or "s",
      calls.chain_confidence(call_chain) == "heuristic" and ", one hop heuristic or more" or "",
      table.concat(call_names, " → ")
    )
  else
    -- The other asymmetry, and the more useful one: A pulls B in and nothing
    -- along the way invokes it. In the require graph alone that looks exactly
    -- like a live dependency.
    lines[#lines + 1] = "calls · nothing resolvable calls into it — loaded, not used"
  end

  ctx.notify.info(table.concat(lines, "\n"))
  vim.cmd("copen")
end

return M
