-- TESTS/shell_quote_spec.lua — `standalone/shell_quote.lua`, the one piece
-- of `standalone/docmap.lua`'s `--api=` subprocess plumbing this repository
-- can unit-test directly: pure `string.*`, no vim shim, no `lfs`, no git
-- checkout, so it needs none of the scaffolding `scripts/ci.lua`'s
-- `lfs`/`dkjson`-gated `standalone` gate does.
--
-- SEC-46 closed the POSIX branch (double a trailing backslash run before
-- quote-escaping) but left the Windows branch wrapping the raw string with
-- no backslash handling at all. A value ending in one or more backslashes
-- -- an entirely ordinary Windows path, e.g. `C:\repos\myrepo\` pasted from
-- Explorer, or `opts.out_dir` built into a `:(exclude)` git pathspec -- then
-- put a lone `\` directly before the closing `"`, which both cmd.exe's own
-- `cd /d "...\"` parsing and a spawned CRT program's (git.exe included)
-- argv-splitting read as the backslash escaping the quote rather than the
-- string ending. This spec pins the fix: on the Windows branch, a run of N
-- trailing backslashes must round-trip as N literal backslashes with the
-- closing quote intact, for any N -- and an embedded quote must still be
-- refused outright, since the Windows branch has no way to escape one.

return function(H)
  local eq, ok = H.eq, H.ok
  local sq = require("standalone.shell_quote")

  -- Windows branch --------------------------------------------------------

  -- No trailing backslash: unaffected by the fix, still quoted as-is.
  do
    local quoted, err = sq.quote("plain", true)
    eq(err, nil, "shell_quote(windows): a plain value is not refused")
    eq(quoted, '"plain"', "shell_quote(windows): a plain value is quoted verbatim")
  end

  -- One trailing backslash (SEC-46's own Windows example): must become two
  -- backslashes before the closing quote, which both cmd.exe's `cd` parsing
  -- and a CRT program's argv-splitting read back as one literal backslash
  -- followed by a real closing quote.
  do
    local quoted, err = sq.quote([[C:\repos\myrepo\]], true)
    eq(err, nil, "shell_quote(windows): a trailing backslash is not refused")
    eq(
      quoted,
      [["C:\repos\myrepo\\"]],
      "shell_quote(windows): one trailing backslash is doubled before the closing quote"
    )
  end

  -- Two trailing backslashes: doubled to four, still reading back as the
  -- original two literal backslashes plus a real closing quote.
  do
    local quoted = sq.quote([[evilout\\]], true)
    eq(
      quoted,
      [["evilout\\\\"]],
      "shell_quote(windows): a two-backslash run is doubled, not left odd"
    )
  end

  -- A backslash that is not at the end of the string is never adjacent to
  -- the closing quote and must stay untouched.
  do
    local quoted = sq.quote([[a\b\c]], true)
    eq(quoted, [["a\b\c"]], "shell_quote(windows): an interior backslash is left alone")
  end

  -- An embedded literal quote has no safe Windows escaping and must still
  -- be refused outright -- the fix above must not have started accepting it.
  do
    local quoted, err = sq.quote('has"quote', true)
    eq(quoted, nil, "shell_quote(windows): an embedded quote is still refused")
    ok(err ~= nil, "shell_quote(windows): ...with an error message")
  end

  -- `$`/backtick stay refused on both branches regardless of platform.
  do
    local quoted, err = sq.quote("has$dollar", true)
    eq(quoted, nil, "shell_quote(windows): a $ is refused")
    ok(err ~= nil, "shell_quote(windows): ...with an error message")
  end

  -- POSIX branch (unchanged by this fix, pinned so a future edit cannot
  -- regress it while only looking at the Windows branch) -----------------

  do
    local quoted = sq.quote([[myrepo\]], false)
    eq(
      quoted,
      [["myrepo\\"]],
      "shell_quote(posix): a trailing backslash is still doubled before quote-escaping"
    )
  end

  do
    local quoted = sq.quote('has"quote', false)
    eq(
      quoted,
      [["has\"quote"]],
      "shell_quote(posix): an embedded quote is backslash-escaped, not refused"
    )
  end
end
