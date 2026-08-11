#!/usr/bin/env bash
#
# Every gate CI runs, in one command.
#
#   scripts/ci.sh              all five, in order, stopping at the first failure
#   scripts/ci.sh stylua       one gate
#   scripts/ci.sh luacheck
#   scripts/ci.sh tests
#   scripts/ci.sh map
#
# A wrapper, not the definition. **What each gate is lives in
# `scripts/ci.lua`** — this file only picks the interpreter. That split is the
# cross-platform fix: Neovim is already a hard requirement of this plugin, so
# using it as the script host means a Windows contributor runs the same checks
# with
#
#   nvim --headless -l scripts/ci.lua
#
# instead of installing Git Bash to run this. Both entry points execute exactly
# the same code, so neither can drift from the other.
#
# `.github/workflows/ci.yml` calls this, one stage per job, so the four jobs
# keep their independent red/green marks and their parallelism.

set -euo pipefail

cd "$(dirname "$0")/.."

command -v nvim >/dev/null 2>&1 || {
  printf '\033[31m%s\033[0m\n' "nvim is not on PATH." >&2
  exit 1
}

exec nvim --headless -l scripts/ci.lua "$@"
