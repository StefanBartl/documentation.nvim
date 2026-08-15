---@module 'documentation.bindings.usrcmds.generate_all'
--- `:DocMap all [full]` / `:DocMapAll` / `:DocMapAllFull` —
--- `documentation.generate_all.run()` (one real headless Neovim subprocess
--- per project, chained sequentially, never blocking this session) driven
--- by `opts.generate_all.projects`.
---
--- Opt-in, and deliberately generic: `opts.generate_all` is plain data a
--- caller's own plugin spec supplies (`{ projects = {{root=..., title=...}, ...} }`)
--- — this file, like the rest of `documentation.nvim`, has no notion of
--- "which repos a consumer's config manages" and never reads one. Neither
--- action is registered at all when `opts.generate_all.projects` is empty
--- or absent — see `usrcmds/init.lua`'s own `setup()`.
---
--- **`full` (2026-08-15): fast by default, LuaLS enrichment on request.**
--- Before this parameter existed, every subprocess this module spawned
--- always ran with `luals = true` — the single-repo `:DocMap` vs `:DocMap
--- full` distinction never applied to the bulk path at all. Splitting it
--- the same way here means `:DocMapAll` across two dozen repositories no
--- longer pays LuaLS's per-repo cost (seconds each) when a plain scan is
--- all that was wanted; `:DocMapAll full` / `:DocMapAllFull` opts back into
--- the old always-enriched behavior explicitly.

local M = {}

---@param ctx Documentation.Bindings.Ctx
---@param full boolean? LuaLS enrichment for every project this run — default false (fast). `:DocMapAllFull`/`:DocMap all full` pass true.
function M.run(ctx, full)
  local cfg = ctx.generate_all
  if not cfg or not cfg.projects or #cfg.projects == 0 then
    ctx.notify.warn("opts.generate_all.projects is not configured -- nothing to generate for")
    return
  end

  local docmap = require("documentation")
  local total = #cfg.projects
  local progress = require("documentation.bindings.progress").create(ctx, "generating maps", total)

  ctx.notify.info(
    ("Generating %d project map(s) asynchronously%s..."):format(
      total,
      full and " (full: LuaLS enrichment)" or ""
    )
  )
  docmap.generate_all.run(cfg.projects, {
    luals = full == true,
    on_progress = function(index, index_total, project)
      if progress then
        progress:update({ text = project.title, current = index, total = index_total })
      end
    end,
    on_done = function(results)
      ---@type string[]
      local failed = {}
      for _, r in ipairs(results) do
        if not r.ok then
          failed[#failed + 1] = r.project.title .. ": " .. tostring(r.err)
        end
      end

      if progress then
        progress:finish(("%d/%d generated"):format(total - #failed, total))
      end

      if #failed > 0 then
        ctx.notify.error("Finished with errors:\n\n" .. table.concat(failed, "\n\n"))
      else
        ctx.notify.info(("All %d project map(s) generated"):format(total))
      end
    end,
  })
end

---Check every configured project for an already-written module map, and
---generate (async, non-blocking) only the ones missing. Called once from
---`usrcmds.setup()` when `opts.generate_all.autoload` is true — see that
---field's own doc-comment for why this is opt-in, never inferred.
---@param cfg Documentation.GenerateAllOpts
---@param notify table `lib.nvim.notify` instance
function M.autoload(cfg, notify)
  if not cfg.projects or #cfg.projects == 0 then
    return
  end

  ---@type Documentation.GenerateAll.Project[]
  local missing = {}
  for _, project in ipairs(cfg.projects) do
    -- Through `config.build`, not a hardcoded "docs/map/module_map.json":
    -- a project pinning its own `out_dir` must be checked at that path, not
    -- the default one it deliberately opted out of.
    local resolved = require("documentation.config").build(project.root, { title = project.title })
    local map_path = resolved.root .. "/" .. resolved.out_dir .. "/module_map.json"
    if vim.fn.filereadable(map_path) == 0 then
      missing[#missing + 1] = project
    end
  end

  if #missing == 0 then
    return
  end

  notify.info(("Generating %d project map(s) that do not exist yet..."):format(#missing))
  require("documentation").generate_all.run(missing, {
    on_done = function(results)
      ---@type string[]
      local failed = {}
      for _, r in ipairs(results) do
        if not r.ok then
          failed[#failed + 1] = r.project.title .. ": " .. tostring(r.err)
        end
      end
      if #failed > 0 then
        notify.error("Autoload finished with errors:\n\n" .. table.concat(failed, "\n\n"))
      else
        notify.info(("Autoload: generated %d missing project map(s)"):format(#missing))
      end
    end,
  })
end

return M
