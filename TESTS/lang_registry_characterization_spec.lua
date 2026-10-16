-- TESTS/lang_registry_characterization_spec.lua — documentation.core.lang_registry
--
-- Pins the behaviour of the registry as seen from outside, so the move of its
-- storage onto `lib.nvim.registry` changes nothing a caller can observe. It
-- was written against the hand-rolled version first (green), then run
-- unchanged against the `lib.nvim.registry`-backed one.
--
-- `lang_registry_spec.lua` covers the everyday contract against the shared
-- singleton. This file covers the edges that depend on module state the
-- singleton has long left behind: "nothing is loaded yet", "registered before
-- the first read", "registered right after a reset". It therefore works on a
-- FRESH copy of the registry (and of every backend module, so each one
-- registers itself again into that copy) and puts the original modules back
-- in `package.loaded` afterwards, so no other spec sees the difference.

return function(H)
  local eq, ok = H.eq, H.ok

  local REG = "documentation.core.lang_registry"

  -- Registration order == order of KNOWN_BACKENDS in the registry.
  local TAILS = {
    "lua",
    "js",
    "ts",
    "tsx",
    "zig",
    "java",
    "c",
    "cpp",
    "asm",
    "python",
    "csharp",
    "go",
    "rust",
    "php",
    "ruby",
    "kotlin",
    "swift",
    "dart",
    "scala",
    "haskell",
    "elixir",
    "erlang",
    "ocaml",
  }

  local function backend_mod(tail)
    return "documentation.core.lang." .. tail
  end

  ---Run `fn(reg)` with a fresh registry module and fresh backend modules, then
  ---restore the originals no matter what.
  local function with_fresh(fn)
    local mods = { REG }
    for _, tail in ipairs(TAILS) do
      mods[#mods + 1] = backend_mod(tail)
    end
    local saved = {}
    for _, m in ipairs(mods) do
      saved[m] = package.loaded[m]
      package.loaded[m] = nil
    end
    local okay, err = pcall(function()
      fn(require(REG))
    end)
    for _, m in ipairs(mods) do
      package.loaded[m] = saved[m]
    end
    if not okay then
      error(err, 0)
    end
  end

  local function names(list)
    local out = {}
    for _, b in ipairs(list) do
      out[#out + 1] = b.name
    end
    return out
  end

  local function fixture(name, ext)
    return {
      name = name,
      extensions = { ext },
      is_source = function(f)
        return f:sub(-#ext - 1) == "." .. ext
      end,
      glossary = { keywords = {} },
    }
  end

  -- 1. Nothing is loaded until the first READ; register alone does not load.
  with_fresh(function(reg)
    reg.register("early", fixture("early", "eee"))
    eq(
      package.loaded[backend_mod("lua")],
      nil,
      "characterization: register() does not load the backends"
    )
    eq(reg.get("early").name, "early", "characterization: get() finds an early registration")
    ok(
      package.loaded[backend_mod("lua")] ~= nil,
      "characterization: the first read loads the backends"
    )
    -- A registration made before the first read stays in front of the known
    -- backends: it was in `order` already when they came.
    local got = names(reg.all(true))
    eq(got[1], "early", "characterization: an early registration keeps the first position")
    eq(got[2], "lua", "characterization: ... and the known backends follow in list order")
    eq(#got, #TAILS + 1, "characterization: ... all of them, none twice")
  end)

  -- 2. Known backends come in the order of the list, each under its own name.
  with_fresh(function(reg)
    local got = names(reg.all())
    eq(#got, #TAILS, "characterization: every known backend is registered")
    for i, tail in ipairs(TAILS) do
      eq(got[i], tail, "characterization: position " .. i .. " is " .. tail)
      eq(
        reg.get(tail),
        require(backend_mod(tail)),
        "characterization: get(" .. tail .. ") is the backend module's own table"
      )
    end
  end)

  -- 3. Registering a name twice replaces the entry in place.
  with_fresh(function(reg)
    local first, second = fixture("dup", "ddd"), fixture("dup", "ddd")
    reg.register("dup", first)
    reg.register("lua2", fixture("lua2", "l2"))
    reg.register("dup", second)
    eq(reg.get("dup"), second, "characterization: the second registration wins")
    local got = names(reg.all(true))
    local count, pos = 0, nil
    for i, n in ipairs(got) do
      if n == "dup" then
        count = count + 1
        pos = i
      end
    end
    eq(count, 1, "characterization: a name registered twice is listed once")
    eq(pos, 1, "characterization: ... at the position of its first registration")
  end)

  -- 4. reset(): fixtures gone, known backends back at once and in list order,
  --    and a registration made right after it comes AFTER them.
  with_fresh(function(reg)
    reg.register("gone", fixture("gone", "ggg"))
    local lua_before = reg.get("lua")
    reg.reset()
    eq(reg.get("gone"), nil, "characterization: reset() drops a fixture")
    eq(reg.get("lua"), lua_before, "characterization: ... and the same lua table is back")
    local got = names(reg.all(true))
    eq(#got, #TAILS, "characterization: reset() leaves exactly the known backends")
    eq(got[1], "lua", "characterization: ... in list order")
  end)

  with_fresh(function(reg)
    reg.get("lua") -- load
    reg.reset()
    reg.register("late", fixture("late", "lll")) -- no read in between
    local got = names(reg.all(true))
    eq(got[1], "lua", "characterization: reset() restores the known backends eagerly ...")
    eq(got[#got], "late", "characterization: ... so a registration right after it comes last")
    eq(#got, #TAILS + 1, "characterization: ... and nothing is duplicated")
  end)

  with_fresh(function(reg)
    -- reset() on a registry that never loaded: eager as well.
    reg.reset()
    eq(#reg.all(true), #TAILS, "characterization: reset() before any read loads the backends")
  end)

  -- 5. The scan-scoped filter.
  with_fresh(function(reg)
    eq(reg.ENABLED, nil, "characterization: no filter by default")
    reg.set_enabled({ "lua" })
    eq(reg.ENABLED.lua, true, "characterization: ENABLED is a set of names")
    ok(reg.for_file("a.lua") ~= nil, "characterization: an enabled backend still claims its file")
    eq(reg.for_file("a.py"), nil, "characterization: a disabled backend claims nothing")
    eq(#reg.all(), 1, "characterization: all() honours the filter")
    eq(#reg.all(true), #TAILS, "characterization: all(true) ignores it")
    eq(#reg.report(), #TAILS, "characterization: report() ignores it: it describes the build")
    local gl = reg.glossaries()
    ok(gl.lua ~= nil, "characterization: glossaries() keeps an enabled backend")
    eq(gl.py, nil, "characterization: ... and drops a disabled one")

    reg.set_enabled(nil)
    eq(reg.ENABLED, nil, "characterization: nil lifts the filter")
    reg.set_enabled({ "lua" })
    reg.set_enabled({})
    eq(reg.ENABLED, nil, "characterization: an empty list lifts it too (all, not none)")
    ok(reg.for_file("a.py") ~= nil, "characterization: ... and the other backends answer again")

    reg.set_enabled({ "golang" })
    eq(reg.ENABLED.golang, true, "characterization: an unknown name is kept")
    eq(reg.for_file("a.lua"), nil, "characterization: ... so nothing is read: not 'everything'")
    reg.set_enabled(nil)
  end)

  -- 6. unknown(): sorted, only the names no backend answers to.
  with_fresh(function(reg)
    local got = reg.unknown({ "zzz", "lua", "golang", "aaa" })
    eq(table.concat(got, ","), "aaa,golang,zzz", "characterization: unknown() is sorted")
    eq(#reg.unknown(nil), 0, "characterization: unknown(nil) is empty")
    eq(#reg.unknown({}), 0, "characterization: unknown({}) is empty")
    -- It is a read: it loads the backends first.
  end)
  with_fresh(function(reg)
    eq(#reg.unknown({ "lua" }), 0, "characterization: a known name is not unknown on a fresh load")
  end)

  -- 7. glossaries(): by extension, the table of one backend shared, not copied.
  with_fresh(function(reg)
    reg.register("g1", {
      name = "g1",
      extensions = { "g1a", "g1b" },
      glossary = { id = 1 },
      is_source = function()
        return false
      end,
    })
    reg.register("g2", {
      name = "g2",
      extensions = { "g2" },
      is_source = function()
        return false
      end,
    })
    reg.register("g3", {
      name = "g3",
      glossary = { id = 3 },
      is_source = function()
        return false
      end,
    })
    local gl = reg.glossaries()
    ok(
      gl.g1a ~= nil and rawequal(gl.g1a, gl.g1b),
      "characterization: one glossary table per backend"
    )
    eq(gl.g2, nil, "characterization: no glossary, no entry")
    eq(gl.g1a.id, 1, "characterization: ... and it is the backend's own")
    ok(
      rawequal(gl.js, gl.ts) and rawequal(gl.ts, gl.tsx),
      "characterization: js, ts and tsx share one table"
    )
    local n = 0
    for _ in pairs(gl) do
      n = n + 1
    end
    ok(n >= 4, "characterization: the known backends contribute")
  end)

  -- 8. for_file: registration order decides; a disabled backend is skipped.
  with_fresh(function(reg)
    local a, b = fixture("fa", "xyz"), fixture("fb", "xyz")
    reg.register("fa", a)
    reg.register("fb", b)
    eq(reg.for_file("q.xyz"), a, "characterization: the first registered claims the file")
    reg.set_enabled({ "fb" })
    eq(reg.for_file("q.xyz"), b, "characterization: a disabled first claimant is skipped")
    reg.set_enabled(nil)
  end)

  -- 9. report(): registration order, three-valued grammar, boolean calls.
  with_fresh(function(reg)
    local report = reg.report()
    eq(#report, #TAILS, "characterization: report lists every backend")
    for i, tail in ipairs(TAILS) do
      eq(report[i].name, tail, "characterization: report keeps registration order at " .. i)
    end
    eq(report[1].grammar, "lua", "characterization: grammar is the backend's field")
    eq(type(report[1].calls), "boolean", "characterization: calls is a real boolean")
    for _, entry in ipairs(report) do
      if entry.grammar then
        eq(type(entry.grammar_loaded), "boolean", "characterization: " .. entry.name .. " probes")
      else
        eq(entry.grammar_loaded, nil, "characterization: " .. entry.name .. " needs no parser")
      end
    end
  end)

  -- 11. The one deliberate difference from the hand-rolled version: a backend
  --     module that fails to load is raised on the read AND tried again on
  --     the next one. The hand-rolled loader marked itself done first, so the
  --     second read served a registry silently missing the failed backend and
  --     every one after it in the list. Not part of the characterised
  --     behaviour above; this is the fix that came with the move.
  --
  --     Nothing here touches `package.loaded` between the reads, and that is
  --     the point: under LuaJIT a module that raised while loading leaves a
  --     sentinel there, and a `require` of it then fails with "loop or
  --     previous error loading module" for good. Clearing it by hand in this
  --     spec once hid exactly that; the registry has to do it itself.
  do
    local real_go = require(backend_mod("go"))
    local saved_preload = package.preload[backend_mod("go")]
    with_fresh(function(reg)
      local fail = true
      package.preload[backend_mod("go")] = function()
        if fail then
          error("simulated load failure")
        end
        return real_go
      end
      local ran, result = pcall(function()
        for read = 1, 2 do
          local okay, err = pcall(reg.get, "lua")
          eq(okay, false, "retry: a backend that fails to load is raised on read " .. read)
          ok(
            tostring(err):find("simulated load failure", 1, true) ~= nil,
            "retry: with its own message on read " .. read .. ", not a stale one: " .. tostring(err)
          )
        end

        fail = false
        local got = reg.get("rust")
        ok(got ~= nil, "retry: the next read loads again, including the backends after the failure")
        eq(#reg.all(true), #TAILS, "retry: ... and the registry is complete, nothing twice")
      end)
      package.preload[backend_mod("go")] = saved_preload
      if not ran then
        error(result, 0)
      end
    end)
  end

  -- 10. The public surface a caller can reach.
  with_fresh(function(reg)
    for _, fn in ipairs({
      "register",
      "for_file",
      "get",
      "all",
      "report",
      "glossaries",
      "set_enabled",
      "unknown",
      "reset",
    }) do
      eq(type(reg[fn]), "function", "characterization: " .. fn .. " is a function")
    end
  end)
end
