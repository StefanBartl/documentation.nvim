-- TESTS/checklist_spec.lua — `documentation.core.checklist`, the hand-verified
-- ledger and its staleness verdict.
--
-- Two halves, tested differently on purpose, mirroring the module's own split:
--
--   * `parse`/`resolve` read Markdown off disk and are exercised against real
--     fixture files, because the whole format is "what a person actually
--     typed" and the failure modes worth catching are typographic (a `*`
--     bullet instead of `-`, an uppercase `[X]`, a comment block that should
--     have stopped attaching).
--   * `status` never touches git — it takes a `path -> commit dates` table —
--     so every staleness case is driven from a literal table here, with no
--     repository, no commits and no clock involved. That is the same split
--     `core/churn.lua` uses and the reason its scoring is testable at all.

return function(H)
  local eq = H.eq
  local checklist = require("documentation.core.checklist")

  local function dwrite(root, rel, lines)
    local abs = root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "checklist spec: fixture must be writable")
    fd:write(table.concat(lines, "\n"))
    fd:close()
  end

  -- ── parse ────────────────────────────────────────────────────────────────

  do
    local sections = checklist.parse(
      table.concat({
        "# Project checklist",
        "",
        "Some intro prose that is not an item.",
        "",
        "## Keybindings",
        "",
        "- [x] `<leader>xy` supports count where it should",
        "      <!-- @ref lua/plugins/dap/keymaps.lua:32 -->",
        "      <!-- @verified 2026-08-08 -->",
        "- [ ] Picker inputs support autocompletion",
        "      <!-- @ref lua/plugins/foo/usrcmds.lua:14 -->",
        "",
        "## Security",
        "",
        "* [X] No plugin writes outside stdpath",
        "      <!-- @owner stefan -->",
        "- [ ] An item that cites nothing at all",
      }, "\n"),
      "docs/CHECKLIST/demo.md"
    )

    eq(#sections, 2, "parse: one section per `## ` heading, intro prose is not one")
    eq(sections[1].name, "Keybindings", "parse: section name is the heading text")
    eq(#sections[1].items, 2, "parse: both items in the first section")

    local first = sections[1].items[1]
    eq(first.done, true, "parse: `- [x]` is done")
    eq(first.text, "`<leader>xy` supports count where it should", "parse: item text, trimmed")
    eq(first.ref, "lua/plugins/dap/keymaps.lua", "parse: @ref path, without the line suffix")
    eq(first.ref_line, 32, "parse: @ref line, as a number")
    eq(first.verified, "2026-08-08", "parse: @verified date, verbatim")
    eq(first.file, "docs/CHECKLIST/demo.md", "parse: item carries its own file")

    local second = sections[1].items[2]
    eq(second.done, false, "parse: `- [ ]` is not done")
    eq(second.verified, nil, "parse: no @verified is nil, not an error")

    -- A hand-written corpus across dozens of files will contain both bullet
    -- markers and both cases. Rejecting either would silently drop items,
    -- which is the one failure mode a ledger must not have.
    local sec = sections[2].items[1]
    eq(sec.done, true, "parse: `* [X]` counts — other bullet marker, uppercase mark")
    eq(#sec.meta, 1, "parse: an unrecognized tag is kept, not dropped")
    eq(sec.meta[1].key, "owner", "parse: unknown tag key")
    eq(sec.meta[1].value, "stefan", "parse: unknown tag value")

    eq(sections[2].items[2].ref, nil, "parse: an item citing nothing is valid")
  end

  do
    -- Hand-written items wrap. Found by running the parser against a real
    -- ledger for the first time: every multi-line item silently lost
    -- everything after its first line, and the quickfix entry ended
    -- mid-sentence.
    local sections = checklist.parse(
      table.concat({
        "## S",
        "- [x] The core pipeline runs with no editor around it — nothing",
        "      under `documentation.core` requires `documentation.editor`",
        "",
        "      <!-- @ref scripts/gen_map.lua:96 -->",
        "      <!-- @verified 2026-08-11 -->",
      }, "\n"),
      "c.md"
    )
    local item = sections[1].items[1]
    eq(
      item.text,
      "The core pipeline runs with no editor around it — nothing under "
        .. "`documentation.core` requires `documentation.editor`",
      "parse: an indented continuation line joins the item text with a single space"
    )
    eq(item.ref, "scripts/gen_map.lua", "parse: a blank line does not end the metadata block")
    eq(item.verified, "2026-08-11", "parse: ...so the citation after it still attaches")
  end

  do
    -- A long `@note` wraps, and the opening line of a multi-line comment
    -- must not be swallowed into the item text — the second thing running
    -- this against a real ledger exposed.
    local sections = checklist.parse(
      table.concat({
        "## S",
        "- [ ] An item",
        "      <!-- @ref a/b.lua:7 -->",
        "      <!-- @note deliberately open: the spec is still moving, and",
        "           this is the one item expected to need re-checking rather",
        "           than to stay settled -->",
      }, "\n"),
      "c.md"
    )
    local item = sections[1].items[1]
    eq(item.text, "An item", "parse: a wrapped comment does not leak into the item text")
    eq(item.ref, "a/b.lua", "parse: the single-line citation before it still resolves")
    eq(#item.meta, 1, "parse: the wrapped comment is one tag, not three lines of noise")
    eq(item.meta[1].key, "note", "parse: ...with its tag read off the opening line")
    eq(
      item.meta[1].value,
      "deliberately open: the spec is still moving, and this is the one item "
        .. "expected to need re-checking rather than to stay settled",
      "parse: ...and its value joined across every line"
    )
  end

  do
    -- The metadata block has to stop at the next non-indented prose line,
    -- or comments paragraphs below a list attach to the last item above it.
    local sections = checklist.parse(
      table.concat({
        "## S",
        "- [ ] item",
        "",
        "Prose that ends the block.",
        "",
        "<!-- @ref should/not/attach.lua -->",
      }, "\n"),
      "c.md"
    )
    eq(sections[1].items[1].ref, nil, "parse: prose ends an item's metadata block")
  end

  do
    -- An item before any heading is real and must not be dropped.
    local sections = checklist.parse("- [ ] orphan\n", "c.md")
    eq(#sections, 1, "parse: a synthetic section holds pre-heading items")
    eq(sections[1].name, "", "parse: the synthetic section has an empty name")
    eq(sections[1].line, 0, "parse: and line 0, since it corresponds to no line")
    eq(#sections[1].items, 1, "parse: the orphan item survives")
  end

  -- ── resolve ──────────────────────────────────────────────────────────────

  do
    local root = H.tmpfile("_checklist_dir")
    dwrite(root, "docs/CHECKLIST/b_second.md", { "## B", "- [x] two", "- [ ] three" })
    dwrite(
      root,
      "docs/CHECKLIST/a_first.md",
      { "## A", "- [x] one", "      <!-- @ref lua/x.lua -->" }
    )

    local result = assert(checklist.resolve(root), "resolve: a folder resolves")
    eq(result.source, "docs/CHECKLIST", "resolve: reports which candidate matched")
    eq(#result.files, 2, "resolve: every .md in the folder")
    -- Sorted, because `vim.fs.dir` gives no ordering guarantee and the
    -- artifact is byte-compared by `--check`.
    eq(result.files[1].name, "a_first", "resolve: files sorted by filename")
    eq(result.files[2].name, "b_second", "resolve: ...so two runs produce identical bytes")
    eq(result.total, 3, "resolve: counts items across every file")
    eq(result.done, 2, "resolve: counts done items")
    eq(result.cited, 1, "resolve: counts items carrying an @ref")
  end

  do
    -- The degenerate single-file case: six items should not need a directory.
    local root = H.tmpfile("_checklist_file")
    dwrite(root, "docs/CHECKLIST.md", { "## S", "- [ ] only" })
    local result = assert(checklist.resolve(root), "resolve: a single file resolves too")
    eq(result.source, "docs/CHECKLIST.md", "resolve: reports the file candidate")
    eq(result.total, 1, "resolve: single-file totals")
  end

  do
    local root = H.tmpfile("_checklist_none")
    vim.fn.mkdir(root, "p")
    eq(checklist.resolve(root), nil, "resolve: nil for a repo with no checklist — not an error")
  end

  -- ── status ───────────────────────────────────────────────────────────────

  local function ledger(items)
    return {
      source = "x",
      files = {
        { path = "c.md", name = "c", sections = { { name = "S", line = 1, items = items } } },
      },
      total = #items,
      done = 0,
      cited = 0,
    }
  end

  do
    local result = ledger({
      {
        done = true,
        text = "stale one",
        line = 1,
        file = "c.md",
        meta = {},
        ref = "a.lua",
        verified = "2026-01-01",
      },
      {
        done = true,
        text = "current one",
        line = 2,
        file = "c.md",
        meta = {},
        ref = "b.lua",
        verified = "2026-06-01",
      },
      { done = true, text = "no date", line = 3, file = "c.md", meta = {}, ref = "a.lua" },
      { done = false, text = "no ref", line = 4, file = "c.md", meta = {} },
    })
    local dates = {
      ["a.lua"] = { "2026-03-01", "2026-05-04", "2025-12-31" },
      ["b.lua"] = { "2026-01-15" },
    }

    local st = checklist.status(result, dates)
    eq(#st, 4, "status: one entry per item")

    local by_text = {}
    for _, s in ipairs(st) do
      by_text[s.item.text] = s
    end

    eq(by_text["stale one"].state, "stale", "status: commits newer than @verified mean stale")
    eq(by_text["stale one"].commits, 2, "status: counts only the commits newer than @verified")
    eq(by_text["stale one"].last_commit, "2026-05-04", "status: reports the newest commit date")

    eq(by_text["current one"].state, "current", "status: an older commit does not mark it stale")
    eq(by_text["current one"].commits, 0, "status: and counts nothing")
    eq(
      by_text["current one"].last_commit,
      "2026-01-15",
      "status: a current item still reports when the file last moved"
    )

    eq(by_text["no date"].state, "unverified", "status: cited but never verified is its own state")
    eq(by_text["no ref"].state, "uncited", "status: citing nothing is a state, not a defect")
    eq(
      by_text["no ref"].commits,
      0,
      "status: an uncited item can never be stale, so it carries no count"
    )

    -- Ordering is what makes this usable in a quickfix list: the things to
    -- re-read come first.
    eq(st[1].item.text, "stale one", "status: stale first")
    eq(st[#st].item.text, "current one", "status: current last")
  end

  do
    -- The deliberate `>` rather than `>=`. A commit on the verification day
    -- itself must not flag the item — of the two possible errors, flagging
    -- everything the moment it is verified is the one that makes a ledger
    -- get ignored.
    local result = ledger({
      {
        done = true,
        text = "same day",
        line = 1,
        file = "c.md",
        meta = {},
        ref = "a.lua",
        verified = "2026-05-04",
      },
    })
    local st = checklist.status(result, { ["a.lua"] = { "2026-05-04" } })
    eq(st[1].state, "current", "status: a same-day commit does not mark an item stale")
  end

  do
    -- A cited file with no history at all (never committed, or outside the
    -- repo) is "current", not an error: there is nothing newer than the
    -- verification, which is exactly what the flag means.
    local result = ledger({
      {
        done = true,
        text = "no history",
        line = 1,
        file = "c.md",
        meta = {},
        ref = "ghost.lua",
        verified = "2026-01-01",
      },
    })
    local st = checklist.status(result, {})
    eq(st[1].state, "current", "status: a cited file with no commits is current")
    eq(st[1].last_commit, nil, "status: and reports no last commit")
  end

  -- ── resolve_refs ─────────────────────────────────────────────────────────

  do
    local result = ledger({
      { done = true, text = "a", line = 1, file = "c.md", meta = {}, ref = "lua/demo/a/init.lua" },
      { done = true, text = "b", line = 2, file = "c.md", meta = {}, ref = "scripts/thing.lua" },
      {
        done = true,
        text = "dup",
        line = 3,
        file = "c.md",
        meta = {},
        ref = "lua/demo/a/init.lua",
      },
      { done = true, text = "none", line = 4, file = "c.md", meta = {} },
    })
    local ir =
      { nodes = { ["lua/demo/a"] = { id = "lua/demo/a", source = "lua/demo/a/init.lua" } } }

    local resolved, unresolved = checklist.resolve_refs(result, ir)
    eq(#resolved, 1, "resolve_refs: deduplicates a path cited twice")
    eq(resolved[1], "lua/demo/a/init.lua", "resolve_refs: matches on node.source")
    eq(#unresolved, 1, "resolve_refs: a path outside the scanned tree is reported, not an error")
    eq(unresolved[1], "scripts/thing.lua", "resolve_refs: ...and named")
  end
end
