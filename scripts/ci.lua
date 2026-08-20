-- scripts/ci.lua — every gate CI runs, as Lua rather than as shell.
--
--   nvim --headless -l scripts/ci.lua              all five, stopping at the first failure
--   nvim --headless -l scripts/ci.lua stylua       one gate
--   nvim --headless -l scripts/ci.lua luacheck
--   nvim --headless -l scripts/ci.lua tests
--   nvim --headless -l scripts/ci.lua map
--   nvim --headless -l scripts/ci.lua standalone
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
-- so the CI jobs keep their independent red/green marks and their
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

---Gates that ran but decided they could not.
---
---**The summary used to say "All 5 gates passed" when one of them had
---shrugged**, which is the whole defect this list exists for: on a machine
---without PUC Lua the `standalone` gate prints *skipped* and green still
---read as five-for-five. Three real defects reached a release behind that
---sentence, so the count is now honest about what actually ran.
---@type string[]
local skipped = {}

---Record a gate that could not run, and say why.
---
---Not a failure: a machine with Neovim and nothing else is the common local
---case, and failing there would make `scripts/ci.sh` unusable for exactly
---the people it exists to serve — which is how a gate gets switched off.
---What changes is that the skip is now *counted*, and that the reason is
---specific enough to act on.
---@param name string
---@param why string
local function skip(name, why)
  skipped[#skipped + 1] = name
  say("  " .. paint("33", "skipped: " .. why))
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
  -- Built with explicit indices, not a `{a, b, c}` literal fed to `ipairs`:
  -- `vim.env.LIB_NVIM_DIR` is `nil` on every run that does not set it —
  -- the normal case, including every CI job today — and a table literal
  -- with `nil` in its first slot makes `ipairs` stop immediately without
  -- ever looking at the slots after it. That silently skipped the
  -- `.deps/lib.nvim` candidate CI actually checks the dependency out to,
  -- so this reported "not found" on every single CI run regardless of
  -- whether the checkout succeeded.
  local candidates = {}
  if vim.env.LIB_NVIM_DIR and vim.env.LIB_NVIM_DIR ~= "" then
    candidates[#candidates + 1] = vim.env.LIB_NVIM_DIR
  end
  candidates[#candidates + 1] = root .. "/.deps/lib.nvim"
  candidates[#candidates + 1] = vim.fs.dirname(root) .. "/lib.nvim"
  for _, d in ipairs(candidates) do
    if vim.fn.isdirectory(d) == 1 then
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

---The first Lua 5.x interpreter on PATH that is not Neovim, or nil.
---
---`lua5.4` before `lua` because Debian-family images ship both and the bare
---name is often 5.1; this gate wants the *other* Lua from the one Neovim
---embeds, which is the entire point of it existing.
---@return string?
---A PUC Lua that can actually run the standalone build, or nil.
---
---**Being on `$PATH` is not the question; being able to `require` the two
---rocks the build needs is.** A machine can easily have more than one PUC
---Lua — this was found on one with 5.1 first on `$PATH` and `lfs`/`dkjson`
---installed for 5.4 — and picking by name alone hands the gate an
---interpreter that dies at its first `require`. That failure reads as a
---broken build rather than a missing dependency, and it makes the gate red
---before anyone has touched anything, which `GATES.standalone`'s own
---comment gives as the reason such a gate gets switched off.
---
---So each candidate is probed rather than assumed, and a machine with no
---usable interpreter takes the stated skip below instead of failing.
---@return string?
local function puc_lua()
  -- Which interpreters exist at all, kept apart from which of them work.
  -- "no PUC Lua here" and "a PUC Lua that cannot load the rocks" are
  -- different problems with different fixes, and one message for both sends
  -- half its readers looking for the wrong thing. Reported by the caller.
  local found = {}
  for _, exe in ipairs({ "lua5.4", "lua5.3", "lua" }) do
    if vim.fn.executable(exe) == 1 then
      found[#found + 1] = exe
      local probe = vim.system({ exe, "-e", "require('lfs') require('dkjson')" }):wait()
      if probe.code == 0 then
        return exe
      end
    end
  end
  return nil, found
end

---Which of the two rocks `exe` cannot load, in order.
---
---Probed one at a time rather than reusing the combined check above: the
---point of this is the *name*, and `require('lfs') require('dkjson')`
---failing tells you only that one of them did.
---@param exe string
---@return string[]
local function missing_rocks(exe)
  local out = {}
  for _, rock in ipairs({ "lfs", "dkjson" }) do
    local probe = vim.system({ exe, "-e", ("require('%s')"):format(rock) }):wait()
    if probe.code ~= 0 then
      out[#out + 1] = rock
    end
  end
  return out
end

--- The standalone build, run under a Lua that is **not** LuaJIT.
---
--- This gate exists because of a defect the other four could not see. The
--- artifact is byte-compared by `map --check` and by a pre-commit hook, and
--- two places rendered numbers host-dependently: LuaJIT writes an integral
--- float as `100`, PUC Lua 5.3+ as `100.0`. Every gate above runs inside
--- Neovim, so all four were green on a tree whose map a second Lua would have
--- called stale. Fixed in `core/json.lua` and `core/quicks.lua`; this is what
--- keeps it fixed.
---
--- Deliberately the **parser-less** build, needing only `lfs` and `dkjson`
--- rather than a `lua-tree-sitter` rock and a compiled grammar. The full
--- parity comparison (byte-identical to a Neovim run) needs both and is a
--- local gate instead — see `docs/ROADMAP/V1_EXTENSION/PORTABILITY.md`. Its
--- published rock has two packaging defects, and a gate that is red before
--- anyone touches anything gets switched off the same day, which is exactly
--- the advice `docs/REUSE.md` gives about extra checks.
---
--- Writes to a temporary directory, never `docs/map`: a gate that rewrites
--- the artifact it is checking is not a gate.
function GATES.standalone()
  step("standalone (non-LuaJIT host)")
  local lua, found = puc_lua()
  if not lua then
    -- Two different situations, and until now they shared one sentence.
    if #found == 0 then
      skip("standalone", "no PUC Lua on PATH — this gate is about the *other* Lua, not Neovim's")
    else
      -- Somebody has a PUC Lua. That is a machine one `luarocks install`
      -- away from running this gate, so the message names the rock instead
      -- of leaving them to work it out.
      local exe = found[1]
      local rocks = missing_rocks(exe)
      skip(
        "standalone",
        ("%s is on PATH but cannot require %s — `luarocks install %s`"):format(
          exe,
          table.concat(rocks, " or "),
          table.concat(rocks, " ")
        )
      )
    end
    return
  end

  -- Repo-relative, because `opts.out_dir` is repo-relative everywhere else
  -- (`docs/map` is the default) and an absolute path would be joined onto the
  -- root rather than replacing it. `.deps/` is already gitignored and already
  -- where the headless runners put throwaway checkouts, so nothing here can
  -- reach the working tree or the scanned corpus.
  local out_rel = ".deps/standalone-map"
  local out_abs = root .. "/" .. out_rel
  vim.fn.delete(out_abs, "rf")
  run({
    lua,
    "standalone/docmap.lua",
    root,
    "--source=lua/documentation",
    "--out-dir=" .. out_rel,
  }, "standalone/docmap.lua")

  local path = out_abs .. "/module_map.json"
  local fd = io.open(path, "rb")
  if not fd then
    fail("standalone build wrote no module_map.json to " .. out_rel)
    return
  end
  local body = fd:read("*a")
  fd:close()

  -- The two shapes the bug produced, asserted directly rather than by
  -- comparing against a reference file: a reference would have to be
  -- regenerated with every real change, and would then stop being evidence.
  -- `%f[%D]` so a genuine fraction like `45.05` is not mistaken for one.
  local bad_value = body:match('"value":%-?%d+%.0%f[%D]')
  local bad_detail = body:match('"detail":"[^"]-%d%.0%f[%D][^"]-"')
  if bad_value or bad_detail then
    fail(
      "standalone artifact renders numbers host-dependently — the defect "
        .. "core/json.lua and core/quicks.lua exist to prevent:\n    "
        .. tostring(bad_value or bad_detail)
    )
    return
  end

  say("  ok: no host-dependent number formatting in the standalone artifact")
end

-- The order is not cosmetic. A formatting failure is the cheapest one to find
-- and the least interesting; a stale map is the most likely to be a real
-- finding rather than a slip. Failing fast on the cheap one first means the
-- expensive checks only ever run on code that is already tidy.
local ORDER = { "stylua", "luacheck", "tests", "map", "standalone" }

local stage = (_G.arg or {})[1] or "all"

if stage == "all" then
  for _, name in ipairs(ORDER) do
    GATES[name]()
  end
  -- Counted from ORDER rather than written out, so adding a sixth gate
  -- cannot leave this line quietly claiming four. It already had: the
  -- `standalone` gate made it five without this line noticing.
  --
  -- **And a gate that skipped is not a gate that passed.** This line used to
  -- say "All 5 gates passed" while one of them had printed *skipped* forty
  -- lines earlier — which is how three real defects reached a release with
  -- every local run green. The number is now what ran.
  if #skipped == 0 then
    say("\n" .. paint("32", ("All %d gates passed."):format(#ORDER)))
  else
    say(
      "\n"
        .. paint("32", ("%d gates passed"):format(#ORDER - #skipped))
        .. ", "
        .. paint("33", ("%d skipped: %s"):format(#skipped, table.concat(skipped, ", ")))
        .. "."
    )
    say(paint("33", "  A skipped gate checked nothing. Green here is not green in CI."))
  end
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
