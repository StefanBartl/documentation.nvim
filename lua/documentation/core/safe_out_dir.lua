---@module 'documentation.core.safe_out_dir'
--- Whitelist an `opts.out_dir` before it is pasted onto `opts.root`.
---
--- `out_dir` is repository input -- `config/file.lua`'s `REPO_KEYS.out_dir`
--- lets a cloned tree's own `.docmap.json` set it -- and two call sites paste
--- it straight onto `root` to build a filesystem path: `init.lua`'s
--- `write_artifacts` (SEC-42) and `editor/serve.lua`'s static route, which
--- serves whatever bare filename a request names out of `root/out_dir`. A
--- value like `"../../../../somewhere"` walks either one outside the
--- repository -- the write side used to create and write into it, the serve
--- side would answer requests out of it instead of the generated map. One
--- whitelist, shared, rather than two copies drifting apart.
---
--- Whitelist, not the `..`-substring blacklist `core/deps.lua` uses
--- elsewhere for a different purpose: every path segment is checked against
--- an explicit allowed character set, and `.`/`..` are rejected as whole
--- segments rather than searched for as a substring, which also rejects a
--- segment like `"a.."` a substring search would let through unexamined. A
--- leading `/` or a Windows drive letter (`out_dir` folded to forward
--- slashes first) is rejected outright as an absolute path masquerading as
--- relative.
---@param out_dir string?
---@return string? safe `nil` when `out_dir` is not a safe relative path.
return function(out_dir)
  local s = (out_dir and out_dir ~= "" and out_dir or "docs/map"):gsub("\\", "/")
  if s:sub(1, 1) == "/" or s:match("^%a:") then
    return nil
  end
  local segments = {}
  for segment in s:gmatch("[^/]+") do
    if segment == "." or segment == ".." or not segment:match("^[%w%-%._]+$") then
      return nil
    end
    segments[#segments + 1] = segment
  end
  if #segments == 0 then
    return nil
  end
  return table.concat(segments, "/")
end
