---@diagnostic disable: missing-fields
-- The fixtures below carry only the fields the unit under test reads; a full
-- IR, node, finding or entry per case would be noise, not coverage.
-- TESTS/browse_endpoints_spec.lua — the Endpoints mode in
-- documentation.editor.browse.view (step 6 of docs/ecosystem.md).
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
    local first, second = assert(entries[1].spec), assert(entries[2].spec)
    eq(first.path, "/users", "endpoints mode: sorted by path first")
    eq(second.path, "/users/:id", "endpoints mode: ... second one after")
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

  -- Endpoint coverage join with runtime-analysis.nvim: pure logic first,
  -- no plugin needed.
  do
    local coverage = require("documentation.core.endpoint_coverage")

    eq(
      coverage.path_of("https://api.example.com/users/123?x=1"),
      "/users/123",
      "path_of: scheme+host+query stripped from a real absolute URL"
    )
    eq(
      coverage.path_of("{{baseUrl}}/users/123"),
      "/users/123",
      "path_of: an unresolved {{var}} prefix stripped the same way a real host is"
    )
    eq(coverage.path_of("/users/123"), "/users/123", "path_of: a bare path passes through")
    eq(coverage.path_of("https://x.test"), "/", "path_of: no path at all normalizes to /")

    ok(
      ("/users/123"):match(coverage.route_pattern("/users/:id")) ~= nil,
      "route_pattern: Express-style :param matches a real segment"
    )
    ok(
      ("/users/123/extra"):match(coverage.route_pattern("/users/:id")) == nil,
      "route_pattern: :param matches exactly one segment, not the rest of the path"
    )
    ok(
      ("/users/123"):match(coverage.route_pattern("/users/{id}")) ~= nil,
      "route_pattern: Hapi-style {param} matches too"
    )
    ok(
      ("/users"):match(coverage.route_pattern("/users/:id")) == nil,
      "route_pattern: a missing segment does not match"
    )

    local entries = {
      { method = "GET", url = "https://api.example.com/users/1", status = 200, at = 1 },
      { method = "POST", url = "https://api.example.com/users", status = 201, at = 2 },
      { method = "GET", url = "https://api.example.com/other", status = 200, at = 3 },
    }
    local get_user = coverage.matches({ method = "get", path = "/users/:id" }, entries)
    eq(#get_user, 1, "matches: exactly the one entry matching both method and path pattern")
    eq(get_user[1].url, "https://api.example.com/users/1", "matches: the real matching entry")
    eq(
      #coverage.matches({ method = "delete", path = "/users/:id" }, entries),
      0,
      "matches: a method with no matching entries returns empty, not nil"
    )
  end

  -- Endpoint coverage, wired through view.entries: badge + detail, both
  -- the "never sent" and "sent" cases, without needing a real plugin --
  -- `coverage.load` is exercised directly above; this only has to prove
  -- `endpoints_entries` reads its result correctly.
  do
    local ir = fake_ir()
    -- Stand in for `coverage.load` by monkey-patching `runtime-analysis.
    -- history` itself (the real soft dependency `coverage.load` requires)
    -- rather than the join module -- so this exercises the exact same
    -- `pcall(require, "runtime-analysis.history")` path production code
    -- takes, not a mocked-out join.
    package.loaded["runtime-analysis.history"] = {
      list = function(_opts)
        return {
          { method = "GET", url = "https://api.example.com/users/1", status = 200, at = 1 },
        }
      end,
    }

    local entries = view.entries(ir, { mode = "endpoints", opts = { root = "/fake/root" } })
    local by_path = {}
    for _, e in ipairs(entries) do
      local spec = assert(e.spec)
      by_path[spec.path .. " " .. spec.method] = e
    end

    local sent = by_path["/users/:id get"]
    ok(sent ~= nil, "coverage: the GET /users/:id entry is present")
    eq(#sent.endpoint_sends, 1, "coverage: matched exactly the one real send")
    ok(sent.label:find("^GET", 1) ~= nil, "coverage: a sent route carries no leading badge")

    local unsent = by_path["/users post"]
    ok(unsent ~= nil, "coverage: the POST /users entry is present")
    eq(#unsent.endpoint_sends, 0, "coverage: no history entry ever matched this route")
    eq(
      unsent.label:find("○", 1, true),
      1,
      "coverage: an unsent route carries the ○ badge, at the start"
    )
    ok(
      unsent.detail:find("never sent", 1, true) ~= nil,
      "coverage: the detail line names it explicitly"
    )

    package.loaded["runtime-analysis.history"] = nil
  end

  -- No opts.root at all (the shape every pre-existing call in this spec
  -- above already uses): coverage is silently skipped, not an error --
  -- `endpoint_sends` stays nil, no badge.
  do
    local ir = fake_ir()
    local entries = view.entries(ir, { mode = "endpoints" })
    for _, e in ipairs(entries) do
      eq(
        e.endpoint_sends,
        nil,
        "coverage: nil with no opts.root, exactly like before this join existed"
      )
    end
  end
end
