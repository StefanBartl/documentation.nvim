-- TESTS/lang_registry_spec.lua — documentation.core.lang_registry
--
-- Its own file rather than a block inside docmap_spec.lua: that file already
-- sits at Lua's 200-local-per-function ceiling, and this suite touches the
-- process-wide registry singleton other specs' real scans depend on, which
-- makes "ends by restoring exactly the state it found" worth being able to
-- see as a whole file rather than one more scoped `do...end` among many.

return function(H)
  local eq, ok = H.eq, H.ok
  local reg = require("documentation.core.lang_registry")

  -- Real "lua" is already registered by the time any spec runs: scan.lua
  -- requires the registry, which requires core/lang/lua.lua, before any
  -- walk happens. Fixtures use their own extensions so they never shadow it
  -- or each other by accident.
  local fixture_a = {
    name = "fixture_a",
    is_source = function(f)
      return f:match("%.aaa$") ~= nil
    end,
  }
  local fixture_b = {
    name = "fixture_b",
    is_source = function(f)
      return f:match("%.bbb$") ~= nil
    end,
  }

  reg.register("fixture_a", fixture_a)
  reg.register("fixture_b", fixture_b)

  eq(
    reg.for_file("x.aaa"),
    fixture_a,
    "lang_registry: for_file finds the backend that claims an extension"
  )
  eq(
    reg.for_file("x.bbb"),
    fixture_b,
    "lang_registry: ... and a different one for a different extension"
  )
  eq(reg.for_file("x.ccc"), nil, "lang_registry: nil when nothing claims it")
  eq(reg.get("fixture_a"), fixture_a, "lang_registry: get retrieves by name")

  -- Order matters when two backends could both claim the same file — first
  -- registered wins, deterministically, not whichever `pairs()` happens to
  -- visit first, which would make --check non-deterministic across runs.
  local fixture_c = {
    name = "fixture_c",
    is_source = function(f)
      return f:match("%.aaa$") ~= nil
    end,
  }
  reg.register("fixture_c", fixture_c)
  eq(
    reg.for_file("x.aaa"),
    fixture_a,
    "lang_registry: first-registered wins when two backends both claim a file"
  )

  local all = reg.all()
  eq(#all >= 4, true, "lang_registry: all() includes lua plus every fixture registered above")

  -- reset()'s real job: clear fixtures, but the real "lua" backend must come
  -- back too, not just eventually — this is the bug an earlier draft of
  -- reset() had. `require()` on an already-cached module returns the SAME
  -- table without re-running the file, so the `register()` call at a
  -- backend's own bottom (core/lang/lua.lua's last line) never fires a
  -- second time; a `reset()` that only cleared state and hoped
  -- `ensure_loaded` would lazily redo the rest left the registry returning
  -- `nil` for every file, forever, for the rest of the process. Asserted
  -- here as the exact failure this once was, not just as "still works" —
  -- verified empirically before the fix, with a throwaway script, that
  -- `for_file` returned a real table before `reset()` and `nil` after it.
  local lua_before = reg.for_file("x.lua")
  ok(lua_before ~= nil, "lang_registry: real lua backend is registered before reset")
  reg.reset()
  eq(reg.for_file("x.aaa"), nil, "lang_registry: reset() drops fixture registrations")
  local lua_after = reg.for_file("x.lua")
  eq(lua_after, lua_before, "lang_registry: ... and restores lua as the SAME already-cached table")

  -- report(): what a host asks before trusting this build.
  --
  -- Run after reset() on purpose, so the registry holds exactly the four
  -- real backends and nothing this file added -- the shape a host actually
  -- sees, not one with fixtures in it.
  local report = reg.report()
  eq(#report, 4, "lang_registry: report covers every registered backend")

  local by_name = {}
  for _, entry in ipairs(report) do
    by_name[entry.name] = entry
  end

  -- The whole reason `grammar` is a field rather than derived from `name`:
  -- three of the four disagree, and only one agrees by coincidence.
  eq(by_name.lua and by_name.lua.grammar, "lua", "lang_registry: report names lua's grammar")
  eq(
    by_name.js and by_name.js.grammar,
    "javascript",
    "lang_registry: ... and js parses with `javascript`, not `js`"
  )
  eq(by_name.ts and by_name.ts.grammar, "typescript", "lang_registry: ... and ts with `typescript`")
  eq(
    by_name.tsx and by_name.tsx.grammar,
    "tsx",
    "lang_registry: ... and tsx with `tsx`, which happens to match"
  )

  -- Three-valued on purpose. Every backend here declares a grammar, so none
  -- may report `nil` -- that value is reserved for a backend needing no
  -- parser, and a host that saw it here would read "needs nothing" where the
  -- truth is "wanted one and did not get it".
  for _, entry in ipairs(report) do
    ok(
      type(entry.grammar_loaded) == "boolean",
      "lang_registry: " .. entry.name .. " declares a grammar, so loaded is boolean, never nil"
    )
  end

  -- Not cached: a second call re-probes. Asserted as equality of the answer
  -- rather than by counting probes, since the point is only that calling
  -- twice is legal and stable within one process -- the case that must not
  -- be frozen (grammars appearing later) cannot be staged from here.
  eq(reg.report()[1].name, report[1].name, "lang_registry: report is repeatable")

  -- Left clean: no fixture registrations survive this spec, and "lua" is
  -- exactly as it would be if this file had never run — the next spec (or
  -- docmap_browse_spec.lua, in the same process) gets a normal registry,
  -- not one that happens to still work because reset() was called last.
end
