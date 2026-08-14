# documentation.nvim — module map

> **Generated** by `documentation`. Do not edit by hand — run `:DocMap`
> (or `nvim --headless -l scripts/gen_map.lua`) to regenerate.

**5 modules** · 6 namespaces · 84 helper files

The [interactive map](index.html) has filtering, full descriptions and
source links; this page is the version the code host renders directly.


## Namespaces

```mermaid
flowchart LR
  nlua["documentation.nvim"]
  nlua_documentation["documentationbr/smalldocumentation.nvim: generated module map./small"]
  nlua_documentation_bindings["bindings"]
  nlua_documentation_config["configbr/smallResolving a full `Documentation.Opts` for a…/small"]
  nlua_documentation_core["core"]
  nlua_documentation_editor["editor"]
  nlua_documentation_mcp["mcpbr/smallAn MCP (Model Context Protocol) server…/small"]
  nlua --> nlua_documentation
  nlua_documentation --> nlua_documentation_bindings
  nlua_documentation --> nlua_documentation_config
  nlua_documentation --> nlua_documentation_core
  nlua_documentation --> nlua_documentation_editor
  nlua_documentation --> nlua_documentation_mcp
```


## Dependencies

Which parts of the tree require which, rolled up to the second level.
The [interactive map](index.html)'s **Deps** view has this per module,
in both directions, with load-time and lazy requires told apart.

```mermaid
flowchart LR
  nlua_documentation_bindings["bindings"]
  nlua_documentation_config["documentation.config"]
  nlua_documentation_core["core"]
  nlua_documentation_editor["editor"]
  nlua_documentation_mcp["documentation.mcp"]
  nlua_documentation_bindings --> nlua_documentation_config
  nlua_documentation_bindings --> nlua_documentation_core
  nlua_documentation_bindings --> nlua_documentation_editor
  nlua_documentation_core --> nlua_documentation_config
  nlua_documentation_editor --> nlua_documentation_bindings
  nlua_documentation_editor --> nlua_documentation_config
  nlua_documentation_editor --> nlua_documentation_core
  nlua_documentation_mcp --> nlua_documentation_core
```


## Modules

| Module | Description | Fns | Docs |
|---|---|---|---|
| `documentation` | documentation.nvim: generated module map. | 10 | [README](../../lua/documentation/README.md) · [src](../../lua/documentation/init.lua) |
| &nbsp;&nbsp;`bindings` |  |  |  |
| &nbsp;&nbsp;&nbsp;&nbsp;`documentation.bindings.usrcmds` | The user commands: `:DocMap` and `:DocBrowse` — registration, argument dispatch and completion. | 6 | [README](../../lua/documentation/bindings/usrcmds/README.md) · [src](../../lua/documentation/bindings/usrcmds/init.lua) |
| &nbsp;&nbsp;`documentation.config` | Resolving a full `Documentation.Opts` for a repository: the defaults in [`DEFAULTS.lua`](DEFAULTS.lua), what can be derived from `root`, and the merge rule… | 2 | [README](../../lua/documentation/config/README.md) · [src](../../lua/documentation/config/init.lua) |
| &nbsp;&nbsp;`core` |  |  | [README](../../lua/documentation/core/README.md) |
| &nbsp;&nbsp;&nbsp;&nbsp;`lang` |  |  |  |
| &nbsp;&nbsp;&nbsp;&nbsp;`render` |  |  |  |
| &nbsp;&nbsp;`editor` |  |  | [README](../../lua/documentation/editor/README.md) |
| &nbsp;&nbsp;&nbsp;&nbsp;`documentation.editor.browse` | `:DocBrowse` — the module map inside the editor. | 37 | [README](../../lua/documentation/editor/browse/README.md) · [src](../../lua/documentation/editor/browse/init.lua) |
| &nbsp;&nbsp;`documentation.mcp` | An MCP (Model Context Protocol) server exposing this repository's module map to a coding agent. | 1 | [src](../../lua/documentation/mcp/init.lua) |

## Drift

0 errors · 1 warnings · 10 info

| Severity | Check | Message |
|---|---|---|
| warn | `doc-references-missing` | docs/ROADMAP/IDEAS/IDEAS.md:105 references 'documentation.core.scan.something', but documentation.core.scan has no 'something' |

<details>
<summary>10 informational findings</summary>


| Check | Message |
|---|---|
| `missing-readme` | lua/documentation/mcp has no README.md |
| `undocumented-param` | complexity has 3 parameter(s) but only 2 @param line(s) |
| `unreferenced-module` | documentation.bindings.docs is required by no other file in the tree |
| `unreferenced-module` | documentation.core.config is required by no other file in the tree |
| `unreferenced-module` | documentation.core.lang.js is required by no other file in the tree |
| `unreferenced-module` | documentation.core.lang.lua is required by no other file in the tree |
| `unreferenced-module` | documentation.core.lang.ts is required by no other file in the tree |
| `unreferenced-module` | documentation.core.lang.tsx is required by no other file in the tree |
| `unreferenced-module` | documentation.editor.health is required by no other file in the tree |
| `unreferenced-module` | documentation.mcp is required by no other file in the tree |

</details>
