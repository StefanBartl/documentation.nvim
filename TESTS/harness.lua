-- TESTS/harness.lua — tiny assertion helper shared by the spec files.
-- Returned to each spec by TESTS/run.lua.

local H = {}

--- Assert equality; raises a descriptive error on mismatch (caught by the runner).
---@param a any # actual
---@param b any # expected
---@param msg string|nil
function H.eq(a, b, msg)
  if a ~= b then
    error(("FAIL %s: expected %s, got %s"):format(msg or "", vim.inspect(b), vim.inspect(a)), 2)
  end
end

--- Assert a truthy value.
---@param v any
---@param msg string|nil
function H.ok(v, msg)
  if not v then
    error(("FAIL %s: expected truthy, got %s"):format(msg or "", vim.inspect(v)), 2)
  end
end

--- Create a fresh temp file path (not created on disk).
---@param suffix string|nil
---@return string
function H.tmpfile(suffix)
  return vim.fn.tempname() .. (suffix or ".tmp")
end

--- Read all lines of a file into an array (empty array if missing).
---@param path string
---@return string[]
function H.read_lines(path)
  local out = {}
  local f = io.open(path, "r")
  if not f then
    return out
  end
  for line in f:lines() do
    out[#out + 1] = line
  end
  f:close()
  return out
end

--- Make `link` lead to the existing path `target`: a symlink, or on Windows a
--- directory junction (`mklink /J`), which needs no privilege.
---
--- A junction is the only kind of link a Windows account without developer mode
--- can make, and it is the kind a Windows repro uses -- so a directory link is
--- made as one there, with the backslash spelling `mklink` insists on. A *file*
--- link on Windows needs the symlink privilege and may not be possible; the
--- caller gets `false` and decides what that means for its case.
---@param target string Existing path the link should lead to.
---@param link string Path of the link to create; its parent must exist.
---@param is_dir boolean
---@return boolean made
---@return string? how `"symlink"` or `"junction"` when made, the error otherwise.
function H.link(target, link, is_dir)
  if vim.fn.has("win32") == 1 and is_dir then
    local out = vim.fn.system({
      "cmd",
      "/C",
      "mklink",
      "/J",
      (link:gsub("/", "\\")),
      (target:gsub("/", "\\")),
    })
    if vim.v.shell_error == 0 then
      return true, "junction"
    end
    return false, vim.trim(out)
  end
  local made, err = vim.uv.fs_symlink(target, link, { dir = is_dir })
  if made then
    return true, "symlink"
  end
  return false, tostring(err)
end

--- Write `lines` to `path`, creating its directory.
---@param path string
---@param lines string[]
function H.write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
end

--- A file's content, or `nil`.
---@param path string
---@return string?
function H.slurp(path)
  local fd = io.open(path, "rb")
  if not fd then
    return nil
  end
  local content = fd:read("*a")
  fd:close()
  return content
end

return H
