-- TESTS/shim_links_spec.lua — how the standalone shim sees a link.
--
-- Two halves, for the two ways the answer is produced:
--
--   A. **On the host's own file system**, the shim and the editor are asked
--      about the same tree -- a directory, a file, links to each, a link to
--      nothing -- and must agree: the type `vim.fs.dir` and
--      `uv.fs_scandir_next` report, `uv.fs_lstat`, `uv.fs_readlink`. The
--      editor is the oracle, as everywhere in the differential. On Windows
--      the links are junctions and the shim's answer comes from a real
--      `cmd.exe`; on anything else they are symlinks.
--   B. **The shim's Windows branch on any host**, driven on a listing written
--      down as `cmd.exe` prints it, with a file system that records every
--      path it is asked about. This is the half that shows what the shim
--      *does* with a link: that a listing never stats one (opening a link to
--      `\\host\share` is the very thing being prevented), that `dir` is run
--      once per directory, that a command that did not run leaves nothing
--      trusted. It cannot show that a real `cmd.exe` prints what the
--      listing says -- half A on a Windows host does.

-- luacheck: ignore 122
-- (The Windows half swaps `package.config`, `io.popen` and `io.stderr` for the
-- length of one call each and puts them back.)
return function(H)
  local eq, ok = H.eq, H.ok
  local root = (vim.fn.getcwd():gsub("\\", "/"))
  local is_windows = vim.fn.has("win32") == 1

  ---Load `vim_shim.lua` against `lfs_impl`, with the Windows path rules if
  ---asked, and put every global back before anything can raise out of here:
  ---leaving `_G.vim` unset takes down every later spec in the run.
  local function load_shim(lfs_impl, windows)
    local saved_vim, saved_config = _G.vim, package.config
    local saved = {
      preload = {
        lfs = package.preload.lfs,
        dkjson = package.preload.dkjson,
        win_links = package.preload["standalone.win_links"],
      },
      loaded = {
        lfs = package.loaded.lfs,
        dkjson = package.loaded.dkjson,
        win_links = package.loaded["standalone.win_links"],
      },
    }
    package.loaded.lfs, package.loaded.dkjson = nil, nil
    package.loaded["standalone.win_links"] = nil
    package.preload.lfs = function()
      return lfs_impl
    end
    package.preload.dkjson = function()
      return { encode = error, decode = error, null = setmetatable({}, { __tostring = tostring }) }
    end
    package.preload["standalone.win_links"] = function()
      return dofile(root .. "/standalone/win_links.lua")
    end
    if windows then
      package.config = "\\\n;\n?\n!\n-\n"
    end
    _G.vim = nil
    local chunk, load_err = loadfile(root .. "/standalone/vim_shim.lua")
    local ran, shim = false, load_err
    if chunk then
      ran, shim = pcall(chunk)
    end
    _G.vim = saved_vim
    package.config = saved_config
    package.preload.lfs = saved.preload.lfs
    package.preload.dkjson = saved.preload.dkjson
    package.preload["standalone.win_links"] = saved.preload.win_links
    package.loaded.lfs = saved.loaded.lfs
    package.loaded.dkjson = saved.loaded.dkjson
    package.loaded["standalone.win_links"] = saved.loaded.win_links
    ok(ran, "shim links: the shim loads: " .. tostring(shim))
    return shim
  end

  -- ---------------------------------------------------------------------
  -- A. The host's own file system.
  -- ---------------------------------------------------------------------
  local real_lfs = {
    attributes = function(path, what)
      assert(what == "mode", "adapter: only `mode`")
      local st = vim.uv.fs_stat(path)
      return st and st.type or nil
    end,
    symlinkattributes = function(path, what)
      if what == "target" then
        return (vim.uv.fs_readlink(path))
      end
      local st = vim.uv.fs_lstat(path)
      return st and st.type or nil
    end,
    dir = function(dir)
      local handle = vim.uv.fs_scandir(dir)
      if not handle then
        error("adapter: cannot open " .. tostring(dir), 0)
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
      return vim.uv.fs_mkdir(path, 493) and true or nil
    end,
    currentdir = function()
      return vim.uv.cwd()
    end,
    chdir = function(path)
      return pcall(vim.uv.chdir, path) and true or nil
    end,
  }

  do
    local shim = load_shim(real_lfs, false)
    local base = (vim.fn.tempname():gsub("\\", "/")) .. "_shim_links"
    H.write(base .. "/dir/f.txt", { "x" })
    H.write(base .. "/file.txt", { "y" })
    ok(H.link(base .. "/dir", base .. "/link_dir", true), "A: a directory link can be made")
    local file_link = H.link(base .. "/file.txt", base .. "/link_file", false)
    local dangling = H.link(base .. "/not_there", base .. "/dangling", false)

    local function listing(iter)
      local out = {}
      for name, ty in iter do
        out[#out + 1] = tostring(name) .. ":" .. tostring(ty)
      end
      table.sort(out)
      return table.concat(out, ",")
    end

    eq(
      listing(shim.fs.dir(base)),
      listing(vim.fs.dir(base)),
      "A: vim.fs.dir reports a link as a link, as the editor does"
    )
    eq(
      listing(shim.fs.dir(base)):find("link_dir:link", 1, true) ~= nil,
      true,
      "A: ...and a link to a directory is not reported as the directory"
    )

    local function scandir_listing(surface)
      local handle = surface.uv.fs_scandir(base)
      local out = {}
      while true do
        local name, ty = surface.uv.fs_scandir_next(handle)
        if not name then
          break
        end
        out[#out + 1] = name .. ":" .. tostring(ty)
      end
      table.sort(out)
      return table.concat(out, ",")
    end
    eq(scandir_listing(shim), scandir_listing(vim), "A: uv.fs_scandir_next agrees as well")

    local function lstat_type(surface, name)
      local st = surface.uv.fs_lstat(base .. "/" .. name)
      return st and st.type or nil
    end
    local names = { "dir", "file.txt", "link_dir", "nothing_here" }
    if file_link then
      names[#names + 1] = "link_file"
    end
    if dangling then
      names[#names + 1] = "dangling"
    end
    for _, name in ipairs(names) do
      eq(lstat_type(shim, name), lstat_type(vim, name), "A: uv.fs_lstat(" .. name .. ")")
    end
    eq(lstat_type(shim, "link_dir"), "link", "A: ...and a link is a link")

    local function norm(target)
      if target == nil then
        return nil
      end
      target = target:gsub("\\", "/")
      return is_windows and target:lower() or target
    end
    for _, name in ipairs(names) do
      eq(
        norm((shim.uv.fs_readlink(base .. "/" .. name))),
        norm((vim.uv.fs_readlink(base .. "/" .. name))),
        "A: uv.fs_readlink(" .. name .. ")"
      )
    end

    vim.fn.delete(base, "rf")
  end

  -- ---------------------------------------------------------------------
  -- B. The Windows branch, on a listing written down.
  -- ---------------------------------------------------------------------
  local win_links = dofile(root .. "/standalone/win_links.lua")

  local DOCS_LISTING = table.concat({
    " Volume in drive C has no label.",
    "",
    " Directory of C:\\proj\\docs",
    "",
    "10/08/2026  06:24 PM    <JUNCTION>     map [C:\\elsewhere\\map]",
    "10/08/2026  06:24 PM    <SYMLINKD>     rel [..\\real]",
    "10/08/2026  06:24 PM    <SYMLINK>      link.lua [..\\x.lua]",
    "10/08/2026  06:24 PM    <JUNCTION>     share [\\\\host\\share\\x]",
    "10/08/2026  06:24 PM    <DIR>          plain",
    "10/08/2026  06:24 PM                12 f.txt",
    win_links.END_MARK,
  }, "\r\n")

  -- What the fake disk holds. `link = true` marks an entry that a following
  -- `stat` would reach through: the fake records any such call.
  local DISK = {
    ["C:/start"] = { kind = "directory", children = {} },
    ["C:/"] = { kind = "directory", children = { "proj" } },
    ["C:/proj"] = { kind = "directory", children = { "docs", "empty", "broken" } },
    ["C:/proj/docs"] = {
      kind = "directory",
      children = { "map", "rel", "link.lua", "share", "plain", "f.txt" },
    },
    ["C:/proj/docs/map"] = { kind = "directory", link = true },
    ["C:/proj/docs/rel"] = { kind = "directory", link = true },
    ["C:/proj/docs/link.lua"] = { kind = "file", link = true },
    ["C:/proj/docs/share"] = { kind = "directory", link = true },
    ["C:/proj/docs/plain"] = { kind = "directory" },
    ["C:/proj/docs/f.txt"] = { kind = "file" },
    ["C:/proj/empty"] = { kind = "directory", children = { "a" } },
    ["C:/proj/empty/a"] = { kind = "file" },
    ["C:/proj/broken"] = { kind = "directory", children = { "x", "y" } },
    ["C:/proj/broken/x"] = { kind = "file" },
    ["C:/proj/broken/y"] = { kind = "file" },
  }

  local function windows_world()
    local world = { cwd = "C:/start", chdirs = {}, commands = {}, stats = {}, linked_stats = {} }
    world.lfs = {
      currentdir = function()
        return world.cwd
      end,
      chdir = function(path)
        world.chdirs[#world.chdirs + 1] = path
        if not DISK[path] and not DISK[path:gsub("/+$", "")] then
          return nil
        end
        world.cwd = path
        return true
      end,
      attributes = function(path, what)
        assert(what == "mode", "fake lfs: only `mode`")
        world.stats[#world.stats + 1] = path
        local entry = DISK[path:gsub("/+$", "")] or DISK[path]
        if entry and entry.link then
          world.linked_stats[#world.linked_stats + 1] = path
        end
        return entry and entry.kind or nil
      end,
      dir = function(dir)
        local entry = DISK[dir:gsub("/+$", "")] or DISK[dir]
        if not entry or not entry.children then
          error("fake lfs: cannot open " .. dir, 0)
        end
        local pending = { ".", ".." }
        for _, child in ipairs(entry.children) do
          pending[#pending + 1] = child
        end
        return function()
          return table.remove(pending, 1)
        end
      end,
      mkdir = function()
        return nil
      end,
    }
    world.popen = function(command)
      world.commands[#world.commands + 1] = { command = command, cwd = world.cwd }
      local text = ""
      if world.cwd == "C:/proj/docs" then
        text = DOCS_LISTING
      elseif world.cwd == "C:/proj/empty" or world.cwd == "C:/" or world.cwd == "C:/proj" then
        text = "File Not Found\r\n" .. win_links.END_MARK .. "\r\n"
      end
      -- "C:/proj/broken": nothing at all, as if cmd.exe never ran.
      return {
        read = function()
          return text
        end,
        close = function()
          return true
        end,
      }
    end
    return world
  end

  do
    local world = windows_world()
    local shim = load_shim(world.lfs, true)
    local real_popen, real_stderr = io.popen, io.stderr
    local warnings = {}
    io.popen = world.popen
    io.stderr = {
      write = function(self, ...)
        for _, part in ipairs({ ... }) do
          warnings[#warnings + 1] = tostring(part)
        end
        return self
      end,
    }
    local ran, err = pcall(function()
      local function dir_types(dir)
        local out = {}
        for name, ty in shim.fs.dir(dir) do
          out[name] = ty
        end
        return out
      end

      local docs = dir_types("C:/proj/docs")
      eq(docs.map, "link", "B: a junction is listed as a link")
      eq(docs.rel, "link", "B: ...a directory symlink")
      eq(docs["link.lua"], "link", "B: ...a file symlink")
      eq(docs.share, "link", "B: ...a link to a share")
      eq(docs.plain, "directory", "B: a plain directory is a directory")
      eq(docs["f.txt"], "file", "B: a plain file is a file")
      eq(#world.linked_stats, 0, "B: no link was ever statted -- the listing never opened one")

      -- The command, and what was done around it.
      eq(#world.commands, 1, "B: `dir` ran once for the directory")
      local command = world.commands[1].command
      ok(command:find("dir /a:l", 1, true), "B: ...as `dir /a:l`: " .. command)
      ok(command:find('set "DIRCMD="', 1, true), "B: ...with DIRCMD cleared: " .. command)
      ok(command:find(win_links.END_MARK, 1, true), "B: ...and the end mark asked for: " .. command)
      ok(not command:find("proj", 1, true), "B: ...with no path on the command line: " .. command)
      eq(world.commands[1].cwd, "C:/proj/docs", "B: ...run from the directory it lists")
      eq(world.cwd, "C:/start", "B: ...and the working directory put back")

      -- lstat / readlink answer from the same listing: no second command.
      eq(shim.uv.fs_lstat("C:/proj/docs/map").type, "link", "B: lstat of a junction")
      eq(shim.uv.fs_lstat("C:/proj/docs/MAP").type, "link", "B: ...whatever case it is asked in")
      eq(shim.uv.fs_lstat("C:/proj/docs/plain").type, "directory", "B: lstat of a plain directory")
      eq(shim.uv.fs_lstat("C:/proj/docs/f.txt").type, "file", "B: lstat of a plain file")
      local missing, why, code = shim.uv.fs_lstat("C:/proj/docs/nothing")
      eq(missing, nil, "B: lstat of a name that is not there")
      eq(code, "ENOENT", "B: ...is ENOENT: " .. tostring(why))
      local gone, _, gone_code = shim.uv.fs_lstat("C:/proj/nodir/x")
      eq(gone, nil, "B: lstat below a missing directory")
      eq(gone_code, "ENOENT", "B: ...is ENOENT without listing a directory that is not there")
      eq(shim.uv.fs_readlink("C:/proj/docs/share"), "\\\\host\\share\\x", "B: readlink: a share")
      eq(shim.uv.fs_readlink("C:/proj/docs/rel"), "..\\real", "B: readlink: a relative target")
      local not_link, _, not_link_code = shim.uv.fs_readlink("C:/proj/docs/plain")
      eq(not_link, nil, "B: readlink of a plain directory")
      eq(not_link_code, "EINVAL", "B: ...is EINVAL, as for the editor")
      eq(#world.commands, 1, "B: ...all of it from the one listing")
      eq(#world.linked_stats, 0, "B: ...still without statting a link")

      -- The root of a drive: `C:` alone would mean the current directory there.
      eq(shim.uv.fs_lstat("C:/proj").type, "directory", "B: lstat under a drive root")
      eq(world.chdirs[#world.chdirs - 1], "C:/", "B: ...lists `C:/`, not `C:`")

      -- A command that did not run is not a directory with no links.
      local broken = dir_types("C:/proj/broken")
      eq(broken.x, "link", "B: no answer from cmd.exe: every entry is treated as a link")
      eq(broken.y, "link", "B: ...every one")
      ok(
        table
          .concat(warnings)
          :find("cannot tell which entries of C:/proj/broken are links", 1, true),
        "B: ...and it is said, once: " .. table.concat(warnings)
      )
      local no_stat, no_stat_why, no_stat_code = shim.uv.fs_lstat("C:/proj/broken/x")
      eq(no_stat, nil, "B: lstat there has no answer")
      eq(no_stat_code, "EIO", "B: ...it is an error, not 'not a link': " .. tostring(no_stat_why))
      local before = #warnings
      dir_types("C:/proj/broken")
      eq(#warnings, before, "B: ...and the failure is not repeated for every question")
      eq(world.cwd, "C:/start", "B: the working directory is put back after a failure too")
    end)
    io.popen, io.stderr = real_popen, real_stderr
    if not ran then
      error(err, 0)
    end
  end
end
