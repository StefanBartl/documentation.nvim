std = "luajit"
max_line_length = false

globals = {
  "vim",
}

read_globals = {
  -- Neovim's bundled LuaJIT ships 5.2-style table.pack/unpack and math.type
  -- as compat shims; luacheck's stock luajit std predates them.
  table = { fields = { "pack", "unpack" } },
  math = { fields = { "type" } },
}

-- 212: unused argument — a check signature is `fun(ir, opts)` whether or not
-- a given check reads `opts`, and keeping the parameter documents the
-- contract better than eliding it.
-- 542: empty if/else branch — used deliberately as a documented no-op.
ignore = {
  "212/self",
  "212/_.*",
  "542",
}

exclude_files = {
  -- Pure `---@meta` LuaCATS annotation scaffolding: `local x ---@type T` /
  -- `return {}` patterns luacheck has no way to know are intentional.
  "**/@types/**",
  -- Vendored dependency checkout used by CI and the headless runners.
  ".deps/**",
}
