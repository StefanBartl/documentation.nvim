-- TESTS/usrcmds_readonly_spec.lua — the "instant" `:DocMap` subcommands that
-- read straight off the already-scanned IR: `why`, `graph`, `dot`, `mermaid`,
-- `tools`, `bindings`, `plugins`, `endpoints`, `consumers`.
--
-- None of these touch git or any other subprocess (`consumers` touches disk,
-- nothing else), so unlike `usrcmds_git_spec.lua` there is no reason to reach
-- for a real fixture repository — a literal IR, the same shape
-- `docmap_spec.lua`'s own churn/diff fixtures use, is what "real behaviour"
-- means here.
--
-- What this closes: every one of these command modules had real branching
-- (usage errors, "nothing found" messages, collision/duplicate detection,
-- sort order, buffer-reuse-by-name) and zero direct coverage — the pure
-- algorithms one layer down (`core/deps.path`, `core/calls.path`,
-- `core/consumers.index`, ...) are already thoroughly tested elsewhere, but
-- nothing exercised the command layer that formats their results, decides
-- what counts as a duplicate, or reuses a scratch buffer by name.

return function(H)
  local eq, ok = H.eq, H.ok

  ---A minimal fake ctx: every command here reads at most cfg/handle/notify/
  ---find_node/open_map, never registry state — so a literal IR closed over by
  ---`handle.ir()` is the whole fixture.
  ---@param ir Documentation.IR
  ---@param cfg table? Merged over the default {root, out_dir, lua_root}.
  ---@return Documentation.Bindings.Ctx ctx
  ---@return table calls {info=string[], warn=string[], opened=string?[]}
  local function fake_ctx(ir, cfg)
    local calls = { info = {}, warn = {}, opened = {} }
    local base_cfg = { root = "/fake/root", out_dir = "docs/map", lua_root = "lua" }
    local ctx = {
      cfg = cfg and vim.tbl_extend("force", base_cfg, cfg) or base_cfg,
      handle = {
        ir = function()
          return ir
        end,
      },
      command_name = "DocMap",
      notify = {
        info = function(msg)
          calls.info[#calls.info + 1] = msg
        end,
        warn = function(msg)
          calls.warn[#calls.warn + 1] = msg
        end,
      },
      find_node = function(ir2, name, lua_root)
        return require("documentation.core.find").node(ir2, name, lua_root)
      end,
      open_map = function(hash)
        calls.opened[#calls.opened + 1] = hash
        return true
      end,
    }
    return ctx, calls
  end

  local function clear_qf()
    vim.fn.setqflist({}, "r")
  end

  local function qf()
    return vim.fn.getqflist({ items = 0, title = 0 })
  end

  -- ================================================================= why
  do
    local why = require("documentation.bindings.usrcmds.why")

    ---@return Documentation.IR
    local function why_ir()
      return {
        root = "a",
        order = { "a", "b", "c" },
        nodes = {
          a = {
            id = "a",
            path = "a",
            module = "pkg.a",
            source = "a/init.lua",
            functions = { { name = "M.go" } },
          },
          b = {
            id = "b",
            path = "b",
            module = "pkg.b",
            source = "b/init.lua",
            functions = { { name = "M.recv" } },
          },
          c = { id = "c", path = "c", module = "pkg.c", source = "c/init.lua", functions = {} },
        },
        edges = {
          { kind = "require", from = "a", to = "b", line = 3, deferred = false },
          {
            kind = "call",
            from = "a",
            to = "b",
            from_fn = "M.go",
            to_fn = "M.recv",
            line = 5,
            confidence = "exact",
          },
        },
      }
    end

    do
      local ctx, calls = fake_ctx(why_ir())
      why.run(ctx, "onlyone")
      eq(#calls.warn, 1, "why: a single-word argument is a usage error")
      ok(calls.warn[1]:find("Usage", 1, true) ~= nil, "why: ...and says so")
    end

    do
      -- from_id resolves, to_id does not: message names `b` (the unresolved one).
      local ctx, calls = fake_ctx(why_ir())
      why.run(ctx, "pkg.a nowhere")
      eq(#calls.warn, 1, "why: an unresolvable second module warns")
      ok(calls.warn[1]:find("nowhere", 1, true) ~= nil, "why: ...naming the one that failed")
    end

    do
      -- from_id itself fails to resolve: message names `a`, not `b`, even
      -- though the `from_id and b or a` idiom reads like it could go either
      -- way — from_id is nil here, so the ternary lands on `a`.
      local ctx, calls = fake_ctx(why_ir())
      why.run(ctx, "nowhere pkg.a")
      ok(
        calls.warn[1]:find("nowhere", 1, true) ~= nil,
        "why: an unresolvable first module names itself"
      )
    end

    do
      local ctx, calls = fake_ctx(why_ir())
      why.run(ctx, "pkg.a pkg.a")
      eq(#calls.info, 1, "why: the same module twice is reported, not treated as connected")
      ok(calls.info[1]:find("same module", 1, true) ~= nil, "why: ...with that exact wording")
    end

    do
      -- b and c: real nodes, no require and no call edge between them at all.
      local ctx, calls = fake_ctx(why_ir())
      why.run(ctx, "pkg.b pkg.c")
      eq(#calls.info, 1, "why: two unconnected real modules get one message")
      ok(
        calls.info[1]:find("does not reach", 1, true) ~= nil,
        "why: ...stating neither loads nor calls"
      )
    end

    do
      -- a -> b: both a require edge and a call edge exist. Both chains report.
      clear_qf()
      local ctx, calls = fake_ctx(why_ir())
      why.run(ctx, "pkg.a pkg.b")
      eq(#calls.info, 1, "why: a real connection is one info message")
      ok(calls.info[1]:find("loads", 1, true) ~= nil, "why: ...covering the require chain")
      ok(calls.info[1]:find("calls", 1, true) ~= nil, "why: ...and the call chain")
      ok(
        calls.info[1]:find("all at load time", 1, true) ~= nil,
        "why: a non-deferred require says so"
      )
      local q = qf()
      eq(#q.items, 2, "why: one quickfix row per hop, both chains")
      ok(
        (q.title or ""):find("pkg.a", 1, true) ~= nil,
        "why: the quickfix title names both modules"
      )
    end

    do
      -- "loads but never calls": a require edge with no matching call edge.
      local ir = why_ir()
      ir.edges = { { kind = "require", from = "a", to = "b", line = 3, deferred = false } }
      clear_qf()
      local ctx, calls = fake_ctx(ir)
      why.run(ctx, "pkg.a pkg.b")
      ok(
        calls.info[1]:find("nothing resolvable calls into it", 1, true) ~= nil,
        "why: a require with no call edge is flagged as loaded-but-unused"
      )
    end

    do
      -- "calls without a require path": a call edge with no require edge.
      local ir = why_ir()
      ir.edges = {
        {
          kind = "call",
          from = "a",
          to = "b",
          from_fn = "M.go",
          to_fn = "M.recv",
          line = 5,
          confidence = "heuristic",
        },
      }
      clear_qf()
      local ctx, calls = fake_ctx(ir)
      why.run(ctx, "pkg.a pkg.b")
      ok(
        calls.info[1]:find("no require path", 1, true) ~= nil,
        "why: a call with no require edge says the static graph understates it"
      )
      ok(
        calls.info[1]:find("heuristic", 1, true) ~= nil,
        "why: and a heuristic-confidence hop says so too"
      )
    end
  end

  -- ============================================================== graph
  do
    local graph = require("documentation.bindings.usrcmds.graph")

    ---@return Documentation.IR
    local function graph_ir()
      return {
        root = "root",
        order = { "root", "a" },
        nodes = {
          root = { id = "root", path = "", module = nil, source = nil, functions = {} },
          a = { id = "a", path = "a", module = "pkg.a", source = "a/init.lua", functions = {} },
        },
        edges = {},
      }
    end

    do
      local ctx, calls = fake_ctx(graph_ir())
      graph.run(ctx, "")
      eq(#calls.warn, 1, "graph: a missing kind warns instead of opening anything")
      eq(#calls.opened, 0, "graph: ...and never calls open_map")
    end

    do
      local ctx, calls = fake_ctx(graph_ir())
      graph.run(ctx, "sideways")
      eq(#calls.warn, 1, "graph: an unrecognized kind warns")
      ok(calls.warn[1]:find("sideways", 1, true) ~= nil, "graph: ...naming what was typed")
    end

    do
      local ctx, calls = fake_ctx(graph_ir())
      graph.run(ctx, "deps nosuch")
      eq(#calls.warn, 1, "graph: an unresolvable module target warns")
      eq(#calls.opened, 0, "graph: ...and never opens")
    end

    do
      local ctx, calls = fake_ctx(graph_ir())
      graph.run(ctx, "deps")
      eq(#calls.opened, 1, "graph: a bare kind with no module opens once")
      ok(
        calls.opened[1]:find("center=root", 1, true) ~= nil,
        "graph: ...centered on the map's own root"
      )
      ok(calls.opened[1]:find("view=deps", 1, true) ~= nil, "graph: ...naming the requested view")
    end

    do
      local ctx, calls = fake_ctx(graph_ir())
      graph.run(ctx, "calls pkg.a")
      eq(#calls.opened, 1, "graph: a resolved module target opens once")
      ok(
        calls.opened[1]:find("center=a", 1, true) ~= nil,
        "graph: ...centered on the resolved node id, not the typed name"
      )
    end
  end

  -- ================================================================= dot
  do
    local dot = require("documentation.bindings.usrcmds.dot")

    ---@return Documentation.IR
    local function dot_ir()
      return {
        root = "root",
        meta = { title = "fixture" },
        order = { "root" },
        nodes = { root = { id = "root", path = "", module = nil, source = nil, functions = {} } },
        edges = {},
      }
    end

    ---@param name string
    ---@return integer?
    local function find_buf_by_name(name)
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if
          vim.api.nvim_buf_is_valid(b)
          and vim.fs.basename(vim.api.nvim_buf_get_name(b)) == name
        then
          return b
        end
      end
    end

    do
      local ctx, calls = fake_ctx(dot_ir())
      dot.run(ctx, "sideways")
      eq(#calls.warn, 1, "dot: an unrecognized kind warns")
    end

    do
      local ctx, calls = fake_ctx(dot_ir())
      dot.run(ctx, "deps nosuch")
      eq(#calls.warn, 1, "dot: an unresolvable module target warns")
    end

    do
      local ctx, calls = fake_ctx(dot_ir())
      dot.run(ctx, "")
      eq(#calls.info, 1, "dot: bare kind (defaults to deps/require) renders once")
      local buf = find_buf_by_name("docmap-require.dot")
      ok(buf ~= nil, "dot: a scratch buffer is named after the kind")
      ok(vim.bo[buf].filetype == "dot", "dot: filetype is dot")
      ok(vim.bo[buf].buftype == "nofile", "dot: buftype is nofile, not a real file")

      -- Regression: `nvim_buf_set_name` raises on a name collision, which a
      -- second `:DocMap dot` used to hit head-on — asking the same question
      -- twice must reuse the buffer, not error or leave it unnamed.
      local before = #vim.api.nvim_list_bufs()
      dot.run(ctx, "")
      local after = #vim.api.nvim_list_bufs()
      eq(after, before, "dot: asking again reuses the named buffer instead of creating a new one")
      eq(#calls.info, 2, "dot: ...and still reports success the second time")
    end

    do
      local ctx = fake_ctx(dot_ir())
      dot.run(ctx, "calls")
      ok(
        find_buf_by_name("docmap-calls.dot") ~= nil,
        "dot: the calls kind gets its own buffer name"
      )
    end
  end

  -- ============================================================= mermaid
  do
    local mermaid = require("documentation.bindings.usrcmds.mermaid")

    ---@return Documentation.IR
    local function mermaid_ir()
      return {
        root = "root",
        meta = { title = "fixture" },
        order = { "root" },
        nodes = {
          root = {
            id = "root",
            path = "",
            module = nil,
            source = nil,
            functions = {},
            children = {},
            depth = 0,
            name = "root",
          },
        },
        edges = {},
      }
    end

    ---@param name string
    ---@return integer?
    local function find_buf_by_name(name)
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if
          vim.api.nvim_buf_is_valid(b)
          and vim.fs.basename(vim.api.nvim_buf_get_name(b)) == name
        then
          return b
        end
      end
    end

    do
      local ctx, calls = fake_ctx(mermaid_ir())
      mermaid.run(ctx, "sideways")
      eq(#calls.warn, 1, "mermaid: an unrecognized kind warns")
    end

    do
      local ctx, calls = fake_ctx(mermaid_ir())
      mermaid.run(ctx, "")
      eq(#calls.info, 1, "mermaid: bare arg defaults to tree and renders once")
      local buf = find_buf_by_name("docmap-tree.mmd")
      ok(buf ~= nil, "mermaid: named after the (defaulted) kind")
      ok(vim.bo[buf].filetype == "markdown", "mermaid: filetype is markdown, not mermaid")

      -- Same buffer-name-collision regression `dot.lua` carries.
      local before = #vim.api.nvim_list_bufs()
      mermaid.run(ctx, "")
      eq(
        #vim.api.nvim_list_bufs(),
        before,
        "mermaid: asking again reuses the buffer instead of erroring on the name"
      )
    end

    do
      local ctx = fake_ctx(mermaid_ir())
      mermaid.run(ctx, "deps")
      ok(
        find_buf_by_name("docmap-deps.mmd") ~= nil,
        "mermaid: the deps kind gets its own buffer name"
      )
    end
  end

  -- =============================================================== tools
  do
    local tools = require("documentation.bindings.usrcmds.tools")

    do
      clear_qf()
      local ctx, calls = fake_ctx({ tools = nil })
      tools.run(ctx)
      eq(#calls.info, 1, "tools: no manifest at all is one info message")
      ok(calls.info[1]:find("No lib.nvim.deps manifest", 1, true) ~= nil, "tools: ...saying so")
      eq(#qf().items, 0, "tools: ...and no quickfix list")
    end

    do
      clear_qf()
      local ctx, calls =
        fake_ctx({ tools = { source = "docs/install.json", tools = {}, errors = {} } })
      tools.run(ctx)
      ok(
        calls.info[1]:find("declares no tools", 1, true) ~= nil,
        "tools: an empty manifest is reported distinctly from a missing one"
      )
    end

    do
      clear_qf()
      local ir = {
        tools = {
          source = "docs/install.json",
          tools = {
            { bin = "rg", required = true, why = "fast search", pkg = { brew = true, apt = true } },
            { bin = "fd", required = false, why = "fast find", pkg = { brew = true } },
          },
          errors = { { index = 3, message = "missing 'bin' field" } },
        },
      }
      local ctx, calls = fake_ctx(ir)
      tools.run(ctx)
      local q = qf()
      eq(#q.items, 3, "tools: one row per declared tool, plus one per invalid entry")
      ok(
        calls.info[1]:find("2 tool(s) declared", 1, true) ~= nil,
        "tools: the count excludes invalid entries"
      )
      ok(
        calls.info[1]:find("1 invalid entry", 1, true) ~= nil,
        "tools: ...and states them separately"
      )
    end
  end

  -- ============================================================ bindings
  do
    local bindings_cmd = require("documentation.bindings.usrcmds.bindings")

    do
      clear_qf()
      local ir =
        { order = { "n1" }, nodes = { n1 = { id = "n1", source = "n1.lua", bindings = {} } } }
      local ctx, calls = fake_ctx(ir)
      bindings_cmd.run(ctx)
      eq(#calls.info, 1, "bindings: nothing bound is one explanatory message")
      ok(calls.info[1]:find("No keymaps", 1, true) ~= nil, "bindings: ...naming what it looked for")
    end

    do
      clear_qf()
      local ir = {
        order = { "n1", "n2" },
        nodes = {
          n1 = {
            id = "n1",
            source = "n1.lua",
            bindings = {
              {
                kind = "keymap",
                callee = "vim.keymap.set",
                line = 3,
                lhs = "<leader>x",
                modes = { "n" },
                events = {},
                desc = "Do x",
                buffer = false,
              },
              {
                kind = "keymap",
                callee = "vim.keymap.set",
                line = 9,
                lhs = "<leader>x",
                modes = { "n" },
                events = {},
                desc = "Do x again",
                buffer = false,
              },
            },
          },
          n2 = {
            id = "n2",
            source = "n2.lua",
            bindings = {
              {
                kind = "keymap",
                callee = "vim.keymap.set",
                line = 2,
                lhs = "<leader>y",
                modes = { "n" },
                events = {},
                buffer = true,
              },
              {
                kind = "keymap",
                callee = "vim.keymap.set",
                line = 4,
                lhs = "<leader>y",
                modes = { "n" },
                events = {},
                buffer = true,
              },
              {
                kind = "usercmd",
                callee = "vim.api.nvim_create_user_command",
                line = 6,
                name = "Foo",
                modes = {},
                events = {},
              },
              {
                kind = "autocmd",
                callee = "vim.api.nvim_create_autocmd",
                line = 8,
                modes = {},
                events = { "BufWritePre" },
              },
            },
          },
        },
      }
      local ctx, calls = fake_ctx(ir)
      bindings_cmd.run(ctx)

      local q = qf()
      eq(#q.items, 6, "bindings: one row per binding, regardless of kind")

      local dup_count = 0
      local nondup_leader_y = 0
      for _, item in ipairs(q.items) do
        if item.text:find("[bound more than once]", 1, true) then
          dup_count = dup_count + 1
        end
        if item.text:find("<leader>y", 1, true) and item.text:find("buffer%-local") then
          nondup_leader_y = nondup_leader_y + 1
        end
      end
      eq(dup_count, 2, "bindings: both <leader>x rows are flagged, once each")
      eq(
        nondup_leader_y,
        2,
        "bindings: buffer-local <leader>y rows exist but are never flagged as duplicates"
      )

      ok(
        calls.info[1]:find("4 keymap(s)", 1, true) ~= nil,
        "bindings: keymap count includes buffer-local entries"
      )
      ok(calls.info[1]:find("1 command(s)", 1, true) ~= nil, "bindings: usercmd counted separately")
      ok(calls.info[1]:find("1 autocmd(s)", 1, true) ~= nil, "bindings: autocmd counted separately")
      ok(
        calls.info[1]:find("1 bound more than once", 1, true) ~= nil,
        "bindings: the collision count is per (mode,lhs) pair, not per extra row"
      )
    end
  end

  -- ============================================================= plugins
  do
    local plugins_cmd = require("documentation.bindings.usrcmds.plugins")

    do
      clear_qf()
      local ir =
        { order = { "n1" }, nodes = { n1 = { id = "n1", source = "n1.lua", plugins = {} } } }
      local ctx, calls = fake_ctx(ir)
      plugins_cmd.run(ctx)
      ok(calls.info[1]:find("No lazy.nvim", 1, true) ~= nil, "plugins: nothing found says so")
    end

    do
      clear_qf()
      local ir = {
        order = { "n1", "n2" },
        nodes = {
          n1 = {
            id = "n1",
            source = "n1.lua",
            plugins = {
              {
                repo = "foo/bar",
                line = 2,
                lazy = false,
                event = {},
                cmd = {},
                ft = {},
                keys = {},
                dependencies = {},
                has_opts = false,
                has_config = false,
              },
              {
                repo = "foo/bar",
                line = 10,
                event = { "VeryLazy" },
                cmd = {},
                ft = {},
                keys = {},
                dependencies = {},
                has_opts = true,
                has_config = false,
              },
            },
          },
          n2 = {
            id = "n2",
            source = "n2.lua",
            plugins = {
              {
                repo = "baz/qux",
                line = 1,
                event = {},
                cmd = {},
                ft = {},
                keys = {},
                dependencies = {},
                has_opts = false,
                has_config = false,
              },
            },
          },
        },
      }
      local ctx, calls = fake_ctx(ir)
      plugins_cmd.run(ctx)

      local q = qf()
      eq(#q.items, 3, "plugins: one row per spec entry")

      local by_line = {}
      for _, item in ipairs(q.items) do
        by_line[item.lnum] = item.text
      end
      ok(by_line[2]:find("eager", 1, true) ~= nil, "plugins: lazy=false renders as eager")
      ok(
        by_line[2]:find("declared more than once", 1, true) ~= nil,
        "plugins: the eager foo/bar row is flagged as a duplicate repo"
      )
      ok(
        by_line[10]:find("event:VeryLazy", 1, true) ~= nil,
        "plugins: the second foo/bar row shows its own trigger"
      )
      ok(
        by_line[10]:find("declared more than once", 1, true) ~= nil,
        "plugins: ...and is flagged too"
      )
      ok(
        by_line[1]:find("no trigger", 1, true) ~= nil,
        "plugins: a spec with no trigger at all says it loads at startup"
      )
      ok(
        not by_line[1]:find("declared more than once", 1, true),
        "plugins: baz/qux is not a duplicate"
      )

      ok(
        calls.info[1]:find("3 plugin spec(s) across 2 file(s)", 1, true) ~= nil,
        "plugins: the summary counts specs and files"
      )
      ok(
        calls.info[1]:find("1 repo(s) declared more than once", 1, true) ~= nil,
        "plugins: ...and repos declared twice, counted once per repo"
      )
    end
  end

  -- =========================================================== endpoints
  do
    local endpoints_cmd = require("documentation.bindings.usrcmds.endpoints")

    do
      clear_qf()
      local ir =
        { order = { "n1" }, nodes = { n1 = { id = "n1", source = "n1.lua", endpoints = {} } } }
      local ctx, calls = fake_ctx(ir)
      endpoints_cmd.run(ctx)
      ok(
        calls.info[1]:find("No call-based route", 1, true) ~= nil,
        "endpoints: nothing found says so"
      )
    end

    do
      clear_qf()
      local ir = {
        order = { "n1", "n2" },
        nodes = {
          n1 = {
            id = "n1",
            source = "n1.lua",
            endpoints = {
              {
                method = "get",
                path = "/b",
                line = 2,
                handler = "h1",
                framework = "express",
                documented = true,
              },
              {
                method = "post",
                path = "/a",
                line = 4,
                handler = "h2",
                framework = "express",
                documented = false,
              },
            },
          },
          n2 = {
            id = "n2",
            source = "n2.lua",
            endpoints = {
              {
                method = "get",
                path = "/a",
                line = 1,
                handler = nil,
                framework = nil,
                documented = false,
              },
            },
          },
        },
      }
      local ctx, calls = fake_ctx(ir)
      endpoints_cmd.run(ctx)

      local q = qf()
      eq(#q.items, 3, "endpoints: one row per route registration")
      -- Sorted by path, then method: /a-get, /a-post, /b-get.
      ok(q.items[1].text:find("GET", 1, true) ~= nil, "endpoints: /a's GET sorts before its POST")
      ok(
        q.items[1].text:find("inline handler", 1, true) ~= nil,
        "endpoints: a nil handler renders as inline"
      )
      ok(q.items[2].text:find("POST", 1, true) ~= nil, "endpoints: /a's POST comes second")
      ok(q.items[3].text:find("/b", 1, true) ~= nil, "endpoints: /b sorts last")

      ok(
        calls.info[1]:find("3 route(s) across 2 file(s)", 1, true) ~= nil,
        "endpoints: the summary counts routes and files"
      )
      ok(
        calls.info[1]:find("1 documented", 1, true) ~= nil,
        "endpoints: ...and how many are documented"
      )
    end
  end

  -- ============================================================ consumers
  --
  -- The one command in this file that touches disk (never git): reads every
  -- sibling checkout's committed `docs/map/module_map.json` under a
  -- directory. `core.consumers.index`/`render` already have thorough literal
  -- coverage in consumers_spec.lua — what is missing here is `core.consumers.
  -- load` itself (never directly exercised anywhere) and the command's own
  -- directory handling.
  do
    local consumers_cmd = require("documentation.bindings.usrcmds.consumers")
    local docmap = require("documentation")

    do
      local ctx, calls = fake_ctx({ order = {}, nodes = {} })
      consumers_cmd.run(ctx, H.tmpfile("_consumers_missing"))
      eq(#calls.warn, 1, "consumers: a nonexistent directory warns")
      ok(calls.warn[1]:find("Not a directory", 1, true) ~= nil, "consumers: ...and says so")
    end

    do
      local empty_dir = H.tmpfile("_consumers_empty")
      vim.fn.mkdir(empty_dir, "p")
      local ctx, calls = fake_ctx({ order = {}, nodes = {} })
      consumers_cmd.run(ctx, empty_dir)
      eq(#calls.warn, 1, "consumers: a directory with no committed maps warns")
      ok(
        calls.warn[1]:find("No committed maps found", 1, true) ~= nil,
        "consumers: ...distinct from 'not a directory'"
      )
    end

    do
      -- A real library and a real consumer, both generated for real —
      -- `core.consumers.load` reads actual files off disk, so a literal
      -- fixture would test nothing about the read path itself.
      local parent = H.tmpfile("_consumers_parent")
      vim.fn.mkdir(parent, "p")
      local libroot = parent .. "/liblib"
      local consumer_root = parent .. "/consumerA"

      local function dwrite(root, rel, lines)
        local abs = root .. "/" .. rel
        vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
        local fd = assert(io.open(abs, "w"), "consumers fixture: must be writable")
        fd:write(table.concat(lines, "\n"))
        fd:close()
      end

      dwrite(libroot, "lua/lib/a.lua", {
        "---@module 'lib.a'",
        "--- A tiny library.",
        "local M = {}",
        "---Go.",
        "function M.go() end",
        "return M",
      })
      docmap.generate({ root = libroot, source = "lua/lib", lua_root = "lua" })

      dwrite(consumer_root, "lua/app/x.lua", {
        "---@module 'app.x'",
        "--- Uses the library.",
        'local a = require("lib.a")',
        "local M = {}",
        "---Use it.",
        "function M.use()",
        "  a.go()",
        "end",
        "return M",
      })
      docmap.generate({ root = consumer_root, source = "lua/app", lua_root = "lua" })

      local handle = docmap.install({ root = libroot, source = "lua/lib", lua_root = "lua" })
      local ctx, calls = fake_ctx(handle.ir(), { root = libroot })

      consumers_cmd.run(ctx, parent)

      eq(#calls.warn, 0, "consumers: a directory with one real consumer map warns nothing")
      eq(#calls.info, 1, "consumers: and reports once")
      ok(
        calls.info[1]:find("(1 maps)", 1, true) ~= nil,
        "consumers: exactly one consumer map was read"
      )

      local found
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if
          vim.api.nvim_buf_is_valid(b)
          and vim.fs.basename(vim.api.nvim_buf_get_name(b)) == "docmap-consumers.md"
        then
          found = b
        end
      end
      ok(found ~= nil, "consumers: a named scratch buffer is created")
      local lines = vim.api.nvim_buf_get_lines(found, 0, -1, false)
      local text = table.concat(lines, "\n")
      ok(text:find("liblib", 1, true) ~= nil, "consumers: titled after the library's own root")

      docmap.uninstall(handle)
    end
  end
end
