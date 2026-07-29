-- TESTS/run.lua — headless test runner for documentation.nvim.
--
-- Run from the repo root:
--   nvim --headless -u NONE -l TESTS/run.lua
--
-- Loads every *_spec.lua listed below, runs it against the shared harness,
-- prints a per-spec result, and exits non-zero on the first failing spec.

-- Make the repo importable whether invoked via -l (cwd) or luafile.
vim.opt.rtp:append(vim.fn.getcwd())

-- lib.nvim is a runtime dependency (notify, fs, ui.kit, usercmd, …), so the
-- specs cannot run without it on the rtp. Three ways it can be found, in
-- descending order of explicitness — CI uses the first, a local checkout the
-- second, an installed plugin manager the third (already on the rtp, so
-- nothing to do). Failing loudly here beats a `module 'lib.nvim.fs' not found`
-- twenty lines into an unrelated-looking spec.
local function add_lib_nvim()
  if pcall(require, "lib.nvim.fs.read") then
    return
  end
  local candidates = {
    vim.env.LIB_NVIM_DIR,
    vim.fn.getcwd() .. "/.deps/lib.nvim",
    vim.fs.dirname(vim.fn.getcwd()) .. "/lib.nvim",
  }
  for _, dir in ipairs(candidates) do
    if dir and vim.fn.isdirectory(dir) == 1 then
      vim.opt.rtp:append(dir)
      if pcall(require, "lib.nvim.fs.read") then
        return
      end
    end
  end
  io.stderr:write("TESTS/run.lua: lib.nvim not found.\n")
  io.stderr:write("  Set LIB_NVIM_DIR, or clone it to .deps/lib.nvim, or beside this repo.\n")
  os.exit(1)
end

add_lib_nvim()

local dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local H = dofile(dir .. "harness.lua")

local specs = {
  "docmap_spec.lua",
  "docmap_browse_spec.lua",
}

--- Straight to stdout rather than through `print`.
---
--- `print` in a headless Neovim goes through the message area, and a spec that
--- opens a window forces a redraw that swallows the pending newline — two spec
--- results then run together on one line, which is exactly as confusing as it
--- sounds when a run is being read for a failure. `docmap_browse_spec` mounts
--- real floats, so this is not hypothetical. A headless runner's output is
--- meant to be read by a person or a log, not rendered in a UI.
---@param s string
local function say(s)
  io.stdout:write(s, "\n")
end

local failed = 0
for _, name in ipairs(specs) do
  local run = dofile(dir .. name)
  local ok, err = pcall(run, H)
  if ok then
    say(("ok    %s"):format(name))
  else
    failed = failed + 1
    say(("FAIL  %s\n      %s"):format(name, tostring(err)))
  end
end

if failed > 0 then
  say(("\n%d spec(s) failed"):format(failed))
  os.exit(1)
end

say("\nDOCUMENTATION_TESTS_OK")
