---@module 'documentation.bindings.usrcmds.serve'
--- `:DocMap serve [stop]` — the local map server.
---
--- The runtime docmap deliberately did without one until the History tab
--- needed it: a `file://` page cannot fetch, so "compute this commit when I
--- click it" requires an origin, and an origin requires a server. See
--- `editor/serve.lua` for the security and lifecycle rules that come with it.

local M = {}

---@param ctx Documentation.Bindings.Ctx
---@param arg string Everything after "serve" — "" or "stop".
function M.run(ctx, arg)
  local serve = require("documentation.editor.serve")
  local sub = vim.trim(arg or "")

  if sub == "stop" then
    if serve.stop() then
      ctx.notify.info("Map server stopped.")
    else
      ctx.notify.info("No map server was running.")
    end
    return
  end
  if sub ~= "" then
    ctx.notify.warn(("Unknown serve argument '%s' (expected nothing or 'stop')."):format(sub))
    return
  end

  local already = serve.is_running()
  local url, err = serve.start(ctx.cfg)
  if not url then
    ctx.notify.warn("Could not start the map server: " .. tostring(err))
    return
  end
  ctx.notify.info(
    (already and "Map server already running at %s" or "Map server listening at %s"):format(url)
      .. "  (:"
      .. ctx.command_name
      .. " serve stop to close)"
  )
end

return M
