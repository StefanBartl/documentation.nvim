-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/tags_spec.lua — `core/tags.lua`, the annotation catalogue, and the
-- join that keeps it honest against the parser it was extracted from.
--
-- The catalogue exists because three separate pieces of work each wanted the
-- same answer — which tags exist, what they mean, where to read more — and
-- each was costed with its own copy of it. Having one copy is only an
-- improvement while it agrees with the parser, and nothing in Lua makes it:
-- the handlers are a table of closures inside `parse_doc_block`, and the
-- catalogue is data in another file. So the agreement is asserted here, in
-- both directions, because each direction fails differently:
--
--   * A catalogued tag with no handler is a **promise the parser does not
--     keep** — the reference panel documents `@raises`, the map ignores it.
--   * A handler for an uncatalogued tag is a **feature no reader can
--     discover** — the map reads it, nothing says so.
--
-- Read out of the source text rather than by calling the parser, because the
-- handler table is local by design (it closes over one block's accumulators)
-- and exporting it to be testable would be the test dictating the shape of
-- the code.

return function(H)
  local eq, ok = H.eq, H.ok
  local tags = require("documentation.core.tags")

  -- ---------------------------------------------------------------------
  -- The catalogue itself
  -- ---------------------------------------------------------------------

  ok(#tags.TAGS >= 20, ("tags: the catalogue is populated (%d)"):format(#tags.TAGS))

  local seen = {}
  for _, t in ipairs(tags.TAGS) do
    ok(not seen[t.name], "tags: " .. t.name .. " is listed once")
    seen[t.name] = true
    ok(type(t.summary) == "string" and #t.summary > 20, "tags: " .. t.name .. " says what it means")
    ok(
      t.scope == "function" or t.scope == "module" or t.scope == "type",
      "tags: " .. t.name .. " declares where it is written"
    )
    ok(type(t.repeats) == "boolean", "tags: " .. t.name .. " says whether it repeats")
  end

  -- The rule that decides linking. A `docmap` tag is this project's own
  -- convention: sending a reader to luals.github.io for one would be a link
  -- that loads, looks authoritative, and does not contain the answer.
  for _, t in ipairs(tags.TAGS) do
    if t.origin == "docmap" then
      eq(t.anchor, nil, "tags: " .. t.name .. " is ours, so it carries no upstream anchor")
      eq(tags.url(t.name), nil, "tags: ... and no upstream URL")
    else
      eq(t.origin, "luals", "tags: " .. t.name .. " has a known origin")
      ok(type(t.anchor) == "string" and #t.anchor > 0, "tags: " .. t.name .. " anchors somewhere")
      local url = tags.url(t.name)
      ok(url and url:find("luals.github.io", 1, true), "tags: " .. t.name .. " links to LuaLS")
      ok(url:find("#" .. t.anchor, 1, true), "tags: ... at its own anchor")
    end
  end

  -- Both spellings, because callers have both: the page holds `@param`, the
  -- parser holds `param`.
  ok(tags.get("param") ~= nil, "tags: get() takes a bare name")
  ok(tags.get("@param") ~= nil, "tags: get() takes the written form too")
  eq(tags.get("raises"), nil, "tags: a tag this plugin does not read is absent, not invented")
  -- Deliberately the wrong argument: what is under test is the refusal.
  ---@diagnostic disable-next-line: param-type-mismatch
  eq(tags.get(nil), nil, "tags: a nil lookup is nil, not an error")

  -- ---------------------------------------------------------------------
  -- The join with the parser
  -- ---------------------------------------------------------------------

  local src = table.concat(vim.fn.readfile("lua/documentation/core/functions.lua"), "\n")

  local handlers_at = src:find("local HANDLERS = {", 1, true)
  ok(handlers_at ~= nil, "tags: the parser dispatches through a named table")
  ---@cast handlers_at -nil

  -- Bounded to the table's own body, so an unrelated `foo = function` later
  -- in the file cannot be mistaken for a handler.
  local body = src:sub(handlers_at, src:find("\n  }", handlers_at, true) or #src)
  local handled = {}
  for name in body:gmatch("\n%s+([%a_]+)%s*=%s*function") do
    handled[name] = true
  end
  for name in body:gmatch('\n%s+%["([%a_]+)"%]%s*=%s*function') do
    handled[name] = true
  end

  local n = 0
  for _ in pairs(handled) do
    n = n + 1
  end
  ok(n >= 14, ("tags: the handler table was parsed (%d handlers)"):format(n))

  -- Direction 1: everything the catalogue promises at function scope, the
  -- parser reads.
  for _, t in ipairs(tags.TAGS) do
    if t.scope == "function" then
      ok(handled[t.name], "tags: @" .. t.name .. " is catalogued and the parser handles it")
    end
  end

  -- Direction 2: everything the parser reads, the catalogue describes.
  for name in pairs(handled) do
    local entry = tags.get(name)
    ok(entry ~= nil, "tags: the parser handles @" .. name .. ", so the catalogue must describe it")
    if entry then
      eq(entry.scope, "function", "tags: @" .. name .. " is a function-scope tag")
    end
  end

  -- ---------------------------------------------------------------------
  -- `repeats` is a claim about the parser, not a label
  -- ---------------------------------------------------------------------

  -- `repeats` is a claim about what the parser does, so it is checked by
  -- making the parser do it rather than by matching source text: the
  -- accumulator's name is not derivable from the tag's (`param` fills
  -- `params`, `see` fills `see`), and a pattern that encodes that mapping
  -- would be the parser written twice.
  for _, name in ipairs({ "param", "return", "see", "todo", "bug", "test", "overload", "generic" }) do
    eq(tags.get(name).repeats, true, "tags: @" .. name .. " is documented as repeating")
  end
  for _, name in ipairs({ "deprecated", "since", "example", "internal", "async", "nodiscard" }) do
    eq(tags.get(name).repeats, false, "tags: @" .. name .. " is documented as not repeating")
  end

  do
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local path = dir .. "/repeats.lua"
    local fd = assert(io.open(path, "wb"))
    fd:write(table.concat({
      "---@module 'repeats'",
      "--- Fixture.",
      "local M = {}",
      "---Two of each repeating tag, one of each single one.",
      "---@param a string first",
      "---@param b string second",
      "---@see other.one, other.two",
      "---@todo first thing",
      "---@todo second thing",
      "---@deprecated use one",
      "---@deprecated use two",
      "---@return nil",
      "function M.go(a, b) end",
      "return M",
    }, "\n") .. "\n")
    fd:close()

    local fns = require("documentation.core.functions").scan_file(path)
    local go
    for _, f in ipairs(fns or {}) do
      if f.name == "M.go" then
        go = f
      end
    end
    ok(go ~= nil, "tags: the fixture parsed")
    if go then
      eq(#go.params, 2, "tags: @param repeats, and both are kept")
      eq(#go.see, 2, "tags: @see repeats, comma-separated inside one tag too")
      eq(#go.todo, 2, "tags: @todo repeats, so two open todos are two")
      -- The other half of the claim: a non-repeating tag written twice keeps
      -- one. Which one is the parser's business; that it is a single value
      -- rather than a list is the catalogue's.
      eq(type(go.deprecated), "string", "tags: @deprecated does not repeat, so it stays one value")
    end
    vim.fn.delete(dir, "rf")
  end

  eq(tags.names()[1], "alias", "tags: names() is sorted")
end
