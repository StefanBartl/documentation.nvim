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

---A commit-ish the caller supplied, or nil if it is not one.
---
---Whitelist, deliberately not an escape or a quoting helper: the value is
---about to become an argument to a subprocess, and the only safe answer to
---"is this a sha" is a shape check that rejects everything else — including
---the `--upload-pack=…`-style arguments that make argument injection into git
---interesting in the first place. Even `HEAD` is refused: it is a perfectly
---good revision but not what this route accepts, and a whitelist that starts
---making exceptions stops being one.
---
---Moved here from `editor/serve.lua` unchanged: it is this module's
---security property now, not that transport's — every caller that turns a
---request into a sha (this file's own `M.answer`, and `docmap-desktop`'s
---`server.rs` before it ever reaches the standalone binary) goes through it.
---Exported for the same reason it always was: a security property that
---cannot be tested without exercising it does not get tested.
---@param s string
---@return string|nil
function M.safe_sha(s)
  return (type(s) == "string" and s:match("^%x%x%x%x%x%x%x+$") and #s <= 40) and s or nil
end

---Read a committed artifact and rehydrate it into an IR, via the host's own
---`git` function.
---
---Absence is a normal outcome, not an error: a revision older than the map
---itself simply has none, and `history.analyze` accepts `nil` for exactly
---that reason.
---@param opts table
---@param rev string Already validated.
---@return Documentation.IR|nil
local function ir_at(opts, rev)
  local rel = (opts.out_dir or "docs/map") .. "/module_map.json"
  local out = opts.git(opts, { "show", ("%s:%s"):format(rev, rel) })
  if not out or out == "" then
    return nil
  end
  local ir = require("documentation.core.artifact").decode(out)
  return ir
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
    local telemetry = require("documentation.core.soft_require").probe("runtime-analysis.telemetry")
    if not telemetry then
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

  local telemetry = require("documentation.core.soft_require").probe("runtime-analysis.telemetry")
  if not telemetry then
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

  local loaded_mod = require("documentation.core.soft_require").probe("runtime-analysis.loaded")
  if not loaded_mod then
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

  local loaded_mod = require("documentation.core.soft_require").probe("runtime-analysis.loaded")
  if not loaded_mod then
    return { available = false, prefix = prefix, snapshots = {} }
  end

  local ok_list, list = pcall(loaded_mod.list_snapshots, prefix)
  return { available = true, prefix = prefix, snapshots = (ok_list and list) or {} }
end

---`/api/checklist` — the staleness verdict for the Analysis → Checklist
---panel.
---
---The panel's *content* is baked into the page, unlike Telemetry's: a
---ledger is parsed Markdown and `ir.checklist` carries it. What cannot be
---baked is exactly this — whether the cited files have moved since the
---items were verified — because it comes from `git log`, and
---`core/churn.lua` already established that git data in a byte-compared
---artifact leaves the map with no fixed point.
---@param opts table Needs `opts.git`, a `(opts, args) -> stdout|nil, err|nil` function the host supplies.
---@return table
function M.checklist(opts)
  local ir = current_ir(opts)
  if not ir then
    return { available = false, reason = "no map generated yet" }
  end

  local ledger = ir.checklist
  if not ledger then
    return { available = false, reason = "this repository has no checklist" }
  end

  if not opts.git then
    return { available = false, reason = "no git access configured" }
  end
  local out, err = opts.git(opts, {
    "log",
    "--no-merges",
    "--format=%x1e%cs",
    "--name-only",
    "--",
    ".",
    (":(exclude)%s"):format(opts.out_dir or "docs/map"),
  })
  if not out then
    return { available = false, reason = err or "git log failed" }
  end

  local checklist = require("documentation.core.checklist")
  local statuses = checklist.status(ledger, checklist.parse_history(out))

  -- Keyed by `file:line`, not sent as an array: the page already holds
  -- every item from the baked ledger and only needs the verdict to attach
  -- to each one. Sending the items back would duplicate what the page has
  -- and make the two copies able to disagree.
  local by_key, counts = {}, { stale = 0, unverified = 0, uncited = 0, current = 0 }
  for _, status in ipairs(statuses) do
    by_key[("%s:%d"):format(status.item.file, status.item.line)] = {
      state = status.state,
      commits = status.commits,
      last_commit = status.last_commit,
    }
    counts[status.state] = (counts[status.state] or 0) + 1
  end

  return { available = true, counts = counts, status = by_key }
end

---`/api/commits`, `param` an optional commit count — the list the History
---tab opens with.
---@param opts table Needs `opts.git`.
---@param param string|nil Decimal count, default 50, clamped to [1, 500].
---@return table
function M.commits(opts, param)
  if not opts.git then
    return { available = false, reason = "no git access configured" }
  end
  local n = tonumber(param) or 50
  n = math.max(1, math.min(n, 500))

  -- Unit/record separators rather than a printable delimiter: a commit
  -- subject can contain anything, including whatever character looked safe.
  local fmt = "%H\31%h\31%an\31%ad\31%s\30"
  local out, err = opts.git(opts, { "log", "-n", tostring(n), "--date=short", "--format=" .. fmt })
  if not out then
    return { available = false, reason = err or "git log failed" }
  end

  local commits = {}
  for record in out:gmatch("([^\30]+)") do
    local rec = vim.trim(record)
    if rec ~= "" then
      local f = vim.split(rec, "\31", { plain = true })
      if #f >= 5 then
        commits[#commits + 1] =
          { sha = f[1], short = f[2], author = f[3], date = f[4], subject = f[5] }
      end
    end
  end

  return { available = true, commits = commits }
end

---`/api/commit/<sha>` — the analysis for one commit, plus its diff text.
---@param opts table Needs `opts.git`.
---@param sha string Already validated by the caller (`M.safe_sha`).
---@return table
function M.commit(opts, sha)
  if not opts.git then
    return { available = false, reason = "no git access configured" }
  end
  local out_dir = opts.out_dir or "docs/map"

  local meta, meta_err = opts.git(opts, {
    "show",
    "-s",
    "--date=short",
    "--format=%H\31%h\31%an\31%ad\31%s\31%b",
    sha,
  })
  if not meta then
    return { available = false, reason = meta_err or "no such commit" }
  end
  local mf = vim.split(vim.trim(meta), "\31", { plain = true })

  -- `git show` rather than `git diff <sha>^ <sha>`: it produces the same
  -- diff and additionally handles the root commit, which has no parent to
  -- name. The out_dir exclusion is not cosmetic — measured in
  -- `editor/serve.lua`'s own history, one commit's full diff was 4.8 MB of
  -- which all but ~16 KB was the regenerated map.
  local diff_text, diff_err = opts.git(opts, {
    "show",
    "--unified=0",
    "--format=",
    sha,
    "--",
    ".",
    (":(exclude)%s"):format(out_dir),
  })
  if not diff_text then
    return { available = false, reason = diff_err or "git show failed" }
  end

  local ir_after = ir_at(opts, sha)
  -- A root commit has no parent; `git show` above already handled that,
  -- and here the absent parent IR is simply nil, which `analyze` accepts.
  local ir_before = ir_at(opts, sha .. "^")

  local history = require("documentation.core.history")
  local impact = history.analyze(diff_text, ir_after, ir_before)

  -- Module display names are resolved here rather than in the browser: the
  -- page has the *current* IR embedded, and a commit can name nodes that
  -- no longer exist, so only this side can label them correctly.
  local names = {}
  local function name_of(id)
    if names[id] then
      return names[id]
    end
    local n = ir_after and ir_after.nodes[id]
    names[id] = (n and (n.module or n.path)) or id
    return names[id]
  end
  for _, t in ipairs(impact.touched) do
    name_of(t.node)
    for _, c in ipairs(impact.callers[t.node .. "#" .. t.fn] or {}) do
      name_of(c.node)
    end
  end
  for _, id in ipairs(impact.calling_modules) do
    name_of(id)
  end
  for _, id in ipairs(impact.impacted_modules) do
    name_of(id)
  end

  return {
    available = true,
    commit = {
      sha = mf[1] or sha,
      short = mf[2] or sha:sub(1, 7),
      author = mf[3] or "",
      date = mf[4] or "",
      subject = mf[5] or "",
      body = vim.trim(mf[6] or ""),
    },
    impact = impact,
    names = names,
    diff = diff_text,
    -- Said explicitly rather than inferred from an empty list: "the map
    -- did not exist yet at this revision" and "this commit touched no
    -- function" are different answers and the UI must not merge them.
    has_map = ir_after ~= nil,
  }
end

---Every fixed-name route this module answers, by the path segment that
---names it. `commit/<sha>` is not in here — see `M.answer` — because its
---name is parametrised by the sha itself, not fixed.
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
  checklist = M.checklist,
  commits = M.commits,
}

---Answer one route by name.
---@param name string
---@param opts table
---@param param string|nil Route-specific parameter (a snapshot name, a commit count — each route's own doc comment says which).
---@return table|nil result
---@return string|nil err Set only when `name` is not a route, or names a syntactically invalid commit.
function M.answer(name, opts, param)
  -- `commit/<sha>` first: it is not in `M.routes` because its name carries
  -- the sha, which cannot be a fixed table key. Validated here rather than
  -- inside `M.commit` for the same reason `editor/serve.lua` validated it
  -- in its own dispatcher: an invalid sha is a routing failure ("this is
  -- not a request this module answers"), not a "nothing to show" case a
  -- route function would report.
  local sha_part = name:match("^commit/(.+)$")
  if sha_part then
    local sha = M.safe_sha(sha_part)
    if not sha then
      -- Deliberately not echoed back: refusing to repeat an unvalidated
      -- value is free, and this is the one input that would otherwise
      -- reach a subprocess.
      return nil, "not a commit hash"
    end
    return M.commit(opts, sha), nil
  end

  local route = M.routes[name]
  if not route then
    local names = {}
    for k in pairs(M.routes) do
      names[#names + 1] = k
    end
    table.sort(names)
    names[#names + 1] = "commit/<sha>"
    return nil, ("no such route: %s (have: %s)"):format(tostring(name), table.concat(names, ", "))
  end
  return route(opts, param), nil
end

return M
