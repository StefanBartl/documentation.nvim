-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
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

  -- `- **Tab:** true` promotion: consumed out of `meta` into `tab`, and the
  -- rich `body` capture — three shapes verified empirically against a real
  -- fixture before writing this, not assumed: a Tab-only bullet with
  -- nothing else in the section, Tab plus a body paragraph, and Tab plus
  -- another bullet with nothing trailing.
  do
    local dr = H.tmpfile("_features_tab")
    dwrite(
      dr,
      "docs/FEATURES/T.md",
      table.concat({
        "## Ordinary feature",
        "",
        "Never promoted.",
        "",
        "- **Module:** `plain.lua`",
        "",
        "## Only Tab bullet, nothing else",
        "",
        "Summary line.",
        "",
        "- **Tab:** true",
        "",
        "## Tab plus body",
        "",
        "Summary line two.",
        "",
        "- **Tab:** true",
        "- **Module:** `x.lua`",
        "",
        "Rich body paragraph here.",
        "",
        "### A subheading",
        "",
        "- a list item",
        "- another",
        "",
        "## Tab plus module only, no trailing body",
        "",
        "Summary line three.",
        "",
        "- **Tab:** true",
        "- **Module:** `y.lua`",
      }, "\n")
    )

    local result = features.resolve(dr)
    local f = result.files[1]
    eq(#f.entries, 4, "tab: four sections in the fixture")

    local plain = f.entries[1]
    eq(plain.tab, false, "tab: an ordinary feature is not promoted")
    eq(plain.body, nil, "tab: an ordinary feature never carries a body, even unpromoted")
    eq(#plain.meta, 1, "tab: ordinary feature's own bullet is untouched")

    local only_tab = f.entries[2]
    eq(only_tab.tab, true, "tab: Tab: true promotes the feature")
    eq(#only_tab.meta, 0, "tab: the Tab bullet itself never appears in meta")
    eq(only_tab.body, nil, "tab: nothing follows the metadata block — no body, not an error")

    local with_body = f.entries[3]
    eq(with_body.tab, true, "tab+body: promoted")
    eq(#with_body.meta, 1, "tab+body: Tab consumed, Module remains")
    eq(with_body.meta[1].key, "Module", "tab+body: the surviving bullet is Module")
    ok(
      with_body.body ~= nil and with_body.body:find("Rich body paragraph here.", 1, true) ~= nil,
      "tab+body: the rich body is captured"
    )
    ok(
      with_body.body:find("### A subheading", 1, true) ~= nil,
      "tab+body: a subheading inside the body is captured verbatim (rendering it is the HTML tab's job, not the parser's)"
    )

    local module_only = f.entries[4]
    eq(module_only.tab, true, "tab+module-only: promoted")
    eq(#module_only.meta, 1, "tab+module-only: Tab consumed, Module remains")
    eq(
      module_only.body,
      nil,
      "tab+module-only: metadata block runs to the end of the section — no body"
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

  -- ------------------------------------------------- single-file catalogue

  -- `docs/FEATURES.md` instead of `docs/FEATURES/`. Nine of the sibling
  -- repos had picked the single file, and resolve() returned nil for every
  -- one of them — a well-formed catalogue that the Features tab reported as
  -- "no features". The parse is the same parse; only the lookup changed.
  do
    local dr = H.tmpfile("_features_single")
    dwrite(
      dr,
      "docs/FEATURES.md",
      table.concat({
        "# Features",
        "",
        "Everything this thing does.",
        "",
        "## First",
        "",
        "Does a thing.",
        "",
        "- **Module:** `a.lua`",
        "",
        "## Second",
        "",
        "Does another.",
        "",
      }, "\n")
    )
    local result = features.resolve(dr)
    ok(result ~= nil, "resolve: a single docs/FEATURES.md resolves")
    eq(result.folder, "docs/FEATURES.md", "resolve: names the file it found")
    eq(#result.files, 1, "resolve: the single file is the one and only theme")
    eq(result.files[1].theme, "FEATURES", "resolve: theme name comes from the file name")
    eq(result.files[1].path, "docs/FEATURES.md", "resolve: path is repo-relative")
    eq(#result.files[1].entries, 2, "resolve: both sections parsed")
    eq(result.files[1].entries[1].name, "First", "resolve: first section")
    eq(result.files[1].entries[1].meta[1].key, "Module", "resolve: metadata parsed as usual")
    eq(
      result.files[1].intro,
      "Everything this thing does.",
      "resolve: the file's own intro is the file intro, not the folder intro"
    )
    eq(result.intro, nil, "resolve: a single file has no folder intro")
  end

  -- The folder wins. A repo splitting a grown FEATURES.md into themes can
  -- leave the old file in place while it works, without the two fighting.
  do
    local dr = H.tmpfile("_features_single_and_folder")
    dwrite(dr, "docs/FEATURES.md", "## From the file\n\nOld.\n")
    dwrite(dr, "docs/FEATURES/CORE.md", "## From the folder\n\nNew.\n")
    local result = features.resolve(dr)
    eq(result.folder, "docs/FEATURES", "resolve: the folder wins over the single file")
    eq(
      result.files[1].entries[1].name,
      "From the folder",
      "resolve: and its content is what comes back"
    )
  end

  -- ------------------------------------------------------------- ordering

  -- `core` first, then `FEATURES`, then the rest alphabetically. Name order
  -- alone put ARCHITECTURE above CORE, which is the reverse of the order
  -- somebody reads them in — core is the answer to "why would I install
  -- this", so it goes at the top.
  do
    local dr = H.tmpfile("_features_order")
    for _, name in ipairs({ "ZEBRA", "CORE", "ARCHITECTURE", "FEATURES", "misc" }) do
      dwrite(dr, "docs/FEATURES/" .. name .. ".md", "## In " .. name .. "\n\nText.\n")
    end
    local result = features.resolve(dr)
    local order = {}
    for _, f in ipairs(result.files) do
      order[#order + 1] = f.theme
    end
    eq(
      table.concat(order, ","),
      "CORE,FEATURES,ARCHITECTURE,ZEBRA,misc",
      "resolve: core first, FEATURES second, the rest by name"
    )
  end

  -- The match is case-insensitive: a repo writing core.md gets the same slot
  -- as one writing CORE.md.
  do
    local dr = H.tmpfile("_features_order_case")
    for _, name in ipairs({ "alpha", "core" }) do
      dwrite(dr, "docs/FEATURES/" .. name .. ".md", "## In " .. name .. "\n\nText.\n")
    end
    local result = features.resolve(dr)
    eq(result.files[1].theme, "core", "resolve: lowercase core still leads")
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
