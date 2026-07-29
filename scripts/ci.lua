-- scripts/ci.lua — every gate CI runs, as Lua rather than as shell.
--
--   nvim --headless -l scripts/ci.lua              all four, stopping at the first failure
--   nvim --headless -l scripts/ci.lua stylua       one gate
--   nvim --headless -l scripts/ci.lua luacheck
--   nvim --headless -l scripts/ci.lua tests
--   nvim --headless -l scripts/ci.lua map
--
-- Why this exists next to `ci.sh`: the plugin is cross-platform by
-- construction — no `io.popen`, no `os.execute`, `vim.system`/`vim.uv`/`vim.fs`
-- throughout — but its own tooling was not. `ci.sh` is bash and the pre-commit
-- hook is sh, so a Windows contributor's answer to "how do I run the checks"
-- was "install Git Bash". Neovim is already a hard requirement here; using it
-- as the script host costs nothing and removes that.
--
-- **What each gate is lives here and nowhere else.** `scripts/ci.sh` is now a
-- wrapper that calls this, and `.github/workflows/ci.yml` calls the wrapper —
-- so the four CI jobs keep their independent red/green marks and their
-- parallelism while the commands themselves exist once. A second copy that
-- drifts is precisely the failure this repository exists to detect.
--
-- The one gate that cannot come through here is stylua under GitHub Actions:
-- the action is both the installer and the runner, so there is no binary on
-- PATH to hand a script. Its `args` must stay identical to `run_stylua` below
-- — the whole tree, not a list of directories.

local root = vim.fn.getcwd():gsub("\\", "/"):gsub("/+$", "")

-- ANSI only when the output is going somewhere that renders it. A CI log
-- capturing stdout is fine with escapes; a Windows console pipe is not always.
local color = vim.env.NO_COLOR == nil
local function paint(code, s)
  return color and ("\27[" .. code .. "m" .. s .. "\27[0m") or s
end

local function say(s)
  io.stdout:write(s, "\n")
end

local function step(name)
  say("\n" .. paint("1", "== " .. name))
end

local function fail(msg)
  io.stderr:write(paint("31", msg) .. "\n")
  vim.cmd("cq 1")
end

---@param exe string
local function need(exe)
  if vim.fn.executable(exe) == 0 then
    fail(exe .. " is not on PATH.")
  end
end

---Run a command, streaming nothing but reporting everything.
---
---`vim.system(...):wait()` rather than `os.execute`: no shell, so no quoting
---rules that differ between cmd.exe and sh, which is the whole point of this
---file existing.
---@param cmd string[]
---@param label string
local function run(cmd, label)
  local proc = vim.system(cmd, { cwd = root, text = true }):wait()
  if proc.stdout and proc.stdout ~= "" then
    io.stdout:write(proc.stdout)
  end
  if proc.stderr and proc.stderr ~= "" then
    io.stderr:write(proc.stderr)
  end
  if proc.code ~= 0 then
    fail(("%s failed (exit %d)."):format(label, proc.code))
  end
end

---lib.nvim is a runtime dependency, and a headless `-l` run has no plugin
---manager to supply it. Resolved the same three ways `TESTS/run.lua` and
---`scripts/gen_map.lua` resolve it — checked here as well so the failure is one
---clear message instead of a Lua stack trace two stages in.
---@return boolean
local function have_lib_nvim()
  local candidates = {
    vim.env.LIB_NVIM_DIR,
    root .. "/.deps/lib.nvim",
    vim.fs.dirname(root) .. "/lib.nvim",
  }
  for _, d in ipairs(candidates) do
    if d and d ~= "" and vim.fn.isdirectory(d) == 1 then
      return true
    end
  end
  return false
end

local function need_lib_nvim()
  if not have_lib_nvim() then
    fail(
      "lib.nvim not found. Set LIB_NVIM_DIR, clone it to .deps/lib.nvim, or put it beside this repo."
    )
  end
end

local GATES = {}

function GATES.stylua()
  step("stylua")
  need("stylua")
  -- The whole tree, not a list of directories. The list form silently skipped
  -- docs/EXAMPLES/, which is how a file sat unformatted in it for as long as it
  -- existed while every local run reported clean.
  run({ "stylua", "--check", "." }, "stylua")
end

function GATES.luacheck()
  step("luacheck")
  need("luacheck")
  run({ "luacheck", "lua", "TESTS", "scripts" }, "luacheck")
end

function GATES.tests()
  step("tests")
  need("nvim")
  need_lib_nvim()
  run({ "nvim", "--headless", "-u", "NONE", "-l", "TESTS/run.lua" }, "tests")
end

function GATES.map()
  step("map --check")
  need("nvim")
  need_lib_nvim()
  run({ "nvim", "--headless", "-l", "scripts/gen_map.lua", "--check" }, "map --check")
end

-- The order is not cosmetic. A formatting failure is the cheapest one to find
-- and the least interesting; a stale map is the most likely to be a real
-- finding rather than a slip. Failing fast on the cheap one first means the
-- expensive checks only ever run on code that is already tidy.
local ORDER = { "stylua", "luacheck", "tests", "map" }

local stage = (_G.arg or {})[1] or "all"

if stage == "all" then
  for _, name in ipairs(ORDER) do
    GATES[name]()
  end
  say("\n" .. paint("32", "All four gates passed."))
elseif GATES[stage] then
  GATES[stage]()
else
  fail(
    ("Unknown stage '%s' (expected: %s, or nothing for all)."):format(
      stage,
      table.concat(ORDER, ", ")
    )
  )
end
