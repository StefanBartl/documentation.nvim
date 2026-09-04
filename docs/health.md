# Health

What `:checkhealth documentation` asks, and why the interesting half is not the
dependency list.

```vim
:checkhealth documentation
```

Checks the dependencies and the treesitter Lua parser, and then the part worth
running it for: the configuration a `:DocMap` issued right now would act on —
the resolved root, the auto-detected `source`, how many `.lua` files are
actually under it, and whether the committed map has fallen behind the sources.

It closes with the external tools declared in
[`docs/install.json`](install.json) — here just `lua-language-server`,
which the opt-in `luals` enrichment pass shells out to. `:Lib deps show
documentation.nvim` reports the same thing on its own, and `:Lib deps install
documentation.nvim` offers to install what is missing, via
[lib.nvim.deps](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/deps/README.md)
— which asks before it installs anything. A popup shows this once, the first
time `setup()` runs after installing; `vim.g.lib_nvim_deps_disable_first_run =
true` (every plugin) or `vim.g.lib_nvim_deps_disabled_plugins = {
"documentation.nvim" }` (just this one) turns it off.

With no `root` set, `:DocMap` resolves one from the current buffer, so "it
mapped the wrong repository" and "it says my tree has one module" are the same
mistake seen from two angles. The command's report names the repository it
acted on; this check shows the same answer before anything is written.
