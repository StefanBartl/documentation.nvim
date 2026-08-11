---@module 'documentation.core.api'
--- The answers behind the generated page's `/api/*` routes, as plain Lua
--- tables — no sockets, no HTTP, no editor.
---
--- ## Why this is separate from `editor/serve.lua`
---
--- Because there is now more than one host. `editor/serve.lua` answers these
--- routes from inside Neovim; `docmap-desktop` answers them from a Rust HTTP
--- server that shells out to the standalone binary. Those are two transports
--- for one set of answers, and the join logic (`telemetry_join`,
--- `loaded_diff`) must exist exactly once or the two hosts will drift into
--- disagreeing about the same project — the expensive failure, since both
--- would look like they were working.
---
--- So: the *answers* live here, in `core/`, reachable from the standalone
--- build. The *transport* stays with each host. `editor/serve.lua` keeps its
--- socket, its security checks and its response encoding; it just stopped
--- computing the bodies itself.
---
--- ## The shape every route returns
---
--- A table, always, never `nil` and never an error for "there is nothing to
--- show". Absence answers `{ available = false, reason = "..." }` — the
--- posture `telemetry_join.lua` insists on everywhere else and the reason the
--- panels can stay visible instead of being hidden when a project has no
--- data. A panel that says *why* it is empty beats one that is silently
--- blank, and beats one that is missing entirely.

local M = {}

---@param opts table A resolved `Documentation.Opts`.
---@return Documentation.IR|nil
local function current_ir(opts)
  return require("documentation.core.artifact").load(opts)
end

---Percent-decode one query-string value.
---
---**`+` first, `%XX` second.** `%2B` is the encoding of a literal `+`, so
---percent-decoding first produces a `+` that the plus-expansion then
---corrupts into a space — a name containing a real `+` comes back wrong and
---the snapshot silently "does not exist". Expanding `+` first is the
---standard `application/x-www-form-urlencoded` order and leaves the decoded
---`+` untouched, because nothing looks at it again.
---
---This is the order `editor/serve.lua` documented and, until this moved
---here and got a test, did not implement — it decoded `%XX` first. Found by
---`TESTS/api_spec.lua`, not by reading it; the comment above the old code
---described the correct property convincingly enough to survive several
---readings.
---@param raw string|nil
---@return string|nil
function M.decode_param(raw)
  if type(raw) ~= "string" or raw == "" then
    return nil
  end
  return (
    raw:gsub("%+", " "):gsub("%%(%x%x)", function(h)
      return string.char(tonumber(h, 16))
    end)
  )
end

---`/api/telemetry` — the `runtime-analysis.telemetry` join for the
---Analysis → Telemetry panel.
---
---No `snapshot`: the live/latest aggregate. With one: that exact named
---capture instead. Nothing here touches git — telemetry is not a revision,
---it is "whatever this namespace's counts are right now", read straight off
---disk on every call, which is why no live Neovim instance is required and
---why this can answer from the standalone build at all.
---@param opts table
---@param snapshot string|nil Already decoded.
---@return table
function M.telemetry(opts, snapshot)
  local telemetry_join = require("documentation.core.telemetry_join")

  local namespace = telemetry_join.namespace(opts)
  if not namespace then
    return { available = false, reason = "no namespace" }
  end

  local ir = current_ir(opts)
  if not ir then
    return { available = false, namespace = namespace, reason = "no map generated yet" }
  end

  local data
  if snapshot and snapshot ~= "" then
    local ok_telemetry, telemetry = pcall(require, "runtime-analysis.telemetry")
    if not ok_telemetry then
      return { available = false, namespace = namespace, reason = "no data" }
    end
    local ok_load, snap = pcall(telemetry.load_snapshot, namespace, snapshot)
    data = ok_load and snap or nil
    if not data then
      return {
        available = false,
        namespace = namespace,
        snapshot = snapshot,
        reason = "snapshot not found",
      }
    end
  else
    data = telemetry_join.load(namespace)
    if not data then
      return { available = false, namespace = namespace, reason = "no data" }
    end
  end

  return {
    available = true,
    namespace = namespace,
    snapshot = snapshot,
    rows = telemetry_join.rows(ir, data),
  }
end

---`/api/telemetry/snapshots` — every named snapshot for this project's
---telemetry namespace, newest first. What the panel's picker populates from.
---@param opts table
---@return table
function M.telemetry_snapshots(opts)
  local telemetry_join = require("documentation.core.telemetry_join")

  local namespace = telemetry_join.namespace(opts)
  if not namespace then
    return { available = false, reason = "no namespace" }
  end

  local ok_telemetry, telemetry = pcall(require, "runtime-analysis.telemetry")
  if not ok_telemetry then
    return { available = false, namespace = namespace, snapshots = {} }
  end

  local ok_list, list = pcall(telemetry.list_snapshots, namespace)
  return { available = true, namespace = namespace, snapshots = (ok_list and list) or {} }
end

---`/api/loaded` — the `runtime-analysis.loaded` persisted-snapshot join for
---the Analysis → Loaded panel.
---
---Unlike telemetry, `snapshot` is **required**: there is no "live aggregate"
---reading here. The live path is `loaded_diff.rows(ir)`, which needs the
---running process's own `package.loaded` and is what `:DocBrowse loaded`
---reads directly. This route exists for the *cold* case a live browse mode
---structurally cannot serve.
---@param opts table
---@param snapshot string|nil Already decoded.
---@return table
function M.loaded(opts, snapshot)
  local loaded_diff = require("documentation.core.loaded_diff")

  local ir = current_ir(opts)
  if not ir then
    return { available = false, reason = "no map generated yet" }
  end

  local prefix = loaded_diff.prefix(opts)
  if not prefix then
    return { available = false, reason = "no single root module prefix for this tree" }
  end

  if not snapshot or snapshot == "" then
    return { available = false, prefix = prefix, reason = "no snapshot named" }
  end

  local ok_loaded, loaded_mod = pcall(require, "runtime-analysis.loaded")
  if not ok_loaded then
    return { available = false, prefix = prefix, reason = "no data" }
  end

  local ok_load, snap = pcall(loaded_mod.load_snapshot, prefix, snapshot)
  if not ok_load or not snap then
    return {
      available = false,
      prefix = prefix,
      snapshot = snapshot,
      reason = "snapshot not found",
    }
  end

  return {
    available = true,
    prefix = prefix,
    snapshot = snapshot,
    captured_at = snap.captured_at,
    rows = loaded_diff.rows_from_snapshot(ir, snap),
  }
end

---`/api/loaded/snapshots` — every named `runtime-analysis.loaded` snapshot
---for this project's root prefix, newest first.
---@param opts table
---@return table
function M.loaded_snapshots(opts)
  local loaded_diff = require("documentation.core.loaded_diff")

  local prefix = loaded_diff.prefix(opts)
  if not prefix then
    return { available = false, reason = "no single root module prefix for this tree" }
  end

  local ok_loaded, loaded_mod = pcall(require, "runtime-analysis.loaded")
  if not ok_loaded then
    return { available = false, prefix = prefix, snapshots = {} }
  end

  local ok_list, list = pcall(loaded_mod.list_snapshots, prefix)
  return { available = true, prefix = prefix, snapshots = (ok_list and list) or {} }
end

---Every route this module answers, by the path segment that names it.
---
---Exported as data rather than left implicit in a dispatch chain so both
---hosts enumerate the same set — the standalone CLI validates `--api=<name>`
---against it, and a name added here reaches every host without either one
---having to be told separately.
---@type table<string, fun(opts: table, param: string|nil): table>
M.routes = {
  telemetry = M.telemetry,
  ["telemetry/snapshots"] = M.telemetry_snapshots,
  loaded = M.loaded,
  ["loaded/snapshots"] = M.loaded_snapshots,
}

---Answer one route by name.
---@param name string
---@param opts table
---@param param string|nil Route-specific parameter (the snapshot name, where one applies).
---@return table|nil result
---@return string|nil err Set only when `name` is not a route.
function M.answer(name, opts, param)
  local route = M.routes[name]
  if not route then
    local names = {}
    for k in pairs(M.routes) do
      names[#names + 1] = k
    end
    table.sort(names)
    return nil, ("no such route: %s (have: %s)"):format(tostring(name), table.concat(names, ", "))
  end
  return route(opts, param), nil
end

return M
