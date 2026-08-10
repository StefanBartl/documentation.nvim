-- TESTS/check_type_vs_class_spec.lua — the `type-vs-class` check in
-- `core/check.lua`.
--
-- Its own file, not a block in docmap_spec.lua: that file already sits
-- near 2,500 lines, and this check needs real files on disk (it re-reads
-- each node's own header comment via `scan.parse_header`), which the
-- fake-IR fixtures most of docmap_spec.lua's own check tests use cannot
-- exercise at all.

return function(H)
  local eq, ok = H.eq, H.ok
  local scan = require("documentation.core.scan")
  local check = require("documentation.core.check")

  local dr = H.tmpfile("_type_vs_class")
  local function dwrite(rel, lines)
    local abs = dr .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "check spec: fixture must be writable")
    fd:write(table.concat(lines, "\n"))
    fd:close()
  end

  -- The real defect: `---@type` on the module table, then fields
  -- actually assigned to it.
  dwrite("lua/t/bad/init.lua", {
    "---@module 't.bad'",
    "--- A module wrongly typed instead of classed.",
    "---@type RateLimits",
    "local M = {}",
    "---A real export.",
    "function M.check(x)",
    "  return x",
    "end",
    "return M",
  })

  -- The correct pattern: `---@class`, not `---@type` — must never fire.
  dwrite("lua/t/good/init.lua", {
    "---@module 't.good'",
    "--- A module correctly classed.",
    "---@class M : RateLimits",
    "local M = {}",
    "---A real export.",
    "function M.check(x)",
    "  return x",
    "end",
    "return M",
  })

  -- `---@type` present, but nothing ever assigned to the table it
  -- annotates — not the bug this check is for, however it might read
  -- otherwise; a module that is genuinely only ever a typed constant.
  dwrite("lua/t/empty/init.lua", {
    "---@module 't.empty'",
    "--- Typed, but exports nothing.",
    "---@type RateLimits",
    "local M = {}",
    "return M",
  })

  -- No annotation at all — the ordinary, unremarkable case.
  dwrite("lua/t/plain/init.lua", {
    "---@module 't.plain'",
    "--- An ordinary module.",
    "local M = {}",
    "---A real export.",
    "function M.check(x)",
    "  return x",
    "end",
    "return M",
  })

  local ir = scan.scan({ root = dr, source = "lua/t", lua_root = "lua" })
  local opts = { root = dr, source = "lua/t", lua_root = "lua", extra_checks = {} }
  local findings = check.run(ir, opts)

  local function by_node(node_id)
    for _, f in ipairs(findings) do
      if f.check == "type-vs-class" and f.node == node_id then
        return f
      end
    end
    return nil
  end

  -- Node ids are the real path key `scan.scan` assigns ("lua/t/bad"), not
  -- the dotted `@module` name ("t.bad") — the two only coincide by luck
  -- for a top-level module.
  local bad = by_node("lua/t/bad")
  ok(bad ~= nil, "check.type-vs-class: fires for @type + real exported fields")
  eq(
    bad.severity,
    "warn",
    "check.type-vs-class: warn severity, matching dead-see-target's own class"
  )
  ok(
    bad.message:find("RateLimits", 1, true) ~= nil,
    "check.type-vs-class: names the real @type value in the message"
  )
  ok(
    bad.message:find("t.bad", 1, true) ~= nil or bad.message:find("M :", 1, true) ~= nil,
    "check.type-vs-class: message points at the real module/class shape to use instead"
  )

  eq(
    by_node("lua/t/good"),
    nil,
    "check.type-vs-class: does NOT fire for the correct ---@class pattern"
  )
  eq(
    by_node("lua/t/empty"),
    nil,
    "check.type-vs-class: does NOT fire for @type with no fields ever assigned"
  )
  eq(by_node("lua/t/plain"), nil, "check.type-vs-class: an unannotated module is unaffected")
end
