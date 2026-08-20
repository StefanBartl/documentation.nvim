-- TESTS/explain_spec.lua — every control that can be explained, is
--
-- The page carries a "what is this?" card on `data-explain`, keyed into an
-- `EXPLAIN` table. Two halves that can drift apart in both directions: an
-- attribute whose key has no text shows nothing on hover, and a text no
-- attribute reaches is prose nobody can ever read. Neither fails loudly —
-- the first is a hover that does nothing, the second is invisible by
-- definition — so the join is what a spec has to hold.
--
-- **Same limit as `hierarchy_gestures_spec.lua`, and for the same reason.**
-- The card opens in a browser; the generated HTML contains the code, not its
-- behaviour. What was verified by driving the real page is that `focusin`
-- delivers the card on the keyboard path, including on a `<summary>` — the
-- shape that looked unfocusable and is not. What a spec can hold is the
-- structure underneath, which is this file.
--
-- Read out of `html.lua` rather than out of `docs/map/index.html`: the source
-- is what a change edits, and a spec that needed the map regenerated first
-- would go red for the wrong reason.

return function(H)
  local eq, ok = H.eq, H.ok

  local path = (vim.fn.getcwd():gsub("\\", "/")) .. "/lua/documentation/core/render/html.lua"
  local fd = assert(io.open(path, "rb"), "explain spec: html.lua must be readable")
  local src = fd:read("*a")
  fd:close()

  ---The `EXPLAIN` table's own keys.
  ---
  ---Sliced to the table's body rather than matched across the whole file:
  ---`"tab.hierarchy"` also appears in prose and in `data-explain` attributes,
  ---and counting those as definitions would make every assertion below
  ---vacuously true.
  ---@return table<string, boolean>
  local function defined_keys()
    local from = src:find("var EXPLAIN = {", 1, true)
    ok(from ~= nil, "explain: the EXPLAIN table must exist")
    local to = src:find("\n  };", from, true)
    ok(to ~= nil, "explain: ...and must be closed")
    local body = src:sub(from, to)
    local keys = {}
    for key in body:gmatch('"([a-z][a-z0-9_.]*)":') do
      keys[key] = true
    end
    return keys
  end

  ---Every key something can actually reach: written as an attribute in the
  ---markup, or assigned from the sub-tab table in the script.
  ---@return table<string, boolean>
  local function reachable_keys()
    local keys = {}
    for key in src:gmatch('data%-explain="([a-z][a-z0-9_.]*)"') do
      keys[key] = true
    end
    -- `renderSubTabs` sets `b.dataset.explain` from this list, so these are
    -- reachable without ever appearing as an attribute in the source. Missing
    -- this is how a first reading of the file concluded four texts were
    -- unreachable when all four were wired.
    for key in src:gmatch('explain:%s*"([a-z][a-z0-9_.]*)"') do
      keys[key] = true
    end
    return keys
  end

  local defined = defined_keys()
  local reachable = reachable_keys()

  local n_defined, n_reachable = 0, 0
  for _ in pairs(defined) do
    n_defined = n_defined + 1
  end
  for _ in pairs(reachable) do
    n_reachable = n_reachable + 1
  end

  -- A floor with headroom, not the exact count: this exists to catch the
  -- patterns above matching nothing, and a number that has to be edited
  -- whenever a control is added is one that gets edited without being
  -- thought about.
  ok(n_defined >= 30, "explain: the table was parsed, found " .. n_defined .. " texts")
  ok(n_reachable >= 30, "explain: the attributes were parsed, found " .. n_reachable)

  -- ---------------------------------------------------------------------
  -- The join, both ways.
  -- ---------------------------------------------------------------------
  local no_text = {}
  for key in pairs(reachable) do
    if not defined[key] then
      no_text[#no_text + 1] = key
    end
  end
  table.sort(no_text)
  eq(
    table.concat(no_text, ", "),
    "",
    "explain: every data-explain key has a text — a key without one is a hover that does nothing"
  )

  local no_control = {}
  for key in pairs(defined) do
    if not reachable[key] then
      no_control[#no_control + 1] = key
    end
  end
  table.sort(no_control)
  eq(
    table.concat(no_control, ", "),
    "",
    "explain: every text is reachable — one that is not is prose no reader can ever see"
  )

  -- ---------------------------------------------------------------------
  -- The two toolbars this was built for, and the rule they now follow.
  --
  -- `title` is what these controls used to carry, and this mechanism's own
  -- `focusin` handler argues against it in the file: a `title` never appears
  -- on focus, which would leave exactly the controls a keyboard user reaches
  -- as the only ones with no explanation. So a control here carries one or
  -- the other, and it must be the one that works on the keyboard.
  -- ---------------------------------------------------------------------
  for _, cls in ipairs({ "hview%-btn", "anview%-btn" }) do
    local total, explained, titled = 0, 0, 0
    for tag in src:gmatch('<button class="[^"]*' .. cls .. '[^"]*"[^>]*>') do
      total = total + 1
      if tag:find("data-explain=", 1, true) then
        explained = explained + 1
      end
      if tag:find("title=", 1, true) then
        titled = titled + 1
      end
    end
    ok(total >= 6, cls .. ": the toolbar was found, " .. total .. " buttons")
    eq(explained, total, cls .. ": every button carries data-explain")
    eq(titled, 0, cls .. ": and none falls back to a title, which no keyboard user ever sees")
  end

  -- ---------------------------------------------------------------------
  -- The card is *associated* with its control, not merely positioned beside
  -- it. Six of these buttons used to carry a `title`, which a screen reader
  -- announces; replacing that with a styled card and nothing else would have
  -- taken the explanation away from the readers least able to spare it.
  -- ---------------------------------------------------------------------
  ok(
    src:find('el.setAttribute("aria-describedby"', 1, true) ~= nil,
    "explain: the anchor is described by the card while it is open"
  )
  ok(
    src:find('explainAnchor.removeAttribute("aria-describedby")', 1, true) ~= nil,
    "explain: ...and stops being, when it closes — a description pointing at a "
      .. "hidden element describes nothing and is announced anyway"
  )
end
