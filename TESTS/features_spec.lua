-- TESTS/features_spec.lua — `core/features.lua` (the `docs/FEATURES/`
-- reader behind the Features tab / `ir.features`).
--
-- Its own file, not a block in docmap_spec.lua, for the same reason
-- `check_type_vs_class_spec.lua`/`tools_spec.lua` are: this needs real
-- files on disk. The fixtures below intentionally mirror shapes found in
-- markdown.nvim's real `docs/FEATURES/headings.md` while developing this
-- parser — the multi-line wrapped bullet in particular is not a synthetic
-- edge case, it is what broke the parser's first version against real data.

return function(H)
  local eq, ok = H.eq, H.ok
  local features = require("documentation.core.features")
  local docmap = require("documentation")

  local function dwrite(root, rel, text)
    local abs = root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "features spec: fixture must be writable")
    fd:write(text)
    fd:close()
  end

  -- ---------------------------------------------------------------- resolve

  -- No docs/FEATURES, no docs/features at all.
  do
    local dr = H.tmpfile("_features_none")
    vim.fn.mkdir(dr, "p")
    eq(features.resolve(dr), nil, "resolve: nil when the repo has no FEATURES folder at all")
  end

  -- A folder that exists but holds no .md files at all — not an error.
  do
    local dr = H.tmpfile("_features_empty_dir")
    vim.fn.mkdir(dr .. "/docs/FEATURES", "p")
    local result = features.resolve(dr)
    ok(result ~= nil, "resolve: an existing-but-empty folder still resolves")
    eq(result.folder, "docs/FEATURES", "resolve: names the folder found")
    eq(#result.files, 0, "resolve: zero theme files is a real, valid state")
  end

  -- The full shape: intro README, a `# Title` + prose theme file, a section
  -- with no metadata at all, a section with a multi-line wrapped bullet
  -- followed by a second bullet, and a section where prose follows the
  -- metadata run with no blank line separating them.
  do
    local dr = H.tmpfile("_features_full")
    dwrite(dr, "docs/FEATURES/README.md", "# Features\n\nThe folder's own intro.\n")
    dwrite(
      dr,
      "docs/FEATURES/UI.md",
      table.concat({
        "# UI",
        "",
        "Everything that draws something on screen.",
        "",
        "## Cache eviction indicator",
        "",
        "A feature does not have to be a visible action.",
        "",
        "## Status line marker",
        "",
        "Shows the current mode, updated on every mode change.",
        "",
        "- **Module:** `ui/statusline.lua` (`render`, `on_mode_changed`,",
        "  `on_theme_changed`)",
        "- **Config:** `opts.statusline.enabled` (default `true`)",
        "",
        "## Trailing prose, no blank line before it",
        "",
        "Summary line.",
        "",
        "- **Module:** `ui/trailing.lua`",
        "This line follows the bullet run with no blank line in between.",
      }, "\n")
    )

    local result = features.resolve(dr)
    ok(result ~= nil, "resolve: reads a real docs/FEATURES folder")
    eq(result.folder, "docs/FEATURES", "resolve: uppercase folder name")
    eq(
      result.intro,
      "# Features\n\nThe folder's own intro.",
      "resolve: README.md read as the folder intro"
    )
    eq(#result.files, 1, "resolve: README.md is never itself a theme file")

    local f = result.files[1]
    eq(f.theme, "UI", "resolve: theme is the filename without extension")
    eq(
      f.intro,
      "Everything that draws something on screen.",
      "resolve: prose before the first ## is the file's own intro"
    )
    eq(#f.entries, 3, "resolve: three ## sections")

    local e1 = f.entries[1]
    eq(e1.name, "Cache eviction indicator", "entry 1: name")
    eq(e1.summary, "A feature does not have to be a visible action.", "entry 1: summary")
    eq(#e1.meta, 0, "entry 1: no metadata bullets — a metadata-free feature is valid")

    local e2 = f.entries[2]
    eq(e2.name, "Status line marker", "entry 2: name")
    eq(#e2.meta, 2, "entry 2: two bullets")
    eq(
      e2.meta[1].value,
      "`ui/statusline.lua` (`render`, `on_mode_changed`, `on_theme_changed`)",
      "entry 2: the wrapped continuation line is folded into the bullet's own value, not treated as ending the run"
    )
    eq(e2.meta[2].key, "Config", "entry 2: second bullet's key")

    local e3 = f.entries[3]
    eq(e3.summary, "Summary line.", "entry 3: summary")
    eq(
      #e3.meta,
      1,
      "entry 3: exactly the one bullet — the flush-left prose after it is not folded in"
    )
    eq(
      e3.meta[1].value,
      "`ui/trailing.lua`",
      "entry 3: a flush-left non-bullet line ends the metadata run instead of being appended to it"
    )
  end

  -- Lowercase docs/features fallback, and uppercase preferred when both
  -- exist — same resolution-order precedent as core/tools.lua's own
  -- docs/install.json-over-docs/INSTALL.md. Only meaningful on a
  -- case-sensitive filesystem — Windows' NTFS treats "docs/FEATURES" and
  -- "docs/features" as the same directory, so the two candidates are
  -- indistinguishable there. Same "POSIX-specific, verified on CI instead"
  -- posture the project's own checklist notes already take for other
  -- platform-dependent behavior; detected rather than assumed, since CI
  -- runs `ubuntu-latest` but a contributor could run either.
  local case_sensitive = (function()
    local dr = H.tmpfile("_features_case_probe")
    vim.fn.mkdir(dr .. "/Probe", "p")
    local uv = vim.uv or vim.loop
    return uv.fs_stat(dr .. "/probe") == nil
  end)()

  if case_sensitive then
    local dr_lower = H.tmpfile("_features_lower")
    dwrite(dr_lower, "docs/features/misc.md", "## Only entry\n\nSomething.\n")
    local lower = features.resolve(dr_lower)
    eq(lower.folder, "docs/features", "resolve: falls back to lowercase docs/features")

    local dr_both = H.tmpfile("_features_both")
    dwrite(dr_both, "docs/FEATURES/a.md", "## A\n\nUppercase.\n")
    dwrite(dr_both, "docs/features/b.md", "## B\n\nLowercase.\n")
    local both = features.resolve(dr_both)
    eq(both.folder, "docs/FEATURES", "resolve: uppercase preferred when a repo somehow ships both")
  end

  -- ----------------------------------------------------- scan_full wiring

  -- ir.features is set, through the real pipeline, not just the standalone
  -- resolve() call above.
  do
    local dr = H.tmpfile("_features_scan_full")
    dwrite(
      dr,
      "lua/t/init.lua",
      table.concat({
        "---@module 't'",
        "--- A trivial module, just so the scan has something to walk.",
        "local M = {}",
        "return M",
      }, "\n")
    )
    dwrite(dr, "docs/FEATURES/CORE.md", "## Only feature\n\nSomething real.\n")

    local ir =
      docmap.scan_full({ root = dr, source = "lua/t", lua_root = "lua", extra_checks = {} })
    ok(ir.features ~= nil, "scan_full: ir.features set when the repo ships docs/FEATURES")
    eq(
      ir.features.files[1].entries[1].name,
      "Only feature",
      "scan_full: real content reaches ir.features"
    )
  end

  -- No docs/FEATURES at all: ir.features stays nil, same as ir.tools does
  -- for a repo with no lib.nvim.deps manifest.
  do
    local dr = H.tmpfile("_features_scan_full_none")
    dwrite(
      dr,
      "lua/t/init.lua",
      table.concat({
        "---@module 't'",
        "--- A trivial module with no docs/FEATURES folder at all.",
        "local M = {}",
        "return M",
      }, "\n")
    )

    local ir =
      docmap.scan_full({ root = dr, source = "lua/t", lua_root = "lua", extra_checks = {} })
    eq(ir.features, nil, "scan_full: ir.features stays nil when the repo ships no FEATURES folder")
  end
end
