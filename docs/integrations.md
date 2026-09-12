# Integrations

Soft-dependency bridges: optional glue to another plugin, off by default,
costing nothing when that plugin is absent.

## Context menu

`documentation.integrations.menu` contributes context-aware entries in the
shape [nvzone/menu](https://github.com/nvzone/menu) expects. documentation.nvim
has **no** dependency on `menu` and never opens a context menu itself; a host —
typically your own `<RightMouse>` dispatcher — composes these entries into its
own menu:

```lua
local items = require("documentation.integrations.menu").items()
-- prepend or append `items` to your own menu table, then menu.open(composed)
```

Entries mirror the `:DocBrowse` list buffer's own key table one-to-one — only
keys applicable in the browser's current mode are offered, so right-click
never shows anything the keyboard does not already provide. Only list-buffer
entries are included; detail-pane keys are excluded because the right-click
trigger lives on the list buffer.
