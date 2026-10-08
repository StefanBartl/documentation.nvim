-- TESTS/shim_behavior_spec.lua — the shim answering the same questions as
-- the editor it stands in for.
--
-- **The blind spot this closes.** `shim_contract_spec.lua` compares *names*:
-- every `vim.*` path and every method `core/` calls, against what the shim
-- provides. That catches an absent function — the shape `node:start()` and
-- `vim.pesc` both had when they reached a release. It cannot catch the other
-- shape: a function that exists, returns a plausible value, and returns a
-- *different* one than Neovim would. `vim.fs.dirname("a/b/")` answering
-- `"a"` where the editor says `"a/b"` is not a crash anywhere; it is a
-- scanner that quietly attributes a file to the wrong module.
--
-- **Why this runs here and not only in the standalone gate.** The shim is
-- plain Lua, and `shim_contract_spec.lua` already proved it can be *loaded*
-- inside Neovim (fake `lfs`/`dkjson` through `package.preload`, `_G.vim`
-- unset for the duration so the shim does not hand back the editor's own
-- table). A thing that can be loaded can be called — so the real `vim.*` and
-- the shim can be driven side by side, here, in the `tests` gate that always
-- runs. That matters more than it sounds: the `standalone` gate skips
-- wherever PUC Lua or one of its two rocks is missing, which is most
-- machines, and three real defects have already walked through that gap.
--
-- **What this deliberately does not answer**, because honesty about a gate's
-- reach is the whole lesson of this corner of the tree:
--
--   * `vim.json.decode`. Decoding is still dkjson's, and no fake for it here
--     could be anything but `vim.json` wearing a hat — the comparison would
--     be `vim.json.decode` against itself. Those cases are tagged
--     `needs = "puc"` and answered by `standalone/selfcheck_behavior.lua`
--     under the real rock; `dkjson` is *refused* here rather than faked, so
--     a case that loses its tag fails loudly instead of quietly agreeing
--     with itself. (Encoding is a different story: the shim writes scalars
--     itself now, exactly so that the bytes which end up in the artifact can
--     be compared here rather than behind the skip.)
--   * Real `lfs`. The filesystem cases below run the shim's own logic — the
--     `.`/`..` filtering, the mode mapping — against an `lfs` adapter built
--     on `vim.uv`. That tests the shim, not the rock; the PUC runner closes
--     the remaining seam.
--   * LuaJIT versus PUC 5.4 semantics. Everything here runs under the
--     editor's LuaJIT. The PUC runner replays the same corpus on the other
--     interpreter.
--   * `vim.uv.hrtime` (documented as CPU time, not wall time) and
--     `vim.treesitter` (a deliberately inert stub). Both are *intended*
--     differences, stated in `standalone/vim_shim.lua`'s own header.
--   * The stdpath cases follow `NVIM_APPNAME` and the `XDG_*` variables: the
--     shim implements both (measured against the editor on Windows), so the
--     comparison holds whatever the environment the suite runs in.

return function(H)
  local eq, ok = H.eq, H.ok

  local root = (vim.fn.getcwd():gsub("\\", "/"))
  local cases = dofile(root .. "/TESTS/fixtures/shim_behavior_cases.lua")
  local fixture = root .. "/TESTS/fixtures/shim_fs"

  ok(vim.fn.isdirectory(fixture) == 1, "shim behavior: the committed fs fixture is there")
  ok(#cases.cases > 40, "shim behavior: corpus loaded (" .. #cases.cases .. " cases)")

  -- ---------------------------------------------------------------------
  -- An `lfs` the shim can run on, built on `vim.uv`.
  --
  -- Faithful to the two details the shim's own code depends on: `lfs.dir`
  -- raises on a directory it cannot open (the shim `pcall`s it and degrades
  -- to an empty iterator), and it yields `.` and `..` like the real rock
  -- (the shim filters them — a filter that is only exercised if they are
  -- actually there).
  -- ---------------------------------------------------------------------
  local function lfs_on_uv()
    return {
      -- The shim's Windows branch changes directory around a `dir` listing
      -- (see `windows_census` there) and puts it back. Only ever reached on a
      -- Windows host here; real, so that listing lists the right directory.
      chdir = function(path)
        return pcall(vim.uv.chdir, path) and true or nil
      end,
      attributes = function(path, what)
        -- Loud rather than nil: the shim asks for `"mode"` and nothing else,
        -- and a silently-nil answer to some future third argument would look
        -- exactly like "file not found".
        assert(what == "mode", "lfs adapter: only the `mode` attribute is implemented")
        local st = vim.uv.fs_stat(path)
        return st and st.type or nil
      end,
      -- `lstat`: what the shim's `**` asks so that a link is not entered, and
      -- (`target`) what `uv.fs_readlink` asks to read where a link points.
      symlinkattributes = function(path, what)
        assert(
          what == "mode" or what == "target",
          "lfs adapter: only the `mode` and `target` attributes are implemented"
        )
        if what == "target" then
          return (vim.uv.fs_readlink(path))
        end
        local st = vim.uv.fs_lstat(path)
        if not st then
          return nil
        end
        return st.type == "link" and "link" or st.type
      end,
      dir = function(dir)
        local handle = vim.uv.fs_scandir(dir)
        if not handle then
          error("lfs adapter: cannot open " .. tostring(dir), 0)
        end
        local pending = { ".", ".." }
        return function()
          if #pending > 0 then
            return table.remove(pending, 1)
          end
          return vim.uv.fs_scandir_next(handle)
        end
      end,
      mkdir = function(path)
        local made = vim.uv.fs_mkdir(path, 493)
        return made and true or nil
      end,
      -- The working directory, which `fnamemodify(":p")` joins relative paths
      -- onto. Native separators, like the rock.
      currentdir = function()
        return vim.uv.cwd()
      end,
    }
  end

  -- dkjson, on the other hand, is not adapted but refused: see this file's
  -- header. A json case that forgot its `needs = "puc"` tag must fail loudly
  -- here rather than quietly compare `vim.json` with itself.
  local function dkjson_refusing()
    local function refuse()
      error("shim behavior spec: json is answered by the PUC runner, not here", 0)
    end
    return {
      encode = refuse,
      decode = refuse,
      null = setmetatable({}, {
        __tostring = function()
          return "null"
        end,
      }),
    }
  end

  -- ---------------------------------------------------------------------
  -- Load the shim. Same dance as `shim_contract_spec.lua`, same reasons,
  -- and the same care about putting `_G.vim` back before anything can
  -- longjmp out of here: leaving it nil takes down every later spec in the
  -- run, and the failure looks like anything but this file.
  -- ---------------------------------------------------------------------
  --
  -- `package.loaded` is cleared as well as `package.preload`, and that is not
  -- belt and braces. `shim_contract_spec.lua` runs first and loads the shim
  -- with a *deliberately empty* fake `lfs` — `attributes` answers nil,
  -- `dir` yields nothing — which is all that spec needs, because it only
  -- reads names. `require` caches by module name, so without this the
  -- filesystem half of the corpus quietly ran against that empty fake and
  -- reported the fixture directory as missing: seven cases red, and none of
  -- them about the shim.
  local saved_vim = _G.vim
  local saved_preload = { lfs = package.preload.lfs, dkjson = package.preload.dkjson }
  local saved_loaded = { lfs = package.loaded.lfs, dkjson = package.loaded.dkjson }
  package.loaded.lfs, package.loaded.dkjson = nil, nil
  package.preload.lfs = lfs_on_uv
  package.preload.dkjson = dkjson_refusing
  -- The shim reads this module on Windows (`pcall`-required, so absent here
  -- it would only degrade); on a Windows host it must be there for the
  -- listing cases below to mean anything.
  local saved_win_links = package.preload["standalone.win_links"]
  local saved_win_links_loaded = package.loaded["standalone.win_links"]
  package.loaded["standalone.win_links"] = nil
  package.preload["standalone.win_links"] = function()
    return dofile(root .. "/standalone/win_links.lua")
  end

  local chunk, load_err = loadfile(root .. "/standalone/vim_shim.lua")
  ok(chunk ~= nil, "shim behavior: vim_shim.lua loads as a chunk — " .. tostring(load_err))

  local shim
  if chunk then
    _G.vim = nil
    local ran, result = pcall(chunk)
    _G.vim = saved_vim
    package.preload.lfs = saved_preload.lfs
    package.preload.dkjson = saved_preload.dkjson
    package.loaded.lfs = saved_loaded.lfs
    package.loaded.dkjson = saved_loaded.dkjson
    package.preload["standalone.win_links"] = saved_win_links
    package.loaded["standalone.win_links"] = saved_win_links_loaded
    ok(ran, "shim behavior: vim_shim.lua runs on the uv-backed lfs — " .. tostring(result))
    if ran then
      shim = result
    end
  end
  ok(shim ~= nil and shim ~= saved_vim, "shim behavior: got the shim's table, not Neovim's own")
  if not shim then
    return
  end

  -- ---------------------------------------------------------------------
  -- The comparison itself.
  -- ---------------------------------------------------------------------
  local mismatches, compared, deferred = {}, 0, 0
  -- A case whose path the *editor* does not have is a typo in the corpus, and
  -- it fails in the one direction nobody notices: both sides answer `missing`,
  -- the case agrees with itself, and it reads as coverage. Collected
  -- separately from real mismatches so the message says which it is.
  local unresolved = {}

  for _, case in ipairs(cases.sorted()) do
    if case.needs == "puc" then
      -- Still resolved against the editor, even though the shim side waits
      -- for the PUC runner: a typo must not hide behind the tag either.
      local answer = cases.evaluate(vim, cases.materialize(case), fixture)
      if answer == "missing" or answer:sub(1, 13) == "unknown-kind:" then
        unresolved[#unresolved + 1] = case.id .. " -> " .. answer
      end
      deferred = deferred + 1
    else
      -- Materialised twice on purpose: a mutating implementation must not be
      -- able to hand the other side something it has already written into.
      local want, want_detail = cases.evaluate(vim, cases.materialize(case), fixture)
      local got, got_detail = cases.evaluate(shim, cases.materialize(case), fixture)
      compared = compared + 1
      if want == "missing" or want:sub(1, 13) == "unknown-kind:" then
        unresolved[#unresolved + 1] = case.id .. " -> " .. want
      elseif want ~= got then
        local line = ("%s\n      neovim: %s\n      shim:   %s"):format(case.id, want, got)
        if case.why then
          line = line .. "\n      case:   " .. case.why
        end
        if want_detail or got_detail then
          line = line
            .. ("\n      raised: neovim=%s shim=%s"):format(
              tostring(want_detail):gsub("\n.*", ""),
              tostring(got_detail):gsub("\n.*", "")
            )
        end
        mismatches[#mismatches + 1] = line
      end
    end
  end

  table.sort(unresolved)
  eq(
    table.concat(unresolved, ", "),
    "",
    "shim behavior: every case names a vim.* path this Neovim has and a kind "
      .. "the runner knows — a typo in either agrees with itself and checks "
      .. "nothing"
  )

  ok(compared > 40, "shim behavior: compared " .. compared .. " cases against the real vim.*")
  eq(
    table.concat(mismatches, "\n    "),
    "",
    "shim behavior: every compared case answers what Neovim answers\n    "
  )

  -- The deferred half is stated rather than assumed: a corpus that quietly
  -- stopped tagging its json cases would look like a bigger run, not a
  -- smaller one.
  ok(
    deferred > 0,
    "shim behavior: "
      .. deferred
      .. " cases are left to the PUC runner (real dkjson, and `system`'s exit status)"
  )

  -- ---------------------------------------------------------------------
  -- What the shim refuses, and `vim.env`. None of it can be a corpus case:
  -- either the editor *answers* where the shim declines, or the answer is a
  -- raise whose message is not comparable. Each refusal is a decision (the
  -- shim's rule is "checked, not guessed"), so each is pinned.
  -- ---------------------------------------------------------------------
  local function raises(fn, ...)
    return not pcall(fn, ...)
  end
  ok(
    raises(shim.fn.glob, fixture .. "/sub/", false, true),
    "shim refuses a glob pattern ending in a separator"
  )
  ok(raises(shim.fn.glob, fixture .. "/*", true, true), "shim refuses glob's nosuf")
  ok(raises(shim.fn.fnamemodify, "~/x", ":p"), 'shim refuses ":p" on a "~" path')
  ok(
    raises(shim.fn.fnamemodify, "a", ":h"),
    "shim refuses a fnamemodify modifier it does not implement"
  )
  ok(
    raises(shim.fn.readfile, fixture .. "/a.txt", "x"),
    "shim refuses a readfile flag it does not implement"
  )
  ok(
    raises(shim.fn.system, { "git", "--version" }, "stdin"),
    "shim refuses system's stdin argument"
  )
  -- Under the editor's LuaJIT a failed command and a successful one both close
  -- as a bare `true`, so the shim must raise rather than report a status it
  -- cannot know. (On PUC Lua the `fn.system/*` cases answer for the real thing.)
  ok(
    raises(shim.fn.system, { "git", "--version" }),
    "shim.fn.system refuses to guess an exit status on LuaJIT"
  )

  eq(shim.env.DOCMAP_SHIM_SURELY_UNSET, nil, "shim.env answers nil for an unset variable")
  eq(shim.env.PATH, vim.env.PATH, "shim.env reads the process environment")
  ok(
    raises(function()
      shim.env.DOCMAP_SHIM_ANY = "x"
    end),
    "shim.env refuses assignment instead of silently doing nothing"
  )

  -- ---------------------------------------------------------------------
  -- `uv.fs_mkdir`, which the corpus cannot carry: it writes, so it needs a
  -- path that is different on every run and can therefore never appear in a
  -- shared expectations file. Both halves of the contract `lib.nvim.fs.
  -- mkdirp` relies on: a fresh directory succeeds, an existing one does not.
  -- ---------------------------------------------------------------------
  local scratch = vim.fn.tempname()
  vim.fn.mkdir(scratch, "p")
  local function mkdir_answer(surface, path)
    local made = surface.uv.fs_mkdir(path, 493)
    return cases.canon(made)
  end
  eq(
    mkdir_answer(shim, scratch .. "/fresh-shim"),
    mkdir_answer(vim, scratch .. "/fresh-real"),
    "shim behavior: uv.fs_mkdir on a new directory"
  )
  eq(
    mkdir_answer(shim, scratch),
    mkdir_answer(vim, scratch),
    "shim behavior: uv.fs_mkdir on a directory that already exists"
  )
  vim.fn.delete(scratch, "rf")

  -- ---------------------------------------------------------------------
  -- Every shim function reachable from the corpus. A new entry in the shim
  -- with no case is a function nobody has compared — the same argument
  -- `shim_contract_spec.lua` makes about an unclassified method name, one
  -- level down.
  -- ---------------------------------------------------------------------
  -- `uv.fs_scandir_next` is deliberately absent: the scandir cases name it in
  -- `next_path` and drive it, so it counts as covered rather than excused.
  local COVERED_ELSEWHERE = {
    ["uv.fs_mkdir"] = "compared above, outside the corpus: it writes",
    ["uv.hrtime"] = "documented as CPU time, not wall time — an intended difference",
    ["treesitter"] = "deliberately inert in the parser-less build, top to bottom",
    ["loop"] = "the same table as uv, by assignment — enumerated once, as uv",
    ["NIL"] = "a sentinel, not a function",
  }
  -- The entries above that name a *table*: the walk stops at them instead of
  -- listing what is inside.
  local NOT_A_FUNCTION = { treesitter = true, loop = true, NIL = true }

  local has_case = {}
  for _, case in ipairs(cases.cases) do
    has_case[case.path] = true
    if case.next_path then
      has_case[case.next_path] = true
    end
  end

  local function walk(tbl, prefix, out, depth)
    if depth > 3 then
      return
    end
    for key, value in pairs(tbl) do
      if type(key) == "string" then
        local path = prefix == "" and key or (prefix .. "." .. key)
        if type(value) == "function" then
          out[#out + 1] = path
        elseif type(value) == "table" and not NOT_A_FUNCTION[path] then
          walk(value, path, out, depth + 1)
        end
      end
    end
  end

  local provided = {}
  walk(shim, "", provided, 1)
  local uncompared = {}
  for _, path in ipairs(provided) do
    if not has_case[path] and not COVERED_ELSEWHERE[path] then
      uncompared[#uncompared + 1] = path
    end
  end
  table.sort(uncompared)
  eq(
    table.concat(uncompared, ", "),
    "",
    "shim behavior: every function the shim provides has at least one case, "
      .. "or a stated reason it is compared elsewhere"
  )

  -- And the exception list must not rot in the other direction: an entry for
  -- something the corpus has since grown a case for is a stale claim.
  for path, why in pairs(COVERED_ELSEWHERE) do
    if not NOT_A_FUNCTION[path] then
      ok(
        has_case[path] == nil,
        "shim behavior: "
          .. path
          .. " has a case now — drop it from the exception list ("
          .. why
          .. ")"
      )
    end
  end
  -- ---------------------------------------------------------------------
  -- Properties of `glob` that are bounds, not parity with the editor: a
  -- walk must terminate on a tree that loops, and must not run away on a deep
  -- one. Neither can be a corpus case (the editor's own answer depends on its
  -- depth limit), so they are asserted directly on the shim.
  -- ---------------------------------------------------------------------
  do
    local base = vim.fn.tempname()
    vim.fn.mkdir(base .. "/a/b", "p")
    vim.fn.writefile({ "x" }, base .. "/a/b/hit.txt")
    local made_link = vim.uv.fs_symlink(base, base .. "/a/b/loop", { dir = true })
    local found = shim.fn.glob(base .. "/**/hit.txt", false, true)
    eq(
      #found,
      1,
      "shim glob: `**` finds the file once" .. (made_link and ", through a symlink loop" or "")
    )
    if made_link then
      local listed = shim.fn.glob(base .. "/a/b/*", false, true)
      eq(#listed, 2, "shim glob: a symlinked directory is still listed, only not entered")
    end

    local deep = base .. "/deep"
    local parts = {}
    for i = 1, 70 do
      parts[i] = "d"
    end
    local deep_dir = deep .. "/" .. table.concat(parts, "/")
    vim.fn.mkdir(deep_dir, "p")
    vim.fn.writefile({ "x" }, deep_dir .. "/bottom.txt")
    vim.fn.writefile({ "x" }, deep .. "/d/top.txt")
    local deep_found = shim.fn.glob(deep .. "/**/*.txt", false, true)
    eq(#deep_found, 1, "shim glob: `**` stops at its depth limit (the 70-deep file is not reached)")
    vim.fn.delete(base, "rf")
  end
end
