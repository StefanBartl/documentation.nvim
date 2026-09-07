-- TESTS/browse_trail_spec.lua — documentation.editor.browse.trail
--
-- `trail.list(root)` deliberately hands back the live array, not a copy (see
-- its own docstring): `browse/init.lua` caches that exact reference on
-- `st.pins` and expects mutations to show up without re-fetching. `M.clear`
-- and `M.hydrate` therefore have to mutate that same table in place --
-- swapping in a fresh one at `pins[root]` would leave a caller's `st.pins`
-- pointing at an orphaned table that never sees the clear/reload again.

return function(H)
  local eq, ok = H.eq, H.ok

  local trail = require("documentation.editor.browse.trail")
  trail.reset()

  local root = "trail-spec-root"

  local function pin(id)
    return { mode = "call", id = id, fn = nil, sha = nil }
  end

  -- ---------------------------------------------------------------------
  -- M.clear must mutate the array `M.list` already handed out, not replace
  -- it -- otherwise a held reference (`st.pins`) goes stale forever.
  -- ---------------------------------------------------------------------
  local held = trail.list(root)
  trail.toggle(root, pin("a"))
  trail.toggle(root, pin("b"))
  eq(#held, 2, "trail: toggle mutates the array M.list already returned")

  local removed = trail.clear(root)
  eq(removed, 2, "trail: clear reports how many pins it dropped")
  eq(#held, 0, "trail: clear empties the SAME table a prior M.list caller is holding")
  eq(#trail.list(root), 0, "trail: a fresh M.list(root) call agrees with the held reference")

  -- ---------------------------------------------------------------------
  -- M.hydrate must do the same: replace the contents, not the table.
  -- ---------------------------------------------------------------------
  local held2 = trail.list(root)
  trail.hydrate(root, { pin("x"), pin("y"), pin("z") })
  eq(#held2, 3, "trail: hydrate populates the SAME table a prior M.list caller is holding")
  eq(held2[1].id, "x", "trail: hydrate's entries land in order")
  ok(held2 == trail.list(root), "trail: hydrate does not swap in a new table for the root")

  trail.reset()
end
