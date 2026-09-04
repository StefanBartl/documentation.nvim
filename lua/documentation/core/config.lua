---@module 'documentation.core.config'
--- **Deprecated alias** for [`documentation.config`](../config/init.lua).
---
--- The defaults and the merge rule moved out of `core/` when the config and
--- bindings layers were split out: `documentation.core` is the pipeline (scan
--- → check → render), and the option table is read by the pipeline, the editor
--- half and the command layer alike. A base every layer depends on is not part
--- of any one of them.
---
--- Kept because it is a *published* entry point — `docs/reuse.md` documents
--- `require("documentation.core.config").build(root, {…})` as the way an
--- embedding plugin pins its own layout, and silently breaking that to tidy a
--- directory would be a poor trade. Re-exports the module itself, metatable
--- included, so `.build(…)` and the callable `config(root)` form both behave
--- exactly as before.
---
--- New code should require `documentation.config`.

return require("documentation.config")
