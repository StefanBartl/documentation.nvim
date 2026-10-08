-- .testing.lua -- configuration of testing.nvim for this project.
-- Written by `testing migrate`; edit freely (it is never overwritten). Every key is optional; the
-- keys are documented in testing.nvim's docs/CONFIG.md. Loading this file executes it (same trust
-- as running the specs).
return {
  -- Lua module root of the project.
  plugin = "documentation",
  -- How the spec files are run: "auto" = sniffed per file, "h" = on the project's own TESTS/harness.lua,
  -- "script" = a self-running script in its own process.
  dialect = "h",
  -- Dependencies (directory names) put on the runtimepath: $<NAME>_DIR, .deps/<name>, ../<name>,
  -- stdpath('data')/lazy/<name>.
  deps = { "lib.nvim", "runtime-analysis.nvim", "ui.nvim" },
  -- "none" = all specs in one nvim, "file" = one nvim per spec file
  -- (nothing leaks from one file into the next).
  isolated = "none",
  -- Guards (safety nets, see testing.nvim docs/GUARDS.md).
  guards = {
    fs = "error",
    -- Real finding, kept at warn: the specs run in one editor (isolated = "none") and leave
    -- buffers, windows, user commands, highlight groups and autocmds behind (setup() of the
    -- plugin and its dependencies). Per-file isolation would fix it.
    state = "warn",
    scheduled_error = "error",
    prompt = "error",
    deprecation = "error",
    -- Guard false alarm, kept at warn: shim_behavior_spec runs io.popen('"git" "--version" 2>&1');
    -- the guard judges a shell string by its first word including the quotes, so allowing git
    -- does not match and the case would fail.
    process_net = "warn",
  },
  -- What the guards let through on purpose.
  guard_allow = {
    -- The specs build tmp repositories (git init/commit/rev-parse), the docmap reads the git
    -- remote/branch, the plugin spawns a headless nvim and the language parsers, and the
    -- fixture cleanup removes directories with rm.
    spawn = { "git", "nvim", "node", "rm" },
    -- Fixtures of the generate-all spec live below .deps/generate-all-*; the callhierarchy spec
    -- makes the runtime append to the Neovim LSP log in the state directory.
    -- The telemetry specs make runtime-analysis.nvim write its telemetry snapshots below
    -- stdpath('cache')/runtime-analysis.nvim (the plugin's own cache directory).
    fs = {
      ".deps",
      vim.fn.stdpath("state") .. "/lsp.log",
      vim.fn.stdpath("cache") .. "/runtime-analysis.nvim",
    },
  },
  -- Environment variables the specs read; a child editor inherits an allowlist only (never secrets).
  -- Not listed on purpose: NVIM_* (the validator refuses names with that prefix, and one refused
  -- entry voids the whole list) and XDG_*_HOME (the child gets its own sandbox values, and
  -- shim_behavior_spec compares the shim with the editor of the same process, so both read those).
  -- TESTS/testing_config_spec.lua keeps the list valid.
  env_allow = {
    -- backend_contract_spec points a language backend at a parser library with these.
    "DOCMAP_CSHARP_PARSER",
    "DOCMAP_DART_PARSER",
    "DOCMAP_ELIXIR_PARSER",
    "DOCMAP_ERLANG_PARSER",
    "DOCMAP_GO_PARSER",
    "DOCMAP_HASKELL_PARSER",
    "DOCMAP_JAVA_PARSER",
    "DOCMAP_KOTLIN_PARSER",
    "DOCMAP_PHP_PARSER",
    "DOCMAP_PYTHON_PARSER",
    "DOCMAP_RUBY_PARSER",
    "DOCMAP_RUST_PARSER",
  },
}
