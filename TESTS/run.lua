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
  -- Built with explicit indices, not a `{a, b, c}` literal fed to `ipairs`:
  -- `vim.env.LIB_NVIM_DIR` is `nil` whenever it is unset — the normal case
  -- for CI, which never sets it and instead relies on the `.deps/lib.nvim`
  -- candidate below — and a table literal with `nil` in its first slot
  -- makes `ipairs` stop immediately without ever inspecting the slots after
  -- it, silently skipping every other candidate regardless of whether the
  -- directory actually exists.
  local candidates = {}
  if vim.env.LIB_NVIM_DIR and vim.env.LIB_NVIM_DIR ~= "" then
    candidates[#candidates + 1] = vim.env.LIB_NVIM_DIR
  end
  candidates[#candidates + 1] = vim.fn.getcwd() .. "/.deps/lib.nvim"
  candidates[#candidates + 1] = vim.fs.dirname(vim.fn.getcwd()) .. "/lib.nvim"
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

-- Optional, unlike lib.nvim: `lang_js_spec.lua` already degrades to a stated
-- skip when no javascript/typescript/tsx parser is on the rtp (true for a
-- plain local run, where nothing should fail loudly over an absent
-- treesitter grammar). CI builds real grammars from source into a directory
-- and points here via this variable so that spec's real assertions run
-- instead of its skip path — see `.github/workflows/ci.yml`.
if
  vim.env.DOCUMENTATION_TS_PARSERS_DIR
  and vim.fn.isdirectory(vim.env.DOCUMENTATION_TS_PARSERS_DIR) == 1
then
  vim.opt.rtp:append(vim.env.DOCUMENTATION_TS_PARSERS_DIR)
end

-- Same shape, same reason: `browse_endpoints_spec.lua`'s `gs` (send a
-- request) test already has a real, tested skip path for the ordinary case
-- of `runtime-analysis.nvim` not being installed — this only lets a real
-- checkout upgrade that one assertion block from "the soft dependency
-- degrades correctly" to "the soft dependency actually works end to end."
if vim.env.RUNTIME_ANALYSIS_DIR and vim.fn.isdirectory(vim.env.RUNTIME_ANALYSIS_DIR) == 1 then
  vim.opt.rtp:append(vim.env.RUNTIME_ANALYSIS_DIR)
end

local dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local H = dofile(dir .. "harness.lua")

local specs = {
  "docmap_spec.lua",
  "lang_registry_spec.lua",
  "detect_source_spec.lua",
  "coverage_gaps_spec.lua",
  "artifact_contract_spec.lua",
  "payload_contract_spec.lua",
  "consumers_spec.lua",
  "consumer_require_spec.lua",
  "glossary_spec.lua",
  "binding_conflict_spec.lua",
  "unused_require_spec.lua",
  "sarif_spec.lua",
  "example_parse_spec.lua",
  "docs_spec.lua",
  "quicks_spec.lua",
  "lang_js_spec.lua",
  "lang_zig_spec.lua",
  "lang_java_spec.lua",
  "lang_cfamily_spec.lua",
  "lang_asm_spec.lua",
  "lang_python_spec.lua",
  "lang_csharp_spec.lua",
  "lang_go_spec.lua",
  "lang_rust_spec.lua",
  "doccoverage_by_language_spec.lua",
  "lang_js_gaps_spec.lua",
  "polyglot_fixture_spec.lua",
  "resolve_relative_spec.lua",
  "snippet_spec.lua",
  "bindings_spec.lua",
  "browse_endpoints_spec.lua",
  "browse_telemetry_spec.lua",
  "telemetry_self_spec.lua",
  "browse_loaded_spec.lua",
  "docmap_browse_spec.lua",
  "pdf_artifact_spec.lua",
  "check_type_vs_class_spec.lua",
  "check_overload_credit_spec.lua",
  "annotate_spec.lua",
  "markers_spec.lua",
  "backend_contract_spec.lua",
  "host_lua_determinism_spec.lua",
  "tools_spec.lua",
  "features_spec.lua",
  "calls_external_spec.lua",
  "external_repos_spec.lua",
  "callhierarchy_spec.lua",
  "diagnostics_spec.lua",
  "mdview_spec.lua",
  "mcp_spec.lua",
  "checklist_spec.lua",
  "api_spec.lua",
  "generate_all_spec.lua",
  "usrcmds_generate_all_spec.lua",
  "usrcmds_actions_spec.lua",
  "functions_doc_tag_spacing_spec.lua",
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
