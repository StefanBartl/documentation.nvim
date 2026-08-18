---@module 'documentation.bindings.usrcmds'
--- The user commands: `:DocMap` and `:DocBrowse` — registration, argument
--- dispatch and completion.
---
--- Opt-in: nothing here runs unless a caller invokes `setup()`, so requiring
--- `documentation` in a plugin does not silently register a command in the
--- user's editor.
---
--- Built on `editor/registry.lua`: `setup()` ensures a live handle exists for
--- `opts.root` (reusing one from a prior `documentation.install()` call rather
--- than scanning a second time) and drives every action through it, so
--- `:DocMap` and any `on_change` subscriber another plugin registered stay in
--- sync with the same IR instead of each holding their own stale copy.
---
--- `opts.command_name` (default "DocMap") is what lets a second `setup()`
--- call — a consuming plugin generating its own map — pick a different name
--- instead of silently overwriting this one; `usercmd.create` defaults to
--- `force = true`, so two `setup()` calls with the same name is not an error,
--- just a bug that changing the name avoids.
---
--- **Dispatch**, which is the reason this file is a dispatcher and not the
--- 700-line if-chain it replaced: the first word of the argument selects an
--- action from `ACTIONS`, the rest is passed to it verbatim. The old chain
--- tested each action's full pattern in turn and fell through to the default —
--- *regenerate the artifacts* — whenever none matched. So `:DocMap graph` with
--- a missing argument, or any typo, silently rewrote files instead of saying
--- anything. Only a genuinely empty argument regenerates now.

local M = {}

-- `Documentation.Bindings.Ctx` is declared in `bindings/@types`.

---The `:DocMap` actions.
---
---Values are thunks rather than module paths so `full` and the bare form can
---share one handler with a flag, and so every `require` stays lazy — a
---`:DocMap check` never loads the churn or diff code.
---@type table<string, fun(ctx: Documentation.Bindings.Ctx, arg: string)>
local ACTIONS = {
  open = function(ctx)
    require("documentation.bindings.usrcmds.open").run(ctx)
  end,
  serve = function(ctx, arg)
    require("documentation.bindings.usrcmds.serve").run(ctx, arg)
  end,
  graph = function(ctx, arg)
    require("documentation.bindings.usrcmds.graph").run(ctx, arg)
  end,
  dot = function(ctx, arg)
    require("documentation.bindings.usrcmds.dot").run(ctx, arg)
  end,
  mermaid = function(ctx, arg)
    require("documentation.bindings.usrcmds.mermaid").run(ctx, arg)
  end,
  why = function(ctx, arg)
    require("documentation.bindings.usrcmds.why").run(ctx, arg)
  end,
  diff = function(ctx, arg)
    require("documentation.bindings.usrcmds.diff").run(ctx, arg)
  end,
  impact = function(ctx, arg)
    require("documentation.bindings.usrcmds.impact").run(ctx, arg)
  end,
  churn = function(ctx, arg)
    require("documentation.bindings.usrcmds.churn").run(ctx, arg)
  end,
  checklist = function(ctx, arg)
    require("documentation.bindings.usrcmds.checklist").run(ctx, arg)
  end,
  plugins = function(ctx)
    require("documentation.bindings.usrcmds.plugins").run(ctx)
  end,
  bindings = function(ctx)
    require("documentation.bindings.usrcmds.bindings").run(ctx)
  end,
  tools = function(ctx)
    require("documentation.bindings.usrcmds.tools").run(ctx)
  end,
  endpoints = function(ctx)
    require("documentation.bindings.usrcmds.endpoints").run(ctx)
  end,
  helptags = function(ctx)
    require("documentation.bindings.usrcmds.helptags").run(ctx)
  end,
  annotate = function(ctx, arg)
    require("documentation.bindings.usrcmds.annotate").run(ctx, arg)
  end,
  check = function(ctx)
    require("documentation.bindings.usrcmds.generate").check(ctx)
  end,
  full = function(ctx)
    require("documentation.bindings.usrcmds.generate").run(ctx, { luals = true })
  end,
  all = function(ctx, arg)
    require("documentation.bindings.usrcmds.generate_all").run(ctx, arg == "full")
  end,
}

---Action names, sorted — the first completion level, and the "did you mean"
---list in the unknown-action message.
---@return string[]
local function action_names()
  local names = vim.tbl_keys(ACTIONS)
  table.sort(names)
  return names
end

-- Exported so `bindings/autocmds.lua` can derive its `:DocMap` args string
-- from the same table dispatch/completion already read, instead of a third
-- hand-typed copy that can (and did) drift out of sync.
M.action_names = action_names

-- Richer than a plain action-name list (`why <a> <b>`, `diff <ref>`,
-- `churn [range]`, ...) -- kept as hand-written prose rather than derived
-- from `action_names()`, because ACTIONS' plain name->thunk shape carries
-- no argument-shape data to derive from. Exported (rather than an inline
-- string literal inside `M.setup`) specifically so a test can assert every
-- `action_names()` entry appears here without registering a real command --
-- this is the string that drifted out of a completeness guarantee before;
-- the guarantee now lives in TESTS/usrcmds_actions_spec.lua instead of
-- "nobody forgets to update this by hand."
---@type string
M.action_usage_hints = "[check|full|open|graph|why <a> <b>|dot|mermaid|diff <ref>|impact <ref>"
  .. "|churn [range]|checklist [all]|plugins|bindings|tools|endpoints|serve [stop]"
  .. "|helptags|annotate [--write|--sidecar]|all [full]]"

---Every module name `find_node` would resolve, for completion.
---
---Offers exactly what the command accepts, namespaces included — completing a
---name the command then rejects is worse than no completion at all.
---@param ir Documentation.IR
---@param lua_root string
---@return string[]
local function module_names(ir, lua_root)
  local check = require("documentation.core.check")
  local names = {}
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    local name = node.module or check.expected_module(node.path .. "/init.lua", lua_root)
    if name then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

---@param candidates string[]
---@param lead string
---@return string[]
local function starting_with(candidates, lead)
  return vim.tbl_filter(function(c)
    return c:find(lead, 1, true) == 1
  end, candidates)
end

---@param p string
---@return string
local function norm(p)
  return (tostring(p):gsub("\\", "/"):gsub("/+$", ""))
end

---Resolve the repository root the map should be generated for, **at the
---moment the command runs** — from the current buffer's file, not from this
---file's own location and not from the process's startup directory.
---
---WHY THE BUFFER AND NOT `getcwd()`
---This resolved `getcwd()` once, in `setup()`, and closed the answer into the
---command. Because the plugin is `cmd`-lazy, "once" meant *the first `:DocMap`
---of the session*, and every later invocation regenerated that first
---repository no matter which one the user was looking at — silently, since the
---report said "Wrote 3 artifacts" without naming a tree. Verified the ugly
---way: a `:DocMap full` in one checkout, then the same command with another
---project's file open, rewrote the first project's artifact a second time and
---reported success.
---
---`getcwd()` is the wrong question even asked per invocation: `:e` a file in a
---sibling repository and the working directory does not follow. "Which project
---am I looking at" is a buffer question, which is how every other plugin that
---has to answer it (LSP roots, git signs, pickers) answers it.
---
---`vim.fs.root` rather than lib.nvim's `polymorphic_rootresolver`, which
---otherwise fits exactly: that helper collapses any root under
---`stdpath("config")` to the config directory itself. Correct for an LSP, wrong
---here — a git worktree checked out *inside* the config tree is its own
---repository with its own `docs/map`, and collapsing it would reintroduce the
---exact "wrote to the wrong tree" bug this function exists to fix. A `.git`
---file (worktrees) matches the marker the same as a `.git` directory.
---@param markers string[]
---@return string
local function buffer_root(markers)
  local name = vim.api.nvim_buf_get_name(0)
  -- No file behind the buffer (`:DocBrowse`'s own scratch buffer, a dashboard,
  -- a fresh `nvim`): there is nothing to walk up from, and the working
  -- directory is the only remaining statement about where the user is.
  if name ~= "" then
    local found = vim.fs.root(name, markers)
    if found then
      return norm(found)
    end
  end
  return norm(vim.fn.getcwd())
end

---@param opts Documentation.Opts?
---@return Documentation.Handle
function M.setup(opts)
  local usercmd = require("lib.nvim.usercmd")
  local notify = require("lib.nvim.notify").create("[documentation]")
  local registry = require("documentation.editor.registry")

  -- An explicit `root` pins, exactly as before: a caller who names a tree in
  -- their spec means "always this one", and a command that wandered off it
  -- would be a different bug of the same family. Only its *absence* — the
  -- `:DocMap`-in-whatever-repo-I-am-in case — resolves per invocation.
  local pinned_root = opts and opts.root and norm(opts.root) or nil
  local markers = (opts and opts.root_markers) or { ".git" }

  ---@return string
  local function resolve_root()
    return pinned_root or buffer_root(markers)
  end

  ---Everything the actions read, for one repository.
  ---
  ---Rebuilt per invocation rather than closed over once. Cheap: `config.build`
  ---is a table merge plus one `vim.fs.dir` probe for `source`, and
  ---`registry.get` makes the handle a hash lookup for every root already
  ---scanned this session. Only a root seen for the first time pays for a scan,
  ---which is the work the user asked for by naming a new tree.
  ---@param root string
  ---@return Documentation.Bindings.Ctx
  local function ctx_for(root)
    -- Always through `config.build`: a caller passing a partial table (the
    -- common case from a plugin spec's `opts`) would otherwise arrive here with
    -- no `out_dir`, no `command_name` and no `source`, and every downstream
    -- `cfg.x or default` would have to repeat the default list.
    local cfg = require("documentation.config").build(root, opts)
    local handle = registry.get(cfg.root) or registry.install(cfg)
    ---@type Documentation.Bindings.Ctx
    return {
      cfg = cfg,
      handle = handle,
      notify = notify,
      command_name = cfg.command_name or "DocMap",
      open_map = require("documentation.bindings.usrcmds.open").opener(
        cfg,
        notify,
        cfg.command_name or "DocMap"
      ),
      find_node = function(ir, name, lua_root)
        return require("documentation.core.find").node(ir, name, lua_root)
      end,
      generate_all = opts and opts.generate_all,
    }
  end

  ---Module names for completion, from the current root — but **only if that
  ---root is already installed**.
  ---
  ---`registry.get`, never `ctx_for`. Completion runs on every keystroke of an
  ---argument, and `ctx_for` installs on a miss: pressing Tab in a repository
  ---this session has not scanned would otherwise block the editor on a full
  ---scan (`full`-sized, with LuaLS, if that is how the tree was configured)
  ---for a list of candidates. An unscanned root simply offers no module names
  ---— the same thing it offered before any of this was dynamic, and the very
  ---next `:DocMap` installs the handle that makes them appear.
  ---@return string[]
  local function completion_names()
    local entry = registry.get(resolve_root())
    if not entry then
      return {}
    end
    local cfg = require("documentation.config").build(resolve_root(), opts)
    return module_names(entry.ir(), cfg.lua_root or "lua")
  end

  -- The command *names* cannot be per-invocation — they are registered once —
  -- so they come from a config built for whichever root is current at setup
  -- time. Neither name depends on the tree, so this is a read of `opts`, not
  -- an early binding of a root.
  -- notify passed only here, not at ctx_for's/completion_names' own
  -- config.build calls below -- opts doesn't change between them, so
  -- warning again there would just repeat this same message on every
  -- command dispatch (or, for completion_names, every keystroke).
  local setup_cfg = require("documentation.config").build(resolve_root(), opts, notify)
  local command_name = setup_cfg.command_name or "DocMap"
  local browse_command_name = setup_cfg.browse_command_name or "DocBrowse"

  local handle = registry.get(setup_cfg.root) or registry.install(setup_cfg)

  -- Self-instrumentation: on by default, `opts.telemetry = false` to opt
  -- out, a no-op without runtime-analysis.nvim installed — see
  -- `documentation.core.telemetry_self`'s own doc-comment for the full
  -- reasoning and its honest limits. After `registry`/`config` above have
  -- already required their own dependencies, so this catches more of the
  -- tree than calling it first would.
  require("documentation.core.telemetry_self").setup(setup_cfg)

  -- Extracted so `:DocMapAll` (registered below, only when `opts.generate_all`
  -- is configured) can dispatch the exact same `all` path `:DocMap all`
  -- itself goes through, rather than a second, hand-rolled call to the
  -- `generate_all` handler that could drift from this one.
  ---@param action string Raw argument text, already trimmed — "" for bare `:DocMap`.
  local function dispatch(action)
    local verb, rest
    if action ~= "" then
      verb, rest = action:match("^(%S+)%s*(.-)$")
      -- Validate *before* resolving a root: an unknown verb must not install a
      -- handle (a full scan) for a tree the user never got to act on.
      if not (verb and ACTIONS[verb]) then
        notify.warn(
          ("Unknown action '%s'. Expected one of: %s  (or no argument to regenerate)."):format(
            verb or action,
            table.concat(action_names(), ", ")
          )
        )
        return
      end
    end

    local ctx = ctx_for(resolve_root())

    -- Empty, and only empty, is the generate action. Anything typed that is
    -- not a known verb is a mistake, and saying so beats writing files.
    if action == "" then
      require("documentation.bindings.usrcmds.generate").run(ctx)
      return
    end

    ACTIONS[verb](ctx, rest or "")
  end

  usercmd.create(command_name, function(args)
    dispatch(vim.trim(args.args or ""))
  end, {
    nargs = "*",
    desc = "Regenerate the module map (:" .. command_name .. " " .. M.action_usage_hints .. ")",
    complete = function(lead, line)
      -- Two completion levels: the action, then — once an action that takes a
      -- module is typed — the module paths the map actually knows, which is
      -- the argument nobody wants to type by hand.
      local after_graph = line:match("graph%s+%a*%s+(.*)$") or line:match("graph%s+(%a*)$")
      if line:match("graph%s+%a+%s") or line:match("why%s") or line:match("dot%s+%a+%s") then
        return starting_with(completion_names(), lead)
      elseif after_graph or line:match("dot%s+%a*$") then
        return starting_with({ "deps", "calls" }, lead)
      end
      return starting_with(action_names(), lead)
    end,
  })

  usercmd.create(browse_command_name, function(args)
    require("documentation.bindings.usrcmds.browse").run(ctx_for(resolve_root()), args.args or "")
  end, {
    nargs = "*",
    desc = ("Browse the module map in the editor (:%s [live] [history|trail|endpoints|module])"):format(
      browse_command_name
    ),
    complete = function(lead, line)
      -- `live` only makes sense as the first token; after it (or after any
      -- module name) the only useful completion is a module path. `history`
      -- and `trail` stand where a module name would, so they stay on offer for
      -- as long as module names do.
      local candidates = { "history", "trail" }
      if not line:match("%s%S+%s") then
        candidates[#candidates + 1] = "live"
      end
      vim.list_extend(candidates, completion_names())
      table.sort(candidates)
      return starting_with(candidates, lead)
    end,
  })

  -- `:DocMapAll` / `:DocMapAllFull` — standalone aliases for `:DocMap all`
  -- / `:DocMap all full`, registered (like `all` itself in ACTIONS above)
  -- only when a caller actually configured `opts.generate_all.projects`.
  -- Reached for often enough, once configured, to earn command names of
  -- their own rather than a remembered subcommand — same reasoning
  -- `runtime-analysis.telemetry`'s `:RATelemetryStartAll` gives for its own
  -- bare-form alias. Split fast/full (2026-08-15) the same way `:DocMap`/
  -- `:DocMap full` already are for a single repo — see
  -- `bindings/usrcmds/generate_all.lua`'s own header for why the bulk path
  -- did not have this distinction before.
  if
    opts
    and opts.generate_all
    and opts.generate_all.projects
    and #opts.generate_all.projects > 0
  then
    local all_command_name = command_name .. "All"
    usercmd.create(all_command_name, function()
      dispatch("all")
    end, {
      desc = ("Generate every configured project's module map, fast scan (same as :%s all)"):format(
        command_name
      ),
    })

    usercmd.create(all_command_name .. "Full", function()
      dispatch("all full")
    end, {
      desc = ("Generate every configured project's module map, with LuaLS enrichment (same as :%s all full)"):format(
        command_name
      ),
    })

    if opts.generate_all.autoload then
      require("documentation.bindings.usrcmds.generate_all").autoload(opts.generate_all, notify)
    end
  end

  return handle
end

return M
