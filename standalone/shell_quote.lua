---@module 'standalone.shell_quote'
--- One shell-quoted argument, or a refusal.
---
--- Pulled out of `standalone/docmap.lua`'s `--api=` handling into its own
--- module for exactly one reason: it is the only piece of that file's
--- subprocess plumbing with no dependency on the vim shim, `lfs`, a git
--- checkout or anything else that keeps the rest of that file from being
--- unit-testable without the full standalone toolchain on PATH. Pure
--- `string.*`, nothing else — see `TESTS/shell_quote_spec.lua`.
---
--- **Not every value that reaches this is trusted.** `opts.out_dir` is
--- repository input — `config/file.lua`'s `REPO_KEYS.out_dir` lets a
--- cloned tree's own `.docmap.json` set it — and it is embedded verbatim
--- into a git pathspec (`core/api.lua`'s `(":(exclude)%s"):format(out_dir)`)
--- before ever reaching here. `opts.root` is the CLI's own first argument,
--- also not this program's to trust. Quoting is the *only* lock on that
--- door, not a second one behind something else.
---
--- `$`/backtick are refused outright rather than quoted: inside a
--- double-quoted POSIX string they still trigger command substitution no
--- matter how the surrounding quote is escaped, so no escaping of the quote
--- character neutralises them. A literal `"` is refused on Windows for the
--- same reason from the other direction — cmd.exe has no backslash-escape
--- for an embedded quote, so a value carrying one cannot be quoted safely
--- here at all.
local M = {}

---@param s string
---@param windows boolean True on the Windows branch (cmd.exe quoting rules), false for POSIX shells.
---@return string? quoted
---@return string? err
function M.quote(s, windows)
  s = tostring(s)
  if s:find("[$`]") then
    return nil, "refused: value contains a shell metacharacter ($ or `): " .. s
  end
  if windows then
    if s:find('"') then
      return nil, 'refused: value contains a literal " and cmd.exe cannot quote it safely: ' .. s
    end
    -- Double a trailing run of backslashes (SEC-46, Windows branch):
    -- otherwise a value ending in `\` -- an entirely ordinary Windows
    -- path, e.g. `opts.root` pasted from Explorer with its separator, or
    -- `opts.out_dir` used to build the `:(exclude)` pathspec above --
    -- puts a lone `\` directly before the closing `"`. Both readers of
    -- this string then see that backslash as escaping the quote instead
    -- of the string ending: cmd.exe's own `cd /d "...\"` parsing breaks
    -- with a syntax error, and a spawned CRT program (git.exe included)
    -- parses argv with the same "an even run of backslashes before a
    -- quote is literal, an odd run escapes it" convention, so a
    -- corrupted final argument reaches git silently. Doubling the run
    -- makes it even either way, which both readers treat as N literal
    -- backslashes followed by a real closing quote -- the same fix the
    -- POSIX branch below already applies, just against that platform's
    -- own escaping rule instead of the shell's backslash-escape.
    -- `s` was already confirmed above to contain no literal `"`, so only
    -- the trailing run (if any) needs doubling; a backslash anywhere
    -- else is never adjacent to a quote and stays literal as-is.
    return '"' .. (s:gsub("(\\+)$", "%1%1")) .. '"'
  end
  -- Escape the escape character *before* the quote (SEC-46): otherwise a
  -- value ending in `\` produces `...\"`, where the trailing backslash
  -- escapes the closing quote instead of terminating the string, and
  -- everything after it runs on as shell syntax rather than staying data.
  return '"' .. (s:gsub("\\", "\\\\"):gsub('"', '\\"')) .. '"'
end

return M
