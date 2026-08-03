-- TESTS/browse_endpoints_spec.lua — the Endpoints mode in
-- documentation.editor.browse.view (step 6 of docs/ECOSYSTEM.md).
--
-- Its own file, not a block in docmap_browse_spec.lua: that file already
-- sits near Lua's 200-local-per-function ceiling. view.lua's own header
-- says its functions are "deliberately pure ... testable headlessly
-- without mounting anything", so this needs no window/buffer at all —
-- a plain IR and a state table in, strings out.

return function(H)
  local eq, ok = H.eq, H.ok
  local view = require("documentation.editor.browse.view")

  ---@return Documentation.IR
  local function fake_ir()
    return {
      order = { "a", "b" },
      nodes = {
        a = {
          id = "a",
          module = "app.routes",
          source = "app/routes.js",
          functions = {
            {
              name = "getUser",
              signature = "getUser(req, res)",
              summary = "Fetch one user.",
              line = 5,
              line_end = 7,
            },
          },
          endpoints = {
            {
              method = "get",
              path = "/users/:id",
              handler = "getUser",
              line = 10,
              framework = "express",
              documented = true,
            },
            {
              method = "post",
              path = "/users",
              handler = nil,
              line = 12,
              framework = "express",
              documented = false,
            },
          },
        },
        b = {
          id = "b",
          module = "app.other",
          source = "app/other.js",
          functions = {},
          endpoints = {},
        },
      },
    }
  end

  -- entries: both routes found, sorted by path then method, no route from
  -- node "b" (it has none) breaking anything.
  do
    local ir = fake_ir()
    local entries = view.entries(ir, { mode = "endpoints" })
    eq(#entries, 2, "endpoints mode: every route across the tree, none missed")
    eq(entries[1].spec.path, "/users", "endpoints mode: sorted by path first")
    eq(entries[2].spec.path, "/users/:id", "endpoints mode: ... second one after")
    eq(entries[1].label, "POST    /users", "endpoints mode: label is METHOD + path")
    ok(entries[1].kind == "endpoint", 'endpoints mode: entry kind is "endpoint"')
  end

  -- An empty tree gets an honest message, not a silently empty list.
  do
    local ir = { order = { "a" }, nodes = { a = { id = "a", endpoints = {} } } }
    local entries = view.entries(ir, { mode = "endpoints" })
    eq(#entries, 1, "endpoints mode: one message entry when nothing was found")
    eq(entries[1].kind, "message", "endpoints mode: ... and it says so, not a blank list")
  end

  -- detail: everything the reader needs to decide whether to send it.
  do
    local ir = fake_ir()
    local entries = view.entries(ir, { mode = "endpoints" })
    local get_entry = entries[2] -- "/users/:id", GET, sorted after "/users"
    local lines = view.detail(ir, { mode = "endpoints" }, get_entry)
    eq(lines[1], "GET /users/:id", "endpoints detail: method and path on the first line")
    ok(
      table.concat(lines, "\n"):find("Framework: express", 1, true) ~= nil,
      "endpoints detail: framework shown when known"
    )
    ok(
      table.concat(lines, "\n"):find("Handler: getUser", 1, true) ~= nil,
      "endpoints detail: named handler shown"
    )
    ok(
      table.concat(lines, "\n"):find("Documented", 1, true) ~= nil,
      "endpoints detail: documented status shown"
    )
    ok(
      table.concat(lines, "\n"):find("gs send a request", 1, true) ~= nil,
      "endpoints detail: the send-a-request hint is there"
    )

    local post_entry = entries[1] -- "/users", POST, no handler name
    local post_lines = view.detail(ir, { mode = "endpoints" }, post_entry)
    ok(
      table.concat(post_lines, "\n"):find("inline", 1, true) ~= nil,
      "endpoints detail: an unnamed handler says so rather than showing nothing"
    )
  end

  -- status: spans the whole tree, like Trail/History — not the centered
  -- node's breadcrumb, which would name something unrelated to what is on
  -- screen.
  do
    local ir = fake_ir()
    local st = { mode = "endpoints", entries = view.entries(ir, { mode = "endpoints" }) }
    local status = view.status(ir, st)
    ok(status:find("2 route", 1, true) ~= nil, "endpoints status: the real count")
    ok(status:find("%[endpoints%]") ~= nil, "endpoints status: the mode tag")
  end

  -- `gs` — the soft-dependency send action. Reached through `keyspecs()`
  -- rather than reimplemented: `vim.deepcopy` cannot clone a function value
  -- (Lua has no such operation), so the copied table's `run` field is still
  -- the real one `init.lua` registers, not a stand-in.
  do
    local browse = require("documentation.editor.browse")
    local keys = browse.keyspecs()
    local send_spec
    for _, k in ipairs(keys) do
      if k.id == "send_request" then
        send_spec = k
      end
    end
    ok(send_spec ~= nil, "gs: the send_request action is registered")
    eq(send_spec.only, "endpoints", "gs: scoped to Endpoints mode only")

    -- `selected(st)` reads `st.entries[st.cursor]` directly whenever
    -- `st.slots.list:is_valid()` is false — the no-real-window path, which
    -- is exactly this test's situation (no browser was ever opened).
    local no_window = {
      is_valid = function()
        return false
      end,
    }

    -- Wrong entry kind under the cursor: must not error.
    local ok1 = pcall(send_spec.run, {
      entries = { { kind = "node", id = "a" } },
      cursor = 1,
      slots = { list = no_window },
    })
    ok(ok1, "gs: a non-endpoint entry under the cursor does not error")

    -- A real endpoint entry, but runtime-analysis.nvim is not on the
    -- runtimepath — the actual state of this repository's own test
    -- environment, exercised as-is rather than simulated.
    local ir = fake_ir()
    local entries = view.entries(ir, { mode = "endpoints" })
    local ok2 = pcall(send_spec.run, {
      ir = ir,
      entries = entries,
      cursor = 1,
      slots = { list = no_window },
      mode = "endpoints",
    })
    ok(ok2, "gs: runtime-analysis.nvim absent degrades to a message, not an error")

    -- If a real checkout of runtime-analysis.nvim is on the rtp
    -- (`TESTS/run.lua` appends `RUNTIME_ANALYSIS_DIR` the same way it
    -- already does `DOCUMENTATION_TS_PARSERS_DIR` for the JS/TS parser
    -- tests), the actual integration is exercised end to end: the soft
    -- dependency resolves and a real request buffer opens, pre-filled with
    -- the selected route's method and path.
    local ok_ra_present = pcall(require, "runtime-analysis")
    if ok_ra_present then
      require("runtime-analysis").setup({})
      send_spec.run({
        ir = ir,
        entries = entries,
        cursor = 1,
        slots = { list = no_window },
        mode = "endpoints",
      })
      -- Checked by content, not by bufnr changing: `:enew` reuses the
      -- current buffer outright when it is still the pristine, unmodified
      -- `[No Name]` buffer (real Vim behavior, verified by hand — an
      -- earlier draft of this test asserted the bufnr must differ and
      -- failed on exactly this headless-session case, asserting something
      -- that was never actually guaranteed).
      local after = vim.api.nvim_get_current_buf()
      eq(
        vim.bo[after].filetype,
        "http",
        "gs: with runtime-analysis.nvim present, a real request buffer opens"
      )
      eq(
        vim.api.nvim_buf_get_lines(after, 0, 1, false)[1],
        "POST /users",
        "gs: pre-filled with the selected route's method and path"
      )
    end
  end
end
