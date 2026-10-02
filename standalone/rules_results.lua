---@module 'standalone.rules_results'
--- Run `rules.nvim`'s engine over a ruleset and a project and print what it
--- found, one line per rule — on **either** host.
---
---   nvim --headless -u NONE -l standalone/rules_results.lua <ruleset> <project> [--no-predicates]
---   lua standalone/rules_results.lua <ruleset> <project> [--no-predicates]
---
--- Under Neovim it uses the real `vim.*`; under plain Lua it installs
--- `standalone.vim_shim` first. The output is deliberately identical for the
--- same input, so a caller can run both and compare them byte for byte — that
--- comparison is what `scripts/ci.lua`'s `standalone` gate does, because it is
--- the only way to learn that the shim answers what the engine asks the way the
--- editor does: every individual shim function can be right and the engine
--- still disagree with itself.
---
--- What is printed is chosen to be host-independent: statuses, finding counts
--- and finding text from the engine's own checks, the parser's `title`,
--- `section`, prose length and `agent`. Error *messages* from the Lua runtime
--- are not printed (LuaJIT and PUC word them differently); a block that failed
--- to parse is counted.
---
--- Dependencies are found the way `standalone/docmap.lua` finds them:
--- `RULES_NVIM_DIR` / `LIB_NVIM_DIR`, then `.deps/<name>`, then a sibling
--- directory of this repository.

local script = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local self_root = (script:match("^(.*)/standalone/[^/]*$") or ".")

---Put `<dir>/lua` on `package.path` for the first candidate that has `probe`.
---@param name string
---@param probe string A path under `lua/` that proves the checkout is the right one.
local function find_dependency(name, probe)
  local env = os.getenv(name:upper():gsub("[.-]", "_") .. "_DIR")
  local candidates = {}
  if env and env ~= "" then
    candidates[#candidates + 1] = env
  end
  candidates[#candidates + 1] = self_root .. "/.deps/" .. name
  candidates[#candidates + 1] = self_root .. "/../" .. name
  for _, dir in ipairs(candidates) do
    local fd = io.open(dir .. "/lua/" .. probe, "r")
    if fd then
      fd:close()
      package.path = dir .. "/lua/?.lua;" .. dir .. "/lua/?/init.lua;" .. package.path
      return
    end
  end
  io.stderr:write(
    ("standalone/rules_results.lua: %s not found (set %s_DIR, or .deps/%s)\n"):format(
      name,
      name:upper():gsub("[.-]", "_"),
      name
    )
  )
  os.exit(2)
end

local ruleset, project, no_predicates = nil, nil, false
for _, a in ipairs(arg) do
  if a == "--no-predicates" then
    no_predicates = true
  elseif not ruleset then
    ruleset = a
  elseif not project then
    project = a
  end
end
if not ruleset or not project then
  io.stderr:write("usage: rules_results.lua <ruleset> <project> [--no-predicates]\n")
  os.exit(2)
end

package.path = self_root .. "/?.lua;" .. package.path
find_dependency("lib.nvim", "lib/lua/error/init.lua")
find_dependency("rules.nvim", "rules/engine/runner.lua")

if not rawget(_G, "vim") then
  require("standalone.vim_shim")
end

local loader = require("rules.engine.loader")
local runner = require("rules.engine.runner")

local rules, parse_errors = loader.load({ ruleset })

---@param s any
---@return string
local function flat(s)
  return (tostring(s):gsub("\\", "/"):gsub("[\r\n\t]", " "))
end

local project_slashed = flat(project):gsub("/+$", "")

---@param path string
---@return string
local function rel(path)
  local p = flat(path)
  if p:sub(1, #project_slashed) == project_slashed then
    p = p:sub(#project_slashed + 1)
  end
  return p
end

local lines = {}
lines[#lines + 1] = ("PARSE\trules=%d\terrors=%d"):format(#rules, #parse_errors)

local families, names = {}, {}
for _, r in ipairs(rules) do
  local fam = runner.family_of(r.id)
  if not families[fam] then
    families[fam] = true
    names[#names + 1] = fam
  end
end
table.sort(names)

local opts = { lua_predicates = not no_predicates }
for _, fam in ipairs(names) do
  for _, res in ipairs(runner.check_family(rules, fam, project, {}, opts)) do
    local rule = res.rule
    local findings = {}
    for _, f in ipairs(res.findings) do
      findings[#findings + 1] = ("%s:%s:%s"):format(rel(f.file), tostring(f.line), flat(f.text))
    end
    table.sort(findings)
    local agent = rule.agent and flat(rule.agent.question or "-") or "-"
    lines[#lines + 1] = table.concat({
      rule.id,
      res.status,
      tostring(#res.findings),
      table.concat(findings, " | "):sub(1, 300),
      "title=" .. flat(rule.title or "-"),
      "section=" .. flat(rule.section or "-"),
      "text=" .. tostring(#(rule.text or "")),
      "agent=" .. agent,
    }, "\t")
  end
end

table.sort(lines, function(a, b)
  -- PARSE first, then by rule id.
  if a:sub(1, 5) == "PARSE" then
    return b:sub(1, 5) ~= "PARSE"
  elseif b:sub(1, 5) == "PARSE" then
    return false
  end
  return a < b
end)

io.stdout:write(table.concat(lines, "\n"), "\n")
