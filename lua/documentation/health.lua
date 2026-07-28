---@module 'documentation.health'
--- `:checkhealth documentation`.
---
--- Scoped to the things that actually go wrong, which is a shorter list than
--- it looks: an absent optional tool degrades to a stated finding rather than
--- an error, so the failure modes worth a health check are the ones that make
--- a command silently do the wrong thing — a missing dependency, an absent
--- treesitter Lua parser, and a map generated for a directory the user did
--- not mean.
---
--- That last one is the reason this exists at all. `:DocMap` defaults its root
--- to the **current working directory**, so "it mapped the wrong repository"
--- and "it says my tree has one module" are the same bug seen from two
--- angles, and neither is visible from the output. The configuration section
--- prints the resolved options and what is actually on disk under them.

local M = {}

-- vim.health shim (start/ok/warn/error/info exist on all supported versions).
local H = vim.health or {}
local h_start = H.start or H.report_start
local h_ok = H.ok or H.report_ok
local h_warn = H.warn or H.report_warn
local h_error = H.error or H.report_error
local h_info = H.info or H.report_info

local MIN_NVIM = { 0, 10, 0 }

---The lib.nvim modules this plugin actually requires, as module paths rather
---than a single `lib.nvim` probe: `lib.nvim` has no `init.lua` for several of
---its namespaces, so "is lib.nvim installed" is not a question `require` can
---answer directly, and the useful answer is which piece is missing anyway.
---@type string[]
local DEPS = {
  "lib.nvim.notify",
  "lib.nvim.map",
  "lib.nvim.usercmd",
  "lib.nvim.autocmd",
  "lib.nvim.debounce",
  "lib.nvim.ui.kit",
  "lib.nvim.fs.read",
  "lib.nvim.fs.mkdirp",
  "lib.nvim.fs.is_subpath",
  "lib.nvim.fs.collect_recursive",
  "lib.nvim.fs.open.url.system_opener",
  "lib.nvim.cross.uv.spawn_capture",
}

---@return boolean
local function version_ok()
  local v = vim.version()
  if v.major ~= MIN_NVIM[1] then
    return v.major > MIN_NVIM[1]
  end
  if v.minor ~= MIN_NVIM[2] then
    return v.minor > MIN_NVIM[2]
  end
  return v.patch >= MIN_NVIM[3]
end

---Bytes at `path`, or nil.
---@param path string
---@return string?
local function read(path)
  local fd = io.open(path, "rb")
  if not fd then
    return nil
  end
  local s = fd:read("*a")
  fd:close()
  return s
end

---Count the `.lua` files directly under `dir`, recursively, without loading
---the scanner: the point of this check is to answer "is `source` pointing at
---anything" even when the scan itself is what is failing.
---@param dir string
---@return integer
local function count_lua(dir)
  local n = 0
  local function walk(d)
    for name, kind in vim.fs.dir(d) do
      local p = d .. "/" .. name
      if kind == "directory" then
        walk(p)
      elseif name:sub(-4) == ".lua" then
        n = n + 1
      end
    end
  end
  pcall(walk, dir)
  return n
end

function M.check()
  -- Environment ------------------------------------------------------------
  h_start("documentation.nvim: environment")

  local v = vim.version()
  local vstr = ("%d.%d.%d"):format(v.major, v.minor, v.patch)
  if version_ok() then
    h_ok(("Neovim %s (>= %d.%d.%d)"):format(vstr, MIN_NVIM[1], MIN_NVIM[2], MIN_NVIM[3]))
  else
    h_warn(
      ("Neovim %s is older than the required %d.%d.%d"):format(
        vstr,
        MIN_NVIM[1],
        MIN_NVIM[2],
        MIN_NVIM[3]
      ),
      { "The scanner uses vim.uv, vim.system and vim.treesitter." }
    )
  end

  -- The Lua parser is not optional the way lua-language-server is: without it
  -- `functions.lua`, `calls.lua` and `symbols.lua` produce nothing, and the
  -- map still renders — a tree of modules with no functions in it, which
  -- looks like a scanner bug rather than a missing parser.
  local ok_parser = pcall(vim.treesitter.language.add, "lua")
  if not ok_parser then
    ok_parser = pcall(vim.treesitter.get_string_parser, "local M = {}", "lua")
  end
  if ok_parser then
    h_ok("treesitter Lua parser available")
  else
    h_error("no treesitter Lua parser", {
      "Functions, call edges and module symbols all come from it.",
      "Install it: :TSInstall lua (nvim-treesitter), or use a Neovim build that bundles it.",
    })
  end

  -- Dependencies -----------------------------------------------------------
  h_start("documentation.nvim: lib.nvim")

  local missing = {}
  for _, mod in ipairs(DEPS) do
    if not pcall(require, mod) then
      missing[#missing + 1] = mod
    end
  end
  if #missing == 0 then
    h_ok(("all %d required lib.nvim modules load"):format(#DEPS))
  else
    h_error(("%d of %d lib.nvim modules failed to load"):format(#missing, #DEPS), {
      "Missing: " .. table.concat(missing, ", "),
      "lib.nvim is a hard dependency: https://github.com/StefanBartl/lib.nvim",
      'Add it to this plugin\'s spec: dependencies = { "StefanBartl/lib.nvim" }',
    })
  end

  -- Optional tools ---------------------------------------------------------
  h_start("documentation.nvim: optional tools")

  if vim.fn.executable("git") == 1 then
    h_ok("git — :DocMap diff/impact, :DocMap serve and :DocBrowse history")
  else
    h_warn("git not on PATH", {
      ":DocMap diff, :DocMap impact, :DocMap serve and :DocBrowse history need it.",
      "Everything else — generate, check, open, graph, dot, why — does not.",
    })
  end

  if vim.fn.executable("lua-language-server") == 1 then
    h_ok("lua-language-server — :DocMap full (class/alias detail, type edges)")
  else
    h_info("lua-language-server not on PATH", {
      "Only :DocMap full needs it; a plain :DocMap never calls it.",
      "Without it the Types and Inheritance views say so instead of rendering blank.",
    })
  end

  -- Commands ---------------------------------------------------------------
  h_start("documentation.nvim: commands")

  local registered = {}
  for name in pairs(vim.api.nvim_get_commands({})) do
    if name == "DocMap" or name == "DocBrowse" or name:match("^Doc") then
      registered[#registered + 1] = name
    end
  end
  if #registered > 0 then
    table.sort(registered)
    h_ok("registered: :" .. table.concat(registered, ", :"))
  else
    h_warn("no command registered", {
      'Commands are opt-in: call require("documentation").setup({}).',
      "Requiring the module alone never creates one, by design.",
      "If your spec lazy-loads on `cmd`, this is expected until it fires.",
    })
  end

  -- Configuration ----------------------------------------------------------
  --
  -- The section this file exists for. Every number below is what a `:DocMap`
  -- issued right now would act on.
  h_start("documentation.nvim: resolved configuration")

  local ok_cfg, cfg = pcall(function()
    return require("documentation.config").build(vim.fn.getcwd())
  end)
  if not ok_cfg then
    h_error("documentation.config failed to load: " .. tostring(cfg))
    return
  end

  h_info(("root      %s"):format(cfg.root))
  h_info(("source    %s   (auto-detected; override with opts.source)"):format(cfg.source))
  h_info(("out_dir   %s"):format(cfg.out_dir))

  local source_dir = cfg.root .. "/" .. cfg.source
  if vim.fn.isdirectory(source_dir) == 0 then
    h_error(("source directory does not exist: %s"):format(source_dir), {
      "A :DocMap here would scan nothing and write an empty map.",
      "Set opts.root or opts.source, or run from the repository you meant.",
    })
  else
    local n = count_lua(source_dir)
    if n == 0 then
      h_warn(("%s contains no .lua files"):format(cfg.source))
    else
      h_ok(("%s contains %d .lua file%s"):format(cfg.source, n, n == 1 and "" or "s"))
    end
  end

  -- Artifacts --------------------------------------------------------------
  h_start("documentation.nvim: artifacts")

  local artifact = cfg.root .. "/" .. cfg.out_dir .. "/module_map.json"
  local raw = read(artifact)
  if not raw then
    h_info(("no map generated yet under %s"):format(cfg.out_dir), {
      "Run :DocMap (or nvim --headless -l scripts/gen_map.lua).",
    })
    return
  end

  local ok_json, decoded = pcall(vim.json.decode, raw, { luanil = { object = true } })
  if not ok_json or type(decoded) ~= "table" or type(decoded.nodes) ~= "table" then
    h_error(("%s/module_map.json is not a readable artifact"):format(cfg.out_dir), {
      "Regenerate it with :DocMap.",
    })
    return
  end

  h_ok(("%s/module_map.json — %d nodes"):format(cfg.out_dir, #decoded.nodes))

  -- Staleness by mtime rather than by regenerating: `:DocMap check` is the
  -- authoritative answer and costs a full scan, which is not what a health
  -- check should spend. This is the cheap approximation, and it says so.
  local art_stat = vim.uv.fs_stat(artifact)
  local newest, newest_path = 0, nil
  local function walk(d)
    for name, kind in vim.fs.dir(d) do
      local p = d .. "/" .. name
      if kind == "directory" then
        walk(p)
      elseif name:sub(-4) == ".lua" then
        local st = vim.uv.fs_stat(p)
        if st and st.mtime.sec > newest then
          newest, newest_path = st.mtime.sec, p
        end
      end
    end
  end
  pcall(walk, source_dir)

  if art_stat and newest > art_stat.mtime.sec then
    h_warn("the map is older than the newest source file", {
      "Newest: " .. tostring(newest_path),
      "Run :DocMap to regenerate, or :DocMap check for the authoritative answer.",
    })
  elseif art_stat then
    h_ok("the map is newer than every source file (mtime check, not a full compare)")
  end
end

return M
