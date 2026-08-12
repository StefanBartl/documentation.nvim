#!/usr/bin/env bash
# Build the standalone engine (scripts/package.lua's output) plus the four
# tree-sitter grammars it needs for full fidelity, for whichever platform
# this script is running on, and stage both under $OUT_DIR ready to attach
# to a GitHub Release.
#
# This is not a new recipe -- it is docs/ROADMAP/V1_EXTENSION/PORTABILITY.md's
# "Step 6" turned into a script, because that step proved every command by
# hand under WSL/Arch first. Anything below that looks unexplained is
# explained there in more depth; comments here are the parts specific to
# running this unattended in CI rather than by hand.
#
#   TRIPLE=x86_64-unknown-linux-gnu EXE_EXT= scripts/build_engine_release.sh
#   TRIPLE=x86_64-pc-windows-msvc EXE_EXT=.exe scripts/build_engine_release.sh
#
# Requires on PATH: gcc, curl, git, tar, and a working `make`. Requires a
# PUC Lua on PATH to run scripts/package.lua and scripts/bundle_manifest.lua
# themselves (built from source below, and used for that too -- see "why a
# from-source Lua" further down).

set -euo pipefail

: "${TRIPLE:?set TRIPLE, e.g. x86_64-unknown-linux-gnu or x86_64-pc-windows-msvc}"
: "${EXE_EXT:=}"
: "${OUT_DIR:=release-out}"

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
mkdir -p "$repo/$OUT_DIR"
out="$(cd "$repo/$OUT_DIR" && pwd)"

echo "== PUC Lua 5.4 from source"
# Not the distro package: Arch's own `lua54` ships no static `.a` at all
# (measured, PORTABILITY.md Step 6), and relying on whatever a given
# runner image happens to package would make this build's correctness
# depend on an image detail nobody here controls. Building from lua.org's
# own tarball is the same commands on every platform this script targets
# and gives full control over exactly what headers the rest of this
# script compiles against.
#
# `linux`/`mingw`, not `generic` — measured, not assumed: `generic` was
# tried first and produces a `lua` that cannot `require()` a C module at
# all ("dynamic libraries not enabled"), because that target defines
# neither `LUA_USE_DLOPEN` nor links `-ldl`/uses `LoadLibrary`. This
# script's own host interpreter needs exactly that: `scripts/package.lua`
# `require()`s `lfs` (dynamically) before it ever gets to producing the
# static bundle.
curl -sL https://www.lua.org/ftp/lua-5.4.8.tar.gz | tar xz -C "$work"
LUA_MAKE=linux
[ -n "$EXE_EXT" ] && LUA_MAKE=mingw
(
  cd "$work/lua-5.4.8"
  # `${MAKE:-make}` rather than a bare `make`: on Windows this repo's own
  # toolchain reaches a mingw `gcc` by prepending its own bin directory to
  # `PATH`, and doing the same for `/usr/bin` to reach that install's
  # `make.exe` also changes which `bash` a later `bash <script>` resolves
  # to if the caller is itself running under a *different* bash (Git
  # Bash) -- found losing an hour to a bash-vs-bash mismatch that looked
  # exactly like this script failing to see its own arguments. Passing an
  # absolute `MAKE=` avoids ever needing to widen `PATH` for this reason.
  "${MAKE:-make}" "$LUA_MAKE" CC="${CC:-gcc}"
)
LUAINC="$work/lua-5.4.8/src"
LUALIBA="$LUAINC/liblua.a"
LUABIN="$LUAINC/lua"
[ -n "$EXE_EXT" ] && LUABIN="$LUAINC/lua.exe"
test -f "$LUALIBA" || { echo "liblua.a missing after build" >&2; exit 1; }

echo "== lua-tree-sitter (--recurse-submodules pins the exact tree-sitter commit it was written against)"
git clone --quiet --recurse-submodules https://github.com/xcb-xwii/lua-tree-sitter "$work/lua-tree-sitter"

# The published rock's two packaging defects (PORTABILITY.md, "Step 2"):
# vendored ICU headers only arrive via --recurse-submodules above, and the
# rockspec's own `incdirs` omits `tree-sitter/lib/src` -- added here as an
# extra -I rather than patching the rockspec, since this script never runs
# `luarocks make` at all (see below).
LTS_SRC=(
  src/init.c src/language.c src/node.c src/parser.c src/point.c
  src/query/init.c src/query/capture.c src/query/cursor.c src/query/match.c
  src/query/quantified_capture.c src/query/runner.c
  src/range/init.c src/range/array.c src/tree.c src/util.c
  tree-sitter/lib/src/lib.c
)
LTS_INC=(-Itree-sitter/lib/include -Iinclude -Itree-sitter/lib/src -I"$LUAINC")

echo "== static lua_tree_sitter.a + lfs.a (for the final bundle)"
mkdir -p "$work/objs"
(
  cd "$work/lua-tree-sitter"
  for f in "${LTS_SRC[@]}"; do
    gcc -O2 -fPIC -c "${LTS_INC[@]}" "$f" -o "$work/objs/$(echo "$f" | tr '/' '_').o"
  done
)
ar rcs "$work/lua_tree_sitter.a" "$work"/objs/*.o

git clone --quiet --depth 1 https://github.com/lunarmodules/luafilesystem.git "$work/luafilesystem"
gcc -O2 -fPIC -c -I"$LUAINC" "$work/luafilesystem/src/lfs.c" -o "$work/lfs.o"
ar rcs "$work/lfs.a" "$work/lfs.o"

# `scripts/package.lua` and `scripts/bundle_manifest.lua` are themselves PUC
# Lua programs -- the interpreter that RUNS them needs `require("lfs")` and
# `require("dkjson")` to work *before* any bundling happens, independent of
# the static archives above (which are only for what luastatic links INTO
# the final binary). A dynamic .so/.dll and a plain .lua file cover that.
echo "== dynamic lfs + dkjson (so the host interpreter running package.lua can require() them)"
gcc -O2 -fPIC -shared -I"$LUAINC" "$work/luafilesystem/src/lfs.c" -o "$work/lfs.dyn.so"
curl -sL -o "$work/dkjson.lua" https://raw.githubusercontent.com/LuaDist/dkjson/master/dkjson.lua

echo "== dynamic lua_tree_sitter.so (so bundle_manifest.lua's probe run can see the real treesitter closure)"
(
  cd "$work/lua-tree-sitter"
  gcc -O2 -fPIC -shared "${LTS_INC[@]}" "${LTS_SRC[@]}" -o "$work/lua_tree_sitter.dyn.so"
)

echo "== luastatic (a plain Lua script, not a build target)"
curl -sL -o "$work/luastatic.lua" https://raw.githubusercontent.com/ers35/luastatic/master/luastatic.lua

echo "== 4 grammars via the tree-sitter CLI"
# The same mechanism .github/workflows/ci.yml's own `tests` job already
# uses for JS/TS/TSX -- `tree-sitter build` needs no separate libtree-sitter
# at all, since a grammar's shared library depends only on the C ABI in
# tree_sitter/parser.h. Simpler than compiling each grammar by hand, and
# already CI-proven for three of the four languages.
if ! command -v tree-sitter >/dev/null 2>&1; then
  npm install -g tree-sitter-cli
fi
mkdir -p "$work/grammars"
GSUF="so"
[ -n "$EXE_EXT" ] && GSUF="dll"
git clone --quiet --depth 1 https://github.com/tree-sitter-grammars/tree-sitter-lua.git "$work/tree-sitter-lua"
git clone --quiet --depth 1 https://github.com/tree-sitter/tree-sitter-javascript.git "$work/tree-sitter-javascript"
git clone --quiet --depth 1 https://github.com/tree-sitter/tree-sitter-typescript.git "$work/tree-sitter-typescript"
tree-sitter build --output "$work/grammars/lua.$GSUF" "$work/tree-sitter-lua"
tree-sitter build --output "$work/grammars/javascript.$GSUF" "$work/tree-sitter-javascript"
tree-sitter build --output "$work/grammars/typescript.$GSUF" "$work/tree-sitter-typescript/typescript"
tree-sitter build --output "$work/grammars/tsx.$GSUF" "$work/tree-sitter-typescript/tsx"

echo "== packaging the engine (scripts/package.lua)"
STATIC_LIBS="$work/static-libs"
mkdir -p "$STATIC_LIBS"
cp "$work/lua_tree_sitter.a" "$work/lfs.a" "$STATIC_LIBS/"

cd "$repo"
LUA_INCDIR="$LUAINC" \
LUA_LIBA="$LUALIBA" \
DOCMAP_STATIC_LIBS="$STATIC_LIBS" \
CC=gcc \
LUASTATIC="$work/luastatic.lua" \
DOCMAP_TS_DIR="$work/grammars" \
LUA_CPATH="$work/?.dyn.so;;" \
LUA_PATH="$work/?.lua;;" \
"$LUABIN" scripts/package.lua --out=build --keep
# --out must be relative -- scripts/package.lua computes several paths as
# `cwd .. "/" .. out_dir` unconditionally (PORTABILITY.md, Step 6); staying
# relative and cd-ing into $repo first sidesteps that rather than teaching
# the script a case nothing else needs.

echo "== staging release assets"
mkdir -p "$out"
cp "build/docmap$EXE_EXT" "$out/docmap-$TRIPLE$EXE_EXT"
tar czf "$out/grammars-$TRIPLE.tar.gz" -C "$work/grammars" .

echo "done:"
ls -la "$out"
