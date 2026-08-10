-- TESTS/callhierarchy_spec.lua — `editor/callhierarchy.lua`, the in-process
-- LSP client that answers `textDocument/prepareCallHierarchy`/
-- `callHierarchy/incomingCalls`/`outgoingCalls`/`textDocument/hover`.
--
-- Driven end to end, not unit-tested against `dispatch()` directly:
-- `vim.cmd.edit()` a real fixture file to fire the real `BufReadPost`
-- autocmd `registry.ensure_callhierarchy` installs, `vim.wait()` for the
-- client to actually attach, then real `vim.lsp.buf_request_all()` calls —
-- the same "assumed untestable headlessly at first, which was wrong"
-- pattern `docmap_spec.lua`'s own live-watch test already established for
-- `BufWritePost`.

return function(H)
  local eq, ok = H.eq, H.ok
  local docmap = require("documentation")

  local function dwrite(root, rel, lines)
    local abs = root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "callhierarchy spec: fixture must be writable")
    fd:write(table.concat(lines, "\n"))
    fd:close()
    return abs
  end

  ---One request through the real LSP client machinery, blocking until it
  ---resolves or 2s pass. Mirrors `vim.lsp.buf.*`'s own use of
  ---`buf_request_all`, not a private call into `callhierarchy.lua` —
  ---exercising the exact path a real `vim.lsp.buf.incoming_calls()` would.
  ---@param bufnr integer
  ---@param method string
  ---@param params table
  ---@return table results Keyed by client id, `{ result = ... }` per client.
  local function request(bufnr, method, params)
    local results
    vim.lsp.buf_request_all(bufnr, method, function()
      return params
    end, function(res)
      results = res
    end)
    local settled = vim.wait(2000, function()
      return results ~= nil
    end, 10)
    ok(settled, "callhierarchy: " .. method .. " settled within 2s")
    return results or {}
  end

  ---@param results table
  ---@return table? result The first non-nil result across every responding client.
  local function first_result(results)
    for _, r in pairs(results) do
      if r.result ~= nil and r.result ~= vim.NIL then
        return r.result
      end
    end
    return nil
  end

  local root = H.tmpfile("_callhierarchy")
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

  local handle = docmap.install({
    root = root,
    source = "lua/demo",
    lua_root = "lua",
    callhierarchy = true,
  })

  -- The one real, empirically-confirmed sharp edge this module's own header
  -- documents (client methods called without an implicit `self`) would show
  -- up here as every request silently returning nothing — worth restating
  -- as the first assertion, so a regression fails loudly at the edge that
  -- actually bit during development, not three assertions downstream.
  local a_path = root .. "/lua/demo/a/init.lua"
  vim.cmd.edit(vim.fn.fnameescape(a_path))
  local a_buf = vim.api.nvim_get_current_buf()

  local attached = vim.wait(2000, function()
    for _, c in ipairs(vim.lsp.get_clients({ bufnr = a_buf })) do
      if c.name == "docmap-callhierarchy" then
        return true
      end
    end
    return false
  end, 10)
  ok(attached, "callhierarchy: the pseudo-client attaches to a real buffer under source")

  -- ------------------------------------------------------- prepareCallHierarchy

  local prep = first_result(request(a_buf, "textDocument/prepareCallHierarchy", {
    textDocument = { uri = vim.uri_from_bufnr(a_buf) },
    position = { line = 5, character = 12 }, -- inside M.one's body
  }))
  ok(prep ~= nil, "prepareCallHierarchy: resolves a position inside a real function")
  local item_one = prep and prep[1]
  ok(item_one ~= nil, "prepareCallHierarchy: returns one item")
  if item_one then
    eq(item_one.name, "M.one", "prepareCallHierarchy: correct function name")
    eq(item_one.data.fn_key, "lua/demo/a#M.one", "prepareCallHierarchy: correct fn_key")
  end

  -- ---------------------------------------------------------- outgoingCalls

  if item_one then
    local out = first_result(request(a_buf, "callHierarchy/outgoingCalls", { item = item_one }))
    ok(out ~= nil, "outgoingCalls: resolves")
    eq(out and #out, 1, "outgoingCalls: M.one calls exactly one function")
    if out and out[1] then
      eq(out[1].to.name, "M.two", "outgoingCalls: the callee is M.two")
      eq(out[1].to.data.fn_key, "lua/demo/b#M.two", "outgoingCalls: the callee's fn_key is correct")
      ok(#out[1].fromRanges == 1, "outgoingCalls: one call-site range")
      -- Line 6 (0-based) is `b.two()` in the fixture above.
      eq(out[1].fromRanges[1].start.line, 6, "outgoingCalls: call-site line is correct")
    end
  end

  -- ---------------------------------------------------------------- hover

  local hover = first_result(request(a_buf, "textDocument/hover", {
    textDocument = { uri = vim.uri_from_bufnr(a_buf) },
    position = { line = 5, character = 12 },
  }))
  ok(hover ~= nil, "hover: injects content for a function with calls")
  if hover then
    ok(hover.contents.value:find("1", 1, true) ~= nil, "hover: mentions the one outgoing call")
  end

  -- ---------------------------------------------------------- incomingCalls

  local b_path = root .. "/lua/demo/b/init.lua"
  vim.cmd.edit(vim.fn.fnameescape(b_path))
  local b_buf = vim.api.nvim_get_current_buf()
  vim.wait(2000, function()
    for _, c in ipairs(vim.lsp.get_clients({ bufnr = b_buf })) do
      if c.name == "docmap-callhierarchy" then
        return true
      end
    end
    return false
  end, 10)

  local prep_b = first_result(request(b_buf, "textDocument/prepareCallHierarchy", {
    textDocument = { uri = vim.uri_from_bufnr(b_buf) },
    position = { line = 4, character = 12 }, -- inside M.two's body
  }))
  local item_two = prep_b and prep_b[1]
  ok(item_two ~= nil, "prepareCallHierarchy: resolves M.two on the second file")

  if item_two then
    local incoming =
      first_result(request(b_buf, "callHierarchy/incomingCalls", { item = item_two }))
    ok(incoming ~= nil, "incomingCalls: resolves")
    eq(incoming and #incoming, 1, "incomingCalls: M.two is called by exactly one function")
    if incoming and incoming[1] then
      eq(incoming[1].from.name, "M.one", "incomingCalls: the caller is M.one")
    end
  end

  -- ------------------------------------------------- scope: outside `source`

  -- Same "the scope check is the fragile half" reasoning `docmap_spec.lua`'s
  -- own live-watch test states for `BufWritePost` — this autocmd is scoped
  -- with the identical `is_subpath` mechanism, so it deserves the identical
  -- negative check: a Lua file *outside* the scanned `source` dir must never
  -- get the client attached, watch or no watch.
  local outsider = dwrite(root, "notes/scratch.lua", { "-- not part of the scanned tree" })
  vim.cmd.edit(vim.fn.fnameescape(outsider))
  local outsider_buf = vim.api.nvim_get_current_buf()
  vim.wait(300, function()
    return false
  end, 25)
  local outsider_attached = false
  for _, c in ipairs(vim.lsp.get_clients({ bufnr = outsider_buf })) do
    if c.name == "docmap-callhierarchy" then
      outsider_attached = true
    end
  end
  eq(outsider_attached, false, "callhierarchy: a file outside source never gets the client")

  handle.uninstall()
  vim.cmd("silent! %bwipeout!")
end
