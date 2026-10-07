-- TESTS/readme_scope_spec.lua — which modules `missing-readme` asks a README
-- of, and that `<plugin>.health` is not reported as unreferenced.
--
-- Built over a synthetic IR, on the precedent many_modules_spec.lua set: the
-- question is what the checks do with `depth` and `stats`, not whether the
-- scanner sets them.
--
-- Both rules came out of one real report: a map of `sessions.nvim` listed five
-- README-less subfolders and an orphaned `sessions.health`. Neither is a
-- defect in that repository — a README for `config/` is not something anyone
-- writes, and `:checkhealth` loads `<plugin>.health` by name.

return function(H)
  local eq, ok = H.eq, H.ok
  local check = require("documentation.core.check")

  local opts = { root = "/fake", lua_root = "lua", extra_checks = {} }

  ---@param id string
  ---@param over table
  local function node(id, over)
    return vim.tbl_extend("force", {
      id = id,
      kind = "module",
      name = id:match("[^/]+$"),
      path = id,
      source = id .. "/init.lua",
      module = id:gsub("^lua/", ""):gsub("/", "."),
      summary = "x",
      body = "",
      readme = nil,
      types = {},
      export = "table",
      depth = 1,
      children = {},
      functions = {},
      required_by = { "lua/other" },
      stats = { files_lua = 1, files_md = 0, files_other = 0 },
    }, over or {})
  end

  ---@param nodes table[]
  local function make_ir(nodes)
    local order, by_id = {}, {}
    for _, n in ipairs(nodes) do
      order[#order + 1] = n.id
      by_id[n.id] = n
    end
    return {
      meta = { title = "t", source = "lua", types_dir = "@types", branch = "main", schema = 1,
        counts = { module = #nodes, namespace = 0, file = 0 } },
      root = "lua",
      order = order,
      nodes = by_id,
      edges = {},
    }
  end

  ---@param ir table
  ---@param code string
  ---@return string Comma-joined ids of the nodes that carry a finding with this code.
  ---Joined because `H.eq` compares tables by identity.
  local function flagged(ir, code)
    local out = {}
    for _, f in ipairs(check.run(ir, opts)) do
      if f.check == code then
        out[#out + 1] = f.node
      end
    end
    table.sort(out)
    return table.concat(out, ",")
  end

  -- The shape that started this: a plugin with small nested folders.
  local ir = make_ir({
    node("lua/sessions", { depth = 1 }),
    node("lua/sessions/config", { depth = 2 }),
    node("lua/sessions/bindings/keymaps", { depth = 3 }),
  })
  eq(
    flagged(ir, "missing-readme"),
    "lua/sessions",
    "readme: only the top-level module is asked for a README"
  )

  -- A subsystem big enough to need a way in is asked, however deep.
  ir = make_ir({
    node("lua/p", { depth = 1, readme = "README.md" }),
    node("lua/p/engine", { depth = 2, stats = { files_lua = 10, files_md = 0, files_other = 0 } }),
    node("lua/p/small", { depth = 2, stats = { files_lua = 9, files_md = 0, files_other = 0 } }),
  })
  eq(
    flagged(ir, "missing-readme"),
    "lua/p/engine",
    "readme: ten files makes a nested module a subsystem; nine does not"
  )

  -- Files in other languages count toward size too.
  ir = make_ir({
    node("lua/p", { depth = 1, readme = "README.md" }),
    node("lua/p/mixed", { depth = 2, stats = { files_lua = 4, files_md = 0, files_other = 6 } }),
  })
  eq(flagged(ir, "missing-readme"), "lua/p/mixed", "readme: size counts every source file, not just Lua")

  -- A module that has one is never reported, at any size.
  ir = make_ir({
    node("lua/p", { depth = 1, readme = "README.md" }),
    node("lua/p/engine", { depth = 2, readme = "README.md", stats = { files_lua = 40, files_md = 0, files_other = 0 } }),
  })
  eq(flagged(ir, "missing-readme"), "", "readme: a module with a README is silent")

  -- `<plugin>.health` has no caller by design.
  ir = make_ir({
    node("lua/sessions", { depth = 1, readme = "README.md" }),
    node("lua/sessions/health", {
      kind = "file",
      depth = 2,
      module = "sessions.health",
      required_by = {},
    }),
    node("lua/sessions/orphan", {
      kind = "file",
      depth = 2,
      module = "sessions.orphan",
      required_by = {},
    }),
  })
  eq(
    flagged(ir, "unreferenced-module"),
    "lua/sessions/orphan",
    "orphans: a health module is loaded by :checkhealth, a real orphan still is reported"
  )

  ok(true, "readme_scope: done")
end
