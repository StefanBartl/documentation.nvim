# documentation.nvim — module map

> **Generated** by `documentation`. Do not edit by hand — run `:DocMap`
> (or `nvim --headless -l scripts/gen_map.lua`) to regenerate.

**2 modules** · 3 namespaces · 32 helper files

The [interactive map](index.html) has filtering, full descriptions and
source links; this page is the version the code host renders directly.


## Namespaces

```mermaid
flowchart LR
  nlua_documentation["documentation.nvim"]
  nlua_documentation_core["core"]
  nlua_documentation_core_render["render"]
  nlua_documentation_editor["editor"]
  nlua_documentation_editor_browse["browsebr/small`:DocBrowse` — the module map inside the…/small"]
  nlua_documentation --> nlua_documentation_core
  nlua_documentation_core --> nlua_documentation_core_render
  nlua_documentation --> nlua_documentation_editor
  nlua_documentation_editor --> nlua_documentation_editor_browse
```


## Dependencies

Which parts of the tree require which, rolled up to the second level.
The [interactive map](index.html)'s **Deps** view has this per module,
in both directions, with load-time and lazy requires told apart.

```mermaid
flowchart LR
  nlua_documentation_core_calls_lua["documentation.core.calls"]
  nlua_documentation_core_check_lua["documentation.core.check"]
  nlua_documentation_core_churn_lua["documentation.core.churn"]
  nlua_documentation_core_cli_lua["documentation.core.cli"]
  nlua_documentation_core_config_lua["documentation.core.config"]
  nlua_documentation_core_coverage_lua["documentation.core.coverage"]
  nlua_documentation_core_deps_lua["documentation.core.deps"]
  nlua_documentation_core_diff_lua["documentation.core.diff"]
  nlua_documentation_core_doccoverage_lua["documentation.core.doccoverage"]
  nlua_documentation_core_find_lua["documentation.core.find"]
  nlua_documentation_core_functions_lua["documentation.core.functions"]
  nlua_documentation_core_history_lua["documentation.core.history"]
  nlua_documentation_core_json_lua["documentation.core.json"]
  nlua_documentation_core_render["render"]
  nlua_documentation_core_scan_lua["documentation.core.scan"]
  nlua_documentation_core_symbols_lua["documentation.core.symbols"]
  nlua_documentation_core_tagfiles_lua["documentation.core.tagfiles"]
  nlua_documentation_editor_browse["documentation.editor.browse"]
  nlua_documentation_editor_command_lua["documentation.editor.command"]
  nlua_documentation_editor_health_lua["documentation.editor.health"]
  nlua_documentation_editor_registry_lua["documentation.editor.registry"]
  nlua_documentation_editor_serve_lua["documentation.editor.serve"]
  nlua_documentation_core_calls_lua --> nlua_documentation_core_deps_lua
  nlua_documentation_core_check_lua --> nlua_documentation_core_deps_lua
  nlua_documentation_core_cli_lua --> nlua_documentation_core_coverage_lua
  nlua_documentation_core_cli_lua --> nlua_documentation_core_doccoverage_lua
  nlua_documentation_core_diff_lua --> nlua_documentation_core_check_lua
  nlua_documentation_core_diff_lua --> nlua_documentation_core_deps_lua
  nlua_documentation_core_doccoverage_lua --> nlua_documentation_core_check_lua
  nlua_documentation_core_doccoverage_lua --> nlua_documentation_core_render
  nlua_documentation_core_find_lua --> nlua_documentation_core_check_lua
  nlua_documentation_core_functions_lua --> nlua_documentation_core_calls_lua
  nlua_documentation_core_functions_lua --> nlua_documentation_core_deps_lua
  nlua_documentation_core_functions_lua --> nlua_documentation_core_scan_lua
  nlua_documentation_core_functions_lua --> nlua_documentation_core_symbols_lua
  nlua_documentation_core_history_lua --> nlua_documentation_core_deps_lua
  nlua_documentation_core_render --> nlua_documentation_core_json_lua
  nlua_documentation_core_scan_lua --> nlua_documentation_core_calls_lua
  nlua_documentation_core_scan_lua --> nlua_documentation_core_deps_lua
  nlua_documentation_core_scan_lua --> nlua_documentation_core_functions_lua
  nlua_documentation_core_symbols_lua --> nlua_documentation_core_scan_lua
  nlua_documentation_core_tagfiles_lua --> nlua_documentation_core_find_lua
  nlua_documentation_editor_browse --> nlua_documentation_core_deps_lua
  nlua_documentation_editor_browse --> nlua_documentation_core_history_lua
  nlua_documentation_editor_browse --> nlua_documentation_editor_command_lua
  nlua_documentation_editor_browse --> nlua_documentation_editor_registry_lua
  nlua_documentation_editor_command_lua --> nlua_documentation_core_check_lua
  nlua_documentation_editor_command_lua --> nlua_documentation_core_churn_lua
  nlua_documentation_editor_command_lua --> nlua_documentation_core_config_lua
  nlua_documentation_editor_command_lua --> nlua_documentation_core_deps_lua
  nlua_documentation_editor_command_lua --> nlua_documentation_core_diff_lua
  nlua_documentation_editor_command_lua --> nlua_documentation_core_find_lua
  nlua_documentation_editor_command_lua --> nlua_documentation_core_history_lua
  nlua_documentation_editor_command_lua --> nlua_documentation_editor_browse
  nlua_documentation_editor_command_lua --> nlua_documentation_editor_registry_lua
  nlua_documentation_editor_command_lua --> nlua_documentation_editor_serve_lua
  nlua_documentation_editor_health_lua --> nlua_documentation_core_config_lua
  nlua_documentation_editor_serve_lua --> nlua_documentation_core_history_lua
  nlua_documentation_editor_serve_lua --> nlua_documentation_editor_browse
```


## Modules

| Module | Description | Fns | Docs |
|---|---|---|---|
| `core` |  |  |  |
| &nbsp;&nbsp;`render` |  |  |  |
| `editor` |  |  |  |
| &nbsp;&nbsp;`documentation.editor.browse` | `:DocBrowse` — the module map inside the editor. | 34 | [README](../../lua/documentation/editor/browse/README.md) · [src](../../lua/documentation/editor/browse/init.lua) |

## Drift

0 errors · 0 warnings · 1 info

No errors or warnings.


<details>
<summary>1 informational findings</summary>


| Check | Message |
|---|---|
| `unreferenced-module` | documentation.editor.health is required by no other file in the tree |

</details>
