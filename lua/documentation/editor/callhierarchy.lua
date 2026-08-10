---@module 'documentation.editor.callhierarchy'
--- A second, narrow LSP client — attached alongside LuaLS, never instead of
--- it — that answers exactly the one question LuaLS cannot: incoming and
--- outgoing calls for a function. Verified 2026-08-10 against LuaLS's own
--- source (`callHierarchy`/`incomingCalls`/`outgoingCalls`/
--- `prepareCallHierarchy` appear nowhere in it) and its own long-open,
--- unstaffed feature request (LuaLS/lua-language-server#2832, opened
--- August 2024) — this is not a workaround for a slow LuaLS feature, it is
--- filling a gap LuaLS has never claimed to cover.
---
--- The extension point is Neovim's own LSP client, not LuaLS: `cmd` on a
--- client config may be a Lua function returning a `vim.lsp.rpc.Client`-
--- shaped table instead of a shell command, which starts no external
--- process at all — everything below runs in-process, backed by
--- `Documentation.Handle.callers`/`callees`, no new scan of any kind.
--- `vim.lsp.buf.incoming_calls()`/`outgoing_calls()`/`hover()` already
--- query every attached client and merge the results (verified against
--- Neovim's own `lsp/buf.lua`), which is the whole reason this can sit
--- beside LuaLS instead of needing to replace it: LuaLS keeps completion,
--- diagnostics, its own hover and everything else; this client is asked
--- only the questions it chose to answer, `initialize`'s own
--- `capabilities` table said so, and nothing else in Neovim ever routes a
--- `textDocument/completion` here.
---
--- One real, sharp edge found empirically before writing this for real,
--- not assumed from documentation, since no worked example of the
--- in-process (no external process) shape of `cmd` turned up anywhere
--- searched: the client table's own methods (`request`/`notify`/
--- `is_closing`/`terminate`) are called *without* an implicit `self` —
--- `client.request(method, params, callback, ...)`, not
--- `client:request(...)` — confirmed by making the mistake first (a
--- `request = function(self, method, ...)` signature received `params` in
--- `method`, shifted by exactly one argument) and then a working probe
--- against a real headless Neovim session, request through to a real
--- `vim.lsp.buf_request_all` round-trip and back. Every handler below is
--- written the way that probe proved works, not the way a colon-call
--- would suggest.

local M = {}

---@type string
local CLIENT_NAME = "docmap-callhierarchy"

-- LSP's SymbolKind.Function — used as `CallHierarchyItem.kind`. Every
-- documented function in this tree is a plain function or method as far as
-- the LSP client cares; the IR's own richer distinctions (`M.foo` vs a
-- local, `@internal`, hooks) have no SymbolKind of their own to map onto,
-- and guessing one would be noise `range`/`detail` already carry better.
local SK_FUNCTION = 12

---Absolute path -> repo-relative, forward-slashed, matching the shape
---`Documentation.Node.source` is written in.
---@param root string Already normalized (forward slashes, no trailing slash).
---@param abs_path string
---@return string?
local function to_repo_relative(root, abs_path)
  local norm = (abs_path:gsub("\\", "/"))
  if norm:sub(1, #root + 1) ~= root .. "/" then
    return nil
  end
  return norm:sub(#root + 2)
end

---The node owning a given source file. `node.id` is the file's own path
---for a `"file"` node but the *directory's* for a `"module"` node — `id`
---and `source` are not interchangeable here, so this walks `source`, not a
---key lookup on `id`. Cheap enough to do per request: a few hundred nodes,
---never the hot path a scan is.
---@param ir Documentation.IR
---@param rel_path string
---@return Documentation.Node?
local function node_for_source(ir, rel_path)
  for _, node in pairs(ir.nodes) do
    if node.source == rel_path then
      return node
    end
  end
  return nil
end

---The function whose declared span contains `line1` (1-based, inclusive of
---both ends) — deliberately the *span* (`fn.line`..`fn.line_end`), not just
---an exact match on `fn.line`: the whole point of tracking `line_end` at
---all was so a cursor resting anywhere in a function's body, not only on
---its declaration line, resolves correctly.
---@param node Documentation.Node
---@param line1 integer
---@return Documentation.FunctionInfo?
local function fn_at_line(node, line1)
  for _, fn in ipairs(node.functions or {}) do
    if line1 >= fn.line and line1 <= fn.line_end then
      return fn
    end
  end
  return nil
end

---@param root string
---@param node Documentation.Node
---@param fn Documentation.FunctionInfo
---@return table CallHierarchyItem
local function make_item(root, node, fn)
  return {
    name = fn.name,
    kind = SK_FUNCTION,
    detail = fn.signature,
    uri = vim.uri_from_fname(root .. "/" .. node.source),
    -- Only line spans are tracked, not columns — both ranges below start
    -- and end at character 0/the line's own length rather than a real
    -- column, which is enough for "jump to this line" (what a call
    -- hierarchy picker actually does with it) without pretending to a
    -- precision the IR was never given.
    range = {
      start = { line = fn.line - 1, character = 0 },
      ["end"] = { line = fn.line_end - 1, character = 0 },
    },
    selectionRange = {
      start = { line = fn.line - 1, character = 0 },
      ["end"] = { line = fn.line - 1, character = #fn.signature },
    },
    -- The `<node id>#<name>` key every `handle.callers`/`callees` call and
    -- the HTML map's own Calls view already use — round-tripped back to
    -- this server unexamined by the client, which is exactly what LSP's
    -- opaque `data` field exists for, so `incomingCalls`/`outgoingCalls`
    -- never have to re-derive it from a range.
    data = { fn_key = node.id .. "#" .. fn.name },
  }
end

---One `Documentation.Edge` (`kind = "call"`) resolved to the
---`CallHierarchyItem` for whichever end `which` names, or `nil` when that
---end's node/function no longer resolves (a rename since the last scan,
---between a `handle.callers()` read and this).
---@param root string
---@param handle Documentation.Handle
---@param edge Documentation.Edge
---@param which "from"|"to"
---@return table? item
local function item_for_edge_end(root, handle, edge, which)
  local node_id = edge[which]
  local fn_name = edge[which .. "_fn"]
  local node = handle.node(node_id)
  if not node then
    return nil
  end
  for _, fn in ipairs(node.functions or {}) do
    if fn.name == fn_name then
      return make_item(root, node, fn)
    end
  end
  return nil
end

---A single-line range for a call site — only `edge.line` is tracked, no
---column, same reasoning as `make_item`'s own ranges.
---@param edge Documentation.Edge
---@return table Range
local function call_site_range(edge)
  local line0 = (edge.line or 1) - 1
  return { start = { line = line0, character = 0 }, ["end"] = { line = line0, character = 200 } }
end

---Heuristic-confidence edges are real data, not noise, the same call the
---HTML map's Calls view already made for them (drawn, just visually
---marked "weak") — LSP's `CallHierarchyItem`/`*Call` shapes have no field
---for "this one's a guess", so the one place left to say it is `detail`,
---appended rather than replacing the function's own signature there.
---@param edge Documentation.Edge
---@return string suffix
local function confidence_suffix(edge)
  return edge.confidence == "heuristic" and " (heuristic match)" or ""
end

---Build the in-process client. `dispatchers` is accepted for signature
---compatibility with `vim.lsp.rpc.Client`; nothing here pushes an
---unsolicited notification (no diagnostics, no progress), so it is never
---called.
---@param handle Documentation.Handle
---@return vim.lsp.rpc.Client
local function make_client(handle)
  local root = handle.root
  local closing = false

  ---@param method string
  ---@param params table
  ---@return table? result
  local function dispatch(method, params)
    if method == "initialize" then
      return {
        capabilities = {
          callHierarchyProvider = true,
          hoverProvider = true,
        },
        serverInfo = { name = CLIENT_NAME },
      }
    elseif method == "shutdown" then
      return vim.NIL
    elseif method == "textDocument/prepareCallHierarchy" or method == "textDocument/hover" then
      local uri = params.textDocument.uri
      local rel = to_repo_relative(root, vim.uri_to_fname(uri))
      if not rel then
        return vim.NIL
      end
      local ir = handle.ir()
      local node = node_for_source(ir, rel)
      if not node then
        return vim.NIL
      end
      local fn = fn_at_line(node, params.position.line + 1)
      if not fn then
        return vim.NIL
      end

      if method == "textDocument/prepareCallHierarchy" then
        return { make_item(root, node, fn) }
      end

      -- Hover: a caller/callee count, not the full lists — a hover popup
      -- is glanced at, not read; the full lists are one
      -- `vim.lsp.buf.incoming_calls()`/`outgoing_calls()` away for anyone
      -- who wants them.
      local fn_key = node.id .. "#" .. fn.name
      local n_in = #handle.callers(fn_key)
      local n_out = #handle.callees(fn_key)
      if n_in == 0 and n_out == 0 then
        return vim.NIL
      end
      return {
        contents = {
          kind = "markdown",
          value = ("**%d** incoming call%s · **%d** outgoing call%s"):format(
            n_in,
            n_in == 1 and "" or "s",
            n_out,
            n_out == 1 and "" or "s"
          ),
        },
      }
    elseif method == "callHierarchy/incomingCalls" or method == "callHierarchy/outgoingCalls" then
      local item = params.item
      local fn_key = item.data and item.data.fn_key
      if not fn_key then
        return {}
      end
      local incoming = method == "callHierarchy/incomingCalls"
      local edges = incoming and handle.callers(fn_key) or handle.callees(fn_key)
      local out = {}
      for _, edge in ipairs(edges) do
        local other = item_for_edge_end(root, handle, edge, incoming and "from" or "to")
        if other then
          other.detail = (other.detail or "") .. confidence_suffix(edge)
          out[#out + 1] = incoming and { from = other, fromRanges = { call_site_range(edge) } }
            or { to = other, fromRanges = { call_site_range(edge) } }
        end
      end
      return out
    end
    return vim.NIL
  end

  return {
    -- `_notify_reply_callback`: part of `vim.lsp.rpc.Client`'s required
    -- shape, never read — nothing here sends a request that could race a
    -- reply notification.
    request = function(method, params, callback, _notify_reply_callback)
      local ok, result = pcall(dispatch, method, params or {})
      vim.schedule(function()
        if ok then
          callback(nil, result, 0)
        else
          callback({ code = -32603, message = tostring(result) }, nil, 0)
        end
      end)
      return true, 0
    end,
    notify = function(method, _params)
      if method == "exit" then
        closing = true
      end
      return true
    end,
    is_closing = function()
      return closing
    end,
    terminate = function()
      closing = true
    end,
  }
end

---@type table<integer, boolean>
local attached_bufs = {}

---Attach the call-hierarchy client to `bufnr`, once. Called from
---`documentation.editor.registry`'s own `ensure_callhierarchy` autocmd, so
---the "is this buffer under a root that opted in" decision already
---happened there — this only guards against attaching twice to the same
---buffer (a `BufReadPost` on a buffer already `:edit`ed once in the same
---session, for instance).
---@param bufnr integer
---@param handle Documentation.Handle
function M.attach(bufnr, handle)
  if attached_bufs[bufnr] or not handle then
    return
  end
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  attached_bufs[bufnr] = true

  vim.lsp.start({
    name = CLIENT_NAME,
    cmd = function()
      return make_client(handle)
    end,
    root_dir = handle.root,
  }, {
    bufnr = bufnr,
    reuse_client = function(client)
      return client.name == CLIENT_NAME
    end,
  })

  vim.api.nvim_buf_attach(bufnr, false, {
    on_detach = function()
      attached_bufs[bufnr] = nil
    end,
  })
end

return M
