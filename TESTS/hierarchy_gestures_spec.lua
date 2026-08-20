-- TESTS/hierarchy_gestures_spec.lua — pin first, act second
--
-- Hovering a box in the Hierarchy lights it and its neighbours and dims the
-- rest; all of it vanished the moment the pointer moved, so the highlighted
-- subgraph could not be read, traced or followed. The first click now holds
-- it, and the second click does what the click used to do.
--
-- **Same limit as `prose_render_spec.lua`, and for the same reason.** These
-- handlers run in the browser: the generated HTML contains the code, not its
-- behaviour, so no Lua spec can dispatch a click. The behaviour was verified
-- by driving the real page — hover focuses, the pointer leaving clears it,
-- the first click pins, the pointer leaving no longer clears it, hovering
-- another box does not steal it, clicking another box re-pins there, Escape
-- releases, and the second click on the same box lands `center=` in the URL.
--
-- What a spec can hold is the structure that keeps those true, and one of
-- them is a real trap: **there must be no `dblclick` handler.** A double
-- click emits two `click` events, which already pin and then act. A third
-- handler on top of them would fire *as well* and act twice — which is what
-- the previous design had, and what this one must not grow back.

return function(H)
  local eq, ok = H.eq, H.ok

  local path = (vim.fn.getcwd():gsub("\\", "/")) .. "/lua/documentation/core/render/html.lua"
  local fd = assert(io.open(path, "rb"), "gestures spec: html.lua must be readable")
  local src = fd:read("*a")
  fd:close()

  -- ---------------------------------------------------------------------
  -- The trap.
  -- ---------------------------------------------------------------------
  eq(
    src:find('hgraph.addEventListener("dblclick"', 1, true),
    nil,
    "gestures: no dblclick handler on the graph — a double click is already two "
      .. "clicks, which pin and then act; a third handler would act twice"
  )

  -- ---------------------------------------------------------------------
  -- The state, and the two things that read it.
  -- ---------------------------------------------------------------------
  ok(
    src:find("var pinnedKey = null;", 1, true) ~= nil,
    "gestures: a pin is a single piece of state"
  )
  ok(src:find("function pin(key){", 1, true) ~= nil, "gestures: ...set in one place")
  ok(src:find("function unpin(){", 1, true) ~= nil, "gestures: ...and released in one place")

  -- A pin that the pointer can overwrite is not a pin. Both hover paths have
  -- to stand down while one is held — this is the property the whole feature
  -- rests on, and it is two early returns that are easy to delete by
  -- accident.
  local guards = 0
  for _ in src:gmatch("if%(pinnedKey !== null%) return;") do
    guards = guards + 1
  end
  eq(
    guards,
    2,
    "gestures: both mouseover and mouseleave stand down while a pin is held — "
      .. "without either, moving the pointer would silently take the view back"
  )

  -- ---------------------------------------------------------------------
  -- The three ways out, all of which were asked for.
  -- ---------------------------------------------------------------------
  ok(
    src:find("if(!box || !box._spec){ unpin(); return; }", 1, true) ~= nil,
    "gestures: a click on empty space releases"
  )
  ok(
    src:find('ev.key === "Escape" && pinnedKey !== null', 1, true) ~= nil,
    "gestures: Escape releases — the meaning it already carries for this page's popups"
  )
  ok(
    src:find("if(pinnedKey === key){ actOn(box); return; }", 1, true) ~= nil,
    "gestures: a second click on the *same* box acts, which is what makes the "
      .. "first one free to pin"
  )

  -- ---------------------------------------------------------------------
  -- The pill still decides what the second click does, not whether the
  -- first one pins. Its meaning is unchanged, and that is worth pinning
  -- down: it would be an easy mistake to make it switch the pinning off.
  -- ---------------------------------------------------------------------
  ok(
    src:find("function actOn(box){", 1, true) ~= nil,
    "gestures: the action is its own function, reached only by the second click"
  )
  ok(
    src:match("function actOn%(box%)%{%s*\n%s*if%(classicClicks%)") ~= nil,
    "gestures: classicClicks is read inside actOn — it chooses the action, "
      .. "it does not decide whether a click pins"
  )

  -- And the pinned box has to look different from a hovered one, or a reader
  -- cannot tell whether moving the mouse will cost them the view.
  ok(src:find(".hnode.pinned{", 1, true) ~= nil, "gestures: a pinned box is visibly pinned")
end
