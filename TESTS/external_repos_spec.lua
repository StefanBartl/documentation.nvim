-- TESTS/external_repos_spec.lua — `core/external_repos.lua`'s
-- `opts.external_repos` -> `ir.tag_links` resolution: the guessed (or,
-- with `local_path`, verified) GitHub blob link for a `requires_external`
-- module that belongs to a third-party plugin, not another `docmap`-shaped
-- project.

return function(H)
  local eq, ok = H.eq, H.ok
  local scan = require("documentation.core.scan")
  local tagfiles = require("documentation.core.tagfiles")
  local external_repos = require("documentation.core.external_repos")

  local function write(root, rel, lines)
    local abs = root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "external_repos spec: fixture must be writable")
    fd:write(table.concat(lines, "\n"))
    fd:close()
  end

  local function scan_requiring(root, mods)
    local lines = { "---@module 'demo.app'", "--- Requires a few external modules." }
    for i, mod in ipairs(mods) do
      lines[#lines + 1] = ("local x%d = require(%q)"):format(i, mod)
    end
    vim.list_extend(lines, { "local M = {}", "function M.noop() end", "return M" })
    write(root, "lua/demo/app/init.lua", lines)
    return scan.scan({ root = root, source = "lua/demo", lua_root = "lua" })
  end

  -- Shorthand string form: defaults to branch "main", lua_root "lua", no
  -- local verification — the flat shape, unverified.
  do
    local root = H.tmpfile("_extrepo_shorthand")
    local ir = scan_requiring(root, { "plenary.async" })
    external_repos.resolve(
      ir,
      { root = root, external_repos = { plenary = "nvim-lua/plenary.nvim" } }
    )
    local link = ir.tag_links["plenary.async"]
    ok(link ~= nil, "resolve: shorthand string form resolves")
    eq(
      link.html,
      "https://github.com/nvim-lua/plenary.nvim/blob/main/lua/plenary/async.lua",
      "resolve: default branch/lua_root, flat-shape guess with no local_path"
    )
    eq(link.title, "plenary.async", "resolve: title is the bare required module string")
  end

  -- Full table form with a custom branch.
  do
    local root = H.tmpfile("_extrepo_branch")
    local ir = scan_requiring(root, { "nio.control" })
    external_repos.resolve(ir, {
      root = root,
      external_repos = { nio = { repo = "nvim-neotest/nvim-nio", branch = "master" } },
    })
    eq(
      ir.tag_links["nio.control"].html,
      "https://github.com/nvim-neotest/nvim-nio/blob/master/lua/nio/control.lua",
      "resolve: custom branch honoured"
    )
  end

  -- `local_path` verification: a real checkout on disk, directory shape
  -- (`init.lua`) — the shape this was built against after a flat-only
  -- guess got it wrong for `lib.nvim`'s own real layout (see
  -- core/external_repos.lua's header).
  do
    local root = H.tmpfile("_extrepo_local_dir")
    local checkout = H.tmpfile("_extrepo_checkout_dir")
    write(checkout, "lua/plenary/async/init.lua", { "return {}" })

    local ir = scan_requiring(root, { "plenary.async" })
    external_repos.resolve(ir, {
      root = root,
      external_repos = { plenary = { repo = "nvim-lua/plenary.nvim", local_path = checkout } },
    })
    eq(
      ir.tag_links["plenary.async"].html,
      "https://github.com/nvim-lua/plenary.nvim/blob/main/lua/plenary/async/init.lua",
      "resolve: directory shape (init.lua) picked when that is what the checkout actually has"
    )
  end

  -- `local_path` verification: flat shape confirmed present.
  do
    local root = H.tmpfile("_extrepo_local_flat")
    local checkout = H.tmpfile("_extrepo_checkout_flat")
    write(checkout, "lua/plenary/async.lua", { "return {}" })

    local ir = scan_requiring(root, { "plenary.async" })
    external_repos.resolve(ir, {
      root = root,
      external_repos = { plenary = { repo = "nvim-lua/plenary.nvim", local_path = checkout } },
    })
    eq(
      ir.tag_links["plenary.async"].html,
      "https://github.com/nvim-lua/plenary.nvim/blob/main/lua/plenary/async.lua",
      "resolve: flat shape confirmed and used when the checkout actually has that instead"
    )
  end

  -- `local_path` given, but the module exists in neither shape on disk
  -- (stale declaration, or a dynamically required path `deps.lua` itself
  -- would not have resolved) — falls back to the flat guess rather than
  -- producing no link at all.
  do
    local root = H.tmpfile("_extrepo_local_missing")
    local checkout = H.tmpfile("_extrepo_checkout_empty")
    vim.fn.mkdir(checkout .. "/lua", "p")

    local ir = scan_requiring(root, { "plenary.async" })
    external_repos.resolve(ir, {
      root = root,
      external_repos = { plenary = { repo = "nvim-lua/plenary.nvim", local_path = checkout } },
    })
    eq(
      ir.tag_links["plenary.async"].html,
      "https://github.com/nvim-lua/plenary.nvim/blob/main/lua/plenary/async.lua",
      "resolve: neither shape found on disk -> falls back to the flat guess, not silence"
    )
  end

  -- Longest, dot-bounded prefix wins — same rule as tagfiles.match_prefix,
  -- verified independently here since the implementation duplicates it
  -- rather than sharing it (different value shapes).
  do
    local root = H.tmpfile("_extrepo_prefix")
    local ir = scan_requiring(root, { "plenary.async.util" })
    external_repos.resolve(ir, {
      root = root,
      external_repos = {
        plenary = "nvim-lua/plenary.nvim",
        ["plenary.async"] = "someone/plenary-async-fork",
      },
    })
    ok(
      ir.tag_links["plenary.async.util"].html:find("someone/plenary%-async%-fork", 1, false) ~= nil,
      "resolve: the longer, more specific prefix wins"
    )
  end

  -- Never overwrites an entry tagfiles.resolve already set — a local
  -- project's own map beats a guessed GitHub URL for the same module.
  do
    local root = H.tmpfile("_extrepo_precedence")
    local other = H.tmpfile("_extrepo_other_project")
    vim.fn.mkdir(other .. "/docs/map", "p")
    write(other, "lua/plenary/async/init.lua", {
      "---@module 'plenary.async'",
      "--- The real thing, docmap-shaped.",
      "local M = {}",
      "return M",
    })
    local other_ir = scan.scan({ root = other, source = "lua/plenary", lua_root = "lua" })
    local json = require("documentation.core.json")
    local fd = assert(io.open(other .. "/docs/map/module_map.json", "w"))
    fd:write(json.encode({
      meta = other_ir.meta,
      root = other_ir.root,
      nodes = (function()
        local out = {}
        for _, id in ipairs(other_ir.order) do
          out[#out + 1] = other_ir.nodes[id]
        end
        return out
      end)(),
    }))
    fd:close()

    local ir = scan_requiring(root, { "plenary.async" })
    tagfiles.resolve(ir, { root = root, tag_files = { plenary = other .. "/docs/map" } })
    ok(ir.tag_links["plenary.async"], "precedence setup: tagfiles resolved this module first")
    local before = ir.tag_links["plenary.async"].html

    external_repos.resolve(
      ir,
      { root = root, external_repos = { plenary = "nvim-lua/plenary.nvim" } }
    )
    eq(
      ir.tag_links["plenary.async"].html,
      before,
      "resolve: does not overwrite a module tagfiles.resolve already linked"
    )
  end

  -- No opts.external_repos at all: a true no-op, ir.tag_links untouched
  -- (stays exactly what tagfiles.resolve alone produced — {} when neither
  -- is configured).
  do
    local root = H.tmpfile("_extrepo_noop")
    local ir = scan_requiring(root, { "plenary.async" })
    ir.tag_links = {}
    external_repos.resolve(ir, { root = root })
    eq(next(ir.tag_links), nil, "resolve: no-op when opts.external_repos is unset")
  end
end
