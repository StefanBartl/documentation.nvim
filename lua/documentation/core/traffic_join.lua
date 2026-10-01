---@module 'documentation.core.traffic_join'
--- Bridge to `github_stats.nvim`'s published digest for the `traffic`
--- browse mode -- the small per-repo summary ("digest") that plugin writes
--- to a local, per-machine directory after every fetch. See its own
--- `docs/FEATURES/DIGEST.md`, the stable cross-repo contract this module is
--- written against (it names this exact option: "`documentation.nvim`:
--- `opts.traffic.digest_dir`").
---
--- **Artifact-first, not live** -- like `telemetry_join`, not `rules_join`:
--- the digest is already on disk, written by github_stats.nvim's own
--- background cycle, so this reads a small JSON file rather than calling
--- into a running plugin's analytics. No live Neovim instance needed, and
--- no requirement that github_stats.nvim's own `setup()` has even run in
--- this process -- `digest_file()`/`file_stem()` both work before it has.
---
--- **Soft dependency throughout.** `github_stats.nvim` not being installed,
--- the resolved repository not being tracked, or nothing having been
--- fetched yet are all "no data", never an error -- see each function's own
--- `nil` case.
---
--- Probes `github_stats.digest`, never `require("github_stats")`: the
--- top-level module loads the dashboard and needs `ui.nvim`, so it would
--- falsely report "not installed" for someone who has the plugin but not
--- its UI dependency (DIGEST.md says so explicitly).

local M = {}

---The published schema this module understands. A higher `schema` on disk
---is a newer github_stats.nvim than this reads -- refused, not guessed at.
local SCHEMA = 1

---Digest files are small by contract (DIGEST.md measures ~4-5 KB in
---practice); a cap still guards against a hand-edited or corrupt file
---turning this read into an unbounded one.
local READ_CAP = 2 * 1024 * 1024

---"owner/repo" the `traffic` mode joins against: `opts.traffic.repo` if
---set, else derived from `root`'s git "origin" remote -- the same
---derivation `core/scan.lua` already does for `opts.repo_url` (GS-16),
---duplicated here rather than threaded through as a forwarded field: the
---auto-derived value is scan-time-only and is never written back onto the
---caller's own config table, so there is nothing to forward.
---@param opts Documentation.Browse.Opts|Documentation.Opts
---@return string?
function M.repo(opts)
  local override = opts.traffic and opts.traffic.repo
  if type(override) == "string" and override ~= "" then
    return override
  end
  if type(opts.root) ~= "string" then
    return nil
  end
  local ok, repo = pcall(function()
    local git = require("lib.nvim.git")
    local git_remote = require("lib.nvim.git.remote")
    local remote_url = git.remote_url("origin", { dir = opts.root })
    local remote = remote_url and git_remote.parse_remote(remote_url)
    return remote and ("%s/%s"):format(remote.owner, remote.repo)
  end)
  if ok and repo then
    return repo
  end
  return nil
end

---@internal
---@param path string
---@param repo string
---@return GHStats.Digest?
local function read_digest_file(path, repo)
  local uv = vim.uv or vim.loop
  local stat = uv.fs_stat(path)
  if not stat or stat.size > READ_CAP then
    return nil
  end

  local ok, decoded = pcall(function()
    return (require("lib.nvim.fs.json").read(path))
  end)
  if not ok or type(decoded) ~= "table" then
    return nil
  end

  if type(decoded.schema) ~= "number" or decoded.schema > SCHEMA then
    return nil
  end

  if decoded.repo ~= repo then
    -- The file-stem sanitizer is not injective (DIGEST.md): a filename
    -- collision between two differently-spelled repos reads as "not
    -- tracked" rather than silently showing the wrong repository's traffic.
    return nil
  end

  return decoded
end

---Read `repo`'s digest straight off disk through the installed
---`github_stats.nvim`, honoring `opts.traffic.digest_dir` the same way the
---plugin's own discovery chain's first step does ("an explicit setting of
---the reader").
---@param repo string "owner/repo"
---@param opts Documentation.Browse.Opts|Documentation.Opts
---@return GHStats.Digest? digest `nil` when `github_stats.nvim` is not
---installed, `repo` is not tracked (no digest file, or nothing was ever
---fetched for it), the file is unreadable or oversized, or its `schema` is
---newer than this module understands.
function M.load(repo, opts)
  local digest_mod = require("documentation.core.soft_require").probe("github_stats.digest")
  if not digest_mod then
    return nil
  end

  local override = opts.traffic and opts.traffic.digest_dir
  if type(override) == "string" and override ~= "" then
    -- `digest_dir()` on the probed module answers from *that module's own*
    -- `config.get()`, which this process's `setup()` (if any) controls, not
    -- this caller's -- so an explicit override here is honored by building
    -- the path the same way `digest.digest_file` does internally, reusing
    -- its own `file_stem` (the sanitizer) rather than duplicating it.
    local ok, stem = pcall(digest_mod.file_stem, repo)
    if not ok or type(stem) ~= "string" then
      return nil
    end
    local dir = (override:gsub("[/\\]+$", ""))
    return read_digest_file(dir .. "/digest/" .. stem .. ".json", repo)
  end

  local ok, path = pcall(digest_mod.digest_file, repo)
  if not ok or type(path) ~= "string" then
    return nil
  end
  return read_digest_file(path, repo)
end

return M
