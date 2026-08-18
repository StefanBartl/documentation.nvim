-- TESTS/unused_require_spec.lua — check.lua's `unused-require`
--
-- The mirror of `require-not-declared`: that one finds a dependency used
-- without being declared, this one finds one declared without being used.
--
-- The last case below is the one worth having. The reference count is
-- deliberately coarse — a mention in a comment counts as a use — and that is
-- not an accident to be fixed later but the direction this check chooses to
-- be wrong in. It was written into the fixture by accident first: an earlier
-- version of this spec named its dead binding `dead` and described the module
-- as "one dead require", so the comment referenced the alias and the check
-- correctly stayed quiet.

return function(H)
  local eq = H.eq

  local root = (vim.fn.tempname():gsub("\\", "/"))
  local n = 0

  ---@param files table<string, string>
  ---@return string[] messages
  local function findings(files)
    n = n + 1
    local abs = ("%s/case%d"):format(root, n)
    for rel, body in pairs(files) do
      local path = abs .. "/" .. rel
      vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
      local fd = io.open(path, "w")
      if fd then
        fd:write(body)
        fd:close()
      end
    end
    local opts = require("documentation.config").build(abs)
    local ir = require("documentation.core.scan").scan(opts)
    local out = {}
    for _, f in ipairs(require("documentation.core.check").run(ir, opts)) do
      if f.check == "unused-require" then
        out[#out + 1] = f.message
      end
    end
    table.sort(out)
    return out
  end

  local HELPER = "---@module 'u.helper'\n--- Helper.\nreturn { value = function() return 1 end }\n"

  -- The case it exists for.
  do
    local found = findings({
      ["lua/u/init.lua"] = "---@module 'u'\n--- Root.\n"
        .. 'local kept = require("u.helper")\n'
        .. 'local leftover = require("u.helper")\n'
        .. "local M = {}\nfunction M.go() return kept.value() end\nreturn M\n",
      ["lua/u/helper.lua"] = HELPER,
    })
    eq(#found, 1, "unused-require: the binding that is never mentioned again is reported")
    eq(
      found[1]:find("leftover", 1, true) ~= nil,
      true,
      "unused-require: ... and it is the unused one, not the used one"
    )
  end

  -- A require with no binding is a load for its side effects — a real and
  -- deliberate pattern, and the one shape that cannot be wrong.
  do
    local found = findings({
      ["lua/u/init.lua"] = "---@module 'u'\n--- Root.\n"
        .. 'require("u.helper")\n'
        .. "return {}\n",
      ["lua/u/helper.lua"] = HELPER,
    })
    eq(#found, 0, "unused-require: a bare require has no alias and is never reported")
  end

  -- Used as a value rather than called. `local_refs` makes the same
  -- allowance for functions, for the same reason: passing something is using
  -- it, and a checker that only understands calls would say otherwise.
  do
    local found = findings({
      ["lua/u/init.lua"] = "---@module 'u'\n--- Root.\n"
        .. 'local helper = require("u.helper")\n'
        .. "local M = {}\nM.exported = helper\nreturn M\n",
      ["lua/u/helper.lua"] = HELPER,
    })
    eq(#found, 0, "unused-require: a binding used as a value, never called, is used")
  end

  -- The deliberate imprecision, locked in so nobody "fixes" it into a
  -- stricter check that starts reporting live code.
  do
    local found = findings({
      ["lua/u/init.lua"] = "---@module 'u'\n--- Root.\n"
        .. 'local helper = require("u.helper")\n'
        .. "-- helper is kept for a rewrite that is still in progress\n"
        .. "return {}\n",
      ["lua/u/helper.lua"] = HELPER,
    })
    eq(
      #found,
      0,
      "unused-require: a mention in a comment counts as a use, erring toward keeping the line"
    )
  end

  vim.fn.delete(root, "rf")
end
