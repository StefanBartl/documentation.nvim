-- TESTS/annotate_spec.lua — `core/annotate.lua`, the `:DocMap annotate`
-- header generator.
--
-- Real files on disk, same reason as check_type_vs_class_spec.lua: this
-- module re-reads each candidate file itself (to find the `local M = {}`
-- anchor and the exported fields' own source lines), which a fake-IR
-- fixture cannot exercise.

return function(H)
  local eq, ok = H.eq, H.ok
  local scan = require("documentation.core.scan")
  local annotate = require("documentation.core.annotate")

  local dr = H.tmpfile("_annotate")
  local function dwrite(rel, lines)
    local abs = dr .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    -- Binary mode: this spec byte-compares before/after `apply`, and text
    -- mode's "\n" -> "\r\n" rewrite on Windows would otherwise desync the
    -- fixture from the `lib.nvim.fs.read`/`write.to_file` pair `annotate.lua`
    -- itself uses, which are binary for the same reason.
    local fd = assert(io.open(abs, "wb"), "annotate spec: fixture must be writable")
    fd:write(table.concat(lines, "\n"))
    fd:close()
  end

  -- No @module, table export, one function and one plain table field.
  dwrite("lua/t/nohdr/init.lua", {
    "local M = {}",
    "",
    "---@param path string",
    "---@return boolean",
    "function M.foo(path)",
    "  return true",
    "end",
    "",
    "M.cfg = {}",
    "",
    "return M",
  })

  -- No @module, table export, a field whose own assignment already carries
  -- a ---@class — must be referenced, not replaced with a bare "table".
  dwrite("lua/t/withclass/init.lua", {
    "local M = {}",
    "",
    "---@class t.withclass.RateLimits",
    "---@field per_minute integer",
    "M.rate_limits = { per_minute = 60 }",
    "",
    "return M",
  })

  -- No @module, function export — no module table to describe, so no
  -- ---@class/---@field block, only the bare header.
  dwrite("lua/t/fnexport/init.lua", {
    "return function(x)",
    "  return x + 1",
    "end",
  })

  -- Already has @module — must never be a candidate.
  dwrite("lua/t/hasmodule/init.lua", {
    "---@module 't.hasmodule'",
    "--- Already documented.",
    "local M = {}",
    "function M.bar()",
    "end",
    "return M",
  })

  local ir = scan.scan({ root = dr, source = "lua/t", lua_root = "lua" })

  -- candidates()
  local ids = {}
  for _, node in ipairs(annotate.candidates(ir)) do
    ids[node.id] = true
  end
  ok(ids["lua/t/nohdr"], "annotate.candidates: includes a table-export file with no @module")
  ok(ids["lua/t/withclass"], "annotate.candidates: includes a file with class-annotated fields")
  ok(ids["lua/t/fnexport"], "annotate.candidates: includes a function-export file with no @module")
  ok(not ids["lua/t/hasmodule"], "annotate.candidates: excludes a file that already has @module")

  local function node_by_id(id)
    return ir.nodes[id]
  end

  -- plan(): plain fields
  local plan_nohdr = assert(
    annotate.plan(node_by_id("lua/t/nohdr"), dr, "lua"),
    "annotate.plan: builds a plan for the plain fixture"
  )
  eq(plan_nohdr.module, "t.nohdr", "annotate.plan: derives the dotted module name from the path")
  eq(plan_nohdr.anchor, 1, "annotate.plan: anchors on the first line (`local M = {}` is line 1)")
  ok(plan_nohdr.has_class, "annotate.plan: generates a class block when fields exist")
  local header_nohdr = table.concat(plan_nohdr.header, "\n")
  ok(
    header_nohdr:find("---@module 't.nohdr'", 1, true) ~= nil,
    "annotate.plan: header opens with the derived ---@module line"
  )
  ok(
    header_nohdr:find("---@class t.nohdr", 1, true) ~= nil,
    "annotate.plan: header declares a ---@class named after the module"
  )
  ok(
    header_nohdr:find("---@field foo fun(path: string): boolean", 1, true) ~= nil,
    "annotate.plan: reconstructs a fun(...) type from the function's own @param/@return"
  )
  ok(
    header_nohdr:find("---@field cfg table", 1, true) ~= nil,
    "annotate.plan: falls back to `table` for an untyped table field"
  )

  -- plan(): referenced class
  local plan_withclass = assert(
    annotate.plan(node_by_id("lua/t/withclass"), dr, "lua"),
    "annotate.plan: builds a plan for the withclass fixture"
  )
  local header_withclass = table.concat(plan_withclass.header, "\n")
  ok(
    header_withclass:find("---@class t.withclass", 1, true) ~= nil,
    "annotate.plan: still declares the module's own ---@class"
  )
  ok(
    header_withclass:find("---@field rate_limits t.withclass.RateLimits", 1, true) ~= nil,
    "annotate.plan: references an already-declared ---@class instead of writing `table`"
  )
  ok(
    header_withclass:find("---@field per_minute", 1, true) == nil,
    "annotate.plan: does not pull the referenced class's own fields into M's field list"
  )

  -- plan(): function export, no class block
  local plan_fn = assert(
    annotate.plan(node_by_id("lua/t/fnexport"), dr, "lua"),
    "annotate.plan: builds a plan for the fnexport fixture"
  )
  eq(plan_fn.anchor, nil, "annotate.plan: no anchor for a function-export file")
  eq(plan_fn.has_class, false, "annotate.plan: no class block for a function-export file")
  eq(#plan_fn.header, 2, "annotate.plan: header is just @module + the TODO line")

  -- Binary reads throughout, matching `dwrite` above and the binary
  -- `lib.nvim.fs.read`/`write.to_file` pair `annotate.lua` itself uses.
  local function dread(path)
    local fd = io.open(path, "rb")
    if not fd then
      return nil
    end
    local content = fd:read("*a")
    fd:close()
    return content
  end

  -- apply(): sidecar never touches the original file.
  local before = assert(dread(dr .. "/lua/t/nohdr/init.lua"))
  local ok_sidecar = annotate.apply(plan_nohdr, dr, "sidecar")
  ok(ok_sidecar, "annotate.apply(sidecar): reports success")
  ok(
    dread(dr .. "/lua/t/nohdr/init.lua.annot.lua") ~= nil,
    "annotate.apply(sidecar): writes the *.annot.lua file"
  )
  local after = assert(dread(dr .. "/lua/t/nohdr/init.lua"))
  eq(before, after, "annotate.apply(sidecar): the original file is byte-for-byte untouched")

  -- apply(): inline splices above the anchor and leaves the code below it
  -- byte-for-byte identical.
  local ok_inline = annotate.apply(plan_nohdr, dr, "inline")
  ok(ok_inline, "annotate.apply(inline): reports success")
  local written = assert(dread(dr .. "/lua/t/nohdr/init.lua"))
  ok(
    written:find("---@module 't.nohdr'", 1, true) ~= nil,
    "annotate.apply(inline): the header is now in the real file"
  )
  local original_tail = table.concat(plan_nohdr.lines, "\n"):match("local M = {}.*$")
  ok(
    written:find(original_tail, 1, true) ~= nil,
    "annotate.apply(inline): everything from `local M = {}` down is byte-for-byte unchanged"
  )
end
