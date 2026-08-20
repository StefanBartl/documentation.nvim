-- TESTS/prose_render_spec.lua — author prose reaches the page as markup
--
-- The doc-comments have always been markdown. `overview.md` renders their
-- inline code correctly because markdown does it natively; the HTML page
-- escaped it into literal backticks, so a summary reading "Registers the
-- single `:Debug` user command" arrived in the Hierarchy boxes with the
-- ticks showing. Measured on this tree: **432 summaries carry backticks**.
--
-- **What this file can and cannot check, stated because the difference
-- matters.** `prose()` runs in the browser: the generated HTML contains the
-- function, not its output, so no Lua spec can see a `<code>` element. The
-- rendering itself was verified by loading the page and reading the DOM —
-- 750 `<code>` elements, 96 of them in Hierarchy boxes, no empty ones and
-- no nested ones.
--
-- What a spec *can* hold is the property that made the bug possible in the
-- first place: **every surface that renders author prose goes through the
-- one function.** Before this, twelve call sites each reached for `esc`
-- independently, and a thirteenth would have joined them without anyone
-- noticing. That is the guarantee here — not the markup, the routing.

return function(H)
  local eq, ok = H.eq, H.ok

  local path = (vim.fn.getcwd():gsub("\\", "/")) .. "/lua/documentation/core/render/html.lua"
  local fd = assert(io.open(path, "rb"), "prose spec: html.lua must be readable")
  local src = fd:read("*a")
  fd:close()

  ok(
    src:find("function prose(s){", 1, true) ~= nil,
    "prose: the page defines one function for author prose"
  )
  ok(
    src:find("var out = esc(s);", 1, true) ~= nil,
    "prose: it escapes first — the entire safety argument is that no tag "
      .. "exists in the string before it writes its own"
  )

  -- One pass, not two. Run separately, the single-backtick rule reads the
  -- double-backtick rule's own output and nests `<code>` inside `<code>` —
  -- which is what happened, and what the DOM showed.
  ok(
    src:find("``([\\s\\S]+?)``|`([^`\\n]+)`", 1, true) ~= nil,
    "prose: one alternation, so the scanner never re-reads what it wrote"
  )

  -- ---------------------------------------------------------------------
  -- The routing guarantee.
  --
  -- Every rendering of a `.summary` into markup must go through `prose`.
  -- Matched on the source line rather than on behaviour, deliberately: the
  -- failure this guards is somebody adding a thirteenth surface with `esc`,
  -- and that is a fact about the source.
  --
  -- `title="..."` attributes are excluded and that is not an oversight: a
  -- native tooltip renders no markup, so a `<code>` there would show as
  -- literal angle brackets. Those keep the raw text, backticks and all.
  -- ---------------------------------------------------------------------
  local offenders = {}
  local n = 0
  for line in src:gmatch("([^\n]*)\n") do
    -- A rendering site: `esc(` applied to something ending in `.summary`,
    -- inside a string being concatenated into markup.
    local site = line:match("esc%(([%w_%.]*%.summary[^%)]*)%)")
    if site and not line:match("title") then
      n = n + 1
      offenders[#offenders + 1] = (line:gsub("^%s+", ""):sub(1, 90))
    end
  end
  eq(
    table.concat(offenders, "\n    "),
    "",
    "prose: no surface renders a summary through esc() — author prose goes "
      .. "through prose(), which is the one place that knows what markdown it accepts"
  )

  -- And the inverse, so this cannot pass by the sites having been deleted.
  local uses = 0
  for _ in src:gmatch("prose%(") do
    uses = uses + 1
  end
  ok(uses >= 12, "prose: the surfaces are actually wired to it (" .. uses .. " call sites)")
end
