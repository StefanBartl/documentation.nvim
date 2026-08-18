-- TESTS/detect_source_spec.lua — documentation.config.detect_source
--
-- Its own file because the thing under test is a *dispatch*, not a
-- heuristic: `config.detect_source` used to be Lua's own guess and nothing
-- else, which meant every tree without a `lua/` directory got `"lua"` back
-- and died on `scan.lua`'s assert. Each case below is one shape that
-- reached that failure, or one that must keep working exactly as before.

return function(H)
  local eq = H.eq
  local cfg = require("documentation.config")

  -- Joined rather than compared as tables: `H.eq` is `~=`, which on two
  -- tables asks whether they are the same table, and every expectation here
  -- is a fresh literal. Adding deep equality to the shared harness for one
  -- spec would be a wider change than the thing it is testing.
  ---@param root string
  ---@return string
  local function detected(root)
    return table.concat(cfg.detect_source(root), " + ")
  end

  -- Real trees under the OS temp dir. Written rather than mocked: the whole
  -- question is what the filesystem actually holds, and a mocked `isdirectory`
  -- would be asserting that the mock agrees with itself.
  local root = (vim.fn.tempname():gsub("\\", "/"))

  ---@param files string[] Repo-relative paths; parent directories are created.
  ---@return string abs
  local function tree(name, files)
    local abs = root .. "/" .. name
    for _, rel in ipairs(files) do
      local path = abs .. "/" .. rel
      vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
      local fd = io.open(path, "w")
      if fd then
        fd:write("")
        fd:close()
      end
    end
    vim.fn.mkdir(abs, "p")
    return abs
  end

  -- The shape every existing user has, and the one that must not move.
  eq(
    detected(tree("plugin", { "lua/thing/init.lua", "lua/thing/util.lua" })),
    "lua/thing",
    "detect_source: lua/<single subdirectory> still wins for a Neovim plugin"
  )
  eq(
    detected(tree("twodirs", { "lua/a/init.lua", "lua/b/init.lua" })),
    "lua",
    "detect_source: ... and two candidates fall back to lua rather than guessing"
  )
  eq(
    detected(tree("typesonly", { "lua/thing/init.lua", "lua/@types/init.lua" })),
    "lua/thing",
    "detect_source: @types is not a candidate source root"
  )

  -- The failure this dispatch exists for. Before it, this returned "lua"
  -- and the scan asserted on a directory that does not exist.
  eq(
    detected(tree("jsproj", { "src/a.js", "src/b.ts", "package.json" })),
    "src",
    "detect_source: a JavaScript project resolves to src, not to a lua/ that is not there"
  )
  eq(
    detected(tree("libproj", { "lib/a.ts" })),
    "lib",
    "detect_source: ... and lib when that is where the sources are"
  )

  -- Evidence, not convention: a `src/` this backend cannot read is not its
  -- source root. Without this, any repository with a src/ of shell scripts
  -- would be claimed as JavaScript.
  eq(
    detected(tree("shellsrc", { "src/build.sh", "src/deploy.sh" })),
    ".",
    "detect_source: a src/ holding nothing any backend reads is not claimed"
  )

  -- A vendored tree full of JavaScript must not make an unrelated directory
  -- look like the project's own source.
  eq(
    detected(tree("vendored", { "src/node_modules/dep/index.js" })),
    ".",
    "detect_source: node_modules is not evidence of this project's own language"
  )

  -- Nothing recognised: the root, which always exists. An honest empty map
  -- rather than an assertion naming a directory the user never had.
  eq(
    detected(tree("python", { "app/main.py", "README.md" })),
    ".",
    "detect_source: an unreadable tree falls back to the root, not to a crash"
  )

  -- A package with sources directly in the root and no src/ at all.
  eq(
    detected(tree("flat", { "index.js", "helper.js" })),
    ".",
    "detect_source: files in the root are found when there is no conventional directory"
  )

  -- Two languages in two directories: the case a single answer silently
  -- lost. Both are returned, in registration order.
  eq(
    detected(tree("polyglot", { "lua/core/init.lua", "src/a.js", "src/b.ts" })),
    "lua/core + src",
    "detect_source: a mixed tree reports every root, not just the first"
  )

  -- One backend answering with a directory that contains another's is
  -- dropped: keeping both would walk lua/thing twice and duplicate every
  -- node in it. Here ECMA falls back to the root for a stray .js while Lua
  -- names lua/thing.
  eq(
    detected(tree("straybelow", { "lua/thing/init.lua", "stray.js" })),
    "lua/thing",
    "detect_source: a candidate containing another candidate is dropped"
  )

  vim.fn.delete(root, "rf")
end
