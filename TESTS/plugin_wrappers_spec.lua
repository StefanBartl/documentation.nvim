-- TESTS/plugin_wrappers_spec.lua — specs registered through a caller's own helper
--
-- `core/plugins.lua` reads the module's own top-level `return { … }`, and its
-- header said every real `lua/plugins/*.lua` uses that form. **Measured
-- again, that stopped being true**: one real config's *largest* spec file is
-- 906 lines registering through `plugins.add({ … })` and exporting the
-- result, and the scan found zero specs in it. Declaring the one wrapper took
-- that config from 52 specs to 85 — sixty-three per cent of it had been
-- invisible, silently, and the Plugins and Lazy-loading panels were both
-- answering about the half that happened to use a table literal.
--
-- Declared, never detected — the same choice `core/bindings.lua` made for
-- keymap wrappers. A helper that takes the spec array as its first argument
-- is declarable; one that reorders or builds it from something else is not,
-- and guessing which is which is how a scanner starts inventing plugins.

return function(H)
  local eq, ok = H.eq, H.ok

  local plugins = require("documentation.core.plugins")
  local functions = require("documentation.core.functions")

  ---Write a Lua file and scan it, with `wrappers` declared for that scan.
  ---@param lines string[]
  ---@param wrappers table<string, true>?
  ---@return Documentation.PluginSpec[]
  local function specs_of(lines, wrappers)
    local path = H.tmpfile(".lua")
    local fd = assert(io.open(path, "w"))
    fd:write(table.concat(lines, "\n"))
    fd:close()
    -- Set and restored around each case rather than left standing: this is a
    -- scan-scoped field, and a spec that leaked it would make the next case
    -- pass for the previous one's reason.
    local before = plugins.WRAPPERS
    plugins.WRAPPERS = wrappers or plugins.DEFAULT_WRAPPERS
    local _, _, _, _, out = functions.scan_file(path)
    plugins.WRAPPERS = before
    return out
  end

  local WRAPPED = {
    "---@module 'plugins.personal'",
    'local helper = require("plugins.control")',
    "",
    "helper.add({",
    "  {",
    '    "author/one",',
    '    event = "VeryLazy",',
    "  },",
    '  "author/two",',
    "})",
    "",
    "return helper.export()",
  }

  -- ---------------------------------------------------------------------
  -- The default changes nothing. Every config that does not declare a
  -- wrapper must produce exactly the map it produced before this existed.
  -- ---------------------------------------------------------------------
  do
    eq(#specs_of(WRAPPED), 0, "wrappers: undeclared, a helper call contributes nothing")
  end

  -- ---------------------------------------------------------------------
  -- Declared, the same file is read — and read the same way a bare `return`
  -- would be, because the ambiguity is about the *table*, not about how the
  -- table was reached.
  -- ---------------------------------------------------------------------
  do
    local found = specs_of(WRAPPED, { ["helper.add"] = true })
    eq(#found, 2, "wrappers: both entries of the declared call are read")
    eq(found[1].repo, "author/one")
    eq(found[1].event[1], "VeryLazy", "wrappers: options are parsed, not just the repo")
    eq(found[2].repo, "author/two", "wrappers: the bare-string shorthand too")
  end

  -- A single-spec table inside a wrapper is one plugin, not an array whose
  -- first element is a trigger value. This is the same ambiguity the bare
  -- `return` shape has, and the reason the resolution is shared code rather
  -- than written twice.
  do
    local found = specs_of({
      "---@module 'plugins.one'",
      "helper.add({",
      '  "author/single",',
      '  event = "VeryLazy",',
      "})",
    }, { ["helper.add"] = true })
    eq(#found, 1, "wrappers: a single-spec table is one plugin")
    eq(found[1].repo, "author/single", "wrappers: ...and its repo is the repo")
    eq(found[1].event[1], "VeryLazy", "wrappers: ...not read as a positional element")
  end

  -- ---------------------------------------------------------------------
  -- The first table argument, and only it. A helper taking `(specs, opts)`
  -- must not have its options read as a second spec array — that would
  -- invent plugins out of configuration, which is the failure this whole
  -- declared-not-detected posture exists to avoid.
  -- ---------------------------------------------------------------------
  do
    local found = specs_of({
      "---@module 'plugins.two'",
      "helper.add({",
      '  { "author/real" },',
      "}, {",
      '  { "author/notaplugin" },',
      "})",
    }, { ["helper.add"] = true })
    eq(#found, 1, "wrappers: only the first table argument is a spec array")
    eq(found[1].repo, "author/real")
  end

  -- ---------------------------------------------------------------------
  -- A bare identifier resolves too — `add({…})`, not only `helper.add({…})`
  -- — because a config may localise the helper. A computed callee does not:
  -- `t[k](…)` is not a name a reader could have declared.
  -- ---------------------------------------------------------------------
  do
    eq(
      #specs_of({ "---@module 'p'", 'add({ { "a/b" } })' }, { add = true }),
      1,
      "wrappers: a bare identifier callee resolves"
    )
    eq(
      #specs_of({ "---@module 'p'", 't[k]({ { "a/b" } })' }, { add = true }),
      0,
      "wrappers: a computed callee is not a declarable name"
    )
  end

  -- ---------------------------------------------------------------------
  -- Both shapes in one file, and the order they read in.
  --
  -- Any depth for the wrapper call, unlike the `return` shape which is a
  -- direct child of the chunk: the real file that motivated this puts the
  -- call after two requires and a comment banner, and a config could as
  -- easily put it inside an `if`. There is no position rule to lean on.
  -- ---------------------------------------------------------------------
  do
    local found = specs_of({
      "---@module 'p'",
      "if true then",
      '  helper.add({ { "nested/one" } })',
      "end",
      'return { { "literal/one" } }',
    }, { ["helper.add"] = true })
    eq(#found, 2, "wrappers: a call nested inside a block is still found")
    eq(found[1].repo, "literal/one", "wrappers: the literal return reports first")
    eq(found[2].repo, "nested/one")
  end

  -- An undeclared helper beside a declared one contributes nothing, which is
  -- what makes this an allow list rather than a heuristic.
  do
    local found = specs_of({
      "---@module 'p'",
      'known.add({ { "a/yes" } })',
      'unknown.add({ { "a/no" } })',
    }, { ["known.add"] = true })
    eq(#found, 1, "wrappers: only declared callees are read")
    eq(found[1].repo, "a/yes")
  end

  ok(
    next(plugins.DEFAULT_WRAPPERS) == nil,
    "wrappers: the default is empty — nothing is assumed about anyone's config"
  )

  -- ---------------------------------------------------------------------
  -- Other plugin managers.
  --
  -- The plan rated packer / vim-plug / mini.deps **M**, as three separate
  -- extractors. Measured first, they were not: all three register through a
  -- call taking either a table or a string, which is what a declared wrapper
  -- already walks. What was actually missing was two small things — a string
  -- argument, and three key spellings — and those are what the cases below
  -- pin down. Written as the three managers rather than as the two
  -- mechanisms on purpose: the mechanisms are the implementation, the
  -- managers are the promise.
  -- ---------------------------------------------------------------------
  do
    local found = specs_of({
      "---@module 'p'",
      'return require("packer").startup(function(use)',
      '  use "wbthomason/packer.nvim"',
      "  use {",
      '    "nvim-telescope/telescope.nvim",',
      '    requires = { "nvim-lua/plenary.nvim" },',
      '    cmd = "Telescope",',
      "  }",
      "end)",
    }, { use = true })
    eq(#found, 2, "packer: both the string and the table form of `use`")
    eq(found[1].repo, "wbthomason/packer.nvim", 'packer: `use "a/b"` is a spec')
    eq(found[2].cmd[1], "Telescope", "packer: shares lazy.nvim's trigger keys")
    eq(
      found[2].dependencies[1],
      "nvim-lua/plenary.nvim",
      "packer: `requires` is the same edge as `dependencies`"
    )
  end

  do
    local found = specs_of({
      "---@module 'p'",
      'Plug("tpope/vim-surround")',
      'Plug("junegunn/fzf.vim")',
      "}",
    }, { Plug = true })
    eq(#found, 2, "vim-plug: each `Plug(...)` call is one spec")
    eq(found[1].repo, "tpope/vim-surround")
  end

  do
    local found = specs_of({
      "---@module 'p'",
      'add("echasnovski/mini.nvim")',
      'add({ source = "nvim-lua/plenary.nvim", depends = { "a/b" } })',
    }, { add = true })
    eq(#found, 2, "mini.deps: the string form and the table form")
    eq(found[2].repo, "nvim-lua/plenary.nvim", "mini.deps: `source` is the repo")
    eq(found[2].dependencies[1], "a/b", "mini.deps: `depends` is the same edge")
  end

  -- A declared wrapper called for something else stays silent: the string
  -- has to look like a repo. This is what keeps `add = true` from turning
  -- every `add("some string")` in the file into a plugin.
  do
    eq(
      #specs_of({ "---@module 'p'", 'add("just a message")' }, { add = true }),
      0,
      "wrappers: a string argument that is not repo-shaped is not a plugin"
    )
  end
end
