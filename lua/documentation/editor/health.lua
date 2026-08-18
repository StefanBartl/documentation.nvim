---@module 'documentation.editor.health'
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

local soft_require = require("documentation.core.soft_require")

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
    if not soft_require.probe(mod) then
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

  local pdfport = soft_require.probe("pdfport")
  if pdfport and type(pdfport.can_create) == "function" and pdfport.can_create("markdown") then
    h_ok("pdfport.nvim — overview.pdf (opts.pdf = true) can be written")
  elseif pdfport then
    h_info("pdfport.nvim installed, but no markdown producer is available", {
      "opts.pdf = true would fail until pandoc + a PDF engine are installed.",
      "See pdfport.nvim's :checkhealth for which producer is missing.",
    })
  else
    h_info("pdfport.nvim not installed", {
      "Only opts.pdf = true (overview.pdf, alongside overview.md) needs it.",
      "https://github.com/StefanBartl/pdfport.nvim",
    })
  end

  -- No external dependency to probe, unlike pdfport above — call hierarchy
  -- is built entirely on Neovim's own LSP client (`vim.lsp.start()` with a
  -- function `cmd`, no external process) and `handle.callers`/`callees`,
  -- which already exist on every installed handle regardless of this
  -- option.
  --
  -- Reports whether the client is actually *running*, not merely that the
  -- option exists. The failure mode this covers is silent and easy to
  -- misread: with no client attached, `vim.lsp.buf.incoming_calls()` opens
  -- nothing, which looks exactly like "this function has no callers"
  -- rather than like a configuration problem. Asking Neovim's own client
  -- list is the only answer that cannot be wrong — an installed handle's
  -- `opts.callhierarchy` says what was *requested*, and the client attaches
  -- on `BufReadPost`, so a buffer opened before `setup()` ran has the
  -- option set and no client. See docs/CALL_HIERARCHY.md.
  local ch_clients = vim.lsp.get_clients({ name = "docmap-callhierarchy" })
  if #ch_clients > 0 then
    local buffers = 0
    for _, client in ipairs(ch_clients) do
      for _ in pairs(client.attached_buffers or {}) do
        buffers = buffers + 1
      end
    end
    h_ok(
      ("Call hierarchy (opts.callhierarchy) — running, attached to %d buffer(s)"):format(buffers)
    )
  else
    h_info(
      "Call hierarchy (opts.callhierarchy) — not attached. Set it true in setup()/install(); "
        .. "the client attaches on BufReadPost to Lua buffers under source/, so an already-open "
        .. "buffer needs :e. No external dependency. See docs/CALL_HIERARCHY.md."
    )
  end

  -- Same posture as call hierarchy directly above: no external dependency,
  -- nothing here that can be missing or broken.
  h_ok(
    "Diagnostics (opts.diagnostics) — no external dependency, set true on install() to publish findings as vim.diagnostic"
  )

  local telemetry_self = soft_require.probe("documentation.core.telemetry_self")
  local self_instance = telemetry_self and telemetry_self.instance()
  if self_instance then
    h_ok(("runtime-analysis.nvim — self-instrumented as %q"):format(self_instance.namespace))
  elseif soft_require.probe("runtime-analysis.telemetry") then
    h_info("runtime-analysis.nvim installed, but not yet self-instrumented", {
      "documentation.setup() starts this automatically unless opts.telemetry = false.",
      "Feeds :DocBrowse's telemetry mode and dead-function suppression.",
    })
  else
    h_info("runtime-analysis.nvim not installed", {
      "Optional: self-instrumentation for :DocBrowse's telemetry mode and",
      "dead-function suppression (opts.telemetry, default true when present).",
      "https://github.com/StefanBartl/runtime-analysis.nvim",
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

  -- What this plugin puts in the user's editor beyond the commands.
  --
  -- "Does this plugin install anything global?" is a fair question to be able
  -- to answer without grepping, and for an autocommand the honest answer is
  -- not derivable at runtime: `nvim_get_autocmds` shows what happens to be
  -- installed *now*, which for four autocmds created lazily by four different
  -- lifecycles is almost never the full set. So this reads the manifest in
  -- `bindings/autocmds.lua`, which states the whole surface including the
  -- parts not currently active.
  local manifest = soft_require.probe("documentation.bindings.autocmds")
  if manifest then
    local buffer_local, global = 0, 0
    for _, a in ipairs(manifest.list) do
      if a.scope == "buffer" then
        buffer_local = buffer_local + 1
      else
        global = global + 1
      end
    end
    h_info(
      ("autocommands: %d global, %d buffer-local — all created lazily, none at require time"):format(
        global,
        buffer_local
      ),
      vim.tbl_map(function(a)
        return ("%s (%s) — %s"):format(table.concat(a.events, ","), a.owner, a.lifetime)
      end, manifest.list)
    )
    h_info("keymaps: none global — every binding is buffer-local to a :DocBrowse scratch buffer")
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
    h_error("documentation.core.config failed to load: " .. tostring(cfg))
    return
  end

  h_info(("root      %s"):format(cfg.root))
  local sources = require("documentation.config").sources(cfg)
  h_info(
    ("source    %s   (auto-detected; override with opts.source)"):format(
      table.concat(sources, ", ")
    )
  )
  h_info(("out_dir   %s"):format(cfg.out_dir))

  -- One report per root. A tree with `lua/` beside `src/` has two answers to
  -- "does the source directory exist and hold anything", and collapsing them
  -- into one would hide whichever half is broken.
  for _, src in ipairs(sources) do
    local source_dir = cfg.root .. "/" .. src
    if vim.fn.isdirectory(source_dir) == 0 then
      h_error(("source directory does not exist: %s"):format(source_dir), {
        "A :DocMap here would scan nothing and write an empty map.",
        "Set opts.root or opts.source, or run from the repository you meant.",
      })
    else
      local n = count_lua(source_dir)
      if n == 0 then
        -- Not a warning for a non-Lua root: `src/` full of TypeScript is a
        -- perfectly good source root, and this counter only knows `.lua`.
        h_info(("%s contains no .lua files"):format(src))
      else
        h_ok(("%s contains %d .lua file%s"):format(src, n, n == 1 and "" or "s"))
      end
    end
  end

  -- The one configuration mistake that produces a *plausible wrong answer*
  -- rather than an error.
  --
  -- `coverage.resolve` treats a missing `tests_dir` as "nothing is tested" by
  -- design — every function is simply left `tested = false`, which is the
  -- honest result for a tree with no tests. But it is indistinguishable from
  -- a tree whose tests are somewhere else: the Analysis tab then reports 0%
  -- test coverage for the whole map, and that reads as a badly tested
  -- repository rather than as a wrong path. Nothing else on the page says
  -- otherwise, so this is where it gets said.
  h_info(
    ("tests_dir %s   (auto-derived fn.tested; override with opts.tests_dir)"):format(
      cfg.tests_dir or "TESTS"
    )
  )

  local tests_dir = cfg.root .. "/" .. (cfg.tests_dir or "TESTS")
  if vim.fn.isdirectory(tests_dir) == 0 then
    h_warn(("%s does not exist"):format(cfg.tests_dir or "TESTS"), {
      "Not an error: a tree with no tests is a valid tree.",
      "But every function will be left `tested = false`, so the Analysis tab's",
      "test-coverage panel will report 0% for the whole map — which looks like",
      "an untested repository rather than a misconfigured path.",
      "If this tree does have tests, set opts.tests_dir to where they are.",
    })
  else
    -- Every `.lua` file, not just `*_spec.lua`: `coverage.lua`'s `lua_files`
    -- filters on the extension alone and nothing else, so a helper or a
    -- fixture under `tests_dir` contributes mentioned names exactly like a
    -- spec does. Counting only spec-shaped names here would report a smaller
    -- number than the one the coverage figure is actually derived from.
    local n = count_lua(tests_dir)
    if n == 0 then
      h_warn(("%s exists but holds no .lua files"):format(cfg.tests_dir or "TESTS"), {
        "Same consequence as a missing directory: fn.tested stays false everywhere,",
        "and the Analysis tab reports 0%% test coverage for the whole map.",
      })
    else
      h_ok(
        ("%s holds %d .lua file%s scanned for function mentions"):format(
          cfg.tests_dir or "TESTS",
          n,
          n == 1 and "" or "s"
        )
      )
    end
  end

  -- How the *headless runner* finds lib.nvim, which is a different question
  -- from the one answered above.
  --
  -- The dependency section asks "does lib.nvim load right now", which a
  -- plugin-manager install satisfies. `TESTS/run.lua` and `scripts/ci.sh` do
  -- not run inside that editor — they are `nvim --headless -u NONE`, with no
  -- plugin manager and an empty rtp — so they resolve lib.nvim through
  -- LIB_NVIM_DIR, `.deps/lib.nvim`, or a sibling checkout. A contributor can
  -- pass everything above and still have `scripts/ci.sh tests` fail on its
  -- first line.
  local lib_candidates = {
    { label = "$LIB_NVIM_DIR", path = vim.env.LIB_NVIM_DIR },
    { label = ".deps/lib.nvim", path = cfg.root .. "/.deps/lib.nvim" },
    { label = "../lib.nvim", path = vim.fs.dirname(cfg.root) .. "/lib.nvim" },
  }
  local found_lib
  for _, c in ipairs(lib_candidates) do
    if c.path and vim.fn.isdirectory(c.path) == 1 then
      found_lib = c
      break
    end
  end
  if found_lib then
    h_ok(("headless runs resolve lib.nvim via %s"):format(found_lib.label))
  else
    h_info("headless runs would not find lib.nvim", {
      "Only affects TESTS/run.lua and scripts/ci.sh, not the plugin itself —",
      "those run with -u NONE and have no plugin manager to supply it.",
      "Fix with any one of: LIB_NVIM_DIR=<path>, a clone at .deps/lib.nvim,",
      "or a checkout beside this repository.",
    })
  end

  -- Artifacts --------------------------------------------------------------
  h_start("documentation.nvim: artifacts")

  local artifact = cfg.root .. "/" .. cfg.out_dir .. "/module_map.json"
  local raw = require("lib.nvim.fs.read")(artifact)
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
  -- Every source root. This asks "is the map older than the newest source
  -- file"; walking only one of two roots would answer it for half the tree
  -- and report the map fresh while the other half had moved on.
  for _, src in ipairs(require("documentation.config").sources(cfg)) do
    pcall(walk, cfg.root .. "/" .. src)
  end

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
