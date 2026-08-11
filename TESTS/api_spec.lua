-- TESTS/api_spec.lua — `documentation.core.api`, the answers behind the
-- generated page's `/api/*` routes now that more than one host asks them.
--
-- The property under test is the contract both hosts depend on, not the
-- joins themselves (`browse_telemetry_spec.lua` and `browse_loaded_spec.lua`
-- already own those): every route answers with a *table*, never nil and
-- never an error, and says `available = false` plus a `reason` when there is
-- nothing to show. That is what lets the Telemetry and Loaded panels stay
-- visible in a project that has no data instead of disappearing — the
-- behaviour the desktop host was explicitly built around.
--
-- Deliberately runs against a root with no map at all: "nothing to show" is
-- the case with two hosts and no test, and the one a passing scan never
-- exercises.

return function(H)
  local eq, ok = H.eq, H.ok
  local api = require("documentation.core.api")

  local nowhere = { root = "/definitely/not/a/repository", out_dir = "docs/map" }

  -- ------------------------------------------------------------- routes
  ok(type(api.routes) == "table", "api: routes is a table")
  for _, name in ipairs({
    "telemetry",
    "telemetry/snapshots",
    "loaded",
    "loaded/snapshots",
    "checklist",
    "commits",
  }) do
    ok(type(api.routes[name]) == "function", "api: route " .. name .. " exists")
  end

  -- ------------------------------------------------- every route answers
  for name in pairs(api.routes) do
    local res, err = api.answer(name, nowhere, nil)
    eq(err, nil, "api: " .. name .. " does not error on a root with no map")
    ok(type(res) == "table", "api: " .. name .. " answers with a table")
    eq(res.available, false, "api: " .. name .. " reports available=false with no map")
    ok(type(res.reason) == "string" and res.reason ~= "", "api: " .. name .. " states a reason")
  end

  -- An unknown route is an error, not an empty answer: a host that asked
  -- for a route this build does not have must find out, rather than render
  -- an empty panel that looks like "no data".
  local bad, bad_err = api.answer("no-such-route", nowhere, nil)
  eq(bad, nil, "api: an unknown route returns no result")
  ok(type(bad_err) == "string", "api: an unknown route explains itself")
  ok(bad_err:find("telemetry", 1, true) ~= nil, "api: the error names the routes that do exist")

  -- ---------------------------------------------------- commit/<sha> shape
  -- Not a fixed key in `api.routes` (the sha varies), so it needs its own
  -- coverage: `M.answer` must recognise the shape, validate the sha itself
  -- via `safe_sha`, and refuse before ever calling `opts.git`.
  local bad_sha, bad_sha_err = api.answer("commit/not-a-sha; rm -rf /", nowhere, nil)
  eq(bad_sha, nil, "api: commit/<invalid> returns no result")
  ok(type(bad_sha_err) == "string" and bad_sha_err ~= "", "api: commit/<invalid> explains itself")
  -- Refused specifically for being an invalid sha, not merely absent from
  -- `api.routes` — the two are different failures ("no such route" vs "not
  -- a commit hash") and a caller building a UI message needs to tell them
  -- apart.
  ok(
    bad_sha_err:find("not a commit hash", 1, true) ~= nil,
    "api: commit/<invalid> names the real reason, not a generic 404"
  )

  -- A syntactically valid but nonexistent sha reaches `M.commit`, which
  -- reports absence the same available=false way every other route does —
  -- `opts.git` is nil on `nowhere`, so this also exercises that guard.
  local shaped, shaped_err = api.answer(("a"):rep(40), nowhere, nil)
  ok(shaped == nil, "api: a 40-char hex string alone is not a route name")
  ok(type(shaped_err) == "string", "api: and says so")
  local via_commit = api.answer("commit/" .. ("a"):rep(40), nowhere, nil)
  eq(
    via_commit.available,
    false,
    "api: commit/<shaped sha> with no git access reports available=false"
  )
  ok(type(via_commit.reason) == "string", "api: and states why")

  -- ---------------------------------------------- real git, real history
  -- Everything above proves the contract in isolation. This proves the
  -- pipeline: `commits`/`checklist`/`commit/<sha>` against this
  -- repository's own real commits, through a real `opts.git` — the case a
  -- fake or missing git function never exercises, and the one that found
  -- the query-decoder ordering bug above did not (that bug lived one layer
  -- up, in what never touches git at all).
  local real_root = (debug.getinfo(1, "S").source:sub(2):match("(.*)[/\\]TESTS[/\\]")) or "."
  local real_opts = { root = real_root, out_dir = "docs/map" }
  real_opts.git = function(o, args)
    local cmd = { "git" }
    vim.list_extend(cmd, args)
    local proc = vim.system(cmd, { cwd = o.root, text = true }):wait()
    if proc.code ~= 0 then
      return nil, vim.trim(proc.stderr or "git failed")
    end
    return proc.stdout or ""
  end

  local commits_res = api.answer("commits", real_opts, "3")
  ok(commits_res.available == true, "api: commits is available against a real repository")
  ok(
    type(commits_res.commits) == "table" and #commits_res.commits > 0,
    "api: commits returns real entries"
  )
  ok(#commits_res.commits <= 3, "api: commits honours the requested count")
  local head = commits_res.commits[1]
  ok(type(head.sha) == "string" and #head.sha == 40, "api: a commit entry has a full sha")
  ok(type(head.subject) == "string", "api: a commit entry has a subject")

  local commit_res = api.answer("commit/" .. head.sha, real_opts, nil)
  ok(commit_res.available == true, "api: commit/<real sha> is available")
  eq(commit_res.commit.sha, head.sha, "api: commit/<sha> reports the same sha back")
  ok(type(commit_res.diff) == "string", "api: commit/<sha> includes diff text")
  ok(type(commit_res.impact) == "table", "api: commit/<sha> includes impact analysis")

  local checklist_res = api.answer("checklist", real_opts, nil)
  ok(checklist_res.available == true, "api: checklist is available against a real repository")
  ok(type(checklist_res.counts) == "table", "api: checklist reports counts")

  -- --------------------------------------------------------- decode_param
  eq(api.decode_param(nil), nil, "decode_param: nil stays nil")
  eq(api.decode_param(""), nil, "decode_param: empty is nil, not an empty name")
  eq(api.decode_param("plain"), "plain", "decode_param: an ordinary name is unchanged")
  eq(api.decode_param("two+words"), "two words", "decode_param: + is a space")
  eq(api.decode_param("a%20b"), "a b", "decode_param: %20 is a space")
  -- The ordering property, and the reason it is written down: `%2B` decodes
  -- to a literal `+`, which a decoder that expanded `+` first would then
  -- corrupt into a space.
  eq(api.decode_param("a%2Bb"), "a+b", "decode_param: %2B survives as a literal +")
end
