-- TESTS/browse_traffic_spec.lua — `documentation.core.traffic_join` and the
-- Traffic mode in `documentation.editor.browse.view`.
--
-- Same shape `browse_rules_spec.lua` already established for a soft
-- dependency: the pure logic (repo resolution, disk read, entry shaping)
-- runs unconditionally against a hand-fabricated fake `github_stats.digest`
-- module; a real checkout (`GITHUB_STATS_DIR`, wired the same way `RULES_DIR`
-- is in `TESTS/run.lua`) only upgrades a couple of assertions from "the
-- soft dependency degrades correctly" to "the real plugin's own path/stem
-- helpers agree with what this module assumes".
--
-- Unlike `rules_join` (a live call into a running plugin), this reads a
-- JSON file straight off disk — the digest github_stats.nvim already wrote
-- — so the fake module here only has to answer `digest_file`/`file_stem`/
-- `digest_dir`, and the fixture itself is written with `lib.nvim.fs.json`.

return function(H)
  local eq, ok = H.eq, H.ok
  local fs_json = require("lib.nvim.fs.json")
  local traffic_join = require("documentation.core.traffic_join")
  local view = require("documentation.editor.browse.view")

  ---@return Documentation.IR
  local function fake_ir()
    return { order = {}, nodes = {}, edges = {} }
  end

  ---@param repo string
  ---@return string
  local function stem_of(repo)
    return (repo:gsub("[/_]", "_"))
  end

  ---Fabricate `github_stats.digest` at `package.loaded["github_stats.digest"]`
  ---and, unless `skip_write` is true, write `digest` to disk at the path the
  ---fake module's own `digest_file(repo)` reports — a real JSON round-trip
  ---through `lib.nvim.fs.json`, not an in-memory stub of the read itself.
  ---@param dir string
  ---@param digest table?
  ---@param skip_write boolean?
  ---@return fun() restore
  local function stub_digest_module(dir, digest, skip_write)
    local previous = package.loaded["github_stats.digest"]
    package.loaded["github_stats.digest"] = {
      digest_dir = function()
        return dir
      end,
      file_stem = function(repo)
        return stem_of(repo)
      end,
      digest_file = function(repo)
        return dir .. "/digest/" .. stem_of(repo) .. ".json"
      end,
    }
    if digest and not skip_write then
      vim.fn.mkdir(dir .. "/digest", "p")
      local ok_write, err =
        fs_json.write(dir .. "/digest/" .. stem_of(digest.repo) .. ".json", digest)
      assert(ok_write, err)
    end
    return function()
      package.loaded["github_stats.digest"] = previous
    end
  end

  ---@return table
  local function fake_digest(repo)
    return {
      schema = 1,
      repo = repo or "me/demo",
      generated = "2026-09-25T10:00:00Z",
      fetched = "2026-09-25T09:30:00Z",
      span = { from = "2026-07-01", to = "2026-09-24" },
      views = {
        d7 = { count = 12, uniques = 5 },
        d30 = { count = 40, uniques = 18 },
        d90 = { count = 120, uniques = 55 },
        trend = 12.5,
      },
      clones = {
        d7 = { count = 3, uniques = 2 },
        d30 = { count = 10, uniques = 6 },
        d90 = { count = 22, uniques = 14 },
      },
      daily = { views = {}, clones = {} },
      referrers = {
        { referrer = "google.com", count = 42, uniques = 30 },
      },
      paths = {
        { path = "/me/demo/blob/main/README.md", title = "README.md", count = 120, uniques = 80 },
      },
    }
  end

  -- traffic_join.repo: explicit override wins, no fallback guessing beyond
  -- the git remote (no root at all -> nil; a root with no derivable remote
  -- -> nil, never an error).
  do
    eq(
      traffic_join.repo({ traffic = { repo = "over/ridden" } }),
      "over/ridden",
      "repo: opts.traffic.repo, verbatim"
    )
    eq(traffic_join.repo({}), nil, "repo: nil with no root and no override")

    local non_repo_dir = vim.fn.tempname()
    vim.fn.mkdir(non_repo_dir, "p")
    eq(
      traffic_join.repo({ root = non_repo_dir }),
      nil,
      "repo: nil when root has no git remote -- never an error"
    )
  end

  -- traffic_join.load: nil, not an error, when github_stats.nvim is not on
  -- the rtp at all (the ordinary case for most projects most of the time).
  do
    local previous = package.loaded["github_stats.digest"]
    package.loaded["github_stats.digest"] = nil
    -- Force soft_require to actually try requiring the module rather than
    -- reusing a real one some earlier block in this run already loaded.
    package.preload["github_stats.digest"] = nil
    eq(traffic_join.load("me/demo", {}), nil, "load: nil when github_stats.nvim is absent")
    package.loaded["github_stats.digest"] = previous
  end

  -- traffic_join.load: the fixture, read back whole, through the default
  -- (unoverridden) digest_dir path.
  do
    local dir = vim.fn.tempname()
    local digest = fake_digest("me/demo")
    local restore = stub_digest_module(dir, digest)
    local loaded = traffic_join.load("me/demo", {})
    restore()

    ok(loaded ~= nil, "load: the fixture round-trips through disk")
    if loaded then
      eq(loaded.repo, "me/demo", "load: repo carried through")
      eq(loaded.views.d7.count, 12, "load: a nested numeric field survives the JSON round-trip")
      eq(#loaded.referrers, 1, "load: referrers carried through")
      eq(#loaded.paths, 1, "load: paths carried through")
    end
  end

  -- traffic_join.load: a schema newer than this module understands is
  -- refused, not guessed at.
  do
    local dir = vim.fn.tempname()
    local digest = fake_digest("me/demo")
    digest.schema = 2
    local restore = stub_digest_module(dir, digest)
    local loaded = traffic_join.load("me/demo", {})
    restore()
    eq(loaded, nil, "load: a newer schema is refused")
  end

  -- traffic_join.load: a digest file whose own `repo` field names a
  -- different repository -- the sanitizer is not injective (DIGEST.md), so
  -- this is "not tracked", never the wrong repository's traffic shown as
  -- the one asked for.
  do
    local dir = vim.fn.tempname()
    local digest = fake_digest("someone/else")
    local restore = stub_digest_module(dir, digest)
    -- Written under "someone/else"'s stem; ask for "me/demo", whose stem the
    -- fake `digest_file` computes independently -- a real mismatch, not a
    -- missing file.
    vim.fn.mkdir(dir .. "/digest", "p")
    fs_json.write(dir .. "/digest/" .. stem_of("me/demo") .. ".json", digest)
    local loaded = traffic_join.load("me/demo", {})
    restore()
    eq(loaded, nil, "load: a repo field mismatch reads as not tracked")
  end

  -- traffic_join.load: opts.traffic.digest_dir overrides the probed
  -- module's own digest_dir(), honored by rebuilding the same digest/<stem>
  -- path under the override.
  do
    local default_dir = vim.fn.tempname()
    local override_dir = vim.fn.tempname()
    local digest = fake_digest("me/demo")
    -- The fake module's digest_dir() answers with `default_dir`; nothing is
    -- ever written there -- only `override_dir` holds the fixture, so a
    -- read that ignored the override would find nothing.
    local restore = stub_digest_module(default_dir, nil, true)
    vim.fn.mkdir(override_dir .. "/digest", "p")
    fs_json.write(override_dir .. "/digest/" .. stem_of("me/demo") .. ".json", digest)
    local loaded = traffic_join.load("me/demo", { traffic = { digest_dir = override_dir } })
    restore()
    ok(loaded ~= nil, "load: the override digest_dir is honored")
    if loaded then
      eq(loaded.repo, "me/demo", "load: repo read from the overridden location")
    end
  end

  -- Traffic mode, no repository resolved at all: an honest message, not an
  -- empty list or an error -- the same posture Rules takes for no gate.
  do
    local ir = fake_ir()
    local entries = view.entries(ir, { mode = "traffic", opts = {} })
    eq(#entries, 1, "traffic mode: one message entry with no repository resolved")
    eq(entries[1].kind, "message", "traffic mode: ... and it says so")
  end

  -- Traffic mode, a repository resolved but github_stats.nvim absent: same
  -- "no data" message shape, never a fabricated empty digest.
  do
    local previous = package.loaded["github_stats.digest"]
    package.loaded["github_stats.digest"] = nil
    package.preload["github_stats.digest"] = nil
    local ir = fake_ir()
    local entries =
      view.entries(ir, { mode = "traffic", opts = { traffic = { repo = "me/demo" } } })
    package.loaded["github_stats.digest"] = previous
    eq(#entries, 1, "traffic mode: one message entry when github_stats.nvim is absent")
    eq(entries[1].kind, "message", "traffic mode: ... never a fabricated digest")
  end

  -- Traffic mode with fake data: two summary rows, one referrer row, one
  -- path row, plus detail and status.
  do
    local dir = vim.fn.tempname()
    local digest = fake_digest("me/demo")
    local restore = stub_digest_module(dir, digest)
    local ir = fake_ir()
    local entries =
      view.entries(ir, { mode = "traffic", opts = { traffic = { repo = "me/demo" } } })
    restore()

    eq(#entries, 4, "traffic mode: 2 summary + 1 referrer + 1 path")
    eq(entries[1].traffic_row.section, "summary", "traffic mode: views summary first")
    eq(entries[1].traffic_row.metric, "views", "traffic mode: ... and it is the views metric")
    eq(entries[2].traffic_row.metric, "clones", "traffic mode: clones summary second")
    eq(entries[3].traffic_row.section, "referrer", "traffic mode: referrer row third")
    eq(entries[4].traffic_row.section, "path", "traffic mode: path row fourth")

    ok(entries[1].label:find("d7 12", 1, true) ~= nil, "traffic mode: d7 count in the label")
    ok(
      entries[3].label:find("google.com", 1, true) ~= nil,
      "traffic mode: referrer name in the label"
    )
    ok(entries[4].label:find("README.md", 1, true) ~= nil, "traffic mode: page title in the label")

    local detail = view.detail(ir, { mode = "traffic" }, entries[1])
    ok(
      table.concat(detail, "\n"):find("trend", 1, true) ~= nil,
      "traffic mode detail: trend is shown for a summary row"
    )

    local path_detail = view.detail(ir, { mode = "traffic" }, entries[4])
    ok(
      table.concat(path_detail, "\n"):find("top 10", 1, true) ~= nil,
      "traffic mode detail: a path row is labeled GitHub's top 10, never a file view count"
    )

    local status = view.status(ir, { mode = "traffic", entries = entries, opts = {} })
    ok(status:find("me/demo", 1, true) ~= nil, "traffic mode status: repo shown")
    ok(status:find("views d7 12", 1, true) ~= nil, "traffic mode status: views d7 count shown")
  end

  -- The real end-to-end check: only when a real github_stats.nvim checkout
  -- is reachable. This exercises the actual plugin's own `file_stem`/
  -- `digest_file`/`digest_dir` -- the three functions `traffic_join` calls
  -- through the probe -- agreeing with what this module assumes, without
  -- needing a full fetch/history pipeline (already covered by that
  -- plugin's own TESTS/digest_spec.lua).
  local ok_digest = pcall(require, "github_stats.digest")
  if ok_digest then
    local digest_mod = require("github_stats.digest")

    ok(type(digest_mod.digest_dir()) == "string", "digest_dir (real): answers before setup()")

    local stem = digest_mod.file_stem("me/demo")
    ok(type(stem) == "string" and stem ~= "", "file_stem (real): a non-empty stem")
    eq(
      digest_mod.digest_file("me/demo"),
      digest_mod.digest_dir() .. "/digest/" .. stem .. ".json",
      "digest_file (real): matches digest_dir()/digest/<stem>.json, the path traffic_join assumes"
    )
  end
end
