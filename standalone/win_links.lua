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
--- Only the three labels `dir` prints for *links* count: `<JUNCTION>`,
--- `<SYMLINKD>` and `<SYMLINK>`. `/a:l` selects every reparse point, and that
--- includes cloud-sync placeholders (OneDrive's "files on demand" make every
--- file of a synced repository one), which are ordinary files to everything
--- that reads them and must stay so. Those carry no such label.
---
--- **Names are matched, not trusted.** `dir` prints in the console's code
--- page and the caller holds the name in the ANSI one, so a name with a byte
--- above 127 cannot be compared reliably. A listing that shows such a link
--- marks itself `opaque`, and from then on every non-ASCII name in that
--- directory is treated as a link too: the directory is answered pessimistically
--- rather than guessed at.
local M = {}

---Printed after the listing by the command that produced it, so a run that
---never happened (no `cmd.exe`, a killed process) cannot read as "this
---directory has no links".
M.END_MARK = "__DOCMAP_DIR_END__"

---@class Standalone.WinLinks.Entry
---@field tag string `JUNCTION`, `SYMLINKD` or `SYMLINK`.
---@field rest string Everything after the label: `name [target]`.

---@class Standalone.WinLinks.Census
---@field complete boolean The end marker was seen, so the listing is the whole answer.
---@field links Standalone.WinLinks.Entry[]
---@field opaque boolean A link's name holds non-ASCII bytes, so names cannot be matched exactly.

local LINK_TAGS = { JUNCTION = true, SYMLINKD = true, SYMLINK = true }

---Read the output of `dir /a:l`.
---
---Locale-proof where it matters: the date and time columns differ per
---language and are never looked at, and the labels in angle brackets are
---not translated.
---@param text string Everything the command wrote to stdout.
---@return Standalone.WinLinks.Census
function M.parse(text)
  local links, opaque = {}, false
  local complete = text:find(M.END_MARK, 1, true) ~= nil
  for line in text:gmatch("[^\r\n]+") do
    local tag, rest = line:match("<(%u+)>%s+(.+)$")
    if tag and LINK_TAGS[tag] then
      links[#links + 1] = { tag = tag, rest = rest }
      if rest:find("[\128-\255]") then
        opaque = true
      end
    end
  end
  return { complete = complete, links = links, opaque = opaque }
end

---@class Standalone.WinLinks.Hit
---@field tag string `JUNCTION`, `SYMLINKD`, `SYMLINK`, or `UNKNOWN` for a name that cannot be told apart.
---@field target string? What `dir` printed in square brackets, when it printed one.

---Is the entry called `name` one of the links in `census`?
---
---The name is looked up as a prefix of each listed line (`name [`) rather
---than cut out of it: a name may itself contain ` [`, and so may a target, and
---any rule for splitting the line has an input it splits wrongly. The names
---asked about come from the directory listing, so they are known to exist.
---Compared without regard to case, as the file system does.
---@param census Standalone.WinLinks.Census
---@param name string
---@return Standalone.WinLinks.Hit?
function M.find(census, name)
  local wanted = name:lower() .. " ["
  for _, link in ipairs(census.links) do
    if link.rest:sub(1, #wanted):lower() == wanted then
      return { tag = link.tag, target = link.rest:sub(#wanted + 1):match("^(.*)%]%s*$") }
    end
  end
  if census.opaque and name:find("[\128-\255]") then
    return { tag = "UNKNOWN" }
  end
  return nil
end

return M
