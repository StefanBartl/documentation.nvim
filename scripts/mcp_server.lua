---@module 'scripts.mcp_server'
--- MCP server entry point for this repository's own module map.
---
---   nvim --headless -l scripts/mcp_server.lua
---
--- Not meant to be run by hand — an MCP client spawns it as a subprocess and
--- talks JSON-RPC over its stdin/stdout. Run interactively it looks like it
--- has hung, because it is doing exactly what it should: waiting for a line.
---
--- Thin on purpose, same as `gen_map.lua`: everything that is not this
--- repository's own layout lives in `documentation.mcp`, so another plugin
--- copies this file and changes only the options at the bottom.

local root = vim.uv.cwd():gsub("\\", "/"):gsub("/+$", "")
vim.opt.runtimepath:prepend(root)

--- Put a dependency on the runtimepath, if it is not already reachable.
--- Same three candidates, same order, and the same reason as `gen_map.lua`'s
--- copy: a headless `nvim -l` run starts with no plugin manager.
---@param modname string A module the dependency provides, used as the probe.
---@param dirname string Repository directory name.
local function ensure(modname, dirname)
  if pcall(require, modname) then
    return
  end
  local candidates = {}
  local env_dir = vim.env[dirname:upper():gsub("[.-]", "_") .. "_DIR"]
  if env_dir and env_dir ~= "" then
    candidates[#candidates + 1] = env_dir
  end
  candidates[#candidates + 1] = root .. "/.deps/" .. dirname
  candidates[#candidates + 1] = vim.fs.dirname(root) .. "/" .. dirname
  for _, dir in ipairs(candidates) do
    if vim.fn.isdirectory(dir) == 1 then
      vim.opt.runtimepath:prepend(dir)
      if pcall(require, modname) then
        return
      end
    end
  end
  -- stderr, not stdout: stdout is the protocol channel from the first byte.
  io.stderr:write(("mcp_server: %s not found (probed require('%s')).\n"):format(dirname, modname))
  os.exit(1)
end

ensure("lib.nvim.fs.read", "lib.nvim")
ensure("documentation.mcp", "documentation.nvim")

-- Anything that notifies during the scan must not land on stdout, which
-- carries JSON-RPC and nothing else. Headless Neovim already routes most
-- messages to stderr, but `vim.notify` is a public hook any module on the
-- runtimepath may have replaced, so pinning it here is cheap insurance
-- against one stray write corrupting every subsequent client parse.
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function(msg, _, _)
  io.stderr:write(tostring(msg), "\n")
end

local opts = require("documentation.config").build(root, {
  source = "lua/documentation",
  title = "documentation.nvim",
})

os.exit(require("documentation.mcp").serve(opts))
