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
#
# Windows needs both dynamic builds linked against `$LUALIBA` explicitly:
# a DLL's imports resolve at link time, not load time, so without it this
# fails with "undefined reference to `lua_pushstring`" (found by the
# first real CI run). Linux does not need the link — the host `lua`
# binary was built with `-Wl,-E` (`SYSLIBS="-Wl,-E -ldl"` in its own build
# log) specifically so a lazily-`dlopen`ed module resolves those symbols
# against the *process* — and adding it anyway broke Linux a different
# way, also found by a real run rather than predicted: `make linux`'s
# `liblua.a` is not built with `-fPIC`, and a non-PIC static archive
# cannot be linked into a `-shared` output at all ("relocation ... can
# not be used when making a shared object"). Two real, independently
# discovered failures, one per platform, each ruling out the "just always
# link it" fix that looked simplest after finding the first one.
LTS_LINK_LIBS=()
[ -n "$EXE_EXT" ] && LTS_LINK_LIBS=("$LUALIBA")

echo "== dynamic lfs + dkjson (so the host interpreter running package.lua can require() them)"
gcc -O2 -fPIC -shared -I"$LUAINC" "$work/luafilesystem/src/lfs.c" "${LTS_LINK_LIBS[@]}" -o "$work/lfs.dyn.so"
curl -sL -o "$work/dkjson.lua" https://raw.githubusercontent.com/LuaDist/dkjson/master/dkjson.lua

echo "== dynamic lua_tree_sitter.so (so bundle_manifest.lua's probe run can see the real treesitter closure)"
(
  cd "$work/lua-tree-sitter"
  gcc -O2 -fPIC -shared "${LTS_INC[@]}" "${LTS_SRC[@]}" "${LTS_LINK_LIBS[@]}" -o "$work/lua_tree_sitter.dyn.so"
)

echo "== luastatic (a plain Lua script, not a build target)"
curl -sL -o "$work/luastatic.lua" https://raw.githubusercontent.com/ers35/luastatic/master/luastatic.lua

echo "== 10 grammars via the tree-sitter CLI"
# The same mechanism .github/workflows/ci.yml's own `tests` job already
# uses for JS/TS/TSX -- `tree-sitter build` needs no separate libtree-sitter
# at all, since a grammar's shared library depends only on the C ABI in
# tree_sitter/parser.h. Simpler than compiling each grammar by hand, and
# already CI-proven for three of the four languages.
TSC=tree-sitter
if ! command -v tree-sitter >/dev/null 2>&1; then
  # Not `npm install -g`: that install's own PATH visibility turned out to
  # be a moving target rather than a portable fact. It "just worked" on a
  # plain Linux runner (ubuntu-latest happens to put its global bin
  # directory on PATH by default), then needed `npm config get prefix` to
  # find inside an MSYS2/MinGW64 shell, and even that broke on the next
  # real run: this environment's own npm reports a `prefix`
  # (`C:\npm\prefix`) that the installed binary was not actually under --
  # apparently a default baked into the `mingw-w64-x86_64-nodejs`
  # package's own npmrc, not the real install location.
  #
  # A local, `--prefix`-pinned install sidesteps all three failures by
  # construction: the destination is a path this script chose and already
  # knows, not one to rediscover afterward by asking npm, reading `PATH`,
  # or guessing a per-platform layout.
  npm install --prefix "$work/npm-local" tree-sitter-cli
  TSC="$work/npm-local/node_modules/.bin/tree-sitter"
  [ -n "$EXE_EXT" ] && TSC="$work/npm-local/node_modules/.bin/tree-sitter.cmd"
fi
mkdir -p "$work/grammars"
GSUF="so"
[ -n "$EXE_EXT" ] && GSUF="dll"
git clone --quiet --depth 1 https://github.com/tree-sitter-grammars/tree-sitter-lua.git "$work/tree-sitter-lua"
git clone --quiet --depth 1 https://github.com/tree-sitter/tree-sitter-javascript.git "$work/tree-sitter-javascript"
git clone --quiet --depth 1 https://github.com/tree-sitter/tree-sitter-typescript.git "$work/tree-sitter-typescript"
git clone --quiet --depth 1 https://github.com/tree-sitter-grammars/tree-sitter-zig.git "$work/tree-sitter-zig"
git clone --quiet --depth 1 https://github.com/tree-sitter/tree-sitter-java.git "$work/tree-sitter-java"
git clone --quiet --depth 1 https://github.com/tree-sitter/tree-sitter-c.git "$work/tree-sitter-c"
git clone --quiet --depth 1 https://github.com/tree-sitter/tree-sitter-cpp.git "$work/tree-sitter-cpp"
git clone --quiet --depth 1 https://github.com/tree-sitter/tree-sitter-python.git "$work/tree-sitter-python"
git clone --quiet --depth 1 https://github.com/tree-sitter/tree-sitter-c-sharp.git "$work/tree-sitter-c-sharp"
"$TSC" build --output "$work/grammars/lua.$GSUF" "$work/tree-sitter-lua"
"$TSC" build --output "$work/grammars/javascript.$GSUF" "$work/tree-sitter-javascript"
"$TSC" build --output "$work/grammars/typescript.$GSUF" "$work/tree-sitter-typescript/typescript"
"$TSC" build --output "$work/grammars/tsx.$GSUF" "$work/tree-sitter-typescript/tsx"
"$TSC" build --output "$work/grammars/zig.$GSUF" "$work/tree-sitter-zig"
"$TSC" build --output "$work/grammars/java.$GSUF" "$work/tree-sitter-java"
"$TSC" build --output "$work/grammars/c.$GSUF" "$work/tree-sitter-c"
"$TSC" build --output "$work/grammars/cpp.$GSUF" "$work/tree-sitter-cpp"
"$TSC" build --output "$work/grammars/python.$GSUF" "$work/tree-sitter-python"
"$TSC" build --output "$work/grammars/c_sharp.$GSUF" "$work/tree-sitter-c-sharp"

echo "== packaging the engine (scripts/package.lua)"
STATIC_LIBS="$work/static-libs"
mkdir -p "$STATIC_LIBS"
cp "$work/lua_tree_sitter.a" "$work/lfs.a" "$STATIC_LIBS/"

# `$work` (from `mktemp -d`) is an *MSYS2-internal* path on Windows --
# `/tmp/tmp.XXXXX`, rooted at wherever MSYS2's own virtual filesystem
# lives (`D:\a\_temp\msys64\tmp\...` on this runner). `bash` and the
# msys2-native tools this script has run so far (gcc, git, curl, cp,
# mkdir) all understand that transparently. `lua.exe` does not: it is a
# genuine Windows binary with no msys2 runtime linked in, and reads an
# environment variable's *value* as plain text -- there is no exec-time
# argv translation the way there is for a bash-invoked command line, so
# it sees the literal string `/tmp/tmp.XXXXX/...` and, on Windows,
# interprets a leading `/` as "root of the current drive": a completely
# different, nonexistent location. `cygpath -m` converts to the real
# Windows path with forward slashes (which Windows' own CRT accepts, so
# no further quoting change is needed downstream).
#
# Found the hard way: `LUA_CPATH`, unconverted, produced a `require('lfs')`
# failure whose own search-path dump showed exactly this split -- default,
# executable-relative entries resolved to real paths; the one entry built
# from `$work` did not.
topath() {
  if [ -n "$EXE_EXT" ]; then
    cygpath -m "$1"
  else
    printf '%s' "$1"
  fi
}
LUAINC_N="$(topath "$LUAINC")"
LUALIBA_N="$(topath "$LUALIBA")"
STATIC_LIBS_N="$(topath "$STATIC_LIBS")"
LUASTATIC_N="$(topath "$work/luastatic.lua")"
GRAMMARS_N="$(topath "$work/grammars")"
WORK_N="$(topath "$work")"

cd "$repo"
LUA_INCDIR="$LUAINC_N" \
LUA_LIBA="$LUALIBA_N" \
DOCMAP_STATIC_LIBS="$STATIC_LIBS_N" \
CC=gcc \
LUASTATIC="$LUASTATIC_N" \
DOCMAP_TS_DIR="$GRAMMARS_N" \
LUA_CPATH="$WORK_N/?.dyn.so;;" \
LUA_PATH="$WORK_N/?.lua;;" \
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
