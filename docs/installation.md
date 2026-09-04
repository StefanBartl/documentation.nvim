# Installation

Every plugin manager, and the one setting that decides which repository a
`:DocMap` acts on. The short version lives in [the README](../README.md); this
page is the complete one.

Requires Neovim 0.10+ (`vim.uv`, `vim.treesitter`) and
[`lib.nvim`](https://github.com/StefanBartl/lib.nvim).

<details open>
<summary><b>lazy.nvim</b></summary>

```lua
{
  "StefanBartl/documentation.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  cmd = { "DocMap", "DocBrowse" },
  opts = {},
}
```
</details>

<details>
<summary><b>vim.pack</b> (Neovim 0.12+, built in)</summary>

```lua
vim.pack.add({
  { src = "https://github.com/StefanBartl/lib.nvim" },
  { src = "https://github.com/StefanBartl/documentation.nvim" },
})

-- No lazy-loading layer here, so do it by hand: create the commands on first
-- use rather than at startup. `setup()` scans the tree, which is not something
-- to pay for in every session that never opens a map.
for _, name in ipairs({ "DocMap", "DocBrowse" }) do
  vim.api.nvim_create_user_command(name, function(a)
    vim.api.nvim_del_user_command("DocMap")
    vim.api.nvim_del_user_command("DocBrowse")
    require("documentation").setup({})
    vim.cmd(("%s %s"):format(name, a.args))
  end, { nargs = "*" })
end
```
</details>

<details>
<summary><b>mini.deps</b></summary>

```lua
local add, later = MiniDeps.add, MiniDeps.later
add({
  source = "StefanBartl/documentation.nvim",
  depends = { "StefanBartl/lib.nvim" },
})
later(function()
  require("documentation").setup({})
end)
```
</details>

<details>
<summary><b>packer.nvim</b></summary>

```lua
use({
  "StefanBartl/documentation.nvim",
  requires = { "StefanBartl/lib.nvim" },
  cmd = { "DocMap", "DocBrowse" },
  config = function()
    require("documentation").setup({})
  end,
})
```
</details>

<details>
<summary><b>paq-nvim</b> / manual <code>rtp</code></summary>

```lua
require("paq")({
  "StefanBartl/lib.nvim",
  "StefanBartl/documentation.nvim",
})

-- paq does no lazy-loading and runs no config hooks:
require("documentation").setup({})
```
</details>

`opts = {}` (or a bare `setup({})`) is enough: with no `root`, the commands
resolve one **per invocation** from the file behind the current buffer — up to
the nearest `.git` — and `documentation.config` derives `source` from it
(`lua/<name>` when `lua/` holds exactly one candidate directory, `lua`
otherwise). Open a file in a sibling checkout and the next `:DocMap` maps that
checkout; both commands name the repository they acted on in their report. Set
`root` explicitly to pin every invocation to one tree instead, which is what a
plugin generating its own map wants.

Whichever manager you use, load it **lazily on the two commands**. `setup()`
scans the tree, and a session that never opens a map should not pay for one.

Nothing registers a command until `setup()` runs — `require("documentation")`
alone never touches the user's editor, so a plugin can embed the pipeline
without also taking the commands.

## Checking that it worked

`:checkhealth documentation` reports the configuration a `:DocMap` issued right
now would act on -- the resolved root, the detected `source`, and how many
files are under it. See [health.md](health.md).
