---@module 'scripts.affected_specs'
--- Which specs does a change touch? The command-line face of
--- `documentation.testing.affected_specs` (contract: docs/testing-contract.md).
---
---   nvim --headless -l scripts/affected_specs.lua --changed lua/a.lua,lua/b.lua
---   nvim --headless -l scripts/affected_specs.lua --since origin/main
---   nvim --headless -l scripts/affected_specs.lua --since HEAD --verify --consumers ..
---
--- Options:
---   --root <dir>       repository to ask about (default: the current directory)
---   --changed a,b      comma-separated changed files
---   --since <rev>      also the files changed between <rev> and the working tree
---   --spec-root <p>    an extra spec directory or file (repeatable)
---   --consumers <dir>  directory of sibling checkouts (cross-repository answer)
---   --verify           settle "stale" by a rescan instead of by git history
---
--- Prints the answer as one JSON document on stdout. Exit code 0: an answer was
--- produced (read `complete` and `graph.stale` before trusting a narrowed
--- selection); 2: no answer is possible (bad option, no module map), the reason
--- on stderr. A caller that gets 2 runs everything.

local start = vim.uv.cwd():gsub("\\", "/"):gsub("/+$", "")

---Put a dependency on the runtimepath, if it is not already reachable (same
---candidate order as `gen_map.lua`: `$<NAME>_DIR`, `.deps/<name>`, a sibling).
---@param modname string
---@param dirname string
local function ensure(modname, dirname)
  if pcall(require, modname) then
    return
  end
  local candidates = {}
  local env_dir = vim.env[dirname:upper():gsub("[.-]", "_") .. "_DIR"]
  if env_dir and env_dir ~= "" then
    candidates[#candidates + 1] = env_dir
  end
  candidates[#candidates + 1] = start .. "/.deps/" .. dirname
  candidates[#candidates + 1] = vim.fs.dirname(start) .. "/" .. dirname
  for _, dir in ipairs(candidates) do
    if vim.fn.isdirectory(dir) == 1 then
      vim.opt.runtimepath:prepend(dir)
      if pcall(require, modname) then
        return
      end
    end
  end
  io.stderr:write(
    ("affected_specs: %s not found (probed require('%s')).\n"):format(dirname, modname)
  )
  os.exit(2)
end

-- This script lives in the plugin's own checkout: put that on the rtp first.
local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/scripts/[^/]*$")
if here then
  vim.opt.runtimepath:prepend(here)
end
ensure("lib.nvim.fs.read", "lib.nvim")
ensure("documentation.testing", "documentation.nvim")

local opts = { root = start, changed = {}, spec_roots = {} }
local argv = _G.arg or {}
local i = 1
---@param flag string
---@return string
local function value(flag)
  i = i + 1
  local v = argv[i]
  if v == nil or v:sub(1, 2) == "--" then
    io.stderr:write(("affected_specs: %s needs a value\n"):format(flag))
    os.exit(2)
  end
  return v
end
while i <= #argv do
  local a = argv[i]
  if a == "--root" then
    opts.root = value(a)
  elseif a == "--changed" then
    for f in value(a):gmatch("[^,]+") do
      opts.changed[#opts.changed + 1] = f
    end
  elseif a == "--since" then
    opts.since = value(a)
  elseif a == "--spec-root" then
    opts.spec_roots[#opts.spec_roots + 1] = value(a)
  elseif a == "--consumers" then
    opts.consumers = value(a)
  elseif a == "--verify" then
    opts.verify = true
  else
    io.stderr:write(("affected_specs: unknown argument %q\n"):format(a))
    os.exit(2)
  end
  i = i + 1
end
if #opts.spec_roots == 0 then
  opts.spec_roots = nil
end

local result, err = require("documentation.testing").affected_specs(opts)
if not result then
  io.stderr:write(tostring(err) .. "\n")
  os.exit(2)
end
io.stdout:write(require("documentation.core.json").encode(result), "\n")
os.exit(0)
