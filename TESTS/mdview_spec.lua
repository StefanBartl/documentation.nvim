-- TESTS/mdview_spec.lua — `editor/registry.lua`'s `ensure_mdview` (`opts.mdview`),
-- Tier A of the roadmap's "mdview.nvim integration" item.
--
-- Stubs `package.loaded["mdview.core.state"]`/`["mdview.adapter.ws_client"]`
-- rather than depending on a real mdview.nvim checkout (which would need a
-- running relay server, a curl subprocess, and a browser tab to exercise for
-- real) — same soft-dependency test posture `pdf_artifact_spec.lua` already
-- established for pdfport.nvim.

return function(H)
  local eq, ok = H.eq, H.ok
  local docmap = require("documentation")

  local function reset_mdview()
    package.loaded["mdview.core.state"] = nil
    package.loaded["mdview.adapter.ws_client"] = nil
  end

  local root = H.tmpfile("_mdview")
  vim.fn.mkdir(root .. "/lua/demo", "p")
  local fd = assert(io.open(root .. "/lua/demo/init.lua", "w"))
  fd:write("---@module 'demo'\n--- A demo module.\nlocal M = {}\nfunction M.run() end\nreturn M\n")
  fd:close()

  -- --------------------------------------------- mdview.nvim not installed
  do
    reset_mdview()
    local handle =
      docmap.install({ root = root, source = "lua/demo", lua_root = "lua", mdview = true })
    -- No error, and nothing left wired: the pcall probe on
    -- "mdview.core.state" fails, so ensure_mdview is a silent no-op.
    handle.uninstall()
  end

  -- ------------------------------------- installed, but no session attached
  do
    reset_mdview()
    local sent = false
    package.loaded["mdview.core.state"] = {
      is_attached = function()
        return false
      end,
      get_server = function()
        return nil
      end,
    }
    package.loaded["mdview.adapter.ws_client"] = {
      send_markdown = function()
        sent = true
      end,
    }
    local handle =
      docmap.install({ root = root, source = "lua/demo", lua_root = "lua", mdview = true })
    ok(not sent, "mdview installed but no session attached -> no push attempted")
    handle.uninstall()
  end

  -- --------------------------------------------------------- happy path
  do
    reset_mdview()
    local calls = {}
    package.loaded["mdview.core.state"] = {
      is_attached = function()
        return true
      end,
      get_server = function()
        return { pid = 1 }
      end,
    }
    package.loaded["mdview.adapter.ws_client"] = {
      send_markdown = function(path, markdown, send_opts)
        calls[#calls + 1] = { path = path, markdown = markdown, opts = send_opts }
      end,
    }

    local handle =
      docmap.install({ root = root, source = "lua/demo", lua_root = "lua", mdview = true })

    eq(#calls, 1, "mdview: install()'s initial scan pushes exactly once")
    local expected_path = (root:gsub("\\", "/")) .. "/docs/map/overview.md"
    eq(calls[1].path, expected_path, "mdview: pushes to <root>/<out_dir>/overview.md")
    ok(calls[1].opts.immediate == true, "mdview: sends immediately, not queued")
    ok(
      calls[1].markdown:find("demo", 1, true),
      "mdview: rendered markdown names the scanned module"
    )
    ok(
      not calls[1].markdown:find("```mermaid", 1, true),
      "mdview: no Mermaid fences (mdview's client can't render them)"
    )
    ok(
      calls[1].markdown:find("interactive map", 1, true),
      "mdview: points at index.html for diagrams instead"
    )

    -- A rescan (the same thing a watch-triggered write or a manual
    -- `:DocMap` would do) pushes again via the on_change subscription.
    handle.rescan()
    eq(#calls, 2, "mdview: a rescan pushes again via on_change")

    -- Idempotent: a second install() over the same root replaces the
    -- handle (registry.lua's documented "replace, don't stack" posture)
    -- and re-wires cleanly rather than double-pushing.
    calls = {}
    local handle2 =
      docmap.install({ root = root, source = "lua/demo", lua_root = "lua", mdview = true })
    eq(#calls, 1, "mdview: re-install() over the same root wires exactly one subscription, not two")

    handle2.uninstall()
  end

  reset_mdview()
end
