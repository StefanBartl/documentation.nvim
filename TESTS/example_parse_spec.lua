-- TESTS/example_parse_spec.lua — check.lua's `example-does-not-parse`
--
-- The second case is the one that matters. An `@example` is as often a
-- fragment as a statement, and a version of this check that only tried to
-- parse a chunk would report `{ timeout = 5000 }` — the most ordinary shape
-- of example there is — as broken.
--
-- Worth knowing while reading this file: no tree in this ecosystem uses
-- `@example` at all (zero blocks in this repository, none in the thirty-odd
-- sibling plugins), so these fixtures are the only evidence this check has.

return function(H)
  local eq = H.eq

  local root = (vim.fn.tempname():gsub("\\", "/"))
  local n = 0

  ---@param body string The module body, appended after a `@module` header.
  ---@return string[] messages
  local function findings(body)
    n = n + 1
    local abs = ("%s/case%d"):format(root, n)
    local path = abs .. "/lua/e/init.lua"
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    local fd = io.open(path, "w")
    if fd then
      fd:write("---@module 'e'\n--- Examples.\nlocal M = {}\n" .. body .. "\nreturn M\n")
      fd:close()
    end
    local opts = require("documentation.config").build(abs)
    local ir = require("documentation.core.scan").scan(opts)
    local out = {}
    for _, f in ipairs(require("documentation.core.check").run(ir, opts)) do
      if f.check == "example-does-not-parse" then
        out[#out + 1] = f.message
      end
    end
    return out
  end

  eq(
    #findings("---Fine.\n---@example\n--- local x = M.a()\nfunction M.a() end"),
    0,
    "example-does-not-parse: a valid statement is not reported"
  )

  eq(
    #findings("---Fine.\n---@example\n--- { timeout = 5000 }\nfunction M.b() end"),
    0,
    "example-does-not-parse: a fragment that is only an expression is not reported"
  )

  eq(
    #findings("---Fine.\n---@example\n--- M.c(1, 2)\nfunction M.c() end"),
    0,
    "example-does-not-parse: a bare call statement is not reported"
  )

  local broken = findings("---Broken.\n---@example\n--- local y = M.d(\nfunction M.d() end")
  eq(#broken, 1, "example-does-not-parse: unbalanced syntax is reported")
  eq(
    broken[1]:find("M.d", 1, true) ~= nil,
    true,
    "example-does-not-parse: ... naming the function whose example it is"
  )

  eq(
    #findings("---No example at all.\nfunction M.e() end"),
    0,
    "example-does-not-parse: a function without an @example is not reported"
  )

  vim.fn.delete(root, "rf")
end
