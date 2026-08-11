-- standalone/check_treesitter.lua — does a real tree-sitter binding work on
-- this machine, without Neovim?
--
-- This is the question PORTABILITY.md's Step 3 turns on, and it had been
-- answered by hand twice (once on Windows, once under WSL) with the result
-- written into prose and the commands themselves thrown away. Prose does not
-- re-run. This does.
--
-- Deliberately **not** part of `TESTS/run.lua`: it needs a `lua-tree-sitter`
-- rock and a compiled grammar, neither of which CI has or should grow a
-- dependency on. It is a diagnostic you run on a machine you are asking a
-- question about, and it prints what it found either way.
--
--   lua standalone/check_treesitter.lua <path-to-grammar-shared-lib> [lang]
--
-- Exit code 0 means every stage below passed; 1 means one did and the output
-- names which. `lang` defaults to "lua" and is the symbol suffix the grammar
-- exports (`tree_sitter_<lang>`), not a file name.
--
-- Building the grammar is one command against a plain grammar checkout, no
-- tree-sitter CLI and no Node toolchain:
--
--   gcc -O2 -shared -o lua_grammar.dll src/parser.c src/scanner.c -Isrc
--
-- The fixture and its expected captures are stated before anything runs, so
-- a pass means "produced this exact answer", not "did not crash".

local GRAMMAR = arg and arg[1]
local LANG = (arg and arg[2]) or "lua"

local SRC = "local alpha = 1\nlocal function beta(gamma)\n  return gamma\nend\n"
local EXPECT = { "alpha", "beta", "gamma", "gamma" }

local failures = {}

---@param label string
---@param ok boolean
---@param detail string?
local function report(label, ok, detail)
  print(("%-34s %s%s"):format(label, ok and "ok" or "FAIL", detail and ("  " .. detail) or ""))
  if not ok then
    failures[#failures + 1] = label
  end
end

if not GRAMMAR then
  io.stderr:write("usage: lua standalone/check_treesitter.lua <grammar-shared-lib> [lang]\n")
  os.exit(2)
end

local ok_require, ts = pcall(require, "lua_tree_sitter")
report("require lua_tree_sitter", ok_require, ok_require and "" or tostring(ts))
if not ok_require then
  io.stderr:write(
    "\nNo binding installed. `luarocks install lua-tree-sitter` (see PORTABILITY.md\n"
  )
  io.stderr:write("for the two packaging fixes its published rock needs).\n")
  os.exit(1)
end

local ok_lang, lang = pcall(ts.Language.load, GRAMMAR, LANG)
report("Language.load", ok_lang, ok_lang and ("ABI " .. tostring(lang:version())) or tostring(lang))
if not ok_lang then
  os.exit(1)
end

local parser = ts.Parser.new()
parser:set_language(lang)
local tree = parser:parse_string(nil, SRC)
report("Parser:parse_string", tree ~= nil)

-- The call that segfaulted in the originally recorded Windows run. It returns
-- a 32-byte `TSNode` by value, which is what made a struct-by-value ABI
-- problem the standing hypothesis for that crash.
local ok_root, root = pcall(function()
  return tree:root_node()
end)
report("Tree:root_node", ok_root and root ~= nil, ok_root and root:type() or tostring(root))
if not ok_root then
  os.exit(1)
end

-- `node:parent()` decides whether a binding needs the ~30-line parent-index
-- shim `ltreesitter` would have required.
local first = root:named_child(0)
report("Node:parent", first ~= nil and first:parent():type() == root:type())

local query = ts.Query.new(lang, "(identifier) @id")
local cursor = ts.Query.Cursor.new(query, root)
local got = {}
while true do
  local cap = cursor:next_capture()
  if not cap then
    break
  end
  local node = cap:node()
  got[#got + 1] = SRC:sub(node:start_byte() + 1, node:end_byte())
end

local same = #got == #EXPECT
if same then
  for i, want in ipairs(EXPECT) do
    if got[i] ~= want then
      same = false
    end
  end
end
report(
  "query -> captures -> source text",
  same,
  ("got [%s], expected [%s]"):format(table.concat(got, " "), table.concat(EXPECT, " "))
)

-- Byte-range restriction: what the real scanner uses to attribute a call site
-- to the function that contains it.
local ranged = ts.Query.Cursor.new(ts.Query.new(lang, "(identifier) @id"), root)
ranged:set_byte_range(0, 15)
local n = 0
while ranged:next_capture() do
  n = n + 1
end
report("Cursor:set_byte_range", n == 1, ("%d capture(s), expected 1"):format(n))

print("")
if #failures == 0 then
  print("PASS — a real tree-sitter pipeline runs here without Neovim.")
  os.exit(0)
end
print("FAIL — " .. table.concat(failures, ", "))
os.exit(1)
