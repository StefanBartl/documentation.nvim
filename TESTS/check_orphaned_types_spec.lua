-- TESTS/check_orphaned_types_spec.lua — the `orphaned-class-alias` check in
-- `core/check.lua`.
--
-- **`types_detail` is injected rather than produced by
-- `lua-language-server`,** and that is the point of the design rather than a
-- shortcut. The check's contract begins at `node.types_detail`: given the
-- types and the files, find the ones nothing names. Driving it through a
-- real `--doc` run would make this spec skip on every machine without the
-- server installed — which is CI — and a spec that always skips is not a
-- gate. `luals_spec.lua` is where the parsing of real `--doc` output is
-- tested; this is where the *rule* is.
--
-- The substring fixture below is a real regression. The first version of
-- this check asked `line:find(name)`, so `T.Orphan` counted as referenced
-- by every mention of `T.Orphan.Inner`. Measured against lib.nvim, that one
-- difference hid four genuine orphans out of twenty-eight.

return function(H)
  local fmsg = require("documentation.core.findings").format
  local eq, ok = H.eq, H.ok
  local scan = require("documentation.core.scan")
  local check = require("documentation.core.check")

  local dr = H.tmpfile("_orphan_types")
  local function dwrite(rel, lines)
    local abs = dr .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "orphaned-types spec: fixture must be writable")
    fd:write(table.concat(lines, "\n"))
    fd:close()
  end

  dwrite("lua/t/a/@types/init.lua", {
    "---@meta",
    "---@module 't.a.@types'",
    "",
    "---@class T.Used",
    "---@field x string",
    "",
    "---@alias T.Base string",
    "",
    "---@class T.Child : T.Base",
    "---@field y string",
    "",
    "---@class T.Orphan",
    "---@field z string",
    "",
    "---@class T.Orphan.Inner",
    "---@field w string",
    "",
    "return {}",
  })

  dwrite("lua/t/a/init.lua", {
    "---@module 't.a'",
    "--- A module that names some of its own types.",
    "local M = {}",
    "---Take a few typed things.",
    "---@param used T.Used",
    "---@param child T.Child",
    "---@param inner T.Orphan.Inner",
    "function M.take(used, child, inner)",
    "  return used, child, inner",
    "end",
    "return M",
  })

  local ir = scan.scan({ root = dr, source = "lua/t", lua_root = "lua" })
  local node = ir.nodes["lua/t/a"]
  ok(node ~= nil, "orphaned-class-alias: the fixture module is scanned")
  ok(
    #(node.types or {}) > 0,
    "orphaned-class-alias: the @types file is part of the node, and therefore "
      .. "part of the corpus this check reads references from"
  )

  local function T(name, kind)
    return {
      name = name,
      kind = kind,
      desc = "",
      file = "lua/t/a/@types/init.lua",
      fields = {},
      extends = {},
    }
  end
  node.types_detail = {
    T("T.Used", "class"),
    T("T.Base", "alias"),
    T("T.Child", "class"),
    T("T.Orphan", "class"),
    T("T.Orphan.Inner", "class"),
  }

  local opts = { root = dr, source = "lua/t", lua_root = "lua", extra_checks = {} }
  local findings = check.run(ir, opts)

  local mine = {}
  for _, f in ipairs(findings) do
    if f.check == "orphaned-class-alias" then
      mine[#mine + 1] = f
    end
  end

  local function reported(name)
    for _, f in ipairs(mine) do
      if fmsg(f):find(" " .. name .. " ", 1, true) then
        return f
      end
    end
    return nil
  end

  local orphan = reported("T.Orphan")
  ok(orphan ~= nil, "orphaned-class-alias: fires for a type nothing references")
  eq(
    orphan.severity,
    "info",
    "orphaned-class-alias: info, matching unreferenced-module — a published type "
      .. "may legitimately be referenced only by a consumer outside this tree"
  )
  eq(orphan.node, "lua/t/a", "orphaned-class-alias: attributed to the node that owns the file")
  ok(
    fmsg(orphan):find("lua/t/a/@types/init.lua", 1, true) ~= nil,
    "orphaned-class-alias: names the file the type is declared in"
  )

  eq(reported("T.Used"), nil, "orphaned-class-alias: a type named in a @param is referenced")
  eq(
    reported("T.Orphan.Inner"),
    nil,
    "orphaned-class-alias: and so is the nested one, which is why T.Orphan is still "
      .. "reported — a substring match would have credited it here"
  )
  eq(
    reported("T.Base"),
    nil,
    "orphaned-class-alias: a parent named only on a `---@class Child : Parent` line "
      .. "is referenced — dropping the whole declaration line would orphan every base class"
  )

  eq(#mine, 1, "orphaned-class-alias: exactly one finding across the whole fixture")

  -- The gate that keeps a plain `:DocMap` quiet. `types_detail = nil` means
  -- LuaLS never ran, and reporting every type in the tree as an orphan then
  -- would be a wrong answer rather than a low one.
  node.types_detail = nil
  local without = check.run(ir, opts)
  local still = 0
  for _, f in ipairs(without) do
    if f.check == "orphaned-class-alias" then
      still = still + 1
    end
  end
  eq(still, 0, "orphaned-class-alias: silent when LuaLS enrichment did not run")
end
