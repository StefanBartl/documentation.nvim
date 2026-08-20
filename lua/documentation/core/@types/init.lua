---@meta
---@module 'documentation.core.@types'
--- Types produced by the `documentation.core` pipeline's *analysis* stages.
---
--- The IR itself — `Documentation.Opts`, `Documentation.IR`,
--- `Documentation.Node`, `Documentation.Finding` and everything they carry —
--- lives one level up in [`documentation/@types`](../../@types/init.lua),
--- because every layer reads it. What is here is narrower: the result shapes
--- of the analyses that run *over* an IR and are consumed by exactly one
--- renderer or command each.
---
--- Both are pure `ir -> result` functions with no filesystem and no git, which
--- is what lets them be driven from a headless spec. See `churn.lua` and
--- `duplicates.lua` for the reasoning behind the scoring in each.

-- ── churn.lua ───────────────────────────────────────────────────────────────

---One ranked module.
---@class Documentation.Churn.Entry
---@field node string Node id.
---@field module string? Declared `@module`, when it has one.
---@field source string? Repo-relative source path — what the commit count was counted against.
---@field commits integer Commits touching this module's source in the range.
---@field complexity integer Summed cyclomatic complexity of its documented functions.
---@field score integer `commits * complexity`.
---@field hottest string? Signature of its single most complex function — where to actually start reading.
---@field calls integer? Calls recorded for this module's functions on **this machine**, or `nil` when no telemetry was passed to `rank`. `nil` and `0` are different answers: nobody measured, versus measured and saw nothing.
---@field calls_recent integer? Of those, the ones in the last `telemetry_join.RECENT_DAYS` days. `nil` under the same rule.

---@class Documentation.Churn.Result
---@field entries Documentation.Churn.Entry[] Highest score first; ties by commits, then node id.
---@field commits integer Distinct commits seen in the range.
---@field unmatched integer Files that changed but back no scanned module — deleted files, docs, CI config.

-- ── duplicates.lua ──────────────────────────────────────────────────────────

---One group of structurally identical functions.
---@class Documentation.Duplicates.Group
---@field shape string The fingerprint they share.
---@field size integer Node count of the shared shape.
---@field members Documentation.Duplicates.Member[] At least two, sorted by node id then function name.

---@class Documentation.Duplicates.Member
---@field node string Node id the function is declared in.
---@field module string? The node's declared `@module`, when it has one.
---@field name string Qualified function name, e.g. "M.read".
---@field signature string
---@field line integer

---@class Documentation.Duplicates.Result
---@field groups Documentation.Duplicates.Group[] Largest group first, then by shape size, then by fingerprint.
---@field functions integer How many functions sit in some group.
---@field considered integer How many functions were large enough to compare at all.
---@field min_size integer The floor that was applied, so a reader can tell "nothing found" from "nothing looked at".

return {}
