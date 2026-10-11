-- TESTS/detect_source_links_spec.lua — source detection does not open a link
-- that leaves the project.
--
-- `config.build` asks every language backend where its sources live, and it
-- does so before the scan has vetted anything: on every `:DocMap`, on every
-- keystroke of its completion, on the CLI's first line. The backends look at
-- fixed names under the root (`lua`, `src`, `lib`, `Sources`, `cmd`, ...), and
-- those names are the repository's to choose. A link of that name used to be
-- opened first -- on Windows a link to `\\host\share` makes the machine contact
-- that host -- and what lay behind it picked the source root: the names of the
-- directories there reached `opts.source` and the refusal message, and a link
-- called `x.py` counted as a Python file.
--
-- Five parts:
--
--   A. **Real links** (`H.link`: symlinks, junctions on Windows) from every name
--      any backend probes to a tree outside the project that holds a source
--      file of every language. Every call that names a path is recorded; none
--      may go through a link. A twin of the same tree whose links stay inside
--      the project must still be detected, which also shows the tree is one
--      each backend can read.
--   B. **Nested links**, which the first-component checks above do not reach.
--   C. **A view of the disk from an earlier call**: a directory that became a
--      link since the last call is not answered for from memory.
--   D. **The Windows rules on any host**, on an in-memory tree that records
--      what the file system is asked, with links to `\\host\share` and its
--      other spellings. The only half that can show the share is never named.
--   E. **Links back up the tree**, which the probes that look below a name must
--      not enter: a directory of them made the work grow with the cube of their
--      number, on every keystroke of the completion.

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("documentation.config")
  local registry = require("documentation.core.lang_registry")
  local safe_fs = require("documentation.core.safe_fs")
  local is_windows = vim.fn.has("win32") == 1

  -- Every fixed name a backend's `detect_source` puts under the root, first
  -- component only: a link by one of these is all it takes to reach the rest.
  -- `member` is a Cargo workspace member (`<member>/src`), which Rust finds by
  -- listing the root.
  local NAMES = {
    "lua",
    "src",
    "lib",
    "source",
    "app",
    "cmd",
    "internal",
    "pkg",
    "Sources",
    "Source",
    "core",
    "bin",
    "apps",
    "asm",
    "boot",
    "kernel",
    "arch",
    "java",
    "shared",
    "include",
    "member",
  }

  -- One file per language the backends know, and the directory shapes they
  -- look for below a name (`OUTSIDE_PKG_NAME` is what `lua/` would take for
  -- the plugin; `pkg/__init__.py` is a Python package; `src/lib.rs` a member).
  local SOURCE_FILES = {
    "a.py",
    "a.rs",
    "a.go",
    "a.swift",
    "a.hs",
    "a.cs",
    "a.scala",
    "a.ml",
    "a.zig",
    "a.dart",
    "a.kt",
    "a.rb",
    "a.erl",
    "a.s",
    "a.java",
    "a.php",
    "a.ex",
    "a.js",
    "a.ts",
    "a.tsx",
    "a.c",
    "a.cpp",
  }

  ---@param dir string
  local function write_payload(dir)
    for _, file in ipairs(SOURCE_FILES) do
      H.write(dir .. "/" .. file, { "-- " .. file })
    end
    H.write(dir .. "/OUTSIDE_PKG_NAME/init.lua", { "return {}" })
    H.write(dir .. "/pkg/__init__.py", { "" })
    H.write(dir .. "/src/lib.rs", { "// member" })
    H.write(dir .. "/main/java/a.java", { "// nested" })
  end

  -- Backends that can answer at all: every one that has the field.
  local backends = {}
  for _, backend in ipairs(registry.all()) do
    if backend.detect_source then
      backends[#backends + 1] = backend
    end
  end
  ok(#backends >= 20, "the registry offers the language backends: " .. #backends)

  ---Sorted, so that the order the backends are registered in is not asserted.
  ---@param list string[]
  ---@return string
  local function joined(list)
    local copy = vim.list_slice(list, 1, #list)
    table.sort(copy)
    return table.concat(copy, " + ")
  end

  -- What a recorded path may not go through: the names above, and the file
  -- link `go.mod` that Go checks for at the root.
  local LINKED = vim.list_extend(vim.list_slice(NAMES, 1, #NAMES), { "go.mod" })

  ---Which of `names` a recorded path goes through when it lies below `base`.
  ---@param path string
  ---@param base string
  ---@param names string[]
  ---@return string?
  local function through(path, base, names)
    -- Folded on every host: the Windows half runs on a POSIX one, and a name
    -- that differs only in case is the same one there.
    local p, b = (path:gsub("\\", "/")):lower(), base:lower()
    if p:sub(1, #b + 1) ~= b .. "/" then
      return nil
    end
    local first = p:sub(#b + 2):match("^[^/]+")
    for _, name in ipairs(names) do
      if first == name:lower() then
        return name
      end
    end
    return nil
  end

  ---Call `fn` with every function that opens a path by name recorded, and put
  ---them back whatever happens. `safe_fs.host` calls `vim.uv.fs_stat` and
  ---`fs_scandir` when it is asked, so what it passes on is seen here; `lstat`
  ---is not recorded because it does not follow the last component, which is
  ---how a link is recognised without opening it.
  ---@param fn fun()
  ---@return string[] paths
  local function recording(fn)
    local uv = vim.uv
    local saved = {
      stat = uv.fs_stat,
      scandir = uv.fs_scandir,
      dir = vim.fs.dir,
      isdirectory = vim.fn.isdirectory,
    }
    local seen = {}
    uv.fs_stat = function(path, ...)
      seen[#seen + 1] = path
      return saved.stat(path, ...)
    end
    uv.fs_scandir = function(path, ...)
      seen[#seen + 1] = path
      return saved.scandir(path, ...)
    end
    vim.fs.dir = function(path, ...)
      seen[#seen + 1] = path
      return saved.dir(path, ...)
    end
    vim.fn.isdirectory = function(path)
      seen[#seen + 1] = path
      return saved.isdirectory(path)
    end
    local ran, err = pcall(fn)
    uv.fs_stat, uv.fs_scandir = saved.stat, saved.scandir
    vim.fs.dir, vim.fn.isdirectory = saved.dir, saved.isdirectory
    if not ran then
      error(err, 0)
    end
    return seen
  end

  ---@param paths string[]
  ---@param base string
  ---@param label string
  local function nothing_through_a_link(paths, base, label)
    ok(#paths > 0, label .. ": the recorder saw the file system being asked at all")
    for _, path in ipairs(paths) do
      local name = through(path, base, LINKED)
      eq(name, nil, label .. ": " .. path .. " goes through the link `" .. tostring(name) .. "`")
    end
  end

  -- ---------------------------------------------------------------------
  -- A. Real links from every probed name.
  -- ---------------------------------------------------------------------
  local base = (vim.fn.tempname():gsub("\\", "/")) .. "_detect_links"
  local outside = base .. "/outside"
  write_payload(outside .. "/payload")
  H.write(outside .. "/payload/go.mod", { "module x" })

  local leaving = base .. "/leaving"
  H.write(leaving .. "/README.md", { "# a repository whose every probed name is a link" })
  local twin = base .. "/twin"
  H.write(twin .. "/README.md", { "# the same, with links that stay inside" })
  write_payload(twin .. "/payload")

  local leaving_root, twin_root = H.canonical(leaving), H.canonical(twin)
  local twin_target = twin_root .. "/payload"
  -- `source` and `Source` are one name on a file system that folds case (macOS,
  -- Windows): the second link would find the first one in the way.
  local folds = safe_fs.folds_case(leaving_root)
  local linked_lower = {}
  for _, name in ipairs(NAMES) do
    if not (folds and linked_lower[name:lower()]) then
      linked_lower[name:lower()] = true
      ok(H.link(outside .. "/payload", leaving_root .. "/" .. name, true), "a link out: " .. name)
      ok(H.link(twin_target, twin_root .. "/" .. name, true), "a link that stays inside: " .. name)
    end
  end
  local made_go_mod = H.link(outside .. "/payload/go.mod", leaving_root .. "/go.mod", false)
  ok(made_go_mod or is_windows, "a file link could not be made on a platform that should allow it")

  safe_fs.forget()
  local found
  local seen = recording(function()
    found = config.detect_source(leaving_root)
  end)
  nothing_through_a_link(seen, leaving_root, "detect_source")
  eq(joined(found), ".", "detect_source: links that leave give no evidence of any language")
  eq(joined(found):find("OUTSIDE_PKG_NAME", 1, true), nil, "...and no name from behind them")

  -- Backend by backend, so that one that goes back to opening a name directly
  -- is named. Asked directly rather than through `config.detect_source`, which
  -- would let the others cover for it.
  for _, backend in ipairs(backends) do
    safe_fs.forget()
    local answer
    local probed = recording(function()
      answer = backend.detect_source(leaving_root)
    end)
    for _, path in ipairs(probed) do
      local name = through(path, leaving_root, LINKED)
      eq(
        name,
        nil,
        backend.name .. ": " .. path .. " goes through the link `" .. tostring(name) .. "`"
      )
    end
    eq(answer, nil, backend.name .. ": nothing behind a link out of the project is evidence")
  end

  -- `config.build` runs the detection whether or not a source was given.
  local built
  seen = recording(function()
    built = config.build(leaving_root, { source = "docs" })
  end)
  nothing_through_a_link(seen, leaving_root, "build")
  eq(built.source, "docs", "build: an explicit source is kept")

  -- Without one, what is detected is what `opts.source` becomes.
  eq(
    joined(config.build(leaving_root).source),
    ".",
    "build: nothing behind a link picks the source"
  )

  -- The twin: the same names, links that stay inside the project. Each is
  -- followed as it always was, so every backend sees its files.
  safe_fs.forget()
  for _, backend in ipairs(backends) do
    ok(
      backend.detect_source(twin_root) ~= nil,
      backend.name .. ": a link that stays inside the project is followed"
    )
  end
  local inside = config.detect_source(twin_root)
  ok(
    joined(inside) ~= ".",
    "detect_source: ...and so is the project as a whole: " .. joined(inside)
  )

  -- ... and what such a link names is what the answer says, not just "something":
  -- the link `src` is the source root, and a link inside `lua/` is its plugin.
  local single = base .. "/single"
  H.write(single .. "/real/a.py", { "x = 1" })
  H.write(single .. "/impl/README.md", { "# the folder `lua` leads to" })
  H.write(single .. "/impl_thing/init.lua", { "return {}" })
  H.write(single .. "/hidden/crate_a/src/lib.rs", { "// a workspace member" })
  local single_root = H.canonical(single)
  ok(H.link(single_root .. "/real", single_root .. "/src", true), "src -> real")
  ok(H.link(single_root .. "/impl", single_root .. "/lua", true), "lua -> impl")
  ok(
    H.link(single_root .. "/impl_thing", single_root .. "/impl/thing", true),
    "thing -> impl_thing"
  )
  ok(H.link(single_root .. "/hidden/crate_a", single_root .. "/member", true), "member -> crate_a")
  safe_fs.forget()
  eq(
    joined(config.detect_source(single_root)),
    "lua/thing + src",
    "single: links that stay inside the project name the sources"
  )
  eq(
    require("documentation.core.lang.rust").detect_source(single_root),
    ".",
    "single: ...and a workspace member reached through one is a member"
  )

  -- ---------------------------------------------------------------------
  -- B. Links further down than the first component.
  -- ---------------------------------------------------------------------
  local nested = base .. "/nested"
  H.write(nested .. "/src/main/README.md", { "# real directories down to the last one" })
  H.write(nested .. "/lib/README.md", { "# real" })
  H.write(nested .. "/src/pkg/README.md", { "# a package directory, without its marker file" })
  local nested_root = H.canonical(nested)
  ok(H.link(outside .. "/payload", nested_root .. "/src/main/java", true), "java/ is a link out")
  local made_file = H.link(outside .. "/payload/a.py", nested_root .. "/lib/evidence.py", false)
  H.link(outside .. "/payload/pkg/__init__.py", nested_root .. "/src/pkg/__init__.py", false)

  safe_fs.forget()
  seen = recording(function()
    found = config.detect_source(nested_root)
  end)
  eq(joined(found), ".", "nested: a link below a real directory is not followed either")
  for _, path in ipairs(seen) do
    ok(
      not path:find("/src/main/java/", 1, true)
        and not path:find("/lib/evidence.py", 1, true)
        and not path:find("/src/pkg/__init__.py", 1, true),
      "nested: " .. path .. " goes through a link"
    )
  end

  if made_file then
    -- A file link that leaves is not a file of the language: `kind` used to be
    -- `"link"`, which is not a directory, and the name did the rest. Nor is
    -- one that stands for the `__init__.py` that makes a directory a package.
    eq(
      require("documentation.core.lang.python").detect_source(nested_root),
      nil,
      "nested: a file link out of the project is not a Python file"
    )
    local inner = base .. "/inner"
    H.write(inner .. "/real/a.py", { "x = 1" })
    H.write(inner .. "/src/README.md", { "# src" })
    local inner_root = H.canonical(inner)
    ok(H.link(inner_root .. "/real/a.py", inner_root .. "/src/a.py", false), "a file link inside")
    safe_fs.forget()
    eq(
      require("documentation.core.lang.python").detect_source(inner_root),
      "src",
      "nested: ...while one that stays inside is"
    )
  else
    ok(is_windows, "a file link could not be made on a platform that should allow it")
  end

  -- ---------------------------------------------------------------------
  -- C. Each call looks at the disk afresh: an editor outlives the checkout it
  -- first saw, and `:DocMap` completion asks on every keystroke. A directory
  -- that has been replaced by a link since the last call must not be answered
  -- for from what the last call remembered.
  -- ---------------------------------------------------------------------
  local stale = base .. "/stale"
  H.write(stale .. "/src/a.py", { "x = 1" })
  local stale_root = H.canonical(stale)
  eq(joined(config.detect_source(stale_root)), "src", "stale: a real src is detected")
  vim.fn.delete(stale_root .. "/src", "rf")
  ok(H.link(outside .. "/payload", stale_root .. "/src", true), "src is now a link out")
  seen = recording(function()
    found = config.detect_source(stale_root)
  end)
  eq(joined(found), ".", "stale: ...and once it is a link out, the next call sees that")
  for _, path in ipairs(seen) do
    eq(through(path, stale_root, { "src" }), nil, "stale: " .. path .. " goes through the link")
  end

  -- ---------------------------------------------------------------------
  -- D. The Windows rules, on an in-memory tree that records what is asked.
  -- ---------------------------------------------------------------------

  ---A file system that is a table, and a list of every `stat` and `scandir`
  ---it was asked. `lstat` and `readlink` are free: they do not open a link.
  ---@param tree table<string, { type: string, target: string? }>
  ---@return table host
  ---@return { op: string, path: string }[] asked
  local function recording_host(tree)
    local by_key, asked = {}, {}
    for path, entry in pairs(tree) do
      by_key[path:lower()] = { name = path:match("([^/]+)$"), entry = entry }
    end
    local host = {}
    function host.lstat(path)
      local hit = by_key[path:lower()]
      if not hit then
        return nil, "ENOENT: no such file or directory: " .. path, "ENOENT"
      end
      return { type = hit.entry.type }
    end
    function host.readlink(path)
      local hit = by_key[path:lower()]
      if not hit or hit.entry.type ~= "link" then
        return nil, "EINVAL: invalid argument: " .. path, "EINVAL"
      end
      return hit.entry.target
    end
    function host.stat(path)
      asked[#asked + 1] = { op = "stat", path = path }
      local hit = by_key[path:lower()]
      if not hit or hit.entry.type == "link" then
        return nil
      end
      return { type = hit.entry.type }
    end
    function host.scandir(path)
      asked[#asked + 1] = { op = "scandir", path = path }
      local hit = by_key[path:lower()]
      if not hit or hit.entry.type ~= "directory" then
        return nil
      end
      local names, want = {}, path:lower()
      for key, other in pairs(by_key) do
        if key:match("^(.*)/[^/]+$") == want then
          names[#names + 1] = other.name
        end
      end
      table.sort(names)
      return { names = names, i = 0 }
    end
    function host.scandir_next(handle)
      handle.i = handle.i + 1
      return handle.names[handle.i]
    end
    return host, asked
  end

  ---Run `fn` with the module pointed at `host` and Windows' rules, and put both
  ---back whatever happens: a later spec must not find them flipped.
  ---@param host table
  ---@param fn fun()
  local function on_windows(host, fn)
    local saved_host, saved_windows = safe_fs.host, safe_fs.windows
    safe_fs.host, safe_fs.windows = host, true
    safe_fs.forget()
    safe_fs.clear_skipped()
    local ran, err = pcall(fn)
    safe_fs.host, safe_fs.windows = saved_host, saved_windows
    safe_fs.forget()
    safe_fs.clear_skipped()
    if not ran then
      error(err, 0)
    end
  end

  local DIR, FILE = { type = "directory" }, { type = "file" }
  local function link(target)
    return { type = "link", target = target }
  end

  -- Every probed name a link to somewhere that is not this project: a share,
  -- the same share in the other spellings that reach it, another drive.
  local targets = {
    "\\\\attacker\\share\\x",
    "//attacker/share/x",
    "\\\\?\\UNC\\attacker\\share\\x",
    "\\\\?\\GLOBALROOT\\Device\\Mup\\attacker\\share",
    "D:\\elsewhere",
  }
  local tree = {
    ["C:/proj"] = DIR,
    ["C:/proj/README.md"] = FILE,
    ["D:/elsewhere"] = DIR,
    ["D:/elsewhere/a.py"] = FILE,
    ["C:/twin"] = DIR,
    ["C:/twin/real"] = DIR,
    ["C:/twin/real/a.py"] = FILE,
    ["C:/twin/src"] = link("C:\\twin\\real"),
  }
  for i, name in ipairs(NAMES) do
    tree["C:/proj/" .. name] = link(targets[(i - 1) % #targets + 1])
  end

  local host, asked = recording_host(tree)
  on_windows(host, function()
    local answer = config.detect_source("C:/proj")
    eq(joined(answer), ".", "windows: links to a share and its relatives give no evidence")
    for _, backend in ipairs(backends) do
      eq(backend.detect_source("C:/proj"), nil, "windows: " .. backend.name)
    end

    ok(#asked > 0, "windows: the host was asked about the project at all")
    for _, call in ipairs(asked) do
      local path, what = (call.path:gsub("\\", "/")), call.op .. " " .. call.path
      ok(path:sub(1, 2) ~= "//", "windows: " .. what .. " names a share")
      ok(path:lower():sub(1, 3) ~= "d:/", "windows: " .. what .. " is on the other drive")
      eq(through(path, "C:/proj", NAMES), nil, "windows: " .. what .. " goes through a link")
    end

    -- A link that stays inside is followed here as well, spelled with
    -- backslashes and a drive letter.
    eq(
      joined(config.detect_source("C:/twin")),
      "src",
      "windows: a link that stays inside the project still names the source"
    )
  end)

  -- ---------------------------------------------------------------------
  -- E. A directory of links back up the tree. The probes that look below a
  -- name -- `src` down to six levels for ECMA, three for Java, one or two for
  -- the rest -- followed a link like any directory, so each of N links made the
  -- next level N times as big: a hundred of them froze `config.build` for
  -- almost a minute, and the scan beside it (which enters a directory link
  -- once) stayed linear. A link is not entered by a probe; the name it probes
  -- may still be one, which is what part A's twin shows.
  -- ---------------------------------------------------------------------

  ---How many directory listings `fn` asks the host for.
  ---@param fn fun()
  ---@return integer
  local function listings(fn)
    local saved = safe_fs.host.scandir
    local count = 0
    safe_fs.host.scandir = function(path)
      count = count + 1
      return saved(path)
    end
    local ran, err = pcall(fn)
    safe_fs.host.scandir = saved
    if not ran then
      error(err, 0)
    end
    return count
  end

  -- Three real directories (`src`, `src/a`, and the root) for the sixteen
  -- links in `src/a`, each leading back to `src`. A backend needs a handful of
  -- listings for the names it tries; without the guard the deepest probes
  -- needed hundreds, and the ones that look two levels down needed one more per link.
  local LOOPS, MOST = 16, 12
  local loops = base .. "/loops"
  H.write(loops .. "/src/a/README.md", { "# nothing a language claims" })
  local loops_root = H.canonical(loops)
  local made_loops = true
  for i = 1, LOOPS do
    made_loops = H.link(loops_root .. "/src", loops_root .. "/src/a/up" .. i, true) and made_loops
  end
  ok(made_loops, "links back up the tree could not be made on a platform that should allow it")

  for _, backend in ipairs(backends) do
    safe_fs.forget()
    local answer
    local asked_for = listings(function()
      answer = backend.detect_source(loops_root)
    end)
    eq(answer, nil, "loops: " .. backend.name .. " finds no evidence in a tree with none")
    ok(
      asked_for <= MOST,
      ("loops: %s listed directories %d times for a tree of three (at most %d)"):format(
        backend.name,
        asked_for,
        MOST
      )
    )
  end

  safe_fs.forget()
  local total = listings(function()
    found = config.build(loops_root).source
  end)
  eq(joined(found), ".", "loops: build detects nothing, and returns")
  ok(total <= MOST * #backends, "loops: build listed directories " .. total .. " times")

  -- What lies behind a link below the name is no evidence either; the same
  -- files in a real directory are, so the tree is one each of them can read.
  -- (`holds` reaches them through `src/via`, `ctl` through the same name.)
  local function write_flat(dir)
    for _, file in ipairs(SOURCE_FILES) do
      H.write(dir .. "/" .. file, { "-- " .. file })
    end
  end
  local holds = base .. "/holds"
  H.write(holds .. "/src/README.md", { "# a link to the sources, not the sources" })
  -- Two levels down, where no backend looks for evidence by itself.
  write_flat(holds .. "/store/real")
  local holds_root = H.canonical(holds)
  ok(H.link(holds_root .. "/store/real", holds_root .. "/src/via", true), "src/via -> real")

  local ctl = base .. "/ctl"
  H.write(ctl .. "/src/README.md", { "# the same files in a real directory" })
  write_flat(ctl .. "/src/via")
  local ctl_root = H.canonical(ctl)

  -- Every backend that looks below `src` rather than at it.
  local DEEP = {
    js = true,
    ts = true,
    tsx = true,
    java = true,
    csharp = true,
    dart = true,
    elixir = true,
    erlang = true,
    haskell = true,
    kotlin = true,
    ocaml = true,
    php = true,
    ruby = true,
    scala = true,
    swift = true,
  }
  for _, backend in ipairs(backends) do
    safe_fs.forget()
    eq(
      backend.detect_source(holds_root),
      nil,
      "holds: " .. backend.name .. " found sources behind a link below src"
    )
    if DEEP[backend.name] then
      safe_fs.forget()
      eq(
        backend.detect_source(ctl_root),
        "src",
        "holds: " .. backend.name .. " finds the same files in a real directory below src"
      )
    end
  end
end
