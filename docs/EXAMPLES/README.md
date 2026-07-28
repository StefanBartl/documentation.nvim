# Examples

Runnable snippets for the parts of the API that are easier to understand from
code than from prose. None of these is meant to be `dofile`'d standalone —
paste the body into your config, or into a user command inside a running
Neovim instance.

| Example | Shows |
|---|---|
| [browse.lua](browse.lua) | `:DocBrowse` — navigating the map inside the editor, from the artifact or from a live watching handle, plus every key it binds. |

## The two entry points, side by side

`generate()` is one-shot: scan, write files, done. `install()` is the live half
— a `Documentation.Handle` another plugin's code reaches for directly instead
of parsing `module_map.json` off disk.

```lua
-- One-shot. What :DocMap and the CI/hook CLI use.
local ir, findings, written = require("documentation").generate({
  root = vim.fn.getcwd(),
  source = "lua/myplugin",
  title = "myplugin.nvim",
  out_dir = "docs/map",
  repo_url = "https://github.com/me/my-plugin",
})

-- Live. Nothing is written; the IR stays in memory.
local handle = require("documentation").install({
  root = vim.fn.getcwd(),
  source = "lua/myplugin",
  watch = true,      -- rescan on BufWritePost under source/**.lua, debounced
})

handle.ir()                                  -- current IR
handle.node("lua/myplugin/init.lua")         -- single node lookup
handle.requires("lua/myplugin/fs")           -- require edges out
handle.required_by("lua/myplugin/fs")        -- …and in
handle.callees("lua/myplugin/fs#M.read")     -- "<node id>#<declared name>",
handle.callers("lua/myplugin/fs#M.read")     -- the same ids the HTML map uses

local unsub = handle.on_change(function(ir, findings)
  -- after the initial scan, and after every rescan (manual or watched)
end)

unsub()
handle.uninstall()   -- idempotent; or require("documentation").uninstall(handle)
```

The graph queries live **on the handle** rather than as free functions over an
IR you captured earlier, and that is the point: they answer against whatever
the handle currently holds, including after a watch-triggered rescan.

To start watching a root that is already installed without replacing its
handle, use `registry.ensure_watch(root)` — `install()` treats a collision as
*replace*, which drops every `on_change` subscriber, so upgrading by
re-installing would silently unsubscribe everyone.
