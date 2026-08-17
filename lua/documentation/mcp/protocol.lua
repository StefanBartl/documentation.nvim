---@module 'documentation.mcp.protocol'
--- JSON-RPC 2.0 dispatch for the MCP server — the half that has nothing to do
--- with stdio.
---
--- Split out from `init.lua` on purpose: a message handler that reads and
--- writes files is a program you can only test by starting a subprocess and
--- talking to it. This one is a function from a decoded request table to a
--- response table, so `TESTS/mcp_spec.lua` drives the entire protocol —
--- handshake, tool listing, every tool, every error path — in-process, and
--- `init.lua` is left with a loop short enough to read.
---
--- **Envelope JSON is `vim.json`, payload JSON is `documentation.core.json`.**
--- Those are different requirements, not an inconsistency. The envelope has to
--- decode arbitrary client input, which `core/json.lua` cannot do (it only
--- encodes); the payload has to be byte-stable across runs, which `vim.json`
--- does not promise. Neither module can do the other's job.
---
--- ### Protocol version
---
--- MCP revises its spec on a date string, and a client announces which
--- revision it speaks in `initialize`. The rule the spec sets, and this
--- follows: echo the client's version when it is one we know, otherwise answer
--- with ours and let the client decide whether to continue. Nothing here
--- branches on the version — the surface used (initialize, tools/list,
--- tools/call, ping) is identical across every revision in `SUPPORTED` — so
--- the list is a compatibility *claim*, and it is deliberately conservative:
--- adding a revision means checking it, not guessing forward.

local tools = require("documentation.mcp.tools")

local M = {}

M.VERSION = "0.1.0"

---Spec revisions this server claims to speak, newest first.
---@type string[]
M.SUPPORTED = { "2025-06-18", "2025-03-26", "2024-11-05" }

-- JSON-RPC 2.0 reserved error codes. Named rather than inlined because the
-- difference between -32601 and -32602 is the difference between "I do not
-- have that" and "you called it wrong", and a client's error message repeats
-- whichever we pick.
local ERR_PARSE = -32700
local ERR_INVALID_REQUEST = -32600
local ERR_METHOD_NOT_FOUND = -32601
local ERR_INVALID_PARAMS = -32602
local ERR_INTERNAL = -32603

---@param id any
---@param result table
---@return table
local function ok(id, result)
  return { jsonrpc = "2.0", id = id, result = result }
end

---@param id any
---@param code integer
---@param message string
---@return table
local function fail(id, code, message)
  return {
    jsonrpc = "2.0",
    id = id == nil and vim.NIL or id,
    error = { code = code, message = message },
  }
end

---@class Documentation.Mcp.Server
---@field handle Documentation.Handle
---@field name string
---@field out_dir? string Repo-relative output directory — the one piece of `Documentation.Opts` a tool call needs that `handle` does not carry. See `mcp/tools.lua`'s `docmap_checklist`.
---@field initialized boolean Set by the `initialized` notification; informational only — see `request` for why nothing is gated on it.

---Build a server bound to one installed handle.
---@param handle Documentation.Handle
---@param opts { name?: string, out_dir?: string }?
---@return Documentation.Mcp.Server
function M.new(handle, opts)
  opts = opts or {}
  return {
    handle = handle,
    name = opts.name or "documentation.nvim",
    out_dir = opts.out_dir,
    initialized = false,
  }
end

---@param server Documentation.Mcp.Server
---@param params table
---@return table
local function do_initialize(server, params)
  local want = type(params) == "table" and params.protocolVersion or nil
  local version = M.SUPPORTED[1]
  for _, v in ipairs(M.SUPPORTED) do
    if want == v then
      version = v
      break
    end
  end

  return {
    protocolVersion = version,
    -- `listChanged = false` is the honest answer: the tool catalogue is a
    -- static table in `tools.lua`, so there is no circumstance under which
    -- this server would send a `notifications/tools/list_changed`. Claiming
    -- the capability and never using it would make a client subscribe to
    -- something that never fires.
    capabilities = { tools = { listChanged = false } },
    serverInfo = { name = server.name, version = M.VERSION },
    instructions = "Tools over a scanned Lua/JS module map: module tree, require graph, "
      .. "call graph and documentation-drift findings for the repository this server was "
      .. "started in. Answers come from a scan held in memory — call docmap_rescan after "
      .. "editing files.",
  }
end

---Handle one decoded JSON-RPC message.
---
---Returns `nil` for a notification (a message with no `id`), which is exactly
---what the caller should write back: nothing. JSON-RPC forbids responding to
---a notification, so a transport that treats `nil` as "send an empty line"
---would be a protocol violation rather than a cosmetic bug.
---
---Nothing is gated on `server.initialized`. The spec permits a server to
---reject requests before the handshake, but refusing them buys nothing here —
---there is no per-session state to protect, every tool is a read over an
---already-scanned tree — and it costs a real failure mode, where a client
---that batches `initialize` with its first `tools/list` gets an error for a
---request that would have worked.
---@param server Documentation.Mcp.Server
---@param msg table Decoded JSON-RPC request or notification.
---@return table? response `nil` for notifications.
function M.request(server, msg)
  if type(msg) ~= "table" or msg.jsonrpc ~= "2.0" or type(msg.method) ~= "string" then
    return fail(
      type(msg) == "table" and msg.id or nil,
      ERR_INVALID_REQUEST,
      "not a JSON-RPC 2.0 request"
    )
  end

  local id = msg.id
  local method = msg.method
  local params = type(msg.params) == "table" and msg.params or {}

  -- Notifications: no id, no response, ever. `notifications/initialized` is
  -- the only one this server expects; anything else is ignored rather than
  -- answered, because answering a notification is itself the error.
  if id == nil then
    if method == "notifications/initialized" then
      server.initialized = true
    end
    return nil
  end

  if method == "initialize" then
    return ok(id, do_initialize(server, params))
  end

  if method == "ping" then
    return ok(id, vim.empty_dict())
  end

  if method == "tools/list" then
    return ok(id, { tools = tools.list() })
  end

  if method == "tools/call" then
    if type(params.name) ~= "string" then
      return fail(id, ERR_INVALID_PARAMS, "tools/call requires a string `name`")
    end
    local args = type(params.arguments) == "table" and params.arguments or {}

    -- A failing tool is a *result*, not a transport error. MCP draws this
    -- line deliberately: a JSON-RPC error is something the client's plumbing
    -- handles and the model never sees, whereas `isError = true` reaches the
    -- model, which can then correct the argument it got wrong. "No such
    -- node" is the model's mistake to fix, so it has to be the model that
    -- hears about it.
    local success, res =
      pcall(tools.call, server.handle, params.name, args, { out_dir = server.out_dir })
    if success then
      return ok(id, res)
    end
    return ok(id, {
      content = { { type = "text", text = tostring(res) } },
      isError = true,
    })
  end

  return fail(id, ERR_METHOD_NOT_FOUND, "unknown method: " .. method)
end

---Decode one line, dispatch it, and encode the response.
---
---The seam the stdio loop sits on, and the only place a malformed line is
---turned into a `-32700`. Returns `nil` when there is nothing to send back —
---a notification, or a blank line, which some clients emit as a keepalive.
---@param server Documentation.Mcp.Server
---@param line string One newline-delimited JSON-RPC message.
---@return string? encoded response, without a trailing newline.
function M.dispatch(server, line)
  if type(line) ~= "string" or line:match("^%s*$") then
    return nil
  end

  local decoded_ok, msg =
    pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
  if not decoded_ok then
    return vim.json.encode(fail(nil, ERR_PARSE, "invalid JSON"))
  end

  -- A crash inside dispatch must not take the process down: an MCP server is
  -- a long-lived subprocess, and a client that loses it mid-session usually
  -- surfaces that to the user as the whole integration being broken rather
  -- than as one failed call. Returning -32603 keeps the session alive.
  local handled_ok, response = pcall(M.request, server, msg)
  if not handled_ok then
    return vim.json.encode(
      fail(type(msg) == "table" and msg.id or nil, ERR_INTERNAL, tostring(response))
    )
  end
  if response == nil then
    return nil
  end
  return vim.json.encode(response)
end

return M
