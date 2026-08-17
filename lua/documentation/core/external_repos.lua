---@module 'documentation.core.external_repos'
--- GitHub links for `requires_external` modules — the second, sibling
--- resolver into `ir.tag_links`, alongside `tagfiles.lua`. That module
--- resolves a `requires_external` module against *another locally checked
--- out project's own generated map*; this one resolves one against a
--- user-declared GitHub repo, for the far more common case: the external
--- module is a third-party plugin (`plenary.nvim`, `nio.nvim`, ...) that
--- ships no `docmap` artifact of its own to resolve against at all.
---
--- Runs strictly after `tagfiles.resolve` and never overwrites an entry it
--- already set — a local, already-checked-out project's own map is a more
--- useful destination than a guessed GitHub URL for the same module, when
--- both happen to be configured.
---
--- No mapping from a bare namespace (`"plenary"`) to a GitHub repo
--- (`"nvim-lua/plenary.nvim"`) exists anywhere in the IR or the wider
--- ecosystem this plugin can see — `core/plugins.lua`'s lazy.nvim spec
--- extraction only fires when scanning a Neovim *config* repo that
--- declares the dependency, not when scanning the dependency's own plugin
--- repo, which is the shape this feature is actually for. Declaring
--- `opts.external_repos` is the only way in.
---
--- ```lua
--- require("documentation").generate({
---   ...,
---   external_repos = {
---     plenary = "nvim-lua/plenary.nvim",
---     -- Verified against a local checkout when one is given (see below) —
---     -- worth it whenever one already exists, which in a sibling-repos-
---     -- under-one-directory setup is often.
---     ["lib.nvim"] = {
---       repo = "StefanBartl/lib.nvim",
---       local_path = "E:/repos/lib.nvim",
---     },
---   },
--- })
--- ```
---
--- **Two path shapes, deliberately checked rather than assumed.** A Lua
--- module `a.b` lives at either `<lua_root>/a/b.lua` (flat) or
--- `<lua_root>/a/b/init.lua` (directory) — both are real, common
--- conventions, and guessing wrong produces a working GitHub link to a 404.
--- Measured against this exact repo's own `require("lib.nvim...")` calls
--- while building this: `lib.nvim` uses the directory shape almost
--- everywhere (`autocmd/init.lua`, `fs/read/init.lua`, ...), which a
--- flat-only guess got wrong for nearly every module. With `local_path` set,
--- both shapes are checked against the real checkout on disk — a local
--- `uv.fs_stat`, not a network call, so `scan_full()`/`--check` stay exactly
--- as offline and deterministic as `tagfiles.lua`'s own local-path
--- resolution already is. Without `local_path` (no local checkout exists,
--- or the caller does not want to name one), the flat shape is assumed,
--- unverified — still better than the inert grey box it replaces even when
--- wrong, since the reader is one click from the repo's own file browser.

local M = {}

local uv = vim.uv

---Longest matching prefix in `external_repos` for `mod` — identical rule to
---`tagfiles.match_prefix` (dot-bounded: `plenary` matches `plenary.async`
---but never `plenaryx`), duplicated rather than shared because the two
---tables hold different value shapes and sharing would need a generic
---signature neither call site benefits from.
---@param mod string
---@param external_repos table<string, string|Documentation.ExternalRepo>
---@return string? prefix
---@return string|Documentation.ExternalRepo? entry
local function match_prefix(mod, external_repos)
  local best_prefix, best_entry
  for prefix, entry in pairs(external_repos) do
    if mod == prefix or mod:sub(1, #prefix + 1) == prefix .. "." then
      if not best_prefix or #prefix > #best_prefix then
        best_prefix, best_entry = prefix, entry
      end
    end
  end
  return best_prefix, best_entry
end

---Normalize the shorthand string form to the full table shape.
---@param entry string|Documentation.ExternalRepo
---@return Documentation.ExternalRepo
local function normalize(entry)
  if type(entry) == "string" then
    return { repo = entry, branch = "main", lua_root = "lua" }
  end
  return {
    repo = entry.repo,
    branch = entry.branch or "main",
    lua_root = entry.lua_root or "lua",
    local_path = entry.local_path,
  }
end

---@param path string
---@return boolean
local function is_file(path)
  local ok, st = pcall(uv.fs_stat, path)
  return ok and st ~= nil and st.type == "file"
end

---The module's path relative to `lua_root`, flat-shape first: `a.b` ->
---`a/b.lua`, checked against `cfg.local_path` when one was given, falling
---back to the directory shape `a/b/init.lua`, falling back to the flat
---shape unverified when neither checkout path resolves (no `local_path`,
---or the module genuinely isn't there — a stale declaration, or a
---dynamically required path this scan's own `deps.lua` would equally not
---have resolved).
---@param mod string
---@param cfg Documentation.ExternalRepo
---@return string
local function module_path(mod, cfg)
  local flat = (mod:gsub("%.", "/")) .. ".lua"
  if not cfg.local_path then
    return flat
  end
  local base = (cfg.local_path:gsub("\\", "/"):gsub("/+$", "")) .. "/" .. cfg.lua_root .. "/"
  if is_file(base .. flat) then
    return flat
  end
  local dir_shape = (mod:gsub("%.", "/")) .. "/init.lua"
  if is_file(base .. dir_shape) then
    return dir_shape
  end
  return flat
end

---Build the blob URL for `mod` inside `cfg.repo`.
---@param mod string
---@param cfg Documentation.ExternalRepo
---@return string
local function blob_url(mod, cfg)
  return "https://github.com/"
    .. cfg.repo
    .. "/blob/"
    .. cfg.branch
    .. "/"
    .. cfg.lua_root
    .. "/"
    .. module_path(mod, cfg)
end

---Extend `ir.tag_links` with a GitHub link for every `requires_external`
---module `opts.external_repos` covers and `tagfiles.resolve` did not
---already resolve. Mutates `ir` in place; a no-op when `opts.external_repos`
---is unset. Must run after `tagfiles.resolve` — see this module's header
---for why an existing entry is never overwritten.
---@param ir Documentation.IR
---@param opts Documentation.Opts
function M.resolve(ir, opts)
  local external_repos = opts.external_repos
  if not external_repos or not next(external_repos) then
    return
  end
  ir.tag_links = ir.tag_links or {}

  local mods = {}
  for _, id in ipairs(ir.order) do
    for _, mod in ipairs(ir.nodes[id].requires_external or {}) do
      mods[mod] = true
    end
  end

  for mod in pairs(mods) do
    if not ir.tag_links[mod] then
      local prefix, entry = match_prefix(mod, external_repos)
      if prefix and entry then
        local cfg = normalize(entry)
        ir.tag_links[mod] = { title = mod, html = blob_url(mod, cfg) }
      end
    end
  end
end

return M
