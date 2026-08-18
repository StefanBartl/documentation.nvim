-- TESTS/glossary_spec.lua — the lookup layer's data
--
-- The page-side tokenizer is JavaScript inside a Lua string and is verified
-- by extracting it from the *generated page* and running it (see the
-- keyword-hover and stdlib commits). What this file guards is the data it
-- reads: the shape every entry must have, and the two rules that are easy to
-- break by adding a plausible-looking line to a table.

return function(H)
  local eq, ok = H.eq, H.ok
  local registry = require("documentation.core.lang_registry")
  local glossaries = registry.glossaries()

  eq(
    (function()
      local exts = {}
      for ext in pairs(glossaries) do
        exts[#exts + 1] = ext
      end
      table.sort(exts)
      return table.concat(exts, ",")
    end)(),
    "js,jsx,lua,ts,tsx",
    -- `jsx` appearing here is not incidental: this assertion is what noticed
    -- `js.lua` claiming a fifth extension, which is exactly the drift a
    -- literal list is for.
    "glossary: keyed by every extension the registered backends claim"
  )

  -- One table shared by the three ECMA registrations, not three copies. The
  -- renderer emits it once and references it three times.
  eq(glossaries.js, glossaries.ts, "glossary: js and ts share one table")
  eq(glossaries.ts, glossaries.tsx, "glossary: ... and tsx the same one")

  for ext, gl in pairs(glossaries) do
    local where = "glossary[" .. ext .. "]"

    ok(
      gl.reference and gl.reference.url and gl.reference.label ~= nil,
      where .. ": has a reference"
    )
    ok(gl.syntax and gl.syntax.strings ~= nil, where .. ": declares its string delimiters")

    for name, entry in pairs(gl.keywords) do
      ok(
        type(entry.summary) == "string" and entry.summary ~= "",
        where .. ": keyword " .. name .. " has a summary"
      )
      -- The rule the whole feature rests on: the explanation is offline and
      -- complete on its own, so a dead link costs an enhancement rather than
      -- the answer.
      ok(
        entry.summary:sub(-1) == "." or entry.summary:sub(-1) == "!",
        where .. ": keyword " .. name .. "'s summary is a sentence"
      )
    end

    for name, entry in pairs(gl.stdlib or {}) do
      ok(
        type(entry.summary) == "string" and entry.summary ~= "",
        where .. ": stdlib " .. name .. " has a summary"
      )
      -- A stdlib key is matched longest-prefix-first against a dotted run in
      -- the source. A key with a trailing or doubled dot can never match
      -- anything the tokenizer produces, so it would be an entry that exists
      -- and is unreachable.
      ok(
        name:match("^[%w_]+[%w_%.]*$") ~= nil and name:match("%.%.") == nil and name:sub(-1) ~= ".",
        where .. ": stdlib key " .. name .. " is a matchable dotted name"
      )
    end
  end

  -- The layering decision, asserted rather than left to a comment: `vim.*`
  -- lives in Lua's glossary because it is what readers of this ecosystem
  -- point at, and it is marked so the card can say so and the renderer can
  -- withhold the Lua manual link from it.
  local lua = glossaries.lua
  for name, entry in pairs(lua.stdlib) do
    if name:sub(1, 4) == "vim." then
      eq(entry.origin, "Neovim", "glossary: " .. name .. " is marked as not being Lua")
    else
      eq(entry.origin, nil, "glossary: " .. name .. " is Lua and carries no foreign origin")
    end
  end

  -- Every ECMA entry is JavaScript, and MDN documents all of them, so an
  -- origin there would be noise on every card.
  for name, entry in pairs(glossaries.ts.stdlib or {}) do
    eq(entry.origin, nil, "glossary: ECMA stdlib entry " .. name .. " needs no origin")
  end
end
