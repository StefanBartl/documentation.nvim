---@meta
---@module 'documentation.testing.@types'
--- The shapes of the affected-selection contract (`docs/testing-contract.md`,
--- `docs/affected-specs.schema.json`). Version 1.

---One reported hole in what the graph can tell. A consumer must treat a
---`blocking` gap as "do not trust a narrowed selection".
---@class Documentation.Testing.Gap
---@field kind "changed_not_in_graph"|"changed_module_without_spec"|"test_support_changed"|"spec_unplaced"|"spec_unreadable"|"invalid_path"|"invalid_spec_root"
---@field path? string Repository-relative file the gap is about.
---@field module? string Module path (`a.b.c`) when the gap is about a module.
---@field reason? string `spec_unplaced`: `dynamic_require` or `no_graph_module`.
---@field message string One English sentence for a human.

---Freshness of the module map the answer was computed from.
---@class Documentation.Testing.Graph
---@field version integer Contract version (1).
---@field map string Repository-relative path of the map file.
---@field generated_at? string ISO 8601 UTC; the commit time of the map, the file's mtime when it is uncommitted.
---@field commit? string Full sha of the newest commit touching the map file; nil when uncommitted.
---@field head? string Full sha of HEAD; nil outside a repository.
---@field stale boolean The code changed after the map was written (or the age cannot be established).
---@field stale_reason? string Why `stale` is true.
---@field verified? boolean true when `stale` was settled by a rescan (`verify = true`): the graph of the map equals the graph of a scan of the tree as it is now.
---@field cross_repo_note? string Set when a consumers directory was given but could not be looked at.
---@field dirty boolean The source tree has uncommitted changes (informational: the map cannot know them).
---@field gaps Documentation.Testing.Gap[] Same list as `Result.gaps`.

---@class Documentation.Testing.Module
---@field id string Node id in the map.
---@field module? string Module path.
---@field path string Repository-relative path of the node.
---@field role "changed"|"dependent" A changed module, or one that (transitively) requires one.
---@field specs string[] Spec files that cover this module (directly or through the graph).

---@class Documentation.Testing.CrossRepo
---@field repo string Directory name of the consumer checkout.
---@field measured boolean false: the consumer could not be analysed (`reason` says why).
---@field reason? string When `measured` is false.
---@field stale? boolean The consumer's own map is older than its code.
---@field specs? string[] Spec files of the consumer, relative to the consumer's root.
---@field unplaced_specs? string[] Spec files of the consumer that cannot be placed in its graph.
---@field modules? string[] Consumer modules (ids) affected.
---@field uncovered? boolean The consumer is affected but has no spec that covers it.

---@class Documentation.Testing.Result
---@field version integer Contract version (1).
---@field specs string[] Spec files to run, repository-relative, sorted.
---@field modules Documentation.Testing.Module[] Changed modules and their transitive dependents.
---@field unplaced_specs string[] Specs the graph cannot place (dynamic `require`, or none of their requires is in the map): never provably unaffected, run them.
---@field ignored string[] Changed files that cannot affect a spec (documentation, assets, data).
---@field complete boolean true when a narrowed selection can be trusted: the map is fresh and no blocking gap exists.
---@field graph Documentation.Testing.Graph
---@field cross_repo Documentation.Testing.CrossRepo[]

---Per-module spec data for the map.
---@class Documentation.Testing.NodeState
---@field specs string[] Specs that require this module directly (at most `MAX_SPECS_PER_NODE`).
---@field spec_count integer All direct specs.
---@field indirect_count integer Specs that only reach it through the graph.
---@field last_status? string Worst status of the direct specs in the last run, when one is known.

---@class Documentation.Testing.SpecState
---@field version integer
---@field nodes table<string, Documentation.Testing.NodeState> Per node id; only nodes with a module path.
---@field totals { modules: integer, with_specs: integer, indirect_only: integer, without_specs: integer }
---@field status { source?: string, kind?: string, ts?: integer }
---@field notes string[]

---@class Documentation.Testing.SpecInfo
---@field path string
---@field modules string[]
---@field prefixes string[]
---@field dynamic boolean
---@field unreadable? string

return {}
