-- TESTS/markers_spec.lua — `core/markers.lua`, marker comments.
--
-- Strings rather than files on disk: `scan_source` takes text precisely so
-- the interesting cases (a marker inside a string literal, a block comment
-- left open across three lines) can be written inline instead of assembled
-- as a fixture tree. `scan_file` is one `io.open` on top of it.

return function(H)
  local eq, ok = H.eq, H.ok
  local markers = require("documentation.core.markers")
  local registry = require("documentation.core.lang_registry")

  local lua_backend = registry.for_file("init.lua")
  local js_backend = registry.for_file("index.js")
  ok(lua_backend ~= nil, "the Lua backend must be registered for this spec to mean anything")
  ok(js_backend ~= nil, "the JS backend must be registered for this spec to mean anything")

  local function scan(src, backend)
    return markers.scan_source(table.concat(src, "\n"), backend or lua_backend)
  end

  -- ---------------------------------------------------------------------
  -- The plain forms, which are the ones the author types all day.
  -- ---------------------------------------------------------------------
  do
    local found = scan({
      "local M = {}",
      "-- TODO: split this out",
      "-- BUG: off by one on the last row",
      "-- PERFORMANCE: this reads the file twice",
      "return M",
    })
    eq(#found, 3, "one marker per marked line")

    eq(found[1].kind, "TODO")
    eq(found[1].word, "TODO")
    eq(found[1].text, "split this out")
    eq(found[1].line, 2)

    -- The canonical kind is what groups them; the written word is what the
    -- author sees highlighted in their buffer, so both survive.
    eq(found[2].kind, "FIX")
    eq(found[2].word, "BUG")

    eq(found[3].kind, "PERF")
    eq(found[3].word, "PERFORMANCE")
  end

  -- ---------------------------------------------------------------------
  -- A keyword is only a marker inside a comment. This is the whole reason
  -- the backend has to state its comment syntax rather than this module
  -- matching `TODO:` anywhere on the line.
  -- ---------------------------------------------------------------------
  do
    local found = scan({
      'local msg = "TODO: write the docs"',
      'log("FIXME: not a marker either")',
    })
    eq(#found, 0, "a keyword in a string literal is not a marker")
  end

  do
    local found = scan({
      'local msg = "not a marker" -- TODO: but this is',
    })
    eq(#found, 1, "a trailing comment after code is still a comment")
    eq(found[1].text, "but this is")
  end

  -- ---------------------------------------------------------------------
  -- Word boundaries. `AUTOTODO:` is somebody's variable, not a to-do.
  -- ---------------------------------------------------------------------
  do
    eq(#scan({ "-- AUTOTODO: nope" }), 0, "a keyword needs its left boundary")
    -- Case-sensitive, matching `todo-comments.nvim`'s own default. A map
    -- that collected `-- todo:` while the editor left it uncoloured would
    -- disagree with the buffer the author is looking at, and the buffer is
    -- the thing they trust.
    eq(#scan({ "-- todo: lowercase is not the marker convention" }), 0)
  end

  -- ---------------------------------------------------------------------
  -- A keyword inside inline code is prose *about* markers. This module's
  -- own header is the reason: it lists the syntaxes it recognises, and the
  -- first version of it reported three open items in the sentence
  -- describing the feature.
  -- ---------------------------------------------------------------------
  do
    eq(
      #scan({ "-- These read `-- TODO:`, `// FIXME:`, `-- PERF:` off the text" }),
      0,
      "a marker quoted as inline code is a mention, not a marker"
    )
    local found = scan({ "-- TODO: rewrite `parse()` to take text" })
    eq(#found, 1, "a real marker whose text contains code is still a marker")
    eq(found[1].text, "rewrite `parse()` to take text", "and its text keeps the code intact")
  end

  -- ---------------------------------------------------------------------
  -- Leftmost wins, not longest. Iterating the spellings longest-first and
  -- taking the first hit made the reported keyword depend on its letter
  -- count rather than on its position.
  -- ---------------------------------------------------------------------
  do
    local found = scan({ "-- TODO: then FIXME: later" })
    eq(#found, 1)
    eq(found[1].word, "TODO", "the first keyword on the line is the one reported")
  end

  -- ---------------------------------------------------------------------
  -- `FIXME` must not be read as `FIX` with a stray `ME:`.
  -- ---------------------------------------------------------------------
  do
    local found = scan({ "-- FIXME: the whole word" })
    eq(#found, 1)
    eq(found[1].word, "FIXME")
    eq(found[1].text, "the whole word")
  end

  -- ---------------------------------------------------------------------
  -- The author form. Dropping the name would turn "ask Stefan" into an
  -- anonymous note.
  -- ---------------------------------------------------------------------
  do
    local found = scan({ "-- TODO(stefan): confirm the encoding" })
    eq(#found, 1)
    eq(found[1].author, "stefan")
    eq(found[1].text, "confirm the encoding")
  end

  -- ---------------------------------------------------------------------
  -- A bare marker is a real marker. Requiring text would undercount, and
  -- an undercount is the silent-degradation failure this map exists to
  -- avoid.
  -- ---------------------------------------------------------------------
  do
    local found = scan({ "-- TODO:" })
    eq(#found, 1)
    eq(found[1].text, "")
  end

  -- ---------------------------------------------------------------------
  -- Block comments, including one spanning lines. Commenting a region out
  -- is one of the more common reasons a TODO exists at all.
  -- ---------------------------------------------------------------------
  do
    local found = scan({
      "--[[",
      "TODO: this block is disabled until the parser lands",
      "]]",
      "local x = 1",
    })
    eq(#found, 1, "a marker on the third line of a block comment is still in a comment")
    eq(found[1].line, 2)
  end

  do
    local found = scan({
      "/* TODO: on one line */",
      "const a = 1; /* NOTE: trailing */",
      "// FIXME: and a line comment",
    }, js_backend)
    eq(#found, 3)
    eq(found[1].kind, "TODO")
    eq(found[2].kind, "NOTE")
    eq(found[3].kind, "FIX")
  end

  -- Text after a block comment closes must not be read as comment.
  do
    local found = scan({
      '/* nothing here */ log("TODO: not a marker")',
    }, js_backend)
    eq(#found, 0, "code after a closed block comment is code again")
  end

  -- ---------------------------------------------------------------------
  -- The grammar is what makes a string literal safe. This is the case the
  -- text scanner cannot get right and the reason it is the fallback: `--`
  -- opens a comment everywhere on the line *except* inside a string, and no
  -- pattern can be made to know the difference.
  -- ---------------------------------------------------------------------
  do
    eq(
      #scan({ 'local doc = "-- TODO: an example in a docstring, not a task"' }),
      0,
      "a marker inside a string literal is data, not a task"
    )
    local found = scan({ 'local doc = "-- TODO: shown" -- TODO: real' })
    eq(#found, 1, "and the real marker on the same line still counts")
    eq(found[1].text, "real")
  end

  -- ---------------------------------------------------------------------
  -- Without a grammar the text scanner runs instead, and carries its own
  -- rule for the case above: a comment opener sitting inside inline code is
  -- prose. Exercised through a backend that declares comment syntax and no
  -- grammar, which is exactly the standalone binary's state when
  -- `DOCMAP_TS_DIR` points at nothing.
  -- ---------------------------------------------------------------------
  do
    local no_grammar = {
      name = "fallback",
      line_comments = { "--" },
      block_comments = { { "--[[", "]]" } },
    }
    local function fscan(line)
      ---@diagnostic disable-next-line: missing-fields
      return markers.scan_source(line, no_grammar)
    end

    eq(#fscan("-- TODO: still found without a parser"), 1, "the fallback finds plain markers")
    eq(
      #fscan("  Two syntaxes are read here: `-- TODO:` and `// FIXME:` alike"),
      0,
      "an opener inside a code span is prose, not a comment"
    )
    -- Stated rather than hidden: this is the case the fallback gets wrong,
    -- and it is why the parser path exists.
    eq(
      #fscan('local doc = "-- TODO: an example in a docstring"'),
      1,
      "and without a grammar a string literal is indistinguishable from a comment"
    )
  end

  -- ---------------------------------------------------------------------
  -- A backend that states no comment syntax gets nothing scanned, rather
  -- than a guess. `#` is a comment in Python and a directive in C.
  -- ---------------------------------------------------------------------
  do
    ---@diagnostic disable-next-line: missing-fields
    eq(#markers.scan_source("# TODO: whose language is this", { name = "mystery" }), 0)
    eq(#markers.scan_source("-- TODO: no backend at all", nil), 0)
  end

  -- ---------------------------------------------------------------------
  -- Every canonical keyword is reachable by every spelling it claims —
  -- the alias table and the matcher cannot drift apart silently.
  -- ---------------------------------------------------------------------
  do
    for _, kw in ipairs(markers.KEYWORDS) do
      local spellings = { kw.name }
      for _, alias in ipairs(kw.aliases) do
        spellings[#spellings + 1] = alias
      end
      for _, word in ipairs(spellings) do
        local found = scan({ "-- " .. word .. ": x" })
        eq(#found, 1, word .. " must be recognised")
        eq(found[1].kind, kw.name, word .. " must map to " .. kw.name)
        eq(found[1].word, word)
      end
    end
  end

  -- ---------------------------------------------------------------------
  -- Doc comments, which is where a marker about a declaration actually
  -- goes. Three grammars name that node something `COMMENT_NODES` did not
  -- know, and all three failed in the quiet direction: the parser answered,
  -- so the text fallback never ran, so the file simply had no markers.
  --
  -- Found by `scripts/parity.lua`, not by `backend_contract_spec.lua` —
  -- that one proves a comment token works by building the smallest file
  -- that could hold a marker, and the smallest file always lands in a plain
  -- `comment` node. It took a file with a *documented declaration* in it.
  --
  -- Each case skips when its grammar is absent, the same rule the language
  -- specs follow.
  -- ---------------------------------------------------------------------
  do
    -- Named rather than written inline at three call sites: a `"\n"` inside
    -- a table literal inside a spec is the kind of byte a later edit gets
    -- wrong silently.
    local NL = string.char(10)
    local cases = {
      {
        lang = "haskell",
        file = "x.hs",
        why = "a marker on the second line of a `-- |` run is inside a `haddock` node",
        src = table.concat({ "-- | Widen a value.", "-- TODO: cap it", "widen n = n" }, NL),
      },
      {
        lang = "kotlin",
        file = "x.kt",
        why = "Kotlin declares `block_comments` and every `/* */` is a `multiline_comment`",
        src = table.concat({ "/**", " * TODO: cap it", " */", "fun f() {}" }, NL),
      },
      {
        lang = "dart",
        file = "x.dart",
        why = "`///` is a `documentation_comment`, and it is where Dart writes prose",
        src = table.concat({ "/// TODO: cap it", "int f() => 1;" }, NL),
      },
    }
    for _, c in ipairs(cases) do
      local backend = registry.for_file(c.file)
      ok(backend ~= nil, c.lang .. " must be registered")
      local explicit = os.getenv("DOCMAP_" .. c.lang:upper() .. "_PARSER")
      local added
      if explicit and explicit ~= "" then
        _, added = pcall(vim.treesitter.language.add, c.lang, { path = explicit })
      else
        _, added = pcall(vim.treesitter.language.add, c.lang)
      end
      if added == true then
        local found = markers.scan_source(c.src, backend)
        eq(#found, 1, c.lang .. ": " .. c.why)
        eq(found[1].kind, "TODO")
        eq(
          found[1].text,
          "cap it",
          c.lang .. ": the note is the note, not the note plus a delimiter"
        )
      else
        ok(true, "markers: no " .. c.lang .. " parser — skipping")
      end
    end
  end

  -- ---------------------------------------------------------------------
  -- A block comment's closer belongs to the comment, not to the note. Only
  -- the parser path had this wrong: it hands `match_marker` the node's whole
  -- span, so `/* TODO: cap it */` was reported with the `*/` still on it and
  -- rendered that way into the Notes tab. The text fallback always sliced at
  -- the closer, which is why one path was right and the other was not.
  -- ---------------------------------------------------------------------
  do
    local found = scan({ "--[[ TODO: cap it ]]", "local x = 1" })
    eq(#found, 1)
    eq(found[1].text, "cap it", "the closing delimiter is not part of the note")

    local js = scan({ "/* TODO: cap it */", "const a = 1;" }, js_backend)
    eq(#js, 1)
    eq(js[1].text, "cap it", "same for the ECMA family's closer")
  end
end
