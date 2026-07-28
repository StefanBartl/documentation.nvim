#!/usr/bin/env bash
#
# Every gate CI runs, in one command.
#
#   scripts/ci.sh              all four, in order, stopping at the first failure
#   scripts/ci.sh stylua       one gate
#   scripts/ci.sh luacheck
#   scripts/ci.sh tests
#   scripts/ci.sh map
#
# The order is not cosmetic. A formatting failure is the cheapest one to find
# and the least interesting; a stale map is the most likely to be a real
# finding rather than a slip. Failing fast on the cheap one first means the
# expensive checks only ever run on code that is already tidy.
#
# `.github/workflows/ci.yml` calls this too, one stage per job — so the four
# jobs keep their independent red/green marks and their parallelism, while
# what each gate *is* stays defined in exactly one place. A workflow that
# spelled the commands out again would be a second copy of them, which is the
# drift this repository exists to detect.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
fail() { printf '\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

# lib.nvim is a runtime dependency, and a headless `-l` run has no plugin
# manager to supply it. Resolved the same three ways `docs/TESTS/run.lua` and
# `scripts/gen_map.lua` resolve it — checked here as well so the failure is one
# clear message instead of a Lua stack trace two stages in.
have_lib_nvim() {
  [ -n "${LIB_NVIM_DIR:-}" ] && [ -d "$LIB_NVIM_DIR" ] && return 0
  [ -d "$ROOT/.deps/lib.nvim" ] && return 0
  [ -d "$ROOT/../lib.nvim" ] && return 0
  return 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is not on PATH."
}

run_stylua() {
  step "stylua"
  need stylua
  # The whole tree, not a list of directories. The list form silently skipped
  # docs/EXAMPLES/, which is how a file sat unformatted in it for as long as it
  # existed while every local run reported clean.
  stylua --check .
}

run_luacheck() {
  step "luacheck"
  need luacheck
  luacheck lua docs/TESTS scripts
}

run_tests() {
  step "tests"
  need nvim
  have_lib_nvim || fail "lib.nvim not found. Set LIB_NVIM_DIR, clone it to .deps/lib.nvim, or put it beside this repo."
  nvim --headless -u NONE -l docs/TESTS/run.lua
}

run_map() {
  step "map --check"
  need nvim
  have_lib_nvim || fail "lib.nvim not found. Set LIB_NVIM_DIR, clone it to .deps/lib.nvim, or put it beside this repo."
  nvim --headless -l scripts/gen_map.lua --check
}

case "${1:-all}" in
  stylua) run_stylua ;;
  luacheck) run_luacheck ;;
  tests) run_tests ;;
  map) run_map ;;
  all)
    run_stylua
    run_luacheck
    run_tests
    run_map
    printf '\n\033[32mAll four gates passed.\033[0m\n'
    ;;
  *)
    fail "Unknown stage '$1' (expected: stylua, luacheck, tests, map, or nothing for all)."
    ;;
esac
