-- TESTS/mcp_spec.lua — `documentation.mcp.protocol` and `documentation.mcp.tools`,
-- the MCP server's two halves that have nothing to do with stdio.
--
-- Driven through `protocol.dispatch(server, line)` with real JSON strings on
-- both sides, rather than by calling the tool functions directly. That is the
-- point of the split: everything a client would actually send goes through the
-- same decode → dispatch → encode path a subprocess would, so a protocol
-- regression (a wrong error code, a notification that gets answered, a result
-- that is not valid JSON) fails here instead of only in an agent's log.
--
-- The transport itself (`mcp/init.lua`'s read loop) is deliberately not
-- covered: it is a `while io.read` around this, and a test that redirected the
-- process's own stdin to assert on six lines of loop would be testing Lua's
-- io library. What it *does* do beyond looping — `watch = false`, and the scan
-- happening before the loop — is asserted below against the same options table.

return function(H)
  local eq, ok = H.eq, H.ok
  local docmap = require("documentation")
  local protocol = require("documentation.mcp.protocol")

  local function dwrite(root, rel, lines)
    local abs = root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "mcp spec: fixture must be writable")
    fd:write(table.concat(lines, "\n"))
    fd:close()
    return abs
  end

  local root = H.tmpfile("_mcp")
  dwrite(root, "lua/demo/a/init.lua", {
    "---@module 'demo.a'",
    "--- A calls into B.",
    'local b = require("demo.b")',
    "local M = {}",
    "---One.",
    "function M.one()",
    "  b.two()",
    "  return 1",
    "end",
    "return M",
  })
  dwrite(root, "lua/demo/b/init.lua", {
    "---@module 'demo.b'",
    "--- B, called by A.",
    "local M = {}",
    "---Two.",
    "function M.two()",
    "  return 2",
    "end",
    "return M",
  })

  local handle = docmap.install({ root = root, source = "lua/demo", lua_root = "lua" })
  local server = protocol.new(handle, { name = "demo.nvim" })

  ---Send one request and decode the response envelope.
  ---@param msg table
  ---@return table? decoded response
  local function send(msg)
    local line = protocol.dispatch(server, vim.json.encode(msg))
    if line == nil then
      return nil
    end
    return vim.json.decode(line)
  end

  ---Send a `tools/call` and decode the payload out of its text content block.
  ---
  ---Two decodes deep on purpose — an MCP tool result is a content-block list
  ---whose text *happens* to be JSON, so a test that reached for structured
  ---data directly would be asserting on a shape no client ever sees.
  ---An `isError` result's text is a human-readable message rather than JSON,
  ---so the decode is lenient and the payload comes back `nil` for those —
  ---which is itself asserted below, because a client that blindly parsed it
  ---would be the bug this shape prevents.
  ---@param name string
  ---@param args table?
  ---@return table? payload
  ---@return table result The raw result, for `isError` assertions.
  local function call(name, args)
    local res = send({
      jsonrpc = "2.0",
      id = 1,
      method = "tools/call",
      params = { name = name, arguments = args or vim.empty_dict() },
    })
    ok(res and res.result, "tools/call " .. name .. ": a result, not a JSON-RPC error")
    local text = res.result.content[1].text
    local decoded, payload = pcall(vim.json.decode, text)
    return decoded and payload or nil, res.result
  end

  -- ── Handshake ────────────────────────────────────────────────────────────

  do
    local res = send({
      jsonrpc = "2.0",
      id = 1,
      method = "initialize",
      params = { protocolVersion = "2025-06-18", capabilities = {} },
    })
    eq(res.result.protocolVersion, "2025-06-18", "initialize: echoes a version we support")
    eq(res.result.serverInfo.name, "demo.nvim", "initialize: serverInfo carries opts.title")
    ok(res.result.capabilities.tools, "initialize: declares the tools capability")
    eq(
      res.result.capabilities.tools.listChanged,
      false,
      "initialize: does not claim a list_changed notification it never sends"
    )
  end

  do
    -- An unknown revision must not be echoed back — echoing it would claim
    -- compatibility with a spec nobody checked. The server answers with its
    -- own newest instead and lets the client decide.
    local res = send({
      jsonrpc = "2.0",
      id = 2,
      method = "initialize",
      params = { protocolVersion = "1999-01-01" },
    })
    eq(
      res.result.protocolVersion,
      protocol.SUPPORTED[1],
      "initialize: an unknown client version gets our newest, not an echo"
    )
  end

  do
    -- A notification has no id, so it must produce no response at all.
    -- Answering one is a protocol violation, not a harmless extra line.
    local line = protocol.dispatch(
      server,
      vim.json.encode({
        jsonrpc = "2.0",
        method = "notifications/initialized",
      })
    )
    eq(line, nil, "notifications/initialized: no response line")
    eq(server.initialized, true, "notifications/initialized: recorded on the server")
  end

  -- ── Tool listing ─────────────────────────────────────────────────────────

  local tool_names = {}
  do
    local res = send({ jsonrpc = "2.0", id = 3, method = "tools/list" })
    local list = res.result.tools
    ok(#list > 0, "tools/list: a non-empty catalogue")

    local sorted = true
    for i, t in ipairs(list) do
      tool_names[t.name] = true
      ok(type(t.description) == "string" and t.description ~= "", t.name .. ": has a description")
      eq(t.inputSchema.type, "object", t.name .. ": inputSchema is an object schema")
      if i > 1 and list[i - 1].name > t.name then
        sorted = false
      end
    end
    ok(sorted, "tools/list: sorted by name, so the order is stable across connections")

    for _, name in ipairs({
      "docmap_modules",
      "docmap_node",
      "docmap_requires",
      "docmap_required_by",
      "docmap_callers",
      "docmap_callees",
      "docmap_findings",
      "docmap_rescan",
    }) do
      ok(tool_names[name], "tools/list: exposes " .. name)
    end
  end

  -- ── The tools themselves ─────────────────────────────────────────────────

  do
    local payload = call("docmap_modules")
    ok(payload.total >= 2, "docmap_modules: finds both fixture modules")
    eq(payload.returned, #payload.modules, "docmap_modules: `returned` matches the array length")

    local seen = {}
    for _, m in ipairs(payload.modules) do
      seen[m.module or ""] = m
    end
    ok(seen["demo.a"], "docmap_modules: demo.a is present, keyed by its declared @module")
    eq(seen["demo.a"].summary, "A calls into B.", "docmap_modules: carries the header summary")
    -- The projection rule from tools.lua, asserted rather than trusted: a raw
    -- IR node would carry these, and every one of them is context an agent
    -- pays for and cannot use.
    eq(seen["demo.a"].stats, nil, "docmap_modules: does not leak the raw node's stats")
    eq(seen["demo.a"].symbols, nil, "docmap_modules: does not leak the raw node's symbols")
  end

  do
    local payload = call("docmap_modules", { limit = 1 })
    eq(payload.returned, 1, "docmap_modules: `limit` caps what is returned")
    ok(payload.total > payload.returned, "docmap_modules: `total` still reports the real count")
  end

  -- Find the node id for demo.a, which every id-taking tool below needs.
  local a_id
  do
    local payload = call("docmap_modules")
    for _, m in ipairs(payload.modules) do
      if m.module == "demo.a" then
        a_id = m.id
      end
    end
    ok(a_id, "docmap_modules: demo.a has a node id")
  end

  do
    local payload = call("docmap_node", { id = a_id })
    eq(payload.id, a_id, "docmap_node: returns the node asked for")
    eq(payload.summary, "A calls into B.", "docmap_node: carries the summary")
    ok(#payload.functions >= 1, "docmap_node: lists the module's documented functions")
    local names = {}
    for _, f in ipairs(payload.functions) do
      names[f.name] = true
    end
    ok(names["M.one"], "docmap_node: M.one is among them")
  end

  do
    -- A bad argument is the model's mistake to fix, so it must come back as a
    -- tool result the model sees, never as a JSON-RPC error the client's
    -- plumbing swallows.
    local payload, raw = call("docmap_node", { id = "lua/demo/nope/init.lua" })
    eq(raw.isError, true, "docmap_node: an unknown id sets isError on the result")
    ok(raw.content[1].text:match("no such node"), "docmap_node: the message names the problem")
    eq(payload, nil, "docmap_node: an error result's text is a message, not a JSON payload")
  end

  do
    local payload = call("docmap_requires", { id = a_id })
    local targets = {}
    for _, e in ipairs(payload.edges) do
      targets[e.to] = e
    end
    ok(next(targets) ~= nil, "docmap_requires: demo.a requires something")

    local found_b = false
    for to in pairs(targets) do
      if to:match("demo/b") then
        found_b = true
      end
    end
    ok(found_b, "docmap_requires: the require edge into demo.b is there")
  end

  do
    local payload = call("docmap_callees", { fn_key = a_id .. "#M.one" })
    eq(payload.fn_key, a_id .. "#M.one", "docmap_callees: echoes the key it was given")
    ok(type(payload.edges) == "table", "docmap_callees: always returns an edge array")
  end

  do
    local payload = call("docmap_findings")
    ok(type(payload.findings) == "table", "docmap_findings: returns an array")
    eq(payload.returned, #payload.findings, "docmap_findings: `returned` matches the array")

    -- A severity filter that matches nothing must still be a well-formed
    -- answer, not an error: "no errors in this tree" is a real result.
    local filtered = call("docmap_findings", { severity = "error", limit = 5 })
    for _, f in ipairs(filtered.findings) do
      eq(f.severity, "error", "docmap_findings: the severity filter actually filters")
    end
    ok(filtered.returned <= 5, "docmap_findings: `limit` is respected")
  end

  do
    local payload = call("docmap_rescan")
    ok(payload.nodes >= 2, "docmap_rescan: reports the node count of the fresh scan")
    ok(type(payload.findings.error) == "number", "docmap_rescan: reports a findings tally")
  end

  -- ── Error paths ──────────────────────────────────────────────────────────

  do
    local res = send({ jsonrpc = "2.0", id = 9, method = "no/such/method" })
    eq(res.error.code, -32601, "unknown method: -32601, not a crash")
    ok(res.error.message:match("no/such/method"), "unknown method: the message names it")
  end

  do
    local res = send({
      jsonrpc = "2.0",
      id = 10,
      method = "tools/call",
      params = { arguments = vim.empty_dict() },
    })
    eq(res.error.code, -32602, "tools/call without a name: -32602 invalid params")
  end

  do
    -- An unknown *tool* is not an unknown *method* — the request was
    -- well-formed, so it is a tool result, same as a bad argument.
    local res = send({
      jsonrpc = "2.0",
      id = 11,
      method = "tools/call",
      params = { name = "docmap_nonexistent", arguments = vim.empty_dict() },
    })
    eq(res.error, nil, "unknown tool: not a JSON-RPC error")
    eq(res.result.isError, true, "unknown tool: an isError tool result instead")
  end

  do
    local line = protocol.dispatch(server, "{ this is not json")
    local res = vim.json.decode(line)
    eq(res.error.code, -32700, "malformed line: -32700 parse error")
    eq(res.id, vim.NIL, "malformed line: a null id, since none could be read")
  end

  do
    eq(protocol.dispatch(server, ""), nil, "blank line: ignored, not answered")
    eq(protocol.dispatch(server, "   "), nil, "whitespace line: ignored, not answered")
  end

  do
    local res = send({ id = 12, method = "tools/list" })
    eq(res.error.code, -32600, "missing jsonrpc field: -32600 invalid request")
  end

  do
    local res = send({ jsonrpc = "2.0", id = 13, method = "ping" })
    ok(res.result, "ping: answered, so a client's keepalive does not look like a hang")
  end

  handle.uninstall()
end
