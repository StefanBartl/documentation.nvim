---@module 'documentation.core.safe_fs'
--- Links under a project root: where they may lead, and what may be written
--- through them.
---
--- ## The problem
---
--- A repository is somebody else's input. It can contain a symlink -- or, on
--- Windows, a junction -- anywhere, and every path this engine builds by
--- pasting names onto `opts.root` follows it without a word:
---
---   * `docs/map` checked out as a link made the generated `index.html`,
---     `module_map.json` and `overview.md` overwrite same-named files wherever
---     it pointed, outside the repository. So did an `out_dir` that a
---     `.docmap.json` in the repository set to a link. `core/safe_out_dir.lua`
---     stops `..` and absolute paths in `out_dir`; it is a check of the
---     *string*, and a link makes a perfectly clean string lead anywhere.
---   * The source walk, and `--check` reading the committed map back, opened
---     whatever a link led to. On Windows a link to `\\host\share\x` makes
---     this machine contact that host -- a stall, and an NTLM negotiation --
---     before anything can look at what came back.
---
--- ## The rule
---
---   * **Writing.** Nothing between the project root and the output directory
---     may be a link, and none of the files written may be one.
---     `check_output` is asked before the first byte is
---     written, so a refusal leaves the tree as it was. A link that stays
---     inside the project is refused as well: what the app shows afterwards is
---     the map, and a map that is not where it was written is a surprise
---     nobody asked for.
---   * **Reading.** A link is followed only when, resolved one step at a time
---     without opening anything on the way, it stays inside the project. One
---     that leaves it, or goes to another machine or a device namespace, is
---     left alone and reported through `M.skipped`.
---
--- The project root itself is not inspected, and neither is anything above
--- it: a person who hands over a path that is reached through a link has
--- decided that. The output directory is a different matter and gets the
--- check even when it was named by hand -- the string is relative to the root,
--- so the links on the way are the repository's.
---
--- ## How a link is recognised
---
--- `vim.uv.fs_lstat`, one path component at a time from the root, each
--- component asked only after everything before it is known not to be a link
--- that leaves the project -- `lstat` does not follow the last component but
--- does follow the earlier ones, so the order is the whole point. The
--- standalone build has no `lstat` on Windows (`lfs` cannot do it there);
--- `standalone/vim_shim.lua` answers the same call from `cmd.exe`, see
--- `standalone/win_links.lua`.
---
--- A link's target is read with `vim.uv.fs_readlink` and judged as a string
--- *before* it is looked at: on Windows a target is a network or device path
--- unless it is a plain drive path (`\\host\share`, `\\?\UNC\...`,
--- `\\?\GLOBALROOT\...`, `\??\...`), and those are never opened. A shim that
--- cannot read a link's target answers that it cannot, and such a link is not
--- followed either.
---
--- What is learned about the disk is remembered until `forget()`, because a
--- walk asks about the same few directories thousands of times. A scan calls
--- it when it starts; `open`, `read` and `check_output` call it themselves.
---
--- ## What this does not cover
---
--- Only the paths that go through this module. Several readers elsewhere in
--- the pipeline still open fixed names under the root directly (the
--- `docs/FEATURES` and checklist folders, README links, the tests directory);
--- they are listed in `docs/SECURITY.md`. A reparse point that is neither a
--- symlink nor a junction is not a link here, and on Windows a junction whose
--- target `lstat` itself cannot represent is outside what this can see.

local M = {}

---Whether the path rules are Windows' (case-insensitive, drive letters,
---backslashes, UNC). Read at call time, so a spec can drive both sets of rules
---from one host.
---@type boolean
M.windows = package.config:sub(1, 1) == "\\"

---The file-system calls, replaceable so a spec can describe a tree that only
---exists in memory -- the Windows rules cannot otherwise be exercised on the
---host the suite usually runs on.
---@class Documentation.SafeFs.Host
---@field lstat fun(path: string): ({ type: string }|nil), string?, string?
---@field readlink fun(path: string): string?, string?, string?
---@field stat fun(path: string): { type: string }|nil
---@field scandir fun(path: string): any
---@field scandir_next fun(handle: any): string?, string?
---@field realpath (fun(path: string): string?)?
---@type Documentation.SafeFs.Host
M.host = {
  lstat = function(path)
    return (vim.uv or vim.loop).fs_lstat(path)
  end,
  readlink = function(path)
    return (vim.uv or vim.loop).fs_readlink(path)
  end,
  stat = function(path)
    return (vim.uv or vim.loop).fs_stat(path)
  end,
  scandir = function(path)
    return (vim.uv or vim.loop).fs_scandir(path)
  end,
  scandir_next = function(handle)
    return (vim.uv or vim.loop).fs_scandir_next(handle)
  end,
  realpath = function(path)
    local uv = vim.uv or vim.loop
    return uv.fs_realpath and uv.fs_realpath(path) or nil
  end,
}

---Links followed on the way to one path before it is called a loop. A real
---tree has a handful at most.
M.MAX_HOPS = 32

---Components handled for one path before giving up. Bounds a pathological
---target (`a/../a/../a/...`) that the hop count alone does not.
M.MAX_STEPS = 4096

---Links the walk did not follow, newest scan only. Each entry is
---`{ path, why, target }`: the repository-relative path of the link, why it
---was left alone (see `describe`) and the target it names when
---that is known. The CLI prints them; nothing else reads them.
---@type { path: string, why: string, target: string? }[]
M.skipped = {}

---@type table<string, { [1]: string?, [2]: string? }>
local lstat_cache = {}
---@type table<string, string|false>
local real_roots = {}

---Forget what has been looked at. Called at the start of each operation that
---goes through this module -- a scan, a write, a check -- so one run never
---answers from another's view of the disk.
function M.forget()
  lstat_cache = {}
  real_roots = {}
end

---Start a scan's list of links that were left alone.
function M.clear_skipped()
  M.skipped = {}
end

---@param path string
---@param why string
---@param target string?
local function note_skip(path, why, target)
  for _, seen in ipairs(M.skipped) do
    if seen.path == path then
      return
    end
  end
  M.skipped[#M.skipped + 1] = { path = path, why = why, target = target }
end

---@param s string
---@return string
local function fold(s)
  return M.windows and s:lower() or s
end

---Forward slashes where a backslash separates directories. Not elsewhere: on
---a POSIX system it is an ordinary character in a file name.
---@param s string
---@return string
local function slashed(s)
  if M.windows then
    return (s:gsub("\\", "/"))
  end
  return s
end

---`root`'s canonical spelling, when the host can say -- an absolute link
---target is written by whoever made the link, and may name the project by
---either spelling of its path.
---@param root string
---@return string?
local function real_root(root)
  local cached = real_roots[root]
  if cached ~= nil then
    return cached or nil
  end
  local ok, resolved = pcall(function()
    return M.host.realpath and M.host.realpath(root) or nil
  end)
  local value = ok and resolved and (slashed(resolved):gsub("/+$", "")) or false
  real_roots[root] = value
  return value or nil
end

---What lies below `root` in `abs`, spelled as it was written (no leading
---slash; empty for `root` itself), or `nil` when `abs` is not under `root`.
---@param root string Forward slashes, no trailing slash.
---@param abs string
---@return string?
local function strip_root(root, abs)
  abs = slashed(abs)
  local bases = { root }
  local alternative = real_root(root)
  if alternative and alternative ~= root then
    bases[2] = alternative
  end
  for _, base in ipairs(bases) do
    local a, b = fold(abs), fold(base)
    if a == b then
      return ""
    end
    if a:sub(1, #b + 1) == b .. "/" then
      return abs:sub(#base + 2)
    end
  end
  return nil
end

---@param path string
---@return string? kind `vim.uv` type of the entry itself, `"link"` for a link.
---@return string? code `"ENOENT"` and the like when there is no kind.
local function lstat_kind(path)
  local hit = lstat_cache[path]
  if hit then
    return hit[1], hit[2]
  end
  local st, err, code = M.host.lstat(path)
  local kind, failure
  if st then
    kind = st.type
  else
    failure = code or (err and err:match("^(%u+):")) or "EIO"
  end
  lstat_cache[path] = { kind, failure }
  return kind, failure
end

---@param code string?
---@return boolean
local function is_absent(code)
  return code == "ENOENT" or code == "ENOTDIR"
end

---Windows drops a trailing dot or space before the file system sees a name,
---and `:` introduces a stream: in either case the name looked at is not the
---name acted on, so a link could hide behind it.
---@param name string
---@return boolean
local function plain_windows_name(name)
  return not (name:find(":", 1, true) or name:match("[%. ]$"))
end

---Sort a link's target into what may be done with it.
---
---  * `"relative"`   relative to the directory holding the link.
---  * `"absolute"`   a local absolute path; the second value is its spelling
---                   with forward slashes.
---  * `"foreign"`    another machine, a device namespace or a volume path
---                   (Windows only): never opened.
---  * `"unsupported"` a form that cannot be resolved without asking the
---                   system, such as `C:x` or `\x` (Windows only).
---
---A pure function of the string and the platform, so it can be tested
---without either.
---@param target string
---@param windows boolean
---@return "relative"|"absolute"|"foreign"|"unsupported" class
---@return string? path
function M.classify_target(target, windows)
  if target == "" then
    return "unsupported"
  end
  if not windows then
    if target:sub(1, 1) == "/" then
      return "absolute", target
    end
    return "relative", target
  end

  local t = target:gsub("\\", "/")
  local head = t:sub(1, 4)
  if head == "//?/" or head == "//./" or head == "/??/" then
    -- The Win32 and NT namespaces. The only form of them that is a plain
    -- local file is the one that wraps a drive path; everything else is a UNC
    -- share (`UNC/host/share`), a device (`GLOBALROOT/Device/...`), a volume
    -- (`Volume{...}`) or a named pipe.
    local rest = t:sub(5)
    if not (rest:match("^%a:/") or rest:match("^%a:$")) then
      return "foreign"
    end
    t = rest
  elseif t:sub(1, 2) == "//" then
    return "foreign"
  end
  if t:match("^%a:/") or t:match("^%a:$") then
    return "absolute", t
  elseif t:match("^%a:") then
    return "unsupported"
  elseif t:sub(1, 1) == "/" then
    return "unsupported"
  end
  return "relative", t
end

---@param rel string
---@return string[] components Last to be handled first.
local function reversed_components(rel)
  local parts = {}
  for part in rel:gmatch("[^/]+") do
    parts[#parts + 1] = part
  end
  local out = {}
  for i = #parts, 1, -1 do
    out[#out + 1] = parts[i]
  end
  return out
end

---Why a path was refused, as a clause: "it leads outside the project".
---@param why string One of the reasons `resolve` returns.
---@param detail string?
---@return string
function M.describe(why, detail)
  if why == "leaves" then
    return "it leads outside the project"
  elseif why == "foreign" then
    return "it leads to another machine or a device namespace"
  elseif why == "loop" then
    return "it goes through too many links, or a link loop"
  elseif why == "unreadable" then
    return "a link on the way cannot be read" .. (detail and (" (" .. detail .. ")") or "")
  elseif why == "unsupported" then
    return "a link on the way has a target that cannot be followed safely"
  elseif why == "name" then
    return "a path component is not a plain name" .. (detail and (" (" .. detail .. ")") or "")
  end
  return why
end

---Resolve `rel` below `root` one component at a time, following the links on
---the way without opening anything the link leads to, and refusing the first
---step that would leave the project.
---
---`..` is applied to the *resolved* path so far, never to the written one:
---`a/link/..` is the directory above whatever `link` points at, which is not
---`a`. A component that does not exist is taken as written -- nothing exists
---below it, so nothing there can be a link.
---@param root string Absolute, forward slashes, no trailing slash. Not inspected.
---@param rel string Path below `root`.
---@return string? path Absolute, with no link left in it.
---@return string? why `"leaves"`, `"foreign"`, `"loop"`, `"unreadable"`, `"unsupported"` or `"name"`.
---@return string? detail The target (or name, or error) the reason is about.
function M.resolve(root, rel)
  rel = slashed(rel)
  local stack = {}
  local pending = reversed_components(rel)
  local hops, steps = 0, 0

  while #pending > 0 do
    steps = steps + 1
    if steps > M.MAX_STEPS then
      return nil, "loop"
    end
    local part = table.remove(pending)
    if part == ".." then
      if #stack == 0 then
        return nil, "leaves", ".."
      end
      stack[#stack] = nil
    elseif part ~= "." then
      if M.windows and not plain_windows_name(part) then
        return nil, "name", part
      end
      stack[#stack + 1] = part
      local abs = root .. "/" .. table.concat(stack, "/")
      local kind, code = lstat_kind(abs)
      if kind == "link" then
        hops = hops + 1
        if hops > M.MAX_HOPS then
          return nil, "loop"
        end
        local target, err = M.host.readlink(abs)
        if not target then
          return nil, "unreadable", err
        end
        local class, named = M.classify_target(target, M.windows)
        if class == "foreign" or class == "unsupported" then
          return nil, class, target
        end
        -- The link component is replaced by what it names.
        stack[#stack] = nil
        local rest = named or ""
        if class == "absolute" then
          local under = strip_root(root, rest)
          if under == nil then
            return nil, "leaves", target
          end
          stack = {}
          rest = under
        end
        for _, p in ipairs(reversed_components(rest)) do
          pending[#pending + 1] = p
        end
      elseif not kind and not is_absent(code) then
        return nil, "unreadable", code
      end
    end
  end

  if #stack == 0 then
    return root
  end
  return root .. "/" .. table.concat(stack, "/")
end

---The first link on the way from `root` to `rel`, followed or not.
---
---This is the writer's question, and a stricter one than `resolve`: a link
---that stays inside the project is still a link. A component that is not
---there ends the walk -- nothing below it exists, so nothing below it is one.
---@param root string
---@param rel string Path below `root`; `..` is refused.
---@return string? link Path below `root` of the first component that is a link.
---@return string? err Set when a component could not be inspected, or is not a plain name.
function M.link_in_chain(root, rel)
  local walked, seen = root, {}
  for part in slashed(rel):gmatch("[^/]+") do
    if part ~= "." then
      if part == ".." or (M.windows and not plain_windows_name(part)) then
        return nil, ("%q is not a plain path component"):format(part)
      end
      walked = walked .. "/" .. part
      seen[#seen + 1] = part
      local kind, code = lstat_kind(walked)
      if kind == "link" then
        return table.concat(seen, "/")
      elseif not kind then
        if is_absent(code) then
          return nil
        end
        return nil, ("%s cannot be inspected (%s)"):format(table.concat(seen, "/"), tostring(code))
      end
    end
  end
  return nil
end

---May the artifacts be written into `out_dir`? Asked before any of them is.
---
---Refuses when a directory on the way is a link, and when one of the files
---about to be written is: opening a link for writing replaces whatever it
---leads to just as surely as writing through its directory does.
---@param root string Absolute, forward slashes, no trailing slash.
---@param out_dir string Relative, already vetted by `core/safe_out_dir.lua`.
---@param names string[] File names that will be written into `out_dir`.
---@return boolean ok
---@return string? err A sentence for the person running the command.
function M.check_output(root, out_dir, names)
  M.forget()
  local link, err = M.link_in_chain(root, out_dir)
  if err then
    return false, err
  end
  if link then
    return false,
      (
        "%s is a link (a symlink or a junction), so the map would be written wherever it leads. "
        .. "Replace it with a plain directory."
      ):format(link)
  end
  for _, name in ipairs(names) do
    local rel = out_dir .. "/" .. name
    local kind, code = lstat_kind(root .. "/" .. rel)
    if kind == "link" then
      return false,
        ("%s is a link, so writing it would overwrite whatever it leads to. Remove it."):format(rel)
    elseif not kind and not is_absent(code) then
      return false, ("%s cannot be inspected (%s)"):format(rel, tostring(code))
    end
  end
  return true
end

---The place `abs` really is, with every link resolved -- or `nil` when it
---cannot be resolved inside the project. Two paths that answer the same are
---the same directory, which is what a walk needs to notice a cycle; compare
---them through `key` where the file system folds case.
---@param root string
---@param abs string Absolute path under `root`.
---@return string?
function M.physical(root, abs)
  local rel = strip_root(root, abs)
  if rel == nil then
    return nil
  end
  return (M.resolve(root, rel))
end

---What to compare two paths by: the path itself, with case folded where the
---file system folds it. A link's target is written by someone else and may
---spell the same directory in another case.
---@param path string
---@return string
function M.key(path)
  return fold(path)
end

---`vim.uv.fs_stat` of `abs`, if it can be reached without leaving the project.
---@param root string
---@param abs string Absolute path under `root`.
---@return { type: string }? stat `nil` when absent or refused.
---@return string? why `"missing"`, `"outside"`, or a reason from `resolve`.
---@return string? detail
function M.stat(root, abs)
  local rel = strip_root(root, abs)
  if rel == nil then
    return nil, "outside"
  end
  local phys, why, detail = M.resolve(root, rel)
  if not phys then
    return nil, why, detail
  end
  local st = M.host.stat(phys)
  if not st then
    return nil, "missing"
  end
  return st
end

---@param root string
---@param abs string
---@return boolean
function M.is_dir(root, abs)
  local st = M.stat(root, abs)
  return st ~= nil and st.type == "directory"
end

---@param root string
---@param abs string
---@return boolean
function M.is_file(root, abs)
  local st = M.stat(root, abs)
  return st ~= nil and st.type == "file"
end

---The entries of `dir`, with a link given the type of what it leads to -- and
---left out, and noted in `M.skipped`, when it cannot be followed
---without leaving the project.
---
---The types come from `lstat` of each entry, not from the listing: a listing
---may leave a type unknown, and the entry would then be looked at with a call
---that follows links.
---@param root string
---@param dir string Absolute path under `root`.
---@return { name: string, type: string }[]
function M.entries(root, dir)
  local rel = strip_root(root, dir)
  if rel == nil then
    return {}
  end
  local phys, why, detail = M.resolve(root, rel)
  if not phys then
    note_skip(rel == "" and "." or rel, why or "leaves", detail)
    return {}
  end
  local handle = M.host.scandir(phys)
  if not handle then
    return {}
  end
  local phys_rel = strip_root(root, phys) --[[@as string]]
  local out = {}
  while true do
    local name = M.host.scandir_next(handle)
    if not name then
      break
    end
    local kind = lstat_kind(phys .. "/" .. name)
    if kind == "link" then
      local child = phys_rel == "" and name or (phys_rel .. "/" .. name)
      local target, cwhy, cdetail = M.resolve(root, child)
      if target then
        local st = M.host.stat(target)
        kind = st and st.type or nil
      else
        note_skip(child, cwhy or "leaves", cdetail)
        kind = nil
      end
    end
    if kind then
      out[#out + 1] = { name = name, type = kind }
    end
  end
  return out
end

---Open `abs` for reading or writing if it can be reached without leaving the
---project. Looks at the disk afresh: a single open is not part of a scan, and
---a long-lived editor must not answer for a link that appeared since.
---@param root string
---@param abs string Absolute path under `root`.
---@param mode string
---@return file*? fd
---@return string? err
function M.open(root, abs, mode)
  M.forget()
  local rel = strip_root(root, abs)
  if rel == nil then
    return nil, "outside the project"
  end
  local phys, why, detail = M.resolve(root, rel)
  if not phys then
    return nil, M.describe(why or "leaves", detail)
  end
  return io.open(phys, mode)
end

---The whole content of `abs`, if it can be reached without leaving the
---project. Looks at the disk afresh, for the reason `open` does.
---@param root string
---@param abs string Absolute path under `root`.
---@return string? content
---@return string? kind `"missing"` when there is no such file, `"refused"` when a link on the way is not followed.
---@return string? message Why, for `"refused"`.
function M.read(root, abs)
  M.forget()
  local rel = strip_root(root, abs)
  if rel == nil then
    return nil, "refused", "outside the project"
  end
  local phys, why, detail = M.resolve(root, rel)
  if not phys then
    return nil, "refused", M.describe(why or "leaves", detail)
  end
  local fd = io.open(phys, "rb")
  if not fd then
    return nil, "missing"
  end
  local content = fd:read("*a")
  fd:close()
  return content
end

return M
