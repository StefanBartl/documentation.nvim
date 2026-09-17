---@module 'standalone.selfcheck_behavior'
--- The other half of the shim behaviour differential: the same corpus, on the
--- other interpreter, with the real rocks.
---
---   lua standalone/selfcheck_behavior.lua <root> <expectations-file>
---
--- `TESTS/shim_behavior_spec.lua` runs inside Neovim and compares the shim
--- against the editor directly, which is where most of the corpus is
--- answered and why that half needs neither PUC Lua nor a rock. Three things
--- it structurally cannot answer, and this file exists for exactly those:
---
---   * **`vim.json.decode` is still dkjson's.** Under Neovim the shim's
---     `dkjson` is refused rather than faked, because a fake forwarding to
---     `vim.json` would compare the editor with itself. Here the rock is
---     real.
---   * **`lfs` is real.** The Neovim half runs the shim's filesystem logic
---     on an `lfs` adapter built over `vim.uv` — faithful, but still not the
---     rock the shipped build loads.
---   * **The interpreter is PUC Lua, not LuaJIT.** Number formatting, string
---     patterns and integer division all differ between them, and this build
---     has already shipped one artifact defect that existed only on the
---     non-LuaJIT side.
---
--- **The expectations are written, not committed.** `scripts/ci.lua` runs
--- `cases.write_expectations` against the `vim` of the Neovim executing it,
--- moments before invoking this file — so the oracle is whatever editor is
--- actually installed. A committed golden file would need regenerating by
--- hand, would drift with the next Neovim release, and would then be
--- evidence of nothing, which is the same argument `GATES.standalone`
--- already makes about reference artifacts.

local root = (arg[1] or "."):gsub("\\", "/"):gsub("/+$", "")
local expectations_path = arg[2]

if not expectations_path then
  io.stderr:write("usage: lua standalone/selfcheck_behavior.lua <root> <expectations-file>\n")
  os.exit(2)
end

local cases = dofile(root .. "/TESTS/fixtures/shim_behavior_cases.lua")
local shim = require("standalone.vim_shim")
local fixture = root .. "/TESTS/fixtures/shim_fs"

local expected, read_err = cases.read_expectations(expectations_path)
if not expected then
  io.stderr:write("selfcheck_behavior: " .. tostring(read_err) .. "\n")
  os.exit(1)
end

local mismatches, compared = {}, 0

for _, case in ipairs(cases.sorted()) do
  if not case.local_only then
    local want = expected[case.id]
    local got, detail = cases.evaluate(shim, cases.materialize(case), fixture)
    if want == nil then
      -- A case the expectations file has never heard of. Almost always means
      -- the two sides are reading different checkouts; saying so beats
      -- reporting it as a behavioural difference.
      mismatches[#mismatches + 1] = ("%s\n      no expectation was written for this case"):format(
        case.id
      )
    elseif want ~= got then
      compared = compared + 1
      local line = ("%s\n      neovim: %s\n      shim:   %s"):format(case.id, want, got)
      if case.why then
        line = line .. "\n      case:   " .. case.why
      end
      if detail then
        line = line .. "\n      raised: " .. tostring(detail):gsub("\n.*", "")
      end
      mismatches[#mismatches + 1] = line
    else
      compared = compared + 1
    end
  end
end

-- The expectations file must not carry ids this corpus no longer has, for the
-- same reason: it is a sign the two sides disagree about which tree they are
-- testing, not a sign the shim is wrong.
local known = {}
for _, case in ipairs(cases.cases) do
  known[case.id] = true
end
local orphans = {}
for id in pairs(expected) do
  if not known[id] then
    orphans[#orphans + 1] = id
  end
end
table.sort(orphans)

if #mismatches == 0 and #orphans == 0 then
  io.stdout:write(
    ("  ok: shim behaviour matches this Neovim on %d cases under %s\n"):format(compared, _VERSION)
  )
  os.exit(0)
end

io.stderr:write("standalone shim behaviour differs from Neovim:\n")
for _, line in ipairs(mismatches) do
  io.stderr:write("    " .. line .. "\n")
end
if #orphans > 0 then
  io.stderr:write(
    "    expectations for cases this corpus does not have: " .. table.concat(orphans, ", ") .. "\n"
  )
end
os.exit(1)
