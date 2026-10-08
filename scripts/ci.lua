-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
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
  -- `standalone` is in the list because it was not: the whole parser-less
  -- build — `vim_shim.lua`, `docmap.lua`, `treesitter.lua` — sat outside the
  -- only gate that reads Lua for unused locals and undefined globals, which
  -- is precisely the tree that has already shipped a `nil` call twice.
  run({ "luacheck", "lua", "TESTS", "scripts", "standalone" }, "luacheck")
end

---testing.nvim is the spec runner. Looked up like the other dependencies:
---`$TESTING_NVIM_DIR`, `.deps/testing.nvim`, a sibling checkout. The runner resolves
---the dependencies named in `.testing.lua` itself.
---@return string|nil
local function find_testing_nvim()
  local candidates = {}
  if vim.env.TESTING_NVIM_DIR and vim.env.TESTING_NVIM_DIR ~= "" then
    candidates[#candidates + 1] = vim.env.TESTING_NVIM_DIR
  end
  candidates[#candidates + 1] = root .. "/.deps/testing.nvim"
  candidates[#candidates + 1] = vim.fs.dirname(root) .. "/testing.nvim"
  for _, d in ipairs(candidates) do
    if vim.fn.filereadable(d .. "/scripts/testing.lua") == 1 then
      return d
    end
  end
  return nil
end

function GATES.tests()
  step("tests")
  need("nvim")
  need_lib_nvim()
  local testing = find_testing_nvim()
  if not testing then
    fail(
      "testing.nvim not found. Set TESTING_NVIM_DIR, clone it to .deps/testing.nvim, "
        .. "or put it beside this repo."
    )
    return
  end
  -- Same call as `scripts/test.sh` (which the CI `tests` job runs directly, to also write the
  -- JSON result): `TESTS/run.lua` stays only as the order manifest the runner reads.
  run({
    "nvim",
    "-n",
    "-i",
    "NONE",
    "--headless",
    "-u",
    "NONE",
    "-l",
    testing .. "/scripts/testing.lua",
    "run",
    ".",
    "--sentinel",
    "DOCUMENTATION_TESTS_OK",
  }, "tests")
end

function GATES.map()
  step("map --check")
  need("nvim")
  need_lib_nvim()
  run({ "nvim", "--headless", "-l", "scripts/gen_map.lua", "--check" }, "map --check")
end

---A PUC Lua that can actually run the standalone build, or nil.
---
---`lua5.4` before `lua` because Debian-family images ship both and the bare
---name is often 5.1; this gate wants the *other* Lua from the one Neovim
---embeds, which is the entire point of it existing.
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
---@return string? exe The first interpreter that loaded both rocks.
---@return string[]? found Every PUC Lua on PATH, returned only when none of
---them worked -- "none installed" and "one installed that cannot load the
---rocks" are different problems, and the caller reports which it is.
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
--- local gate instead. Its
--- published rock has two packaging defects, and a gate that is red before
--- anyone touches anything gets switched off the same day, which is exactly
--- the advice `docs/reuse.md` gives about extra checks.
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

  -- ------------------------------------------------------------------
  -- Links, on the interpreter and the `lfs` this build actually ships.
  --
  -- `TESTS/shim_links_spec.lua` compares the shim with the editor on the
  -- host's own file system, but through an `lfs` adapted onto `vim.uv`. What
  -- only this gate has is the real rock -- and on Windows the real
  -- `cmd.exe` -- under the real PUC Lua: the interpreter `docmap-desktop`
  -- runs. Two checks, the two things a repository can do with a link:
  --   * make `docs/map` one, and the engine must refuse to write and leave
  --     the folder it points at exactly as it was;
  --   * put one in the source tree that leaves the project, and the engine
  --     must not read what is behind it, and must say it did not.
  local links_dir = root .. "/.deps/standalone-links"
  vim.fn.delete(links_dir, "rf")
  vim.fn.mkdir(links_dir .. "/repo/lua/t", "p")
  vim.fn.mkdir(links_dir .. "/repo/docs", "p")
  vim.fn.mkdir(links_dir .. "/outside/map", "p")
  vim.fn.mkdir(links_dir .. "/outside/lua", "p")
  vim.fn.writefile(
    { "---@module 't'", "--- T-SUMMARY.", "local M = {}", "return M" },
    links_dir .. "/repo/lua/t/init.lua"
  )
  vim.fn.writefile({ "VICTIM" }, links_dir .. "/outside/map/index.html")
  vim.fn.writefile({ "VICTIM" }, links_dir .. "/outside/map/module_map.json")
  vim.fn.writefile({ "VICTIM" }, links_dir .. "/outside/map/overview.md")
  vim.fn.writefile(
    { "---@module 'leaked'", "--- OUTSIDE-SUMMARY.", "local M = {}", "return M" },
    links_dir .. "/outside/lua/init.lua"
  )

  ---A directory link: a junction on Windows (needs no privilege), a symlink
  ---elsewhere.
  ---@param target string
  ---@param link string
  ---@return boolean
  local function make_dir_link(target, link)
    if vim.fn.has("win32") == 1 then
      local made = vim
        .system({
          "cmd",
          "/C",
          "mklink",
          "/J",
          (link:gsub("/", "\\")),
          (target:gsub("/", "\\")),
        }, { text = true })
        :wait()
      return made.code == 0
    end
    return vim.uv.fs_symlink(target, link, { dir = true }) == true
  end

  if not make_dir_link(links_dir .. "/outside/map", links_dir .. "/repo/docs/map") then
    fail("standalone links check: could not make a directory link in " .. links_dir)
    return
  end
  local refused = vim
    .system({ lua, "standalone/docmap.lua", links_dir .. "/repo", "--source=lua/t" }, {
      cwd = root,
      text = true,
    })
    :wait()
  if refused.code == 0 then
    fail("standalone build wrote the map through docs/map, a link out of the project")
    return
  end
  if not (refused.stderr or ""):find("refusing to write the map", 1, true) then
    fail(
      "standalone build failed on a linked docs/map, but not with the refusal:\n    "
        .. (refused.stderr or ""):sub(1, 600)
    )
    return
  end
  for _, name in ipairs({ "index.html", "module_map.json", "overview.md" }) do
    local victim = table.concat(vim.fn.readfile(links_dir .. "/outside/map/" .. name), "\n")
    if victim ~= "VICTIM" then
      fail("standalone build overwrote outside/map/" .. name .. " through a link")
      return
    end
  end
  say("  ok: a linked docs/map is refused, and what it points at is untouched")

  vim.fn.delete(links_dir .. "/repo/docs/map")
  if not make_dir_link(links_dir .. "/outside/lua", links_dir .. "/repo/lua/t/leaving") then
    fail("standalone links check: could not make a directory link in the source tree")
    return
  end
  local walked = vim
    .system({
      lua,
      "standalone/docmap.lua",
      links_dir .. "/repo",
      "--source=lua/t",
      "--out-dir=out",
    }, { cwd = root, text = true })
    :wait()
  if walked.code ~= 0 then
    fail(
      "standalone build failed on a source tree with a link out of the project:\n    "
        .. (walked.stderr or ""):sub(1, 600)
    )
    return
  end
  local walked_map = table.concat(vim.fn.readfile(links_dir .. "/repo/out/module_map.json"), "\n")
  if walked_map:find("OUTSIDE-SUMMARY", 1, true) or walked_map:find("leaked", 1, true) then
    fail("standalone build read a folder behind a link that leaves the project")
    return
  end
  if not (walked.stderr or ""):find("not followed", 1, true) then
    fail(
      "standalone build did not say it left a link alone:\n    "
        .. (walked.stderr or ""):sub(1, 600)
    )
    return
  end
  say("  ok: a link out of the source tree is not read, and the run says so")
  vim.fn.delete(links_dir, "rf")

  -- ------------------------------------------------------------------
  -- The behavioural differential, replayed on the other interpreter.
  --
  -- `TESTS/shim_behavior_spec.lua` already compared most of this corpus
  -- against the real `vim.*` in the always-green `tests` gate — deliberately,
  -- because this gate skips on most machines. What it could not answer is
  -- what needs the two rocks and the other Lua: `vim.json.decode` is still
  -- dkjson's, `lfs` is real here and adapted there, and PUC 5.4 is not
  -- LuaJIT.
  --
  -- The expectations are written from the `vim` of *this* Neovim, seconds
  -- before the replay, rather than read from a committed golden file: a
  -- golden would drift with the next Neovim release and would then be
  -- evidence of nothing.
  --
  -- Both steps are wrapped: a corpus that cannot be loaded, and a case naming
  -- something this Neovim does not have, are both *this gate's* red — with a
  -- sentence saying which. Unwrapped they surface as a Lua traceback out of a
  -- file nobody was editing, which reads like the build is broken.
  local loaded, cases = pcall(dofile, root .. "/TESTS/fixtures/shim_behavior_cases.lua")
  if not loaded then
    fail("cannot load the shim behaviour corpus: " .. tostring(cases))
    return
  end
  vim.fn.mkdir(root .. "/.deps", "p")
  local expectations = root .. "/.deps/shim-expectations.txt"
  local ok_write, written =
    pcall(cases.write_expectations, vim, root .. "/TESTS/fixtures/shim_fs", expectations)
  if not ok_write then
    fail("shim behaviour corpus is broken: " .. tostring(written))
    return
  end
  say(("  ok: wrote %d expectations from this Neovim"):format(written))
  run({ lua, "standalone/selfcheck_behavior.lua", root, expectations }, "standalone shim behaviour")

  -- ------------------------------------------------------------------
  -- The rules.nvim engine on both hosts.
  --
  -- The differential above proves each shim function against the editor. It
  -- cannot prove the *engine* on top of them: every function can be right and
  -- the engine still answer differently, because of an ordering, a separator,
  -- a value one of them returns where the other returns nothing. So the same
  -- script runs the same ruleset over the same project once in this Neovim and
  -- once under PUC Lua with the shim, and the two outputs must be identical.
  --
  -- Identical is necessary and not sufficient — two hosts can fail the same
  -- way — so each is also held to what the fixture *means*, written by hand in
  -- `expected_*.txt`: which rule passes, which fails, which is judgement, and
  -- (second run, predicates off) that every predicate reports `error` rather
  -- than quietly vanishing.
  local rules_dir
  local rules_candidates = {}
  if vim.env.RULES_NVIM_DIR and vim.env.RULES_NVIM_DIR ~= "" then
    rules_candidates[#rules_candidates + 1] = vim.env.RULES_NVIM_DIR
  end
  rules_candidates[#rules_candidates + 1] = root .. "/.deps/rules.nvim"
  rules_candidates[#rules_candidates + 1] = vim.fs.dirname(root) .. "/rules.nvim"
  for _, d in ipairs(rules_candidates) do
    if vim.fn.filereadable(d .. "/lua/rules/engine/runner.lua") == 1 then
      rules_dir = d
      break
    end
  end
  if not rules_dir then
    -- On a developer's machine a missing sibling checkout is the normal state
    -- and skipping is honest. In CI the checkout is a step of the job, so its
    -- absence is the job being wrong, and a skip there would be the silent
    -- green this whole gate exists to prevent.
    if vim.env.CI then
      fail("rules.nvim was not checked out to .deps/rules.nvim, and CI must not skip this step.")
    else
      skip(
        "rules engine under the shim",
        "rules.nvim not found — set RULES_NVIM_DIR, clone it to .deps/rules.nvim, or put it beside this repo"
      )
    end
    return
  end

  local fixture_dir = root .. "/TESTS/fixtures/rules_engine"
  ---@param host string[]
  ---@param extra string[]
  ---@return string stdout
  local function engine_output(host, extra)
    local cmd = vim.list_extend(vim.deepcopy(host), {
      "standalone/rules_results.lua",
      fixture_dir .. "/ruleset",
      fixture_dir .. "/project",
    })
    vim.list_extend(cmd, extra)
    local proc = vim.system(cmd, { cwd = root, text = true }):wait()
    if proc.code ~= 0 then
      fail(
        ("rules engine run failed (exit %d): %s\n%s"):format(
          proc.code,
          table.concat(cmd, " "),
          proc.stderr or ""
        )
      )
    end
    local out = (proc.stdout or ""):gsub("\r\n", "\n")
    return out
  end

  ---The part of each line the fixture's author wrote an expectation for.
  ---@param out string
  ---@return string
  local function meaning(out)
    local lines = {}
    for line in out:gmatch("[^\n]+") do
      local id, status = line:match("^([^\t]+)\t([^\t]+)")
      lines[#lines + 1] = id == "PARSE" and line or (id .. "\t" .. status)
    end
    return table.concat(lines, "\n") .. "\n"
  end

  for _, mode in ipairs({
    { label = "predicates trusted", extra = {}, expected = "expected_trusted.txt" },
    {
      label = "predicates off",
      extra = { "--no-predicates" },
      expected = "expected_untrusted.txt",
    },
  }) do
    local in_nvim =
      engine_output({ vim.v.progpath, "-n", "--headless", "-u", "NONE", "-l" }, mode.extra)
    local under_shim = engine_output({ lua }, mode.extra)
    if in_nvim ~= under_shim then
      local a, b =
        vim.split(in_nvim, "\n", { plain = true }), vim.split(under_shim, "\n", { plain = true })
      local shown = {}
      for i = 1, math.max(#a, #b) do
        if a[i] ~= b[i] then
          shown[#shown + 1] = ("    neovim: %s\n    shim:   %s"):format(
            a[i] or "<none>",
            b[i] or "<none>"
          )
          if #shown == 5 then
            break
          end
        end
      end
      fail(
        ("rules engine differs between Neovim and the shim (%s):\n%s"):format(
          mode.label,
          table.concat(shown, "\n")
        )
      )
      return
    end
    local want = table.concat(vim.fn.readfile(fixture_dir .. "/" .. mode.expected), "\n") .. "\n"
    if meaning(in_nvim) ~= want then
      fail(
        ("rules engine does not say what %s says it should (%s):\n--- got\n%s--- want\n%s"):format(
          mode.expected,
          mode.label,
          meaning(in_nvim),
          want
        )
      )
      return
    end
    say(("  ok: rules engine, %s: identical on both hosts and as expected"):format(mode.label))
  end
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
