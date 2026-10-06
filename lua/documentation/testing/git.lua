---@module 'documentation.testing.git'
--- The few read-only git questions the testing provider asks, behind one
--- runner so a missing git, a non-repository and a failed command all collapse
--- into the same honest answer: `nil`, "I do not know".
---
--- Argument vectors only (no shell), and every revision or path that came from
--- a caller is placed after `--` or validated first, so a hostile `since`
--- (`--output=/etc/x`) can never become an option of git.

local M = {}

---Run `git -C <root> --no-optional-locks <args...>` and return trimmed stdout.
---@param root string
---@param args string[]
---@return string|nil out `nil` on any failure (no git, not a repository, non-zero exit); `""` when the command succeeded with no output.
function M.run(root, args)
  local argv = { "git", "--no-optional-locks", "-C", root }
  vim.list_extend(argv, args)
  local ok, out = require("lib.nvim.cross.run_argv").run_blocking_captured(argv)
  if not ok or type(out) ~= "string" then
    return nil
  end
  return vim.trim(out)
end

---Whether `root` is inside a git work tree.
---@param root string
---@return boolean
function M.in_repo(root)
  return M.run(root, { "rev-parse", "--is-inside-work-tree" }) == "true"
end

---Full sha of HEAD, or nil (no repository, no commit yet).
---@param root string
---@return string|nil
function M.head(root)
  local out = M.run(root, { "rev-parse", "--verify", "-q", "HEAD" })
  if out and out:match("^%x+$") then
    return out
  end
  return nil
end

---The newest commit touching `pathspecs`: sha and committer time.
---@param root string
---@param pathspecs string[] Repo-relative paths; always passed after `--`.
---@return string|nil sha
---@return integer|nil time Unix seconds.
function M.last_commit(root, pathspecs)
  local args = { "log", "-1", "--format=%H%x09%ct", "--" }
  vim.list_extend(args, pathspecs)
  local out = M.run(root, args)
  if not out or out == "" then
    return nil, nil
  end
  local sha, ct = out:match("^(%x+)\t(%d+)$")
  if not sha then
    return nil, nil
  end
  return sha, tonumber(ct)
end

---Whether `ancestor` is an ancestor of (or equal to) `descendant`.
---@param root string
---@param ancestor string
---@param descendant string
---@return boolean
function M.is_ancestor(root, ancestor, descendant)
  if not (ancestor:match("^%x+$") and descendant:match("^%x+$")) then
    return false
  end
  return M.run(root, { "merge-base", "--is-ancestor", ancestor, descendant }) ~= nil
end

---Whether any of `pathspecs` has uncommitted changes (modified or untracked).
---@param root string
---@param pathspecs string[]
---@return boolean
function M.dirty(root, pathspecs)
  local args = { "status", "--porcelain", "--" }
  vim.list_extend(args, pathspecs)
  local out = M.run(root, args)
  return out ~= nil and out ~= ""
end

---A revision as the caller may spell it: refs, shas, `HEAD~3`, `main@{1}`.
---Anything that could be read as an option, contains whitespace or a control
---character, or is absurdly long is refused outright.
---@param rev any
---@return boolean
function M.valid_rev(rev)
  return type(rev) == "string"
    and #rev > 0
    and #rev <= 200
    and rev:sub(1, 1) ~= "-"
    and rev:match("^[%w%._/~^@{}%-]+$") ~= nil
    and not rev:find("..", 1, true)
end

---Repo-relative files changed since `rev` (committed, staged, unstaged) plus
---the untracked ones, deletions excluded (a deleted file has nothing to map).
---@param root string
---@param rev string A revision accepted by `valid_rev`.
---@return string[]|nil files `nil` when git could not answer.
function M.changed_since(root, rev)
  local out = M.run(root, { "diff", "--name-only", "--diff-filter=d", "-z", rev, "--" })
  if out == nil then
    return nil
  end
  local files, seen = {}, {}
  ---@param blob string
  local function take(blob)
    for name in blob:gmatch("[^%z]+") do
      if not seen[name] then
        seen[name] = true
        files[#files + 1] = name
      end
    end
  end
  take(out)
  local untracked = M.run(root, { "ls-files", "--others", "--exclude-standard", "-z" })
  if untracked then
    take(untracked)
  end
  table.sort(files)
  return files
end

return M
