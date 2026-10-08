-- TESTS/safe_fs_spec.lua — `documentation.core.safe_fs`: where a link may
-- lead, decided without opening what it leads to.
--
-- Three layers, because the rules live in three places:
--
--   1. `classify_target` is a function of a string and a platform. The
--      Windows half of it (UNC, `\\?\GLOBALROOT`, `\??\`, device and volume
--      paths) is the half nobody can reach with a real link on the host this
--      suite normally runs on, so it is driven directly.
--   2. `resolve` / `link_in_chain` / `entries` against an **in-memory tree**
--      standing in for the file system, with the Windows rules switched on:
--      drive letters, case-insensitive names, backslash targets, names that
--      Win32 rewrites (`map.`). A fake host is the only way to run those
--      rules here at all; it is declared as such and kept small.
--   3. The same functions on the **real file system**, with real links:
--      symlinks, or junctions on Windows (`H.link`). This is the layer that
--      shows the in-memory one describes what the OS really does.
--
-- A failure in (3) with (2) green means the fake is wrong; the reverse means
-- the Windows rules are.

return function(H)
  local eq, ok = H.eq, H.ok
  local safe_fs = require("documentation.core.safe_fs")

  ---Run `fn` with the module pointed at `host` and the platform rules of
  ---`windows`, and put both back whatever happens: this suite runs in one
  ---editor, and a spec that leaves `safe_fs.windows` flipped breaks every
  ---later one in a way that points at neither.
  local function with_host(host, windows, fn)
    local saved_host, saved_windows = safe_fs.host, safe_fs.windows
    safe_fs.host, safe_fs.windows = host, windows
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

  -- ---------------------------------------------------------------------
  -- 1. Classifying a link target.
  -- ---------------------------------------------------------------------
  local function class_of(target, windows)
    local class, path = safe_fs.classify_target(target, windows)
    return class .. (path and (":" .. path) or "")
  end

  for target, want in pairs({
    -- another machine, however it is spelled
    ["\\\\host\\share\\x"] = "foreign",
    ["//host/share/x"] = "foreign",
    ["\\\\?\\UNC\\host\\share\\x"] = "foreign",
    ["\\??\\UNC\\host\\share\\x"] = "foreign",
    -- the device namespace, which reaches the same shares by another door
    ["\\\\?\\GLOBALROOT\\Device\\Mup\\host\\share"] = "foreign",
    ["\\??\\GLOBALROOT\\Device\\Mup\\host\\share"] = "foreign",
    ["\\\\.\\pipe\\name"] = "foreign",
    ["\\\\?\\Volume{01234567-89ab-cdef-0123-456789abcdef}\\x"] = "foreign",
    ["\\??\\Volume{01234567-89ab-cdef-0123-456789abcdef}\\"] = "foreign",
    -- a plain drive path, plain or in the verbatim forms that wrap one
    ["C:\\proj\\x"] = "absolute:C:/proj/x",
    ["C:/proj/x"] = "absolute:C:/proj/x",
    ["\\\\?\\C:\\proj\\x"] = "absolute:C:/proj/x",
    ["\\??\\C:\\proj\\x"] = "absolute:C:/proj/x",
    -- forms that mean something only relative to state this cannot see
    ["C:x"] = "unsupported",
    ["\\x"] = "unsupported",
    [""] = "unsupported",
    -- relative
    ["..\\real"] = "relative:../real",
    ["real\\sub"] = "relative:real/sub",
  }) do
    eq(class_of(target, true), want, "classify (windows): " .. target)
  end

  for target, want in pairs({
    ["/etc/passwd"] = "absolute:/etc/passwd",
    ["../real"] = "relative:../real",
    ["real"] = "relative:real",
    -- On a POSIX system a backslash is part of a name, not a separator, and
    -- `\\host\share` is one odd relative name rather than a share.
    ["\\\\host\\share"] = "relative:\\\\host\\share",
    [""] = "unsupported",
  }) do
    eq(class_of(target, false), want, "classify (posix): " .. target)
  end

  for _, why in ipairs({ "leaves", "foreign", "loop", "unreadable", "unsupported", "name" }) do
    ok(
      safe_fs.describe(why, "x") ~= why,
      "describe: `" .. why .. "` has a sentence of its own, not the bare code"
    )
  end

  -- ---------------------------------------------------------------------
  -- 2. The Windows rules, on an in-memory tree.
  -- ---------------------------------------------------------------------

  ---A file system that is a table. `entries` maps a path to `{ type, target }`;
  ---a link carries the `target` text exactly as the OS would hand it back.
  ---Lookups fold case when `windows`, as NTFS does.
  local function fake_host(entries, windows)
    local function key(p)
      return windows and p:lower() or p
    end
    local by_key = {}
    for path, entry in pairs(entries) do
      by_key[key(path)] = { name = path:match("([^/]+)$"), path = path, entry = entry }
    end
    local host = {}
    function host.lstat(path)
      local hit = by_key[key(path)]
      if not hit then
        return nil, "ENOENT: no such file or directory: " .. path, "ENOENT"
      end
      return { type = hit.entry.type }
    end
    function host.readlink(path)
      local hit = by_key[key(path)]
      if not hit or hit.entry.type ~= "link" then
        return nil, "EINVAL: invalid argument: " .. path, "EINVAL"
      end
      return hit.entry.target
    end
    function host.stat(path)
      -- Only ever asked about a path that has been resolved, so it holds no
      -- link: answering for a link here would be answering for the file
      -- system the module is built not to ask.
      local hit = by_key[key(path)]
      if not hit or hit.entry.type == "link" then
        return nil
      end
      return { type = hit.entry.type }
    end
    function host.scandir(path)
      local want = key(path)
      local names = {}
      for k, hit in pairs(by_key) do
        if k:match("^(.*)/[^/]+$") == want then
          names[#names + 1] = hit.name
        end
      end
      table.sort(names)
      return { names = names, i = 0 }
    end
    function host.scandir_next(handle)
      handle.i = handle.i + 1
      return handle.names[handle.i]
    end
    host.realpath = nil
    return host
  end

  local DIR, FILE = { type = "directory" }, { type = "file" }
  local function link(target)
    return { type = "link", target = target }
  end

  local win = fake_host({
    ["C:/proj"] = DIR,
    ["C:/proj/docs"] = DIR,
    ["C:/proj/docs/map"] = link("D:\\elsewhere\\map"),
    ["C:/proj/docs/net"] = link("\\\\host\\share\\x"),
    ["C:/proj/docs/dev"] = link("\\\\?\\GLOBALROOT\\Device\\Mup\\host\\share"),
    ["C:/proj/docs/nt"] = link("\\??\\UNC\\host\\share"),
    ["C:/proj/docs/ok"] = link("C:\\proj\\real"),
    ["C:/proj/docs/shouting"] = link("c:\\PROJ\\real"),
    ["C:/proj/docs/rel"] = link("..\\real"),
    ["C:/proj/docs/up"] = link("..\\..\\other"),
    ["C:/proj/docs/drive"] = link("D:x"),
    ["C:/proj/docs/self"] = link("self"),
    ["C:/proj/docs/plain"] = DIR,
    ["C:/proj/docs/plain/f.lua"] = FILE,
    ["C:/proj/real"] = DIR,
    ["C:/proj/real/file.lua"] = FILE,
  }, true)

  with_host(win, true, function()
    local root = "C:/proj"

    local function refused(rel, want_why, label)
      local path, why = safe_fs.resolve(root, rel)
      eq(path, nil, label .. ": nothing is returned to open")
      eq(why, want_why, label .. ": reason")
    end

    refused("docs/map", "leaves", "a link to another drive")
    refused("docs/map/anything", "leaves", "...and nothing below it")
    refused("docs/net", "foreign", "a UNC share")
    refused("docs/dev", "foreign", "the GLOBALROOT door to a share")
    refused("docs/nt", "foreign", "the NT spelling of a UNC share")
    refused("docs/up", "leaves", "a relative target that climbs out of the project")
    refused("docs/drive", "unsupported", "a drive-relative target")
    refused("docs/self", "loop", "a link that names itself")
    refused("docs/map.", "name", "a name Win32 would rewrite (trailing dot)")
    refused("docs/a:b", "name", "a stream spelling")

    eq(
      safe_fs.resolve(root, "docs/ok/file.lua"),
      "C:/proj/real/file.lua",
      "an absolute link that stays inside is followed"
    )
    eq(
      safe_fs.resolve(root, "docs/shouting/file.lua"),
      "C:/proj/real/file.lua",
      "...whatever case the target spells the project in"
    )
    eq(
      safe_fs.resolve(root, "DOCS/OK/file.lua"),
      "C:/proj/real/file.lua",
      "...and whatever case the path does"
    )
    eq(
      safe_fs.resolve(root, "docs/rel/file.lua"),
      "C:/proj/real/file.lua",
      "a relative link that stays inside is followed"
    )
    eq(
      safe_fs.resolve(root, "docs\\plain\\f.lua"),
      "C:/proj/docs/plain/f.lua",
      "backslashes are separators on this platform"
    )
    eq(
      safe_fs.resolve(root, "docs/missing/deeper"),
      "C:/proj/docs/missing/deeper",
      "a name that is not there is taken as written, not refused"
    )

    -- The writer's question is stricter: a link that stays inside is a link.
    eq(safe_fs.link_in_chain(root, "docs/ok"), "docs/ok", "writer: an in-project link still counts")
    eq(safe_fs.link_in_chain(root, "docs/ok/x"), "docs/ok", "writer: ...whatever lies below it")
    eq(safe_fs.link_in_chain(root, "docs/map"), "docs/map", "writer: a link out of the project")
    eq(safe_fs.link_in_chain(root, "DOCS/Map"), "DOCS/Map", "writer: ...spelled in other case")
    eq(safe_fs.link_in_chain(root, "docs/plain"), nil, "writer: a plain directory is fine")
    eq(safe_fs.link_in_chain(root, "docs/new/dir"), nil, "writer: a path not there yet is fine")
    local _, bad = safe_fs.link_in_chain(root, "docs/map.")
    ok(bad ~= nil, "writer: a name Win32 would rewrite is refused, not looked up")

    local allowed, why = safe_fs.check_output(root, "docs/map", { "index.html" })
    eq(allowed, false, "check_output: refuses a linked output directory")
    ok(why:find("docs/map", 1, true), "check_output: ...and names it: " .. tostring(why))
    eq(safe_fs.check_output(root, "docs/plain", { "index.html" }), true, "check_output: plain ok")

    -- The listing: what a walk is handed.
    local listed = {}
    for _, e in ipairs(safe_fs.entries(root, "C:/proj/docs")) do
      listed[e.name] = e.type
    end
    eq(listed.ok, "directory", "entries: an in-project link is the thing it leads to")
    eq(listed.rel, "directory", "entries: ...relative or absolute")
    eq(listed.plain, "directory", "entries: a plain directory")
    eq(listed.map, nil, "entries: a link to another drive is left out")
    eq(listed.net, nil, "entries: ...and one to a share")
    eq(listed.dev, nil, "entries: ...and one through the device namespace")
    local skipped = {}
    for _, s in ipairs(safe_fs.skipped) do
      skipped[s.path] = s.why
    end
    eq(skipped["docs/map"], "leaves", "skipped: noted with its reason")
    eq(skipped["docs/net"], "foreign", "skipped: a share is foreign, not merely outside")
    eq(skipped["docs/dev"], "foreign", "skipped: so is the device spelling")
  end)

  -- A POSIX tree through the same machinery: the one difference the rules
  -- make is that a backslash is a character and case is significant.
  local posix = fake_host({
    ["/p"] = DIR,
    ["/p/real"] = DIR,
    ["/p/real/f"] = FILE,
    ["/p/ln"] = link("/p/real"),
    ["/p/Ln"] = link("/etc"),
  }, false)
  with_host(posix, false, function()
    eq(safe_fs.resolve("/p", "ln/f"), "/p/real/f", "posix: an absolute link inside is followed")
    local _, why = safe_fs.resolve("/p", "Ln")
    eq(why, "leaves", "posix: names are case-sensitive, so `Ln` is the other link")
    eq(safe_fs.link_in_chain("/p", "LN"), nil, "posix: `LN` is not `ln`; it is simply not there")
  end)

  -- ---------------------------------------------------------------------
  -- 3. The real file system.
  -- ---------------------------------------------------------------------
  local is_windows = vim.fn.has("win32") == 1
  local base = (vim.fn.tempname():gsub("\\", "/")) .. "_safe_fs"
  local root = base .. "/root"
  local outside = base .. "/outside"
  H.write(root .. "/real/f.lua", { "return 1" })
  H.write(root .. "/real/sub/g.lua", { "return 2" })
  vim.fn.mkdir(root .. "/a/b", "p")
  H.write(outside .. "/x/secret.txt", { "SECRET" })

  local made_in, how = H.link(root .. "/real", root .. "/a/in", true)
  ok(made_in, "real: a directory link inside the project can be made here: " .. tostring(how))
  ok(H.link(outside .. "/x", root .. "/a/out", true), "real: ...and one that leaves it")

  safe_fs.forget()
  eq(
    safe_fs.resolve(root, "a/in/f.lua"),
    root .. "/real/f.lua",
    "real: a link that stays inside the project is followed"
  )
  local path, why, detail = safe_fs.resolve(root, "a/out/secret.txt")
  eq(path, nil, "real: a link that leaves the project is not followed")
  eq(why, "leaves", "real: ...for that reason")
  ok(detail ~= nil, "real: ...and the target it names is reported")
  eq(safe_fs.resolve(root, "a/b"), root .. "/a/b", "real: a plain directory resolves to itself")

  eq(safe_fs.link_in_chain(root, "a/in/f.lua"), "a/in", "real writer: an inside link counts")
  eq(safe_fs.link_in_chain(root, "a/out"), "a/out", "real writer: so does one that leaves")
  eq(safe_fs.link_in_chain(root, "a/b"), nil, "real writer: a plain directory is fine")
  eq(safe_fs.link_in_chain(root, "a/not/there"), nil, "real writer: ...and so is nothing")

  eq(safe_fs.is_dir(root, root .. "/a/in"), true, "real: a followed link is a directory")
  eq(safe_fs.is_dir(root, root .. "/a/out"), false, "real: a refused one is not")
  eq(safe_fs.is_file(root, root .. "/a/in/f.lua"), true, "real: a file through a followed link")
  eq(
    safe_fs.is_file(root, root .. "/a/out/secret.txt"),
    false,
    "real: ...not through a refused one"
  )

  local content, kind, msg = safe_fs.read(root, root .. "/a/out/secret.txt")
  eq(content, nil, "real read: nothing comes back through a link that leaves")
  eq(kind, "refused", "real read: ...and it says refused, not missing")
  ok(msg:find("outside the project", 1, true), "real read: ...with the reason: " .. tostring(msg))
  eq(safe_fs.read(root, root .. "/a/in/f.lua"), "return 1\n", "real read: inside link read")
  local _, missing = safe_fs.read(root, root .. "/a/b/nothing.lua")
  eq(missing, "missing", "real read: an absent file is missing, not refused")
  local _, elsewhere = safe_fs.read(root, outside .. "/x/secret.txt")
  eq(elsewhere, "refused", "real read: a path outside the root is not read at all")

  safe_fs.clear_skipped()
  local names = {}
  for _, e in ipairs(safe_fs.entries(root, root .. "/a")) do
    names[e.name] = e.type
  end
  eq(names["in"], "directory", "real entries: the inside link is listed as a directory")
  eq(names.b, "directory", "real entries: a plain directory is listed")
  eq(names.out, nil, "real entries: the link that leaves is not listed")
  eq(#safe_fs.skipped, 1, "real entries: ...and is noted exactly once")
  eq(safe_fs.skipped[1].path, "a/out", "real entries: ...by its path in the project")
  eq(safe_fs.skipped[1].why, "leaves", "real entries: ...with its reason")

  eq(
    safe_fs.physical(root, root .. "/a/in"),
    root .. "/real",
    "real physical: two names of one directory share an answer"
  )

  local allowed, refusal = safe_fs.check_output(root, "a/out", { "index.html" })
  eq(allowed, false, "real check_output: a linked output directory is refused")
  ok(refusal:find("a/out", 1, true), "real check_output: ...naming it: " .. tostring(refusal))
  eq(safe_fs.check_output(root, "a/b", { "index.html" }), true, "real check_output: plain ok")

  -- A file that is a link, in an otherwise plain directory: writing it would
  -- overwrite whatever it leads to.
  local made_file = H.link(outside .. "/x/secret.txt", root .. "/a/b/index.html", false)
  if made_file then
    local file_ok, file_why = safe_fs.check_output(root, "a/b", { "index.html", "overview.md" })
    eq(file_ok, false, "real check_output: a linked artifact file is refused")
    ok(file_why:find("a/b/index.html", 1, true), "real check_output: ...naming it")
    eq(H.slurp(outside .. "/x/secret.txt"), "SECRET\n", "real check_output: ...and writes nothing")
  else
    -- A Windows account without the symlink privilege. The directory cases
    -- above are the ones that matter there; this one needs a file link.
    ok(is_windows, "real: a file link could not be made on a platform that should allow it")
  end

  if not is_windows then
    -- Relative targets are a symlink thing; a junction is always absolute.
    ok(H.link("../real", root .. "/a/rel", true), "real: a relative link can be made")
    ok(
      H.link("../../outside/x", root .. "/a/esc", true),
      "real: ...and a relative one that climbs out"
    )
    ok(H.link("../real/sub", root .. "/a/subs", true), "real: ...and one into a subdirectory")
    safe_fs.forget()
    eq(safe_fs.resolve(root, "a/rel/f.lua"), root .. "/real/f.lua", "real: relative link inside")
    local _, esc_why = safe_fs.resolve(root, "a/esc/secret.txt")
    eq(esc_why, "leaves", "real: a relative link that climbs out of the project")
    -- `..` applies to where the link *leads*, never to where it sits.
    eq(
      safe_fs.resolve(root, "a/subs/.."),
      root .. "/real",
      "real: `a/subs/..` is the parent of what `subs` leads to, not `a`"
    )
    local _, up_why = safe_fs.resolve(root, "..")
    eq(up_why, "leaves", "real: `..` out of the root itself")

    -- Loops end.
    vim.uv.fs_symlink("self", root .. "/a/self")
    vim.uv.fs_symlink("two", root .. "/a/one")
    vim.uv.fs_symlink("one", root .. "/a/two")
    local _, loop1 = safe_fs.resolve(root, "a/self")
    local _, loop2 = safe_fs.resolve(root, "a/one/x")
    eq(loop1, "loop", "real: a link to itself is a loop, not a hang")
    eq(loop2, "loop", "real: so are two links at each other")

    -- A link nothing is at the end of is not an error and not a thing.
    vim.uv.fs_symlink(root .. "/gone", root .. "/a/dangling")
    safe_fs.forget()
    safe_fs.clear_skipped()
    local listed = {}
    for _, e in ipairs(safe_fs.entries(root, root .. "/a")) do
      listed[e.name] = e.type
    end
    eq(listed.dangling, nil, "real entries: a dangling link inside is not listed")
    for _, s in ipairs(safe_fs.skipped) do
      ok(s.path ~= "a/dangling", "real entries: ...and is not reported as one that leaves")
    end

    -- The project reached through another spelling of its path: an absolute
    -- link written with the canonical spelling still counts as inside.
    local canonical = vim.uv.fs_realpath(root)
    vim.uv.fs_symlink(root, base .. "/alias")
    vim.uv.fs_symlink(canonical .. "/real", root .. "/a/canon")
    safe_fs.forget()
    eq(
      safe_fs.resolve(base .. "/alias", "a/canon/f.lua"),
      base .. "/alias/real/f.lua",
      "real: a target spelled with the canonical path is inside a project named by an alias"
    )
  end

  vim.fn.delete(base, "rf")
end
