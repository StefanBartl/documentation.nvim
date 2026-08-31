-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/browse_lookup_spec.lua — `K` in the browser's detail pane
--
-- The feature is a glossary card for the word under the cursor, and the one
-- decision worth holding is *where it declines to answer*. Counted over this
-- repository's own browser text, a glossary term appears 213 times inside an
-- inline `code` span and 2 558 times in plain English prose — "and", "for",
-- "in", "end", "type". Answering everywhere would be wrong twelve times out
-- of thirteen, and wrong in the worst available way: a correct definition
-- attached to a word that is not code. So the span is the gate, and most of
-- what follows is that gate under load.
--
-- Everything here runs against the *real* Lua glossary, not a fixture. The
-- resolution rules exist to agree with the generated page's tokenizer, and a
-- hand-written table could agree with the code while both drifted from the
-- data they are supposed to describe.

return function(H)
  local eq, ok = H.eq, H.ok

  local L = require("documentation.editor.browse.lookup")

  -- ---------------------------------------------------------------------
  -- The glossary comes from the language registry, by extension.
  -- ---------------------------------------------------------------------
  local gl = L.glossary_for("lua/documentation/init.lua")
  ok(gl ~= nil, "lookup: a .lua path finds the Lua glossary")
  eq(L.glossary_for("README.md"), nil, "lookup: a language with no glossary is nil, not an error")
  eq(L.glossary_for(nil), nil, "lookup: no path, no glossary")
  eq(L.glossary_for("Makefile"), nil, "lookup: no extension, no glossary")

  -- ---------------------------------------------------------------------
  -- The gate: inside a code span, and nowhere else.
  -- ---------------------------------------------------------------------
  local line = "the `vim.fs.dirname` helper and end"
  local word, span = L.word_at(line, 5)
  eq(
    word,
    "vim.fs.dirname",
    "lookup: the whole dotted run, not the part under the cursor — "
      .. "stopping at the dot would look up `vim`, which means nothing on its own"
  )
  ok(span ~= nil, "lookup: ...and reports the span it came from")

  eq(
    (L.word_at(line, 32)),
    nil,
    "lookup: `end` in prose is not answered — this is the entire feature, and "
      .. "the case that made it a span lookup rather than a word lookup"
  )
  eq((L.word_at(line, 0)), nil, "lookup: outside every span, nothing")

  -- The backtick itself counts as inside: a cursor resting on the opening
  -- tick is pointing at that word by any reading a person would give it.
  eq((L.word_at(line, 4)), "vim.fs.dirname", "lookup: the opening backtick is inside")

  -- ---------------------------------------------------------------------
  -- Resolution, in the order the page's tokenizer resolves.
  -- ---------------------------------------------------------------------
  local key, entry, kind = L.resolve("vim.fs.dirname", gl)
  eq(key, "vim.fs.dirname", "lookup: a stdlib name resolves to itself")
  eq(kind, "stdlib", "lookup: ...as stdlib")
  ok(entry ~= nil and entry.summary ~= nil, "lookup: ...carrying the entry")

  eq(
    (L.resolve("s:gsub", gl)),
    "string.gsub",
    "lookup: a colon call reads through syntax.method_namespace — the key that "
      .. "matched is not the word, which is why the card is titled with the key"
  )
  eq((select(3, L.resolve("end", gl))), "keyword", "lookup: a bare word can be a keyword")
  eq(
    (L.resolve("foo.end", gl)),
    nil,
    "lookup: a keyword is bare by definition — `end` in `foo.end` is not Lua"
  )
  eq(
    (L.resolve("vim.uv.", gl)),
    "vim.uv",
    "lookup: trailing punctuation a doc comment writes is trimmed first"
  )
  eq(
    (L.resolve("s:notamethod", gl)),
    nil,
    "lookup: a colon call the namespace lacks is not a keyword either"
  )
  eq((L.resolve("wholly.made.up", gl)), nil, "lookup: an unknown name resolves to nothing")
  eq((L.resolve("vim.fs.dirname", nil)), nil, "lookup: no glossary, no answer")

  -- ---------------------------------------------------------------------
  -- The card, and the link it withholds.
  --
  -- Sending a reader to the Lua 5.1 manual for `vim.split` is a link that
  -- looks right and answers nothing. An entry with an `origin` is not from
  -- the referenced manual, so it gets no reference line.
  -- ---------------------------------------------------------------------
  local k1, e1, kind1 = L.resolve("s:gsub", gl)
  local card = L.card(k1, e1, kind1, gl)
  eq(card[1], "string.gsub", "card: titled with the key that matched, not the word typed")
  ok(card[2]:find("stdlib", 1, true) ~= nil, "card: the kind is on the second line")
  ok(
    table.concat(card, "\n"):find("lua.org", 1, true) ~= nil,
    "card: a genuine Lua name gets the manual link"
  )

  local k2, e2, kind2 = L.resolve("vim.split", gl)
  ok(e2.origin ~= nil, "card: vim.split carries an origin — it is not from the Lua manual")
  local card2 = L.card(k2, e2, kind2, gl)
  eq(
    table.concat(card2, "\n"):find("lua.org", 1, true),
    nil,
    "card: ...so the manual link is withheld, rather than pointing at a page "
      .. "that does not document it"
  )
  ok(card2[2]:find(e2.origin, 1, true) ~= nil, "card: the origin is shown instead")

  -- ---------------------------------------------------------------------
  -- The trap, and it is a real one: **`<Tab>` must not be bound.**
  --
  -- A terminal sends the same byte for `<Tab>` and `<C-i>`. This feature was
  -- first written with `<Tab>` as the key into the detail pane, which
  -- silently took `<C-i>` away from the browser's history — a stepped-forward
  -- view came back as `[structure]`. `docmap_browse_spec.lua` caught it, and
  -- would catch it again; this holds the *reason* next to the feature that
  -- caused it, so the next person reaching for the obvious key finds out here
  -- rather than from a history test three files away.
  --
  -- Checked against the source because `KEYS` is a local table: the failure
  -- being guarded is somebody typing the four characters, and that is a fact
  -- about the file.
  local path = (vim.fn.getcwd():gsub("\\", "/")) .. "/lua/documentation/editor/browse/init.lua"
  local fd = assert(io.open(path, "rb"), "lookup spec: browse/init.lua must be readable")
  local src = fd:read("*a")
  fd:close()

  eq(
    src:match('keys = {[^}]*"<Tab>"'),
    nil,
    "lookup: no action binds <Tab> — it is the same keycode as <C-i>, which "
      .. "the history already owns"
  )
  ok(
    src:find('keys = { "w" },', 1, true) ~= nil,
    "lookup: `w` is the key into the detail pane — free, because a read-only "
      .. "list has no word motion to shadow"
  )
end
