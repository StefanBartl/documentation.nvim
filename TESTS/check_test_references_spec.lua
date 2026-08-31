-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/check_test_references_spec.lua — the `test-references-missing`
-- check in `core/check.lua`.
--
-- Its own file for the same reason `check_type_vs_class_spec.lua` has one:
-- this check reads real files from disk on both sides — the spec tree it
-- parses and the module source it reads a surface from — which the fake-IR
-- fixtures in `docmap_spec.lua` cannot exercise.
--
-- **Every negative case here is a false positive that was actually
-- measured**, not one imagined while writing the check. Run against three
-- real repositories, the first version of this check produced nine
-- findings and all nine were wrong: four re-exports, five runtime-assembled
-- surfaces, and one shadowing local. Those three shapes are the three
-- `must not fire` fixtures below, so a future simplification that looks
-- harmless fails here instead of on somebody's repository.

return function(H)
  local fmsg = require("documentation.core.findings").format
  local eq, ok = H.eq, H.ok
  local scan = require("documentation.core.scan")
  local check = require("documentation.core.check")

  local dr = H.tmpfile("_test_refs")
  local function dwrite(rel, lines)
    local abs = dr .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "test-references spec: fixture must be writable")
    fd:write(table.concat(lines, "\n"))
    fd:close()
  end

  -- An ordinary module: a declared function, a module-scope constant, and
  -- a re-export by assignment. All three are real members.
  dwrite("lua/t/mod/init.lua", {
    "---@module 't.mod'",
    "--- An ordinary module.",
    "local M = {}",
    "M.CONST = 1",
    "M.reexport = require('t.other').alive",
    "---A real export.",
    "function M.alive()",
    "  return true",
    "end",
    "return M",
  })

  dwrite("lua/t/other/init.lua", {
    "---@module 't.other'",
    "--- The re-export's source.",
    "local M = {}",
    "---A real export.",
    "function M.alive()",
    "  return true",
    "end",
    "return M",
  })

  -- A surface assembled at runtime: a lazy `__index` can answer for names
  -- that appear nowhere in the source.
  dwrite("lua/t/dyn/init.lua", {
    "---@module 't.dyn'",
    "--- A module with a lazy __index.",
    "local M = {}",
    "return setmetatable(M, {",
    "  __index = function(_, k)",
    "    return require('t.other')[k]",
    "  end,",
    "})",
  })

  -- The other runtime shape: the exported table is a call's result, so
  -- nothing static can enumerate it. This is `lib.nvim`'s `Path`, which
  -- gets its `new` from a class factory.
  dwrite("lua/t/factory/init.lua", {
    "---@module 't.factory'",
    "--- A module whose table comes from a factory.",
    "local P = require('t.other').build()",
    "return P",
  })

  dwrite("SPECS/good_spec.lua", {
    "local mod = require('t.mod')",
    "return function()",
    "  mod.alive()",
    "  return mod.CONST, mod.reexport",
    "end",
  })

  dwrite("SPECS/gone_spec.lua", {
    "local mod = require('t.mod')",
    "return function()",
    "  return mod.removed",
    "end",
  })

  -- The measured shadowing case: a local inside a function body reusing
  -- the name the file bound at chunk level.
  dwrite("SPECS/shadow_spec.lua", {
    "local mod = require('t.mod')",
    "return function()",
    "  local mod = { removed = 1 }",
    "  return mod.removed",
    "end",
  })

  dwrite("SPECS/dynamic_spec.lua", {
    "local dyn = require('t.dyn')",
    "local fac = require('t.factory')",
    "return function()",
    "  return dyn.anything, fac.new",
    "end",
  })

  local ir = scan.scan({ root = dr, source = "lua/t", lua_root = "lua" })
  local opts = {
    root = dr,
    source = "lua/t",
    lua_root = "lua",
    tests_dir = "SPECS",
    extra_checks = {},
  }
  local findings = check.run(ir, opts)

  local mine = {}
  for _, f in ipairs(findings) do
    if f.check == "test-references-missing" then
      mine[#mine + 1] = f
    end
  end

  local function in_file(name)
    for _, f in ipairs(mine) do
      if fmsg(f):find(name, 1, true) then
        return f
      end
    end
    return nil
  end

  -- The positive control. Without it the whole check is unproven: measured
  -- across three real repositories it fires zero times, which is the right
  -- answer for a healthy tree and no evidence at all that it works.
  local gone = in_file("gone_spec.lua")
  ok(gone ~= nil, "test-references-missing: fires on a spec naming a function that is gone")
  ---@cast gone -nil
  eq(
    gone.severity,
    "warn",
    "test-references-missing: warn, matching doc-references-missing's own class"
  )
  ok(
    fmsg(gone):find("removed", 1, true) ~= nil and fmsg(gone):find("t.mod", 1, true) ~= nil,
    "test-references-missing: names both the missing member and the module"
  )
  eq(gone.node, "lua/t/mod", "test-references-missing: attributed to the module, not the spec")

  eq(in_file("good_spec.lua"), nil, "test-references-missing: a declared function is a member")

  -- Each of the three below is a measured false positive, not a
  -- hypothetical one.
  ok(
    not (fmsg(gone):find("CONST", 1, true) or fmsg(gone):find("reexport", 1, true)),
    "test-references-missing: a constant and a re-export by assignment are members"
  )
  eq(
    in_file("shadow_spec.lua"),
    nil,
    "test-references-missing: a name bound twice in one file is not reasoned about — "
      .. "the shadowing local measured in runtime-analysis.nvim"
  )
  eq(
    in_file("dynamic_spec.lua"),
    nil,
    "test-references-missing: a module whose surface is built at runtime is left alone — "
      .. "the lazy __index and the class factory both measured in lib.nvim"
  )

  eq(#mine, 1, "test-references-missing: exactly one finding across the whole fixture")
end
