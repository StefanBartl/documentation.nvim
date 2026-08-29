-- scripts/parity.lua — the parity audit, measured rather than reasoned.
--
-- The feature-parity audit asks for one row per contract capability, one column per language,
-- and every empty cell either filled or given a written reason. This script
-- produces the *cells*. The reasons are prose and live in
-- `docs/LANGUAGES.md`; a script cannot write them and should not pretend to.
--
-- **Why a script and not a hand-written table.** The docs pass that preceded
-- this one found two counts stated in prose that the code contradicted, both
-- because somebody wrote a number down once and it stopped being true
-- quietly. A parity matrix is that failure mode with eleven times the surface
-- area. So every cell here is the result of running the backend over a real
-- file in its own language and looking at what came back — never a judgement
-- about what the language "should" support.
--
-- Usage, from the repo root:
--
--   DOCMAP_TS_DIR=C:/tools/docmap-grammars nvim --headless -u NONE -l scripts/parity.lua
--
-- `--markdown` emits the table as Markdown for pasting into `docs/LANGUAGES.md`;
-- the default is a fixed-width grid for reading in a terminal.
--
-- A backend whose grammar cannot be loaded is reported as `?` throughout
-- rather than as a row of blanks: "not measured" and "measured, absent" are
-- different facts, and collapsing them is exactly what this audit exists to
-- stop.

local root = (vim.fn.getcwd():gsub("\\", "/"))
vim.opt.runtimepath:append(root)
if vim.env.LIB_NVIM_DIR and vim.env.LIB_NVIM_DIR ~= "" then
  vim.opt.runtimepath:append(vim.env.LIB_NVIM_DIR)
else
  vim.opt.runtimepath:append(vim.fs.dirname(root) .. "/lib.nvim")
end

local registry = require("documentation.core.lang_registry")
local markers = require("documentation.core.markers")

---The eleven capabilities the parity entry names, in its order. `probe` is
---handed the backend's own answers and returns whether that capability came
---back with something in it.
---@type { key: string, label: string, probe: fun(a: table): boolean }[]
local CAPS = {
  {
    key = "file",
    label = "File summary",
    probe = function(a)
      return a.header.summary ~= nil and a.header.summary ~= ""
    end,
  },
  {
    key = "ident",
    label = "Module identity",
    probe = function(a)
      return a.header.module ~= nil and a.header.module ~= ""
    end,
  },
  {
    key = "decl",
    label = "Declaration summary",
    probe = function(a)
      for _, f in ipairs(a.functions) do
        if f.summary and f.summary ~= "" then
          return true
        end
      end
      return false
    end,
  },
  {
    key = "params",
    label = "Parameters",
    probe = function(a)
      for _, f in ipairs(a.functions) do
        if f.params and #f.params > 0 then
          return true
        end
      end
      return false
    end,
  },
  {
    key = "returns",
    label = "Returns",
    probe = function(a)
      for _, f in ipairs(a.functions) do
        if f.returns and #f.returns > 0 then
          return true
        end
      end
      return false
    end,
  },
  {
    key = "vis",
    label = "Visibility",
    probe = function(a)
      for _, f in ipairs(a.functions) do
        if f.internal then
          return true
        end
      end
      return false
    end,
  },
  {
    key = "req",
    label = "Require edges",
    probe = function(a)
      return #a.requires > 0
    end,
  },
  {
    key = "call",
    label = "Call edges",
    probe = function(a)
      return #a.calls > 0
    end,
  },
  {
    key = "sym",
    label = "Symbols",
    probe = function(a)
      return #a.symbols > 0
    end,
  },
  {
    key = "mark",
    label = "Markers",
    probe = function(a)
      return #a.markers > 0
    end,
  },
  {
    key = "gloss",
    label = "Glossary",
    probe = function(a)
      return a.backend.glossary ~= nil
    end,
  },
}

---Fixture per backend. One file each, in `TESTS/fixtures/parity/`, written to
---exercise all eleven in that language's own idiom — which is the whole
---point: a fixture that spells a Lua idea in Go syntax measures nothing.
local FIXTURES = {
  lua = "lua.lua",
  js = "js.js",
  ts = "ts.ts",
  tsx = "tsx.tsx",
  zig = "zig.zig",
  java = "Java.java",
  c = "c.c",
  cpp = "cpp.cpp",
  asm = "asm.s",
  python = "python.py",
  csharp = "csharp.cs",
  go = "go.go",
  -- Under `src/`, because that is where Rust puts it and where its module
  -- identity comes from: `module_path_of` reads the file's position under
  -- `src/`, so a fixture sitting anywhere else measures "no identity" and
  -- reports a language fact that is really a fixture fact.
  rust = "src/rust.rs",
  php = "php.php",
  ruby = "ruby.rb",
  kotlin = "kotlin.kt",
  swift = "swift.swift",
  dart = "dart.dart",
  scala = "scala.scala",
  haskell = "haskell.hs",
  elixir = "elixir.ex",
  erlang = "erlang.erl",
  ocaml = "ocaml.ml",
}

---A second grammar a backend needs for a file it reads but does not own.
---
---**OCaml is the only entry and it earned this table by failing quietly.**
---Visibility in OCaml lives in the sibling `.mli`, which is a *different
---language to the parser* — so a host holding `ocaml.dll` and not
---`ocaml_interface.dll` parses the `.ml` perfectly, cannot read the
---interface, concludes there is no `.mli`, and reports **every declaration
---as public**. Not an error, not a degraded parse: a confident wrong answer
---about the one question that file exists to settle. The first parity run
---showed OCaml's visibility cell blank for exactly this reason, and the
---blank was the audit's, not the backend's.
---@type table<string, string[]>
local EXTRA_GRAMMARS = {
  ocaml = { "ocaml_interface" },
}

---Make one grammar loadable. Mirrors `standalone/treesitter.lua`'s
---resolution order so a run here and a run there disagree about a grammar
---for the same reasons, not for new ones.
---@param name string
---@return boolean
local function add_grammar(name)
  local explicit = os.getenv("DOCMAP_TS_" .. name:upper())
  if explicit and explicit ~= "" then
    local ok, added = pcall(vim.treesitter.language.add, name, { path = explicit })
    if ok and added then
      return true
    end
  end
  local dir = os.getenv("DOCMAP_TS_DIR")
  if dir and dir ~= "" then
    for _, ext in ipairs({ "dll", "so", "dylib" }) do
      local path = ("%s/%s.%s"):format(dir, name, ext)
      if vim.fn.filereadable(path) == 1 then
        local ok, added = pcall(vim.treesitter.language.add, name, { path = path })
        if ok and added then
          return true
        end
      end
    end
  end
  local ok, added = pcall(vim.treesitter.language.add, name)
  return ok and added == true
end

---Everything `backend` needs to read its own files, including the sibling
---grammars in `EXTRA_GRAMMARS`. An extra that will not load is **not** a
---reason to skip the row: the backend still reads its own language, and the
---cell it costs is exactly the finding worth reporting.
---@param backend Documentation.LangBackend
---@return boolean ready
local function ensure_grammar(backend)
  for _, extra in ipairs(EXTRA_GRAMMARS[backend.name] or {}) do
    add_grammar(extra)
  end
  if not backend.grammar then
    return true -- Needs none. Full fidelity, not a degradation.
  end
  return add_grammar(backend.grammar)
end

---@param backend Documentation.LangBackend
---@param path string
---@return table? answers `nil` when the file could not be read.
local function measure(backend, path)
  local fh = io.open(path, "r")
  if not fh then
    return nil
  end
  local src = fh:read("*a")
  fh:close()
  local header = backend.parse_header(path)
  local functions, calls, requires, symbols = backend.scan_file(path)
  return {
    backend = backend,
    header = header,
    functions = functions or {},
    calls = calls or {},
    requires = requires or {},
    symbols = symbols or {},
    markers = markers.scan_source(src, backend) or {},
  }
end

local rows = {}
for _, entry in ipairs(registry.report()) do
  local backend = registry.get(entry.name)
  local fixture = FIXTURES[entry.name]
  local cells = {}
  local note
  if not backend then
    -- Unreachable in practice — `report()` iterates the same table `get`
    -- reads — but the registry's own type says optional, and a parity audit
    -- that silences a type to save a branch is not the tool to cut corners
    -- with.
    note = "not registered"
  elseif not fixture then
    note = "no fixture"
  elseif not ensure_grammar(backend) then
    note = "grammar unavailable"
  else
    local path = ("%s/TESTS/fixtures/parity/%s"):format(root, fixture)
    local ok, answers = pcall(measure, backend, path)
    if not ok then
      note = "scan error: " .. tostring(answers):gsub("\n.*", "")
    elseif not answers then
      note = "fixture missing: " .. fixture
    else
      for _, cap in ipairs(CAPS) do
        local fine, got = pcall(cap.probe, answers)
        cells[cap.key] = fine and got or false
      end
    end
  end
  rows[#rows + 1] = { name = entry.name, cells = cells, note = note }
end

local markdown = false
for _, arg in ipairs(vim.v.argv) do
  if arg == "--markdown" then
    markdown = true
  end
end

local out = {}
if markdown then
  local head = { "Language" }
  local sep = { "---" }
  for _, cap in ipairs(CAPS) do
    head[#head + 1] = cap.label
    sep[#sep + 1] = ":-:"
  end
  out[#out + 1] = "| " .. table.concat(head, " | ") .. " |"
  out[#out + 1] = "|" .. table.concat(sep, "|") .. "|"
  for _, row in ipairs(rows) do
    local line = { "`" .. row.name .. "`" }
    for _, cap in ipairs(CAPS) do
      line[#line + 1] = row.note and "?" or (row.cells[cap.key] and "✓" or "—")
    end
    out[#out + 1] = "| " .. table.concat(line, " | ") .. " |"
  end
else
  local head = { ("%-8s"):format("lang") }
  for _, cap in ipairs(CAPS) do
    head[#head + 1] = ("%-6s"):format(cap.key)
  end
  out[#out + 1] = table.concat(head, " ")
  for _, row in ipairs(rows) do
    local line = { ("%-8s"):format(row.name) }
    for _, cap in ipairs(CAPS) do
      line[#line + 1] = ("%-6s"):format(row.note and "?" or (row.cells[cap.key] and "yes" or "-"))
    end
    out[#out + 1] = table.concat(line, " ") .. (row.note and ("   << " .. row.note) or "")
  end
end

io.write(table.concat(out, "\n") .. "\n")
