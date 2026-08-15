-- TESTS/bindings_spec.lua — `core/bindings.lua`, the keymap/user-command/
-- autocmd extractor, and its `opts.bindings.wrappers` declaration.
--
-- Runs the extractor against real parsed source rather than a stubbed tree:
-- the whole module is treesitter shape-matching, so a fixture that is not
-- actually parsed would test nothing that can break. Each case is written as
-- the source a config would really contain.

return function(H)
  local eq, ok = H.eq, H.ok
  local B = require("documentation.core.bindings")

  ---@param src string
  ---@return Documentation.BindingSpec[]
  local function extract(src)
    local root = vim.treesitter.get_string_parser(src, "lua"):parse()[1]:root()
    return B.extract(root, src)
  end

  local function reset()
    B.WRAPPERS = B.DEFAULT_WRAPPERS
  end

  -- ------------------------------------------------------------- built-ins
  do
    reset()
    local out = extract([[
vim.keymap.set("n", "<leader>x", function() end, { desc = "Do x" })
vim.keymap.set({ "n", "v" }, "gy", "y", { desc = "Yank" })
vim.api.nvim_create_user_command("Foo", function() end, { desc = "Foo it" })
vim.api.nvim_create_autocmd("BufWritePre", { desc = "Trim" })
]])
    eq(#out, 4, "bindings: the vim.* APIs are recognized with no configuration")

    eq(out[1].kind, "keymap", "bindings: vim.keymap.set is a keymap")
    eq(out[1].lhs, "<leader>x", "bindings: lhs is read as a literal")
    eq(out[1].desc, "Do x", "bindings: desc is read out of the options table")
    eq(
      table.concat(out[1].modes, ","),
      "n",
      "bindings: a single mode string becomes a one-item list"
    )

    eq(
      table.concat(out[2].modes, ","),
      "n,v",
      "bindings: a { 'n', 'v' } mode list is normalised the same way"
    )

    eq(out[3].kind, "usercmd", "bindings: nvim_create_user_command is a usercmd")
    eq(out[3].name, "Foo", "bindings: the command name is captured")

    eq(out[4].kind, "autocmd", "bindings: nvim_create_autocmd is an autocmd")
    eq(table.concat(out[4].events, ","), "BufWritePre", "bindings: the event is captured")
  end

  -- ------------------------------------------- wrappers are NOT guessed at
  do
    reset()
    local src = [[
map("n", "<leader>a", "x", { desc = "Wrapped" })
usercmd.create("Bar", function() end, { desc = "Wrapped cmd" })
]]
    eq(
      #extract(src),
      0,
      "bindings: an undeclared wrapper contributes nothing — `map` is also a list helper"
    )

    B.WRAPPERS = { map = "keymap", ["usercmd.create"] = "usercmd" }
    local out = extract(src)
    eq(#out, 2, "bindings: the same source yields bindings once the wrappers are declared")
    eq(out[1].lhs, "<leader>a", "bindings: a wrapper reuses the built-in argument layout")
    eq(out[1].callee, "map", "bindings: callee records what actually matched")
    eq(out[2].name, "Bar", "bindings: a dotted wrapper key matches the call text as written")
  end

  -- ------------------------------- a bare local alias is matched literally
  do
    -- Real shape from a real config: `local nvim_create_autocmd =
    -- api.nvim_create_autocmd`, then called bare. The alias is never traced
    -- (see the module header) — it matches only because the caller declared
    -- the name it is called by.
    reset()
    local src = [[
local nvim_create_autocmd = api.nvim_create_autocmd
nvim_create_autocmd("VimEnter", { desc = "Aliased" })
]]
    eq(#extract(src), 0, "bindings: a bare alias is invisible until declared")

    B.WRAPPERS = { nvim_create_autocmd = "autocmd" }
    local out = extract(src)
    eq(#out, 1, "bindings: declaring the alias name is what makes it visible")
    eq(out[1].desc, "Aliased", "bindings: and it parses like the API it aliases")
  end

  -- --------------------------------------------------- buffer-local shapes
  do
    reset()
    local out = extract([[
vim.api.nvim_buf_set_keymap(0, "n", "<leader>b", "x", { desc = "Buf" })
vim.keymap.set("n", "<leader>c", "x", { buffer = "0", desc = "Also buf" })
]])
    eq(#out, 2, "bindings: the buf_ variants are recognized")
    ok(out[1].buffer, "bindings: nvim_buf_set_keymap is buffer-local")
    eq(out[1].lhs, "<leader>b", "bindings: and its shifted argument layout still reads lhs")
    ok(out[2].buffer, "bindings: an explicit `buffer` in the options table counts too")
  end

  -- ------------------------------------ non-literals are left, not guessed
  do
    reset()
    local out = extract([[
vim.keymap.set("n", prefix .. "x", "y", { desc = "Computed" })
vim.keymap.set("n", "<leader>real", "y", { desc = "Literal" })
]])
    eq(#out, 1, "bindings: a computed lhs is dropped rather than guessed at")
    eq(out[1].lhs, "<leader>real", "bindings: the literal one is still collected")
  end

  -- --------------------------------------------------- nested call sites
  do
    reset()
    B.WRAPPERS = { map = "keymap" }
    local out = extract([[
local M = {}
function M.setup()
  vim.api.nvim_create_autocmd("FileType", {
    callback = function()
      map("n", "<leader>n", "x", { desc = "Nested" })
    end,
  })
end
return M
]])
    eq(#out, 2, "bindings: calls are found at any depth, not only at the top level")
  end

  -- --------------------------------------- an unknown layout is not honoured
  do
    reset()
    B.WRAPPERS = { map = "not_a_layout" }
    eq(
      #extract([[map("n", "<leader>z", "x")]]),
      0,
      "bindings: a wrapper naming a layout that does not exist is ignored, not crashed on"
    )
  end

  reset()
end
