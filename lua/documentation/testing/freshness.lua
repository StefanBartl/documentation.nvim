---@module 'documentation.testing.freshness'
--- How old is the module map compared to the code it describes.
---
--- `module_map.json` is byte-deterministic on purpose (`--check` compares it
--- byte for byte), so it cannot carry a timestamp or a commit of its own: that
--- would invalidate it on every regeneration. The freshness of a committed map
--- is therefore read from git, not from the file:
---
---   * `commit`        the newest commit touching the map file,
---   * `generated_at`  that commit's time (the file's mtime when the map is
---                     uncommitted or modified: git has no date for it yet),
---   * `stale`         the newest commit touching the source tree is NOT an
---                     ancestor of the map's commit, i.e. code changed after
---                     the map was last written.
---
--- Anything that cannot be established (no git, an untracked map in a
--- non-repository, a command that failed) is reported as stale with the
--- reason, never as fresh: an affected-selection built on a graph of unknown
--- age must not look trustworthy.

local gitq = require("documentation.testing.git")

local M = {}

---ISO 8601 UTC, second resolution.
---@param t integer|nil Unix seconds.
---@return string|nil
function M.iso(t)
  if type(t) ~= "number" then
    return nil
  end
  return os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(t)) --[[@as string]]
end

---Source pathspecs worth asking git about: the Lua root plus every scanned
---source directory the map recorded. Only plain relative paths are kept, so a
---hostile `meta.source` cannot become an option or escape the repository.
---@param meta table|nil The map's `meta`.
---@param lua_root string|nil
---@return string[]
function M.source_pathspecs(meta, lua_root)
  local out, seen = {}, {}
  ---@param p any
  local function add(p)
    if
      type(p) == "string"
      and p ~= ""
      and #p <= 300
      and p:sub(1, 1) ~= "-"
      and p:sub(1, 1) ~= "/"
      and not p:match("^%a:")
      and not p:find("..", 1, true)
      and not p:find("[%c]")
      and not seen[p]
    then
      seen[p] = true
      out[#out + 1] = p
    end
  end
  add(lua_root or "lua")
  local source = type(meta) == "table" and meta.source or nil
  if type(source) == "string" then
    add(source)
  elseif type(source) == "table" then
    for _, s in ipairs(source) do
      add(s)
    end
  end
  return out
end

---@param root string Repository root.
---@param map_rel string Repo-relative path of the map file.
---@param map_abs string Absolute path of the map file.
---@param meta table|nil The map's `meta` (source directories).
---@param lua_root string|nil
---@return Documentation.Testing.Graph graph Without `gaps` (the caller owns those).
function M.assess(root, map_rel, map_abs, meta, lua_root)
  local stat = (vim.uv or vim.loop).fs_stat(map_abs)
  local mtime = stat and stat.mtime and stat.mtime.sec or nil

  local graph = {
    version = 1,
    map = map_rel,
    generated_at = M.iso(mtime),
    commit = nil,
    head = nil,
    stale = true,
    stale_reason = nil,
    dirty = false,
    gaps = {},
  }

  if not gitq.in_repo(root) then
    graph.stale_reason = "no git history: the age of the map cannot be judged"
    return graph
  end

  graph.head = gitq.head(root)
  local specs = M.source_pathspecs(meta, lua_root)
  graph.dirty = gitq.dirty(root, specs)

  local map_modified = gitq.dirty(root, { map_rel })
  local map_sha, map_time = gitq.last_commit(root, { map_rel })
  if not map_sha or map_modified then
    -- Not in history yet, or rewritten since: the file on disk is what counts.
    graph.stale_reason = map_modified
        and map_sha
        and "the map has uncommitted changes: its commit does not describe it"
      or "the map is not committed: no commit to compare against"
    -- Uncommitted but newer than every source commit is still a usable graph:
    -- compare by time, the only data there is.
    local src_sha, src_time = gitq.last_commit(root, specs)
    if mtime and (not src_sha or (src_time and mtime >= src_time)) then
      graph.stale = false
      graph.stale_reason = nil
    end
    graph.commit = map_sha
    return graph
  end

  graph.commit = map_sha
  graph.generated_at = M.iso(map_time)

  local src_sha = gitq.last_commit(root, specs)
  if not src_sha then
    graph.stale = false
    return graph
  end
  if src_sha == map_sha or gitq.is_ancestor(root, src_sha, map_sha) then
    graph.stale = false
    return graph
  end
  graph.stale_reason = ("code under %s changed in %s after the map was written in %s"):format(
    table.concat(specs, ", "),
    src_sha:sub(1, 12),
    map_sha:sub(1, 12)
  )
  return graph
end

return M
