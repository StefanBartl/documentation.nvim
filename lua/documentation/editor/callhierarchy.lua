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
---
---`root` arrives already canonicalised by `config.normalise_root`
---(`lib.nvim.fs.normkey` -> `uv.fs_realpath`), but `abs_path` comes from
---`vim.uri_to_fname` on a URI built from a *buffer name* — whatever spelling
---the file was opened under. On Windows those can be the same file under
---two names (an 8.3 short path against its long form, or a differently-cased
---drive letter), and a raw prefix compare then rejects a file that is
---plainly inside the tree. Slash-unification alone is not enough, so try the
---cheap comparison first and fall back to canonicalising `abs_path` the same
---way `root` already was.
---@param root string Already normalized (forward slashes, no trailing slash).
---@param abs_path string
---@return string?
local function to_repo_relative(root, abs_path)
  local norm = (abs_path:gsub("\\", "/"))
  if norm:sub(1, #root + 1) ~= root .. "/" then
    norm = require("documentation.config").normalise_root(norm)
    if norm:sub(1, #root + 1) ~= root .. "/" then
      return nil
    end
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

---How long a loaded telemetry snapshot is reused before being read again.
---
---**A cache is not optional here, and a TTL is the right kind.** A hover
---fires on `K` and on every `CursorHold` in a tree this client is attached
---to; `telemetry_join.load` reads and decodes a JSON file, so without this
---the cost would land on a keystroke. `on_change` cannot help -- telemetry is
---written by a *different* Neovim session running the instrumented code, so
---nothing in this process ever observes it changing.
---
---Two seconds, because that is the shortest window that collapses one
---reader's burst of hovers into a single read -- and because the number this
---shows is a snapshot of a file another process appends to all day: no TTL
---makes it live, and a longer one only makes it wrong for longer.
local TELEMETRY_TTL_MS = 2000

---Telemetry rows for `namespace`, joined against `ir`, cached for
---`TELEMETRY_TTL_MS`.
---
---`nil` throughout is a first-class answer and never an error:
---`runtime-analysis.nvim` not installed, telemetry never enabled for this
---namespace, or no namespace to ask about. Every one of those means "no
---opinion", which is the reading `telemetry_join`'s own header insists on --
---absence of runtime data is not evidence of death.
local telemetry_rows
do
  local cached_at, cached_ns, cached = 0, nil, nil
  ---@param namespace string?
  ---@param ir Documentation.IR
  ---@return table<string, Documentation.TelemetryJoin.Row>?
  telemetry_rows = function(namespace, ir)
    if not namespace or namespace == "" then
      return nil
    end
    local now = (vim.uv or vim.loop).now()
    -- The namespace is part of the key, not only the clock: one Neovim
    -- session can have handles for two repositories attached at once, and a
    -- cache keyed on time alone would answer the second with the first
    -- one's numbers for two seconds.
    if cached_ns == namespace and (now - cached_at) < TELEMETRY_TTL_MS then
      return cached
    end
    local join = require("documentation.core.telemetry_join")
    local data = join.load(namespace)
    -- A negative result is cached too. A tree with no telemetry at all is
    -- the common case, and it is the one where re-reading a file that is not
    -- there on every hover would be pure waste.
    cached_at, cached_ns, cached = now, namespace, data and join.by_key(ir, data) or nil
    return cached
  end
end

---The runtime half of the hover, as a Markdown fragment.
---
---**Three states, and the middle one is why this is worth rendering at all.**
---Real recent calls say the function is alive. Recorded calls but none
---recently is a *cold path* -- a reading `calls` alone cannot give, and the
---reason `Row.calls_recent` exists. A row with no calls ever adds nothing the
---static counts did not already say, so it renders nothing.
---@param row Documentation.TelemetryJoin.Row?
---@return string? fragment
local function runtime_fragment(row)
  if not row or row.calls == 0 then
    return nil
  end
  local days = require("documentation.core.telemetry_join").RECENT_DAYS
  if row.calls_recent > 0 then
    return ("called **%d**× in the last %d days"):format(row.calls_recent, days)
  end
  return ("**not called** in the last %d days (%d recorded in total)"):format(days, row.calls)
end

---Build the in-process client. `dispatchers` is accepted for signature
---compatibility with `vim.lsp.rpc.Client`; nothing here pushes an
---unsolicited notification (no diagnostics, no progress), so it is never
---called.
---@param handle Documentation.Handle
---@param namespace string? Telemetry namespace this root joins against, resolved by the caller from `opts` -- the handle carries no options, and `ir.meta.title` would silently ignore an explicit `opts.telemetry_namespace`.
---@return vim.lsp.rpc.Client
local function make_client(handle, namespace)
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
      local rows = telemetry_rows(namespace, ir)
      local runtime = runtime_fragment(rows and rows[fn_key])

      -- **The silent case was the interesting one.** This used to return
      -- nothing whenever both static counts were zero -- which is exactly the
      -- shape `telemetry_join`'s own header describes as static analysis's
      -- blind spot: a callback bound as a value, or dynamic dispatch, looks
      -- dead here while telemetry proves it is alive. A hover that says
      -- nothing about the one function whose aliveness only runtime data can
      -- attest to is the wrong silence.
      if n_in == 0 and n_out == 0 and not runtime then
        return vim.NIL
      end

      local parts = {
        ("**%d** incoming call%s"):format(n_in, n_in == 1 and "" or "s"),
        ("**%d** outgoing call%s"):format(n_out, n_out == 1 and "" or "s"),
      }
      if runtime then
        parts[#parts + 1] = runtime
      end
      return {
        contents = {
          kind = "markdown",
          value = table.concat(parts, " · "),
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
---@param namespace string? Telemetry namespace for this root; `nil` simply means the hover carries no runtime half.
function M.attach(bufnr, handle, namespace)
  if attached_bufs[bufnr] or not handle then
    return
  end
  if not require("lib.nvim.safe_api").is_valid_buffer(bufnr) then
    return
  end
  attached_bufs[bufnr] = true

  vim.lsp.start({
    name = CLIENT_NAME,
    cmd = function()
      return make_client(handle, namespace)
    end,
    root_dir = handle.root,
  }, {
    bufnr = bufnr,
    -- **The root has to be part of this, and leaving it out was a real
    -- bug.** `reuse_client` *replaces* the default predicate, which already
    -- compares `root_dir`; matching on the name alone meant the second
    -- repository opened in a session attached to the *first* one's client.
    -- Every request then resolved the buffer's path against the wrong root,
    -- `to_repo_relative` returned nil, and the whole feature answered
    -- nothing — no call hierarchy, no hover, no error, for as long as both
    -- were open.
    --
    -- Found by a spec that installs a second handle rather than by reading
    -- this line: with one root in play it behaves identically either way,
    -- which is why it survived.
    --
    -- `client.root_dir` is the modern field and `client.config.root_dir` the
    -- older one; both are read because this plugin supports Neovim 0.10 and
    -- the field moved after it.
    reuse_client = function(client)
      local client_root = client.root_dir or (client.config and client.config.root_dir)
      return client.name == CLIENT_NAME and client_root == handle.root
    end,
  })

  vim.api.nvim_buf_attach(bufnr, false, {
    on_detach = function()
      attached_bufs[bufnr] = nil
    end,
  })
end

return M
