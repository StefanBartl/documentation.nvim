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
  helptags = function(ctx)
    require("documentation.bindings.usrcmds.helptags").run(ctx)
  end,
  check = function(ctx)
    require("documentation.bindings.usrcmds.generate").check(ctx)
  end,
  full = function(ctx)
    require("documentation.bindings.usrcmds.generate").run(ctx, { luals = true })
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

---Resolve the repository root the map should be generated for.
---
---The **current working directory**, not this file's own location. As
---`lib.nvim.docmap` the answer was the opposite — the map being generated was
---always lib.nvim's own, so walking up from this file was the correct root and
---`getcwd()` was the wrong one. A standalone plugin maps whatever repository
---the user is in; walking up from here would resolve to documentation.nvim's
---own checkout inside the plugin manager's directory, which is never the tree
---anyone typed `:DocMap` to see.
---
---Pass `opts.root` explicitly (from a lazy spec, from `install()`) whenever
---the answer must not depend on where the user happens to be.
---@return string
local function default_root()
  return (vim.fn.getcwd():gsub("\\", "/"):gsub("/+$", ""))
end

---@param opts Documentation.Opts?
---@return Documentation.Handle
function M.setup(opts)
  local usercmd = require("lib.nvim.usercmd")
  local notify = require("lib.nvim.notify").create("[documentation]")
  local registry = require("documentation.editor.registry")

  -- Always through `config.build`: a caller passing a partial table (the
  -- common case from a plugin spec's `opts`) would otherwise arrive here with
  -- no `out_dir`, no `command_name` and no `source`, and every downstream
  -- `cfg.x or default` would have to repeat the default list.
  local cfg = require("documentation.config").build((opts and opts.root) or default_root(), opts)
  local command_name = cfg.command_name or "DocMap"
  local browse_command_name = cfg.browse_command_name or "DocBrowse"

  local handle = registry.get(cfg.root) or registry.install(cfg)

  ---@type Documentation.Bindings.Ctx
  local ctx = {
    cfg = cfg,
    handle = handle,
    notify = notify,
    command_name = command_name,
    open_map = require("documentation.bindings.usrcmds.open").opener(cfg, notify, command_name),
    find_node = function(ir, name, lua_root)
      return require("documentation.core.find").node(ir, name, lua_root)
    end,
  }

  usercmd.create(command_name, function(args)
    local action = vim.trim(args.args or "")

    -- Empty, and only empty, is the generate action. Anything typed that is
    -- not a known verb is a mistake, and saying so beats writing files.
    if action == "" then
      require("documentation.bindings.usrcmds.generate").run(ctx)
      return
    end

    local verb, rest = action:match("^(%S+)%s*(.-)$")
    local handler = verb and ACTIONS[verb]
    if not handler then
      notify.warn(
        ("Unknown action '%s'. Expected one of: %s  (or no argument to regenerate)."):format(
          verb or action,
          table.concat(action_names(), ", ")
        )
      )
      return
    end

    handler(ctx, rest or "")
  end, {
    nargs = "*",
    desc = "Regenerate the module map (:"
      .. command_name
      .. " [check|full|open|graph|why <a> <b>|dot|diff <ref>|impact <ref>|churn [range]|serve [stop]|helptags])",
    complete = function(lead, line)
      -- Two completion levels: the action, then — once an action that takes a
      -- module is typed — the module paths the map actually knows, which is
      -- the argument nobody wants to type by hand.
      local after_graph = line:match("graph%s+%a*%s+(.*)$") or line:match("graph%s+(%a*)$")
      if line:match("graph%s+%a+%s") or line:match("why%s") or line:match("dot%s+%a+%s") then
        return starting_with(module_names(handle.ir(), cfg.lua_root or "lua"), lead)
      elseif after_graph or line:match("dot%s+%a*$") then
        return starting_with({ "deps", "calls" }, lead)
      end
      return starting_with(action_names(), lead)
    end,
  })

  usercmd.create(browse_command_name, function(args)
    require("documentation.bindings.usrcmds.browse").run(ctx, args.args or "")
  end, {
    nargs = "*",
    desc = ("Browse the module map in the editor (:%s [live] [history|trail|module])"):format(
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
      vim.list_extend(candidates, module_names(handle.ir(), cfg.lua_root or "lua"))
      table.sort(candidates)
      return starting_with(candidates, lead)
    end,
  })

  return handle
end

return M
