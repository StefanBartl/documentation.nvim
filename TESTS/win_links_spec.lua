-- TESTS/win_links_spec.lua — reading `dir /a:l` for the links in a directory.
--
-- The standalone build cannot lstat on Windows, so it asks `cmd.exe`
-- (`standalone/win_links.lua`). The parse is pure and is tested here on
-- listings written down as `cmd.exe` prints them -- in two languages, because
-- the date and time columns are the locale's and the labels are not. What
-- these cannot show is that a real `cmd.exe` prints exactly this; that is
-- what the Windows job of the suite is for (`shim_windows_links_spec.lua`
-- drives the shim's own Windows branch on a canned listing, and
-- `scan_links_spec.lua` runs the scanner against real junctions there).

return function(H)
  local eq, ok = H.eq, H.ok
  local win_links = dofile((vim.fn.getcwd():gsub("\\", "/")) .. "/standalone/win_links.lua")
  local MARK = win_links.END_MARK

  local ENGLISH = table.concat({
    " Volume in drive C has no label.",
    " Volume Serial Number is 1A2B-3C4D",
    "",
    " Directory of C:\\Users\\dev\\repo\\docs",
    "",
    "10/08/2026  06:24 PM    <JUNCTION>     map [C:\\Users\\dev\\other]",
    "10/08/2026  06:24 PM    <SYMLINKD>     rel [..\\real]",
    "10/08/2026  06:24 PM    <SYMLINK>      f.txt [..\\f.txt]",
    "10/08/2026  06:24 PM    <JUNCTION>     share [\\\\host\\share\\x]",
    "10/08/2026  06:24 PM    <SYMLINKD>     my dir [x] [..\\t]",
    "10/08/2026  06:24 PM    <DIR>          plain",
    "10/08/2026  06:24 PM                12 cloud.txt",
    "               1 File(s)              0 bytes",
    "               4 Dir(s)  123,456,789,012 bytes free",
    MARK,
  }, "\r\n")

  local GERMAN = table.concat({
    " Volume in Laufwerk C: hat keine Bezeichnung.",
    " Volumeseriennummer: 1A2B-3C4D",
    "",
    " Verzeichnis von C:\\Users\\dev\\repo\\docs",
    "",
    "08.10.2026  18:24    <JUNCTION>     karte [C:\\Users\\dev\\anderes]",
    "08.10.2026  18:24    <SYMLINKD>     rel [..\\real]",
    MARK,
  }, "\r\n")

  local en = win_links.parse(ENGLISH)
  ok(en.complete, "english: the end mark is there, so the listing is the whole answer")
  eq(#en.links, 5, "english: five links, the plain directory and the placeholder file are not")
  eq(en.opaque, false, "english: every name is plain ASCII")

  local function target_of(census, name)
    local hit = win_links.find(census, name)
    return hit and (hit.tag .. " " .. tostring(hit.target)) or nil
  end

  eq(target_of(en, "map"), "JUNCTION C:\\Users\\dev\\other", "a junction, with its target")
  eq(target_of(en, "MAP"), "JUNCTION C:\\Users\\dev\\other", "...found whatever case is asked")
  eq(target_of(en, "rel"), "SYMLINKD ..\\real", "a directory symlink")
  eq(target_of(en, "f.txt"), "SYMLINK ..\\f.txt", "a file symlink")
  eq(target_of(en, "share"), "JUNCTION \\\\host\\share\\x", "a link to a share keeps its target")
  eq(target_of(en, "my dir [x]"), "SYMLINKD ..\\t", "a name holding ` [` is matched, not cut")
  -- `my dir [x] [..\t]` is also a link called `my dir` whose target is
  -- `x] [..\t`: the line cannot tell the two apart. Names are asked about only
  -- when they are in the directory, so the cost is a plain entry called `my
  -- dir` beside such a link being taken for one -- which is the safe error.
  ok(win_links.find(en, "my dir") ~= nil, "an ambiguous line errs towards 'link'")
  eq(target_of(en, "plain"), nil, "a plain directory is not a link")
  eq(target_of(en, "cloud.txt"), nil, "a file with no label is not a link, whatever else it is")
  eq(target_of(en, "map2"), nil, "a name that merely starts alike is not the link")

  local de = win_links.parse(GERMAN)
  ok(de.complete, "german: complete")
  eq(
    target_of(de, "karte"),
    "JUNCTION C:\\Users\\dev\\anderes",
    "german: the labels are not translated"
  )
  eq(target_of(de, "rel"), "SYMLINKD ..\\real", "german: a second link")

  -- A run that never happened is not a directory with no links.
  local cut = win_links.parse(ENGLISH:gsub(MARK, ""))
  eq(cut.complete, false, "no end mark: the listing is not trusted as complete")
  local empty = win_links.parse("File Not Found\r\n" .. MARK .. "\r\n")
  ok(empty.complete, "a directory with no links prints only the mark, and that is an answer")
  eq(#empty.links, 0, "...of no links")
  eq(win_links.parse("").complete, false, "no output at all is not an answer")

  -- Names the console code page would have garbled cannot be matched, so the
  -- directory is answered pessimistically for them and for nothing else.
  local odd = win_links.parse(table.concat({
    "08.10.2026  18:24    <JUNCTION>     k\129rte [C:\\x]",
    MARK,
  }, "\r\n"))
  ok(odd.opaque, "a non-ASCII name in a link line marks the listing opaque")
  eq(win_links.find(odd, "gr\246\223e").tag, "UNKNOWN", "...and another non-ASCII name may be it")
  eq(win_links.find(odd, "ascii"), nil, "...but an ASCII name is still answered exactly")
end
