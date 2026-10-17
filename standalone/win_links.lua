---@module 'standalone.win_links'
--- Which entries of a Windows directory are links, read out of `dir /a:l`.
---
--- ## Why this exists
---
--- The standalone build runs on `lfs`, and on Windows `lfs.symlinkattributes`
--- *is* `lfs.attributes`: it follows the link it was asked about. So the shim
--- had no way to tell a junction from a directory, and a junction in a cloned
--- repository was walked, written through and read like any other folder. The
--- one tool every Windows has that reports the difference without opening the
--- entry is `cmd.exe`'s own `dir`, which lists reparse points when asked
--- (`/a:l`) and labels each one by kind.
---
--- ## What is trusted, and what is not
---
--- Pure `string.*`, nothing else, for the reason `standalone/shell_quote.lua`
--- gives: the parsing is the part worth unit-testing, and it has no business
--- needing `lfs`, a shell or a Windows machine to be tested
--- (`TESTS/win_links_spec.lua`). Spawning the command lives in
--- `standalone/vim_shim.lua`.
---
--- A line is a link by its **shape**, not by what its label says. Under `/a:l`
--- a link prints `<label> name [target]`: a token in angle brackets, then the
--- name, then the target in square brackets. The label is the language's
--- (`<DIR>` is `<REP>` on French Windows, and the junction label is no more
--- safe from translation), so it is kept as information when it is one of the
--- three English ones (`<JUNCTION>`, `<SYMLINKD>`, `<SYMLINK>`) and is
--- `UNKNOWN` otherwise; it decides nothing. `/a:l` selects every reparse
--- point, which includes cloud-sync placeholders (OneDrive's "files on demand"
--- make every file of a synced repository one), and those are ordinary files
--- to everything that reads them and must stay so: a placeholder file prints
--- no `<label>` and a placeholder folder prints no ` [`, and only a symlink or
--- a junction prints both. The closing `]` is not asked for: a target that
--- holds a line break is printed over two lines, and the first of them is
--- still a link, only one whose target cannot be read.
---
--- **Names are matched, not trusted.** `dir` prints in the console's code
--- page and the caller holds the name in the ANSI one, so a name with a byte
--- above 127 cannot be compared reliably: the console may show a character it
--- has no glyph for as `?` (which no file name can hold) or as a look-alike
--- letter, and then the printed line is plain ASCII and gives nothing away.
--- Likewise an 8.3 alias (`DOCUME~1`) names the same entry as the long name
--- `dir` prints, and is not printed itself. So in a directory that lists at
--- least one link, a name with a non-ASCII byte, a `?` or a `~` and a digit is
--- answered as a link: the directory is answered pessimistically rather than
--- guessed at. A directory with no link is not affected.
---
--- Two lines that read a name alike (` evil` and `evil`, which differ in a
--- blank the padding swallows; `Docs` and `docs`) are no more telling than a
--- name that cannot be matched: the one is taken for the other's target, so
--- the name is answered as a link with no target.
---
--- The same holds when only **one** of such a pair is a link: a real directory
--- `evil` beside a link ` evil` gives one line, which both names read. The
--- listing alone cannot say which of the two it belongs to, so the caller
--- hands over the names the directory holds (`note_names`), and a name that
--- another name of the directory reads alike is answered as a link with no
--- target when a line matches it -- never with that line's target.
local M = {}

---Printed after the listing by the command that produced it, so a run that
---never happened (no `cmd.exe`, a killed process) cannot read as "this
---directory has no links".
M.END_MARK = "__DOCMAP_DIR_END__"

---@class Standalone.WinLinks.Entry
---@field tag string `JUNCTION`, `SYMLINKD` or `SYMLINK` as printed, `UNKNOWN` for any other label.
---@field rest string Everything after the label: `name [target]`.

---@class Standalone.WinLinks.Census
---@field complete boolean The end marker was seen, so the listing is the whole answer.
---@field links Standalone.WinLinks.Entry[]
---@field by_name table<string, Standalone.WinLinks.Entry|false> Lower-cased text in front of the first ` [` of a line, to the line that has it, or `false` when more than one does.
---@field nested Standalone.WinLinks.Entry[] The links with a second ` [`, in listing order: the only ones that can read as a name which holds ` [`.
---@field shared table<string, true>? Lookup keys (see `lookup_key`) that more than one name of the directory has, once `note_names` has been told the names.

local LINK_TAGS = { JUNCTION = true, SYMLINKD = true, SYMLINK = true }

---How many links with a second ` [` a name holding ` [` is looked up in. Such
---lines are a name or a target holding ` [`: a handful in a real tree. A
---directory with more is a crafted one, and every name with a ` [` would be
---compared with every one of them, so past this the name is not looked up
---and is answered as a link.
local MAX_NESTED = 32

---Read the output of `dir /a:l`.
---
---Locale-proof where it matters: the date and time columns differ per
---language and are never looked at, and neither is the text of the label
---(see the module header for what makes a line a link).
---@param text string Everything the command wrote to stdout.
---@return Standalone.WinLinks.Census
function M.parse(text)
  local links, by_name, nested = {}, {}, {}
  local complete = text:find(M.END_MARK, 1, true) ~= nil
  for line in text:gmatch("[^\r\n]+") do
    local label, rest = line:match("<([^<>]+)>%s+(.+)$")
    local at = label and rest:find(" [", 1, true)
    if at then
      local link = { tag = LINK_TAGS[label] and label or "UNKNOWN", rest = rest }
      links[#links + 1] = link
      -- Only the first ` [` is a key and the rest of the line is not looked
      -- at for more: the target is the repository's to write and can be
      -- thousands of characters of ` [`, so a key for each would cost memory
      -- and time in the square of the line. A name that holds ` [` itself is
      -- read off the lines that have a second one (see `find`). A key that a
      -- second line has as well belongs to neither.
      local key = rest:sub(1, at - 1):lower()
      by_name[key] = by_name[key] == nil and link or false
      if rest:find(" [", at + 1, true) then
        nested[#nested + 1] = link
      end
    end
  end
  return { complete = complete, links = links, by_name = by_name, nested = nested }
end

---The text a name is looked up by: without its leading blanks, which the
---parse cannot tell from the padding after the label (` evil` is listed as
---`evil`), and in lower case, as the file system compares it.
---@param name string
---@return string
local function lookup_key(name)
  return (name:gsub("^%s+", "")):lower()
end

---Tell the census which names the directory holds, so that names it reads
---alike are known (see the module header). Only worth asking for when the
---census lists a link: a directory without one answers no name as a link.
---@param census Standalone.WinLinks.Census
---@param names string[] Every entry of the directory, as the file system lists it.
function M.note_names(census, names)
  local seen, shared = {}, {}
  for _, name in ipairs(names) do
    local key = lookup_key(name)
    if seen[key] then
      shared[key] = true
    end
    seen[key] = true
  end
  census.shared = shared
end

---@class Standalone.WinLinks.Hit
---@field tag string `JUNCTION`, `SYMLINKD`, `SYMLINK`, or `UNKNOWN` for a name that cannot be told apart.
---@field target string? What `dir` printed in square brackets, when it printed one.

---Is the entry called `name` one of the links in `census`?
---
---The name is looked up as the text in front of a ` [` of a listed line
---rather than cut out of it: a name may itself contain ` [`, and so may a
---target, and any rule for splitting the line has an input it splits wrongly.
---A name without ` [` can only be the text in front of the first one of its
---line, which is what the table holds; a name with one is read off the lines
---that have a second, as long as there are not more than `MAX_NESTED` of them.
---The names asked about come from the directory listing, so they are known to
---exist. Compared without regard to case, as the file system does.
---
---A name that more than one line reads, or that cannot be matched exactly but
---could be the one of a listed link, is answered `UNKNOWN`, with no target
---(see the module header).
---@param census Standalone.WinLinks.Census
---@param name string
---@return Standalone.WinLinks.Hit?
function M.find(census, name)
  -- The padding after the label and a leading space of the name are one run
  -- of whitespace to the parse, so ` evil` is listed as `evil`.
  local plain = (name:gsub("^%s+", ""))
  local lowered = lookup_key(name)
  local link = census.by_name[lowered]
  if link == nil and lowered:find(" [", 1, true) then
    if #census.nested > MAX_NESTED then
      return { tag = "UNKNOWN" }
    end
    local wanted = lowered .. " ["
    for _, candidate in ipairs(census.nested) do
      if candidate.rest:sub(1, #wanted):lower() == wanted then
        link = link == nil and candidate or false
      end
    end
  end
  -- A line that another name of the directory reads as well may be that
  -- name's: a real directory `evil` must not take the target of a link
  -- ` evil`, nor the other way round.
  if link == false or (link and census.shared and census.shared[lowered]) then
    return { tag = "UNKNOWN" }
  end
  if link then
    return {
      tag = link.tag,
      target = link.rest:sub(#lowered + 3):match("^(.*)%]%s*$"),
    }
  end
  if #census.links > 0 and (plain:find("[\128-\255?]") or plain:find("~%d")) then
    return { tag = "UNKNOWN" }
  end
  return nil
end

return M
