-- TESTS/analysis_tools_spec.lua — an Analysis tool is registered in four places
--
-- Adding one means touching four: the toolbar button, `drawAnalysis`'s
-- dispatch, `drawAnalysis`'s own guard against an unknown value, and the URL
-- parser's validator. Miss any of the last three and the button is there,
-- looks live, and silently shows Test coverage instead — which is the worst
-- shape a failure can have, because nothing is empty and nothing errors.
--
-- Found the hard way while adding `lazy`: four edits for one feature is
-- exactly the arithmetic that goes wrong on the fifth.
--
-- Read out of `html.lua` rather than the generated page, same reason
-- `explain_spec.lua` gives: the source is what a change edits.

return function(H)
  local ok = H.ok

  local path = (vim.fn.getcwd():gsub("\\", "/")) .. "/lua/documentation/core/render/html.lua"
  local fd = assert(io.open(path, "rb"), "analysis spec: html.lua must be readable")
  local src = fd:read("*a")
  fd:close()

  ---Every tool the toolbar offers.
  ---@return string[]
  local function buttons()
    local out = {}
    for name in src:gmatch('data%-atool="([a-z]+)"') do
      out[#out + 1] = name
    end
    table.sort(out)
    return out
  end

  local tools = buttons()
  -- A floor with headroom: this exists to catch the pattern matching
  -- nothing, not to be edited whenever a tool is added.
  ok(#tools >= 16, "analysis: the toolbar was parsed, found " .. #tools .. " tools")

  -- `test` is the default and is therefore *deliberately* absent from the
  -- two validators — they fall back to it, so listing it would be dead
  -- weight rather than a missing entry. Every other tool must be in both.
  for _, tool in ipairs(tools) do
    if tool ~= "test" then
      ok(
        src:find('atool === "' .. tool .. '"', 1, true) ~= nil,
        "analysis: " .. tool .. " is dispatched — without this its button shows Test coverage"
      )
      ok(
        src:find('v === "' .. tool .. '"', 1, true) ~= nil,
        "analysis: "
          .. tool
          .. " survives a URL round trip — without this a shared link "
          .. "silently lands on a different panel than the one that was shared"
      )
    end
    ok(
      src:find('"atool.' .. tool .. '"', 1, true) ~= nil,
      "analysis: " .. tool .. " has an explanation — `explain_spec` holds the other direction"
    )
  end

  -- ---------------------------------------------------------------------
  -- The four load states, which is what `lazy` is for.
  --
  -- `pluginTraits` used to answer "no trigger — loads at startup" for every
  -- spec without `event`/`cmd`/`ft`/`keys`. That is wrong for one of them,
  -- and wrong in the direction that matters: `lazy = true` with no trigger
  -- does **not** load at startup — it loads when something `require`s it.
  -- Telling its author it costs them startup time is the opposite of the
  -- truth, and it is the normal state of a dependency-only plugin.
  --
  -- Measured, not supposed: against a real 52-entry config, seven specs sat
  -- in exactly that state and every one was labelled "loads at startup".
  -- ---------------------------------------------------------------------
  ok(
    src:find('if(spec.lazy === true) return "ondemand";', 1, true) ~= nil,
    "plugins: `lazy = true` with no trigger is its own state, not startup"
  )
  ok(
    src:find("loads only when required", 1, true) ~= nil,
    "plugins: ...and the row says so rather than claiming a startup cost"
  )
  ok(
    src:find('if(spec.lazy === false) return "startup";', 1, true) ~= nil,
    "plugins: an explicit `lazy = false` is startup whatever else it declares"
  )

  -- The panel is an inverted index over the same data, so it must not
  -- introduce a second extraction. A `n.plugins` read is the only source.
  local lazy_body = src:match("function renderAnalysisLazy%(%)(.-)function renderAnalysisPlugins")
  ok(lazy_body ~= nil, "analysis: renderAnalysisLazy is present and precedes the Plugins panel")
  if lazy_body then
    ok(
      lazy_body:find("n.plugins", 1, true) ~= nil,
      "lazy: reads the same `n.plugins` the Plugins panel does — no second extraction"
    )
    -- Keyed by kind *and* value: an `ft` named `lua` and a `cmd` named `lua`
    -- would otherwise share a row and claim each other's plugins.
    ok(
      lazy_body:find('kind + "\\u0000" + value', 1, true) ~= nil,
      "lazy: a bucket is identified by kind and value, not by value alone"
    )
    -- The two trigger-less states get their own buckets. A panel about load
    -- timing that omitted "at startup" would answer the easy half.
    ok(
      lazy_body:find('bucket("startup", "")', 1, true) ~= nil,
      "lazy: what is paid for unconditionally is on the panel"
    )
    ok(
      lazy_body:find('bucket("ondemand", "")', 1, true) ~= nil,
      "lazy: ...and so is the state that costs nothing until something asks"
    )
  end
end
