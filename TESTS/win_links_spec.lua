-- TESTS/win_links_spec.lua — reading `dir /a:l` for the links in a directory.
--
-- The standalone build cannot lstat on Windows, so it asks `cmd.exe`
-- (`standalone/win_links.lua`). The parse is pure and is tested here on
-- listings written down as `cmd.exe` prints them -- in four languages, because
-- the date and time columns are the locale's and so, as far as is known, are
-- the labels (`<DIR>` is `<REP>` in French), which is why a line is a link by
-- its shape and not by its label. What these cannot show is that a real
-- `cmd.exe` prints exactly this; that is what the Windows job of the suite is
-- for (`shim_links_spec.lua` drives the shim's own Windows branch on a canned
-- listing, and `scan_links_spec.lua` runs the scanner against real junctions
-- there).

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
    "10/08/2026  06:24 PM    <JUNCTION>     Docs [C:\\Users\\dev\\Other]",
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
    "08.10.2026  18:24    <JUNCTION>     Karte [C:\\Users\\dev\\anderes]",
    "08.10.2026  18:24    <SYMLINKD>     rel [..\\real]",
    MARK,
  }, "\r\n")

  -- Written from memory of the French and Spanish message tables, which could
  -- not be run here: `<DIR>` is `<REP>` in French, and a translated junction
  -- label is no more than likely. The parse must not depend on either.
  local FRENCH = table.concat({
    " Le volume dans le lecteur C n'a pas de nom.",
    "",
    " Repertoire de C:\\Users\\dev\\repo\\docs",
    "",
    "08/10/2026  18:24    <JONCTION>     carte [C:\\Users\\dev\\autre]",
    "08/10/2026  18:24    <SYMLINKD>     rel [..\\reel]",
    "08/10/2026  18:24    <REP>          simple",
    "08/10/2026  18:24    <REP>          nuage",
    MARK,
  }, "\r\n")

  local SPANISH = table.concat({
    " El volumen de la unidad C no tiene etiqueta.",
    "",
    " Directorio de C:\\Users\\dev\\repo\\docs",
    "",
    "08/10/2026  18:24    <UNION>        mapa [C:\\Users\\dev\\otro]",
    "08/10/2026  18:24    <ENLACE>       f.txt [..\\f.txt]",
    "08/10/2026  18:24    <DIR>          simple",
    MARK,
  }, "\r\n")

  local en = win_links.parse(ENGLISH)
  ok(en.complete, "english: the end mark is there, so the listing is the whole answer")
  eq(#en.links, 6, "english: six links, the plain directory and the placeholder file are not")

  local function target_of(census, name)
    local hit = win_links.find(census, name)
    return hit and (hit.tag .. " " .. tostring(hit.target)) or nil
  end

  local function tag_of(census, name)
    local hit = win_links.find(census, name)
    return hit and hit.tag
  end

  eq(target_of(en, "map"), "JUNCTION C:\\Users\\dev\\other", "a junction, with its target")
  eq(target_of(en, "MAP"), "JUNCTION C:\\Users\\dev\\other", "...found whatever case is asked")
  eq(target_of(en, "rel"), "SYMLINKD ..\\real", "a directory symlink")
  eq(target_of(en, "f.txt"), "SYMLINK ..\\f.txt", "a file symlink")
  eq(target_of(en, "share"), "JUNCTION \\\\host\\share\\x", "a link to a share keeps its target")
  eq(
    target_of(en, "Docs"),
    "JUNCTION C:\\Users\\dev\\Other",
    "a link with capitals in its own name, asked in the spelling it has"
  )
  eq(
    target_of(en, "docs"),
    "JUNCTION C:\\Users\\dev\\Other",
    "...and in another: the listing is compared without case as well"
  )
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
    "german: found whatever case it is asked in"
  )
  eq(target_of(de, "Karte"), "JUNCTION C:\\Users\\dev\\anderes", "german: ...and as listed")
  eq(target_of(de, "rel"), "SYMLINKD ..\\real", "german: a second link")

  -- A translated label does not hide a link: the line is a link by its shape,
  -- a label in angle brackets in front of `name [target]`.
  local fr = win_links.parse(FRENCH)
  ok(fr.complete, "french: complete")
  eq(#fr.links, 2, "french: the two links, not the two plain directories")
  eq(
    target_of(fr, "carte"),
    "UNKNOWN C:\\Users\\dev\\autre",
    "french: a junction under a label that is not known, with its target"
  )
  eq(target_of(fr, "rel"), "SYMLINKD ..\\reel", "french: a label that is known keeps its name")
  eq(target_of(fr, "simple"), nil, "french: a directory with no `[target]` is not a link")
  eq(target_of(fr, "nuage"), nil, "french: ...nor is another")
  local es = win_links.parse(SPANISH)
  eq(target_of(es, "mapa"), "UNKNOWN C:\\Users\\dev\\otro", "spanish: a junction")
  eq(target_of(es, "f.txt"), "UNKNOWN ..\\f.txt", "spanish: a file symlink")
  eq(target_of(es, "simple"), nil, "spanish: a plain directory")

  -- A run that never happened is not a directory with no links.
  local cut = win_links.parse(ENGLISH:gsub(MARK, ""))
  eq(cut.complete, false, "no end mark: the listing is not trusted as complete")
  local empty = win_links.parse("File Not Found\r\n" .. MARK .. "\r\n")
  ok(empty.complete, "a directory with no links prints only the mark, and that is an answer")
  eq(#empty.links, 0, "...of no links")
  eq(win_links.parse("").complete, false, "no output at all is not an answer")

  -- Names the console code page would have garbled cannot be matched, so a
  -- directory that lists a link is answered pessimistically for them and for
  -- nothing else. What the printed line shows decides nothing: the console
  -- turns a character it has no glyph for into `?` or into a look-alike
  -- letter, and neither is a byte above 127.
  local odd = win_links.parse(table.concat({
    "08.10.2026  18:24    <JUNCTION>     k\129rte [C:\\x]",
    MARK,
  }, "\r\n"))
  eq(tag_of(odd, "gr\246\223e"), "UNKNOWN", "a non-ASCII name may be the link")
  eq(win_links.find(odd, "ascii"), nil, "...but an ASCII name is still answered exactly")

  local dashed = win_links.parse(table.concat({
    "08.10.2026  18:24    <JUNCTION>     a-b [C:\\x]",
    "08.10.2026  18:24    <SYMLINKD>     c?d [C:\\y]",
    "08.10.2026  18:24    <DIR>          plain",
    MARK,
  }, "\r\n"))
  eq(
    tag_of(dashed, "a\150b"),
    "UNKNOWN",
    "an en dash printed as `-` is a name the printed line does not give away"
  )
  eq(tag_of(dashed, "c\154d"), "UNKNOWN", "...and so is a letter printed as `?`")
  eq(tag_of(dashed, "x?y"), "UNKNOWN", "a `?` asked for is no file name, so it is a link")
  eq(target_of(dashed, "c?d"), "SYMLINKD C:\\y", "a name is still matched as printed")
  eq(target_of(dashed, "a-b"), "JUNCTION C:\\x", "...whether it holds a `-` or a `?`")
  eq(target_of(dashed, "plain"), nil, "a plain name is not a link")
  eq(target_of(dashed, "ab"), nil, "...nor is one that merely looks alike")

  -- A name asked for with its leading blank: the parse reads the padding of
  -- the column and the blank as one run, so the two cannot be told apart.
  local padded = win_links.parse(table.concat({
    "10/08/2026  06:24 PM    <SYMLINKD>      evil [C:\\x]",
    MARK,
  }, "\r\n"))
  eq(target_of(padded, " evil"), "SYMLINKD C:\\x", "a link whose name starts with a blank")
  eq(
    target_of(padded, "evil"),
    "SYMLINKD C:\\x",
    "...is also the plain name, which is the safe error"
  )

  -- ...and that is why two links the listing reads alike are no one's: the
  -- hostile `evil` must not be judged by the benign ` evil`, which `dir` lists
  -- first, nor `Docs` by `docs`, nor a name holding ` [` by another that does.
  -- Each is answered as a link with no target.
  local twins = win_links.parse(table.concat({
    "10/08/2026  06:24 PM    <SYMLINKD>      evil [..\\real]",
    "10/08/2026  06:24 PM    <SYMLINKD>     evil [C:\\Users\\victim\\outside]",
    "10/08/2026  06:24 PM    <JUNCTION>     Docs [C:\\a]",
    "10/08/2026  06:24 PM    <JUNCTION>     docs [C:\\b]",
    "10/08/2026  06:24 PM    <JUNCTION>      my dir [x] [..\\a]",
    "10/08/2026  06:24 PM    <JUNCTION>     my dir [x] [C:\\b]",
    "10/08/2026  06:24 PM    <JUNCTION>     lone [C:\\c]",
    MARK,
  }, "\r\n"))
  eq(target_of(twins, "evil"), "UNKNOWN nil", "twins: the plain name of a pair has no target")
  eq(target_of(twins, " evil"), "UNKNOWN nil", "twins: ...nor has the one with the blank")
  eq(target_of(twins, "docs"), "UNKNOWN nil", "twins: a pair that differs in case has none")
  eq(target_of(twins, "DOCS"), "UNKNOWN nil", "twins: ...in any case")
  eq(target_of(twins, "my dir [x]"), "UNKNOWN nil", "twins: a pair of names holding ` [` has none")
  eq(target_of(twins, " my dir [x]"), "UNKNOWN nil", "twins: ...with the blank as well")
  eq(target_of(twins, "lone"), "JUNCTION C:\\c", "twins: a link that nothing reads alike is exact")

  -- ...and when only one of such a pair is a link, the listing has one line,
  -- which both names read: a real directory must not take the link's target,
  -- whichever of the two has the blank. The names the directory holds say
  -- that a pair is there.
  local function pair(line, names)
    local census = win_links.parse(table.concat({ line, MARK }, "\r\n"))
    win_links.note_names(census, names)
    return census
  end
  local blank_link = pair("10/08/2026  06:24 PM    <SYMLINKD>      evil [..\\tgt]", {
    "evil",
    " evil",
    "tgt",
  })
  eq(target_of(blank_link, "evil"), "UNKNOWN nil", "pair: a real `evil` beside a link ` evil`")
  eq(target_of(blank_link, " evil"), "UNKNOWN nil", "pair: ...and the link itself has no target")
  eq(target_of(blank_link, "tgt"), nil, "pair: ...while a name with no twin is still exact")
  local plain_link = pair("10/08/2026  06:24 PM    <SYMLINKD>     evil [..\\tgt]", {
    " evil",
    "evil",
  })
  eq(target_of(plain_link, " evil"), "UNKNOWN nil", "pair: a real ` evil` beside a link `evil`")
  eq(target_of(plain_link, "evil"), "UNKNOWN nil", "pair: ...and the link itself has no target")
  local cased = pair("10/08/2026  06:24 PM    <JUNCTION>     docs [C:\\x]", { "Docs", "docs" })
  eq(target_of(cased, "Docs"), "UNKNOWN nil", "pair: a real `Docs` beside a link `docs`")
  local alone = pair("10/08/2026  06:24 PM    <SYMLINKD>      evil [..\\tgt]", { " evil", "x" })
  eq(target_of(alone, " evil"), "SYMLINKD ..\\tgt", "pair: a link with no twin keeps its target")
  -- A name holding ` [` reads the line of the name in front of it: a link
  -- `a [b` is listed `a [b [tgt]`, which a real `a` reads as well, and a link
  -- `a` to `b [x` is listed alike, which a real `a [b` reads.
  local nested_link = pair("10/08/2026  06:24 PM    <SYMLINKD>     a [b [tgt]", {
    "a",
    "a [b",
  })
  eq(target_of(nested_link, "a"), "UNKNOWN nil", "pair: a real `a` beside a link `a [b`")
  eq(target_of(nested_link, "a [b"), "UNKNOWN nil", "pair: ...and the link itself has no target")
  local nested_real = pair("10/08/2026  06:24 PM    <SYMLINKD>     a [b [x]", { "a [b", "a" })
  eq(target_of(nested_real, "a [b"), "UNKNOWN nil", "pair: a real `a [b` beside a link `a`")
  eq(target_of(nested_real, "a"), "UNKNOWN nil", "pair: ...and the link itself has no target")
  local nested_alone = pair("10/08/2026  06:24 PM    <SYMLINKD>     a [b [tgt]", { "a [b", "x" })
  eq(target_of(nested_alone, "a [b"), "SYMLINKD tgt", "pair: a lone `a [b` keeps its target")

  -- A target that holds a line break is printed over two lines. The first is
  -- a link whose target cannot be read, wherever the break falls and however
  -- it is written; it must not fall out of the census for want of a `]`.
  local head = "10/08/2026  06:24 PM    <SYMLINKD>     evil ["
  for label, text in pairs({
    ["a line feed"] = head .. "x\n\\..\\..\\outside]",
    ["a carriage return and a line feed"] = head .. "x\r\n\\..\\..\\outside]",
    ["a carriage return"] = head .. "x\r\\..\\..\\outside]",
    ["a break right after the bracket"] = head .. "\r\n..\\..\\outside]",
    ["a break right before the closing one"] = head .. "x\r\n]",
  }) do
    local split = win_links.parse(text .. "\r\n" .. MARK)
    ok(split.complete, "split: " .. label .. ": the listing is complete")
    eq(#split.links, 1, "split: " .. label .. ": the first line is a link")
    eq(target_of(split, "evil"), "SYMLINKD nil", "split: " .. label .. ": found, with no target")
  end
  -- ...and a line forged inside a target, which reads like a link that sorts
  -- after it, makes that name ambiguous rather than the forger's.
  local forged = win_links.parse(table.concat({
    "10/08/2026  06:24 PM    <SYMLINKD>     aaa [x",
    "10/08/2026  06:24 PM    <SYMLINKD>     evil [..\\real]]",
    "10/08/2026  06:24 PM    <SYMLINKD>     evil [C:\\Users\\victim\\outside]",
    MARK,
  }, "\r\n"))
  eq(target_of(forged, "evil"), "UNKNOWN nil", "forged: a line made up in a target is not believed")

  -- `dir` lists the long name only; the 8.3 alias names the same entry.
  eq(tag_of(en, "DOCUME~1"), "UNKNOWN", "the alias of a link may be that link")
  eq(tag_of(en, "docume~1.lua"), "UNKNOWN", "...with an extension, in any case")
  eq(tag_of(en, "plain~2"), "UNKNOWN", "...whichever entry it is the alias of")
  eq(target_of(en, "readme.md"), nil, "a name with no tilde and digit is answered exactly")
  eq(target_of(en, "a~b"), nil, "...and a tilde with no digit after it is not an alias")

  -- ...and a directory that lists no link has none to be reached through a
  -- name that cannot be matched.
  local none = win_links.parse("File Not Found\r\n" .. MARK .. "\r\n")
  eq(win_links.find(none, "DOCUME~1"), nil, "no link listed: an alias reaches nothing")
  eq(win_links.find(none, "caf\130"), nil, "...nor does a non-ASCII name")
  eq(win_links.find(none, "a?b"), nil, "...nor does a `?`")
  local only_plain = win_links.parse(table.concat({
    "08/10/2026  18:24    <REP>          simple",
    MARK,
  }, "\r\n"))
  eq(#only_plain.links, 0, "a listing of plain directories only has no link")
  eq(win_links.find(only_plain, "caf\130"), nil, "...so it answers every name as not a link")

  -- The lookup is a table, not a walk over every listed link, and it answers
  -- as the walk did: whatever the case, a name may hold ` [`, and a target may
  -- hold `]` and `[`. Where the walk found a second line that reads the name,
  -- which is no one's name, the answer is a link with no target.
  local function linear(census, name)
    local wanted = name:lower() .. " ["
    local found
    for _, link in ipairs(census.links) do
      if link.rest:sub(1, #wanted):lower() == wanted then
        if found then
          return { tag = "UNKNOWN" }
        end
        found = { tag = link.tag, target = link.rest:sub(#wanted + 1):match("^(.*)%]%s*$") }
      end
    end
    return found
  end

  local tangled = win_links.parse(table.concat({
    "10/08/2026  06:24 PM    <JUNCTION>     Docs [C:\\a]",
    "10/08/2026  06:24 PM    <SYMLINKD>     docs [C:\\b]",
    "10/08/2026  06:24 PM    <SYMLINKD>     my dir [x] [..\\t]",
    "10/08/2026  06:24 PM    <SYMLINKD>     my dir [C:\\second]",
    "10/08/2026  06:24 PM    <JUNCTION>     t [a] b [c]",
    "10/08/2026  06:24 PM    <SYMLINK>      f.txt [..\\f.txt]",
    "10/08/2026  06:24 PM    <JONCTION>     carte [C:\\fr]",
    "10/08/2026  06:24 PM    <JUNCTION>     k [a] [b] [c]",
    "10/08/2026  06:24 PM    <JUNCTION>     k [a] [b] [d]",
    "10/08/2026  06:24 PM    <JUNCTION>     k [a] [b] [e]",
    MARK,
  }, "\r\n"))
  for _, name in ipairs({
    "Docs",
    "docs",
    "DOCS",
    "my dir",
    "my dir [x]",
    "My Dir [X]",
    "t",
    "t [a]",
    "t [a] b",
    "T [A] B",
    "f.txt",
    "F.TXT",
    "carte",
    "plain",
    "my",
    "t [a",
    "k",
    "k [a]",
    "k [a] [b]",
    "",
  }) do
    local old, new = linear(tangled, name), win_links.find(tangled, name)
    eq(
      new and new.tag,
      old and old.tag,
      "lookup: the same link for `" .. name .. "` as the walk found"
    )
    eq(
      new and new.target,
      old and old.target,
      "lookup: ...with the same target for `" .. name .. "`"
    )
  end
  eq(
    target_of(tangled, "docs"),
    "UNKNOWN nil",
    "lookup: two links that read alike are no one's, and have no target"
  )
  eq(target_of(tangled, "my dir"), "UNKNOWN nil", "lookup: ...also when the name has a ` [`")
  eq(
    target_of(tangled, "my dir [x]"),
    "SYMLINKD ..\\t",
    "lookup: ...while a longer name that only one of them reads is found"
  )
  eq(target_of(tangled, "k"), "UNKNOWN nil", "lookup: three lines are no more telling than two")
  eq(target_of(tangled, "k [a]"), "UNKNOWN nil", "lookup: ...a name holding ` [` read by three")
  eq(target_of(tangled, "k [a] [b]"), "UNKNOWN nil", "lookup: ...and one that holds two")

  -- A directory of thousands of links, asked about thousands of names: the walk
  -- took seconds (every name against every link), the table takes milliseconds.
  -- The bound is far above what the table needs and far below the walk's.
  local lines = {}
  for i = 1, 3000 do
    lines[#lines + 1] = ("10/08/2026  06:24 PM    <JUNCTION>     link%05d [C:\\t%d]"):format(i, i)
  end
  lines[#lines + 1] = MARK
  local started = os.clock()
  local crowded = win_links.parse(table.concat(lines, "\r\n"))
  local hits = 0
  for i = 1, 3000 do
    if win_links.find(crowded, ("entry%05d"):format(i)) then
      hits = hits + 1
    end
  end
  eq(hits, 0, "lookup: none of three thousand plain names is a link")
  eq(
    target_of(crowded, "LINK02999"),
    "JUNCTION C:\\t2999",
    "lookup: ...and a link among them is found"
  )
  ok(os.clock() - started < 1, "lookup: three thousand links and names take well under a second")

  -- The target is the repository's to write, and a junction's can hold
  -- thousands of characters. A line made of ` [` must cost what it weighs: a
  -- key for each of them would be a copy of the line up to there, so three
  -- hundred such links took seconds and hundreds of megabytes.
  local hostile = ("x ["):rep(1300)
  local stem = "10/08/2026  06:24 PM    <JUNCTION>     "
  local flood = { stem .. "a [b] [C:\\" .. hostile .. "]" }
  for i = 1, 300 do
    flood[#flood + 1] = ("%slink%05d [C:\\%s]"):format(stem, i, hostile)
  end
  flood[#flood + 1] = MARK
  local flood_text = table.concat(flood, "\r\n")
  collectgarbage()
  local before = collectgarbage("count")
  started = os.clock()
  local flooded = win_links.parse(flood_text)
  local took = os.clock() - started
  collectgarbage()
  local kept = collectgarbage("count") - before
  local keys = 0
  for _ in pairs(flooded.by_name) do
    keys = keys + 1
  end
  eq(#flooded.links, 301, "flood: every line is a link")
  eq(keys, 301, "flood: one key for each, however many ` [` the target holds")
  ok(took < 1, "flood: three hundred long targets are read in well under a second")
  ok(kept < 8 * 1024, "flood: ...and cost about what they weigh (" .. math.floor(kept) .. " KB)")
  eq(
    target_of(flooded, "link00007"),
    "JUNCTION C:\\" .. hostile,
    "flood: a link among them is found, with its whole target"
  )
  eq(
    target_of(flooded, "a [b]"),
    "UNKNOWN nil",
    "flood: every one of them has a second ` [`, so a name holding one is taken for a link"
  )
  eq(target_of(flooded, "x"), nil, "flood: the ` [` of a target is not a name")

  -- A name that holds ` [` is read off the lines that have a second one. Where
  -- thousands of links are made that way, thousands of such names would each be
  -- compared with every one of them; past a few dozen the name is answered as
  -- a link instead, and the other names are not touched by it.
  local crafted = {}
  for i = 1, 3000 do
    crafted[#crafted + 1] = ("%sn%05d [x] [y%d]"):format(stem, i, i)
  end
  crafted[#crafted + 1] = MARK
  local crowd = win_links.parse(table.concat(crafted, "\r\n"))
  started = os.clock()
  local unknown = 0
  for i = 1, 3000 do
    local hit = win_links.find(crowd, ("q%05d [z]"):format(i))
    if hit and hit.tag == "UNKNOWN" and hit.target == nil then
      unknown = unknown + 1
    end
  end
  eq(unknown, 3000, "crafted: a name holding ` [` among too many such links is taken for a link")
  ok(os.clock() - started < 1, "crafted: ...without being compared with each of them")
  eq(target_of(crowd, "n02999"), "JUNCTION x] [y2999", "crafted: a link is still found by its name")
  eq(win_links.find(crowd, "plain"), nil, "crafted: ...and a name without ` [` is answered exactly")
  local few = win_links.parse(table.concat(crafted, "\r\n", 1, 30) .. "\r\n" .. MARK)
  eq(win_links.find(few, "q00001 [z]"), nil, "crafted: a few of them are looked through")
  eq(target_of(few, "n00005 [x]"), "JUNCTION y5", "crafted: ...and a name is found among them")
  local some = win_links.parse(table.concat(crafted, "\r\n", 1, 100) .. "\r\n" .. MARK)
  eq(tag_of(some, "q00001 [z]"), "UNKNOWN", "crafted: a hundred of them are already too many")

  -- Batches: many directories listed by one `cmd.exe`, each read like a
  -- listing of its own, and only where the command said it stood.
  for name, want in pairs({
    ["src"] = true,
    ["my dir"] = true,
    ["a-b.c_d~1"] = true,
    ["100%"] = false,
    ["(x)"] = false,
    ["a^b"] = false,
    ["a&b"] = false,
    ["wow!"] = false,
    [" lead"] = false,
    ["trail "] = false,
    ["dot."] = false,
    ["caf\195\169"] = false,
    ["tab\there"] = false,
    [""] = false,
  }) do
    eq(win_links.batchable(name), want, "batch: is `" .. name .. "` batchable")
  end

  local rels = { "src", "src\\core", "gone", "moved", "docs" }
  local nonce = "5eed"
  local command = win_links.batch_command(rels, nonce)
  ok(command:find('^set "DIRCMD=" & cd & '), "batch: DIRCMD cleared, start printed: " .. command)
  ok(
    command:find(
      '(pushd "src\\core" 2>nul && (cd & dir /a:l 2>nul & echo __DOCMAP_DIR_5eed_2__ & popd))',
      1,
      true
    ),
    "batch: one piece per directory: " .. command
  )
  eq(
    #win_links.batch_piece("src", nonce, 1) + #" & ",
    #command:match("^.-(%(pushd.-popd%)%) & )"),
    "batch: a piece is as long as it says"
  )

  local function mark(i, n)
    return win_links.batch_mark(n or nonce, i) .. " "
  end
  local listed = win_links.parse_batch(
    table.concat({
      "C:\\repo",
      "C:\\repo\\SRC",
      " Volume in drive C has no label.",
      "",
      " Directory of C:\\repo\\src",
      "",
      "10/08/2026  06:24 PM    <JUNCTION>     map [C:\\elsewhere]",
      "10/08/2026  06:24 PM    <SYMLINKD>     cut [x",
      -- A target may print any line; a mark it cannot know the nonce of is
      -- only a line of the listing.
      mark(1, "0000"),
      mark(2, "0000"),
      "C:\\repo\\src\\core\\dummy",
      "]",
      "10/08/2026  06:24 PM    <SYMLINKD>     late [..\\late]",
      mark(1),
      "C:\\repo\\src\\core",
      " Directory of C:\\repo\\src\\core",
      mark(2),
      -- `gone` could not be entered: nothing at all for it.
      "C:\\repo\\elsewhere",
      "10/08/2026  06:24 PM    <JUNCTION>     m [x]",
      mark(4),
      "C:\\repo\\docs",
      "10/08/2026  06:24 PM    <JUNCTION>     j [C:\\x]",
    }, "\r\n"),
    rels,
    nonce
  )
  ok(listed[1], "batch: the first directory is read, whatever case `cd` printed it in")
  eq(target_of(listed[1], "map"), "JUNCTION C:\\elsewhere", "batch: ...with its links")
  eq(target_of(listed[1], "late"), "SYMLINKD ..\\late", "batch: ...past a mark it could not know")
  ok(listed[2], "batch: the second is read")
  eq(#listed[2].links, 0, "batch: ...and holds no link, though the first one's target named it")
  eq(listed[3], nil, "batch: a directory that was not entered is not answered")
  eq(listed[4], nil, "batch: nor one the command did not stand in")
  eq(listed[5], nil, "batch: nor one whose mark never came")
  eq(next(win_links.parse_batch("", rels, nonce)), nil, "batch: no output answers nothing")
  local root = win_links.parse_batch("C:\\\r\n" .. "C:\\src\r\n" .. mark(1), { "src" }, nonce)
  ok(root[1], "batch: from the root of a drive, which `cd` prints with its backslash")
end
