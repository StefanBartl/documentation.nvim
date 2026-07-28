# documentation.nvim — module map

> **Generated** by `documentation`. Do not edit by hand — run `:DocMap`
> (or `nvim --headless -l scripts/gen_map.lua`) to regenerate.

**2 modules** · 1 namespaces · 30 helper files

The [interactive map](index.html) has filtering, full descriptions and
source links; this page is the version the code host renders directly.


## Namespaces

```mermaid
flowchart LR
  nlua_documentation["documentation.nvim"]
  nlua_documentation_browse["browsebr/small`:DocBrowse` — the module map inside the…/small"]
  nlua_documentation_render["render"]
  nlua_documentation --> nlua_documentation_browse
  nlua_documentation --> nlua_documentation_render
```


## Dependencies

Which parts of the tree require which, rolled up to the second level.
The [interactive map](index.html)'s **Deps** view has this per module,
in both directions, with load-time and lazy requires told apart.

```mermaid
flowchart LR
  nlua_documentation_browse_filter_lua["documentation.browse.filter"]
  nlua_documentation_browse_trail_lua["documentation.browse.trail"]
  nlua_documentation_browse_trail_store_lua["documentation.browse.trail_store"]
  nlua_documentation_browse_view_lua["documentation.browse.view"]
  nlua_documentation_render_markdown_lua["documentation.render.markdown"]
  nlua_documentation_render_mermaid_lua["documentation.render.mermaid"]
  nlua_documentation_browse_trail_store_lua --> nlua_documentation_browse_trail_lua
  nlua_documentation_browse_view_lua --> nlua_documentation_browse_filter_lua
  nlua_documentation_render_markdown_lua --> nlua_documentation_render_mermaid_lua
```


## Modules

| Module | Description | Fns | Docs |
|---|---|---|---|
| `documentation.browse` | `:DocBrowse` — the module map inside the editor. | 34 | [README](../../lua/documentation/browse/README.md) · [src](../../lua/documentation/browse/init.lua) |
| `render` |  |  |  |

## Drift

0 errors · 0 warnings · 1 info

No errors or warnings.


<details>
<summary>1 informational findings</summary>


| Check | Message |
|---|---|
| `unreferenced-module` | documentation.health is required by no other file in the tree |

</details>
