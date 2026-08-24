-- TESTS/docmap_browse_spec.lua — documentation.editor.browse
--
-- Two halves, deliberately separated: `view`/`source` are pure and get a
-- synthetic IR (deterministic, no dependency on whether docs/map is present
-- or current), while the UI half mounts the real kit layout and drives the
-- real keymaps.

return function(H)
  local eq, ok = H.eq, H.ok

  local source = require("documentation.editor.browse.source")
  local view = require("documentation.editor.browse.view")
  local browse = require("documentation.editor.browse")

  -- A three-node tree: root -> {alpha, beta}. alpha requires beta, and
  -- alpha's `M.run` calls beta's `M.helper`.
  local function fixture()
    local ir = {
      root = "lua/x",
      meta = { title = "x" },
      order = { "lua/x", "lua/x/alpha", "lua/x/beta" },
      nodes = {
        ["lua/x"] = {
          id = "lua/x",
          kind = "namespace",
          name = "x",
          path = "lua/x",
          summary = "",
          body = "",
          children = { "lua/x/alpha", "lua/x/beta" },
          functions = {},
          requires = {},
          required_by = {},
          requires_external = {},
          symbols = {},
          types = {},
          depth = 0,
        },
        ["lua/x/alpha"] = {
          id = "lua/x/alpha",
          kind = "module",
          name = "alpha",
          path = "lua/x/alpha",
          source = "lua/x/alpha/init.lua",
          module = "x.alpha",
          summary = "Alpha does things.",
          body = "",
          parent = "lua/x",
          children = {},
          functions = {
            {
              name = "M.run",
              signature = "run(a)",
              summary = "Runs.",
              line = 12,
              params = {},
              returns = {},
            },
          },
          requires = { "lua/x/beta" },
          required_by = {},
          requires_external = { "plenary.async" },
          symbols = {},
          types = {},
          depth = 1,
        },
        ["lua/x/beta"] = {
          id = "lua/x/beta",
          kind = "module",
          name = "beta",
          path = "lua/x/beta",
          source = "lua/x/beta/init.lua",
          module = "x.beta",
          summary = "Beta helps.",
          body = "",
          parent = "lua/x",
          children = {},
          functions = {
            {
              name = "M.helper",
              signature = "helper()",
              summary = "Helps.",
              line = 30,
              params = {},
              returns = {},
            },
          },
          requires = {},
          required_by = { "lua/x/alpha" },
          requires_external = {},
          symbols = {},
          types = {},
          depth = 1,
        },
      },
      edges = {
        {
          kind = "require",
          from = "lua/x/alpha",
          to = "lua/x/beta",
          to_module = "x.beta",
          line = 3,
        },
        {
          kind = "call",
          from = "lua/x/alpha",
          to = "lua/x/beta",
          from_fn = "M.run",
          to_fn = "M.helper",
          line = 14,
          confidence = "exact",
        },
      },
    }
    return ir
  end

  local ir = fixture()

  -- ------------------------------------------------------- source.rehydrate
  --
  -- The artifact writes `nodes` as an ARRAY in walk order and carries no
  -- `order` key (that array *is* the order — a JSON object's key order would
  -- not be deterministic). In memory both exist. Rehydration bridges the two,
  -- and getting it wrong makes every node lookup miss.
  local doc = {
    root = "lua/x",
    nodes = {
      { id = "lua/x", name = "x", children = { "lua/x/alpha" } },
      { id = "lua/x/alpha", name = "alpha" },
    },
  }
  local hydrated = source.rehydrate(doc)
  eq(hydrated.nodes["lua/x"].name, "x", "rehydrate: nodes become a map keyed by id")
  eq(hydrated.order[2], "lua/x/alpha", "rehydrate: order is the original array sequence")
  eq(type(hydrated.edges), "table", "rehydrate: edges is always a table")

  -- ------------------------------------------------------- structure mode
  local st = { mode = "structure", id = "lua/x", dir = "out", depth = 2, cursor = 1 }
  local entries = view.entries(ir, st)
  eq(#entries, 2, "structure: root lists its two children")
  eq(entries[1].kind, "node", "structure: children are node entries")
  eq(entries[1].id, "lua/x/alpha", "structure: first child is alpha")

  st.id = "lua/x/alpha"
  entries = view.entries(ir, st)
  eq(#entries, 1, "structure: a leaf module lists its own functions")
  eq(entries[1].kind, "function", "structure: functions appear as function entries")
  eq(entries[1].fn, "M.run", "structure: the function entry carries its declared name")
  eq(entries[1].line, 12, "structure: the function entry carries its line, for gd")
  eq(entries[1].source, "lua/x/alpha/init.lua", "structure: and its source path")

  -- ------------------------------------------------------------- deps mode
  st = { mode = "deps", id = "lua/x/alpha", dir = "out", depth = 2, cursor = 1 }
  entries = view.entries(ir, st)
  -- beta (resolved) + the external require, which is listed but not navigable
  eq(#entries, 2, "deps out: one resolved dependency plus one external")
  eq(entries[1].id, "lua/x/beta", "deps out: alpha requires beta")
  eq(entries[2].kind, "external", "deps out: unresolved requires are shown as external")

  st.dir = "in"
  entries = view.entries(ir, st)
  eq(#entries, 1, "deps in: nothing requires alpha... except the message")
  eq(entries[1].kind, "message", "deps in: an empty direction says so instead of rendering blank")

  st = { mode = "deps", id = "lua/x/beta", dir = "in", depth = 2, cursor = 1 }
  entries = view.entries(ir, st)
  eq(entries[1].id, "lua/x/alpha", "deps in: beta is required by alpha")

  -- depth is honored: with depth 1 from the root, only direct edges appear
  local reached = view.walk_requires(ir, "lua/x/alpha", "out", 1)
  eq(#reached, 1, "walk_requires: depth 1 reaches the direct dependency")
  eq(reached[1].depth, 1, "walk_requires: and reports its distance")

  -- ------------------------------------------------------------ calls mode
  st = { mode = "calls", id = "lua/x/alpha", dir = "out", depth = 2, cursor = 1 }
  entries = view.entries(ir, st)
  eq(#entries, 1, "calls out: alpha has one outgoing call")
  eq(entries[1].fn, "M.helper", "calls out: the entry names the callee")
  eq(entries[1].id, "lua/x/beta", "calls out: and the node it lives in")
  -- The jump target must be the callee's DECLARATION, not the call site:
  -- e.line (14) is in alpha, which is the file already being looked at.
  eq(entries[1].line, 30, "calls out: gd targets the callee's declaration line, not the call site")
  eq(entries[1].site_line, 14, "calls out: the call site is kept separately")

  st = { mode = "calls", id = "lua/x/beta", dir = "in", depth = 2, cursor = 1 }
  entries = view.entries(ir, st)
  eq(#entries, 1, "calls in: beta has one caller")
  eq(entries[1].fn, "M.run", "calls in: the entry names the caller")

  -- narrowing to one function
  st = { mode = "calls", id = "lua/x/alpha", fn = "M.run", dir = "out", depth = 2, cursor = 1 }
  eq(#view.entries(ir, st), 1, "calls: pinning a function keeps its own edges")
  st.fn = "M.nonexistent"
  eq(view.entries(ir, st)[1].kind, "message", "calls: pinning a function with no edges reports it")

  -- ------------------------------------------------------------ types mode
  st = { mode = "types", id = "lua/x/alpha", dir = "out", depth = 2, cursor = 1 }
  entries = view.entries(ir, st)
  eq(
    entries[1].kind,
    "message",
    "types: a map without LuaLS detail says so rather than looking empty"
  )

  ir.nodes["lua/x/alpha"].types_detail = {
    {
      name = "X.Alpha",
      kind = "class",
      desc = "An alpha.",
      file = "lua/x/alpha/@types/init.lua",
      fields = {},
    },
  }
  entries = view.entries(ir, st)
  eq(entries[1].kind, "type", "types: with detail present, classes are listed")
  eq(entries[1].type_name, "X.Alpha", "types: the entry carries the type name")
  ir.nodes["lua/x/alpha"].types_detail = nil

  -- ------------------------------------------------------- detail + status
  local detail = view.detail(
    ir,
    { mode = "structure", id = "lua/x/alpha" },
    { kind = "node", id = "lua/x/beta" }
  )
  eq(detail[1], "x.beta", "detail: a node detail leads with its module path")

  detail = view.detail(
    ir,
    { mode = "structure", id = "lua/x/alpha" },
    { kind = "function", id = "lua/x/alpha", fn = "M.run" }
  )
  eq(detail[1], "run(a)", "detail: a function detail leads with its signature")
  local joined = table.concat(detail, "\n")
  ok(
    joined:find("1 callers", 1, true) or joined:find("0 callers", 1, true),
    "detail: reports caller/callee counts"
  )

  eq(view.breadcrumb(ir, "lua/x/alpha"), "x ▸ alpha", "breadcrumb: walks parents to the root")
  local status = view.status(ir, { mode = "deps", id = "lua/x/alpha", dir = "in", depth = 3 })
  ok(status:find("deps", 1, true) ~= nil, "status: names the mode")
  ok(status:find("depth 3", 1, true) ~= nil, "status: shows the depth axis in deps mode")

  -- A missing node must not raise — a stale map can point anywhere.
  eq(
    view.entries(ir, { mode = "structure", id = "nope", dir = "out", depth = 2 })[1].kind,
    "message",
    "entries: an unknown node id reports instead of erroring"
  )

  -- ---------------------------------------------------------- history mode
  --
  -- The one mode whose data does not come from the IR: `init.lua` runs git
  -- and parks the result on the state. So these tests hand `view` exactly
  -- what git would have produced — which is also the point of the split.

  -- Level 1, before the commit list has arrived.
  st = { mode = "history", id = "lua/x/alpha", dir = "out", depth = 2, cursor = 1 }
  entries = view.entries(ir, st)
  eq(entries[1].kind, "message", "history: says it is loading rather than looking empty")

  st.commits = {}
  eq(view.entries(ir, st)[1].label, "(no commits)", "history: an empty repo says so")

  st.commits = {
    {
      sha = "a1b2c3d4e5f6a7b8c9d0",
      short = "a1b2c3d",
      author = "A",
      date = "2026-01-01",
      subject = "first",
    },
    {
      sha = "0f1e2d3c4b5a69788796",
      short = "0f1e2d3",
      author = "B",
      date = "2025-12-31",
      subject = "older",
    },
  }
  entries = view.entries(ir, st)
  eq(#entries, 2, "history: one row per commit")
  eq(entries[1].kind, "commit", "history: commit rows are their own kind")
  eq(
    entries[1].sha,
    "a1b2c3d4e5f6a7b8c9d0",
    "history: the row carries the full sha, not the short one"
  )
  ok(entries[1].label:find("first", 1, true) ~= nil, "history: the subject is in the label")

  -- Level 2: a commit is open but its analysis has not landed yet.
  st.sha = "a1b2c3d4e5f6a7b8c9d0"
  eq(view.entries(ir, st)[1].kind, "message", "history: an unanalysed commit says it is working")

  st.impact = {
    files = { "lua/x/alpha/init.lua" },
    touched = { { node = "lua/x/alpha", fn = "M.run", line = 12, signature = "run(a)" } },
    callers = { ["lua/x/alpha#M.run"] = { { node = "lua/x/beta", fn = "M.helper", line = 40 } } },
    calling_modules = { "lua/x/beta" },
    impacted_modules = { "lua/x/beta" },
    unattributed = { "README.md" },
    approximate = false,
  }
  entries = view.entries(ir, st)
  eq(#entries, 2, "history: one touched function plus the unattributed path")
  eq(entries[1].kind, "function", "history: a touched function is navigable")
  eq(entries[1].fn, "M.run", "history: named")
  eq(entries[1].id, "lua/x/alpha", "history: and placed in its node")
  eq(#entries[1].callers, 1, "history: its callers ride along on the entry")
  eq(
    entries[1].source,
    "lua/x/alpha/init.lua",
    "history: gd targets the declaration in the current tree, not the revision"
  )
  eq(
    entries[2].kind,
    "message",
    "history: a changed path with no attribution is shown but not navigable"
  )

  -- Nothing attributable at all: still not an empty pane.
  local saved_impact = st.impact
  st.impact = { files = { "README.md" }, touched = {}, callers = {}, unattributed = {} }
  eq(#view.entries(ir, st), 1, "history: a docs-only commit collapses to one message")
  eq(view.entries(ir, st)[1].kind, "message", "history: ... and it is not selectable")
  st.impact = saved_impact

  -- Detail panes.
  detail = view.detail(ir, { mode = "history", commits = st.commits }, nil)
  ok(
    table.concat(detail, "\n"):find("Commits", 1, true) ~= nil,
    "history detail: the commit list explains itself when nothing is selected"
  )

  detail = view.detail(
    ir,
    { mode = "history" },
    { kind = "commit", sha = st.commits[1].sha, commit = st.commits[1] }
  )
  eq(detail[1], "first", "history detail: a commit leads with its subject")
  ok(
    table.concat(detail, "\n"):find("a1b2c3d4e5f6a7b8c9d0", 1, true) ~= nil,
    "history detail: and shows the full hash"
  )

  detail = view.detail(ir, st, entries[1])
  local hjoined = table.concat(detail, "\n")
  eq(detail[1], "M.run", "history detail: a touched function leads with its name")
  ok(hjoined:find("Called by 1", 1, true) ~= nil, "history detail: counts the direct callers")
  ok(hjoined:find("M.helper", 1, true) ~= nil, "history detail: and names them")
  ok(hjoined:find("impacted transitively", 1, true) ~= nil, "history detail: reports the radius")

  -- The approximation caveat is the whole reason `approximate` exists: an
  -- over-reaching attribution that says nothing would be worse than no
  -- attribution at all.
  st.impact.approximate = true
  ok(
    table.concat(view.detail(ir, st, entries[1]), "\n"):find("approximated", 1, true) ~= nil,
    "history detail: an approximate analysis warns about it"
  )
  st.impact.approximate = false

  st.impact_has_map = false
  ok(
    table.concat(view.detail(ir, st, entries[1]), "\n"):find("predates", 1, true) ~= nil,
    "history detail: a revision without a committed map warns about it"
  )
  st.impact_has_map = nil

  status = view.status(ir, { mode = "history", commits = st.commits })
  ok(status:find("history", 1, true) ~= nil, "history status: names the mode")
  ok(status:find("2 commits", 1, true) ~= nil, "history status: counts the list")
  status = view.status(ir, { mode = "history", sha = st.sha, impact = st.impact })
  ok(status:find("a1b2c3d4", 1, true) ~= nil, "history status: an open commit becomes the subject")

  -- ------------------------------------------------------------ trail mode
  --
  -- `trail.lua` is pure by design — a table of records, no window, no buffer,
  -- no `vim` API — so the whole model is driven here without mounting
  -- anything. Only the keys that reach it need the UI half below.
  local trail = require("documentation.editor.browse.trail")
  trail.reset()
  local troot = "/tmp/x"

  eq(trail.count(troot), 0, "trail: a fresh root has no pins")

  local pin_a = { mode = "structure", id = "lua/x/alpha", label = "alpha" }
  local verb, n = trail.toggle(troot, pin_a)
  eq(verb, "pinned", "trail: the first toggle pins")
  eq(n, 1, "trail: and reports the new length")

  -- Identity is what the pin is *about*, not how it was being looked at: the
  -- same node in the same mode at a different depth is the same bookmark, and
  -- a trail that grew a near-duplicate for it would fill up with entries
  -- nobody meant to create.
  verb, n = trail.toggle(troot, { mode = "structure", id = "lua/x/alpha", label = "alpha (again)" })
  eq(verb, "unpinned", "trail: re-pinning the same subject toggles it off")
  eq(n, 0, "trail: and the trail is empty again")

  trail.toggle(troot, pin_a)
  trail.toggle(troot, { mode = "deps", id = "lua/x/alpha", dir = "in", depth = 3, label = "alpha" })
  eq(trail.count(troot), 2, "trail: the same node in a different mode is a different pin")
  trail.toggle(troot, { mode = "structure", id = "lua/x/alpha", fn = "M.run", label = "M.run" })
  eq(trail.count(troot), 3, "trail: and so is a function inside it")

  -- Ordering is insertion order, not sorted: a trail is a record of where the
  -- reader went, and re-sorting it would destroy the only information the
  -- order carries.
  local list = trail.list(troot)
  eq(list[1].label, "alpha", "trail: pins keep the order they were added in")
  eq(list[3].fn, "M.run", "trail: including the newest")

  -- Roots do not see each other's pins. They are keyed by repository, which
  -- is what lets a pin outlive the window it was taken in.
  eq(trail.count("/tmp/y"), 0, "trail: a second root starts empty")

  eq(trail.remove_at(troot, 2).mode, "deps", "trail: remove_at returns what it removed")
  eq(trail.count(troot), 2, "trail: and shortens the list")
  eq(trail.remove_at(troot, 99), nil, "trail: an out-of-range index removes nothing")
  eq(trail.clear(troot), 2, "trail: clear reports how many it dropped")
  eq(trail.count(troot), 0, "trail: and leaves nothing")

  -- Rendering. The empty state explains the keys rather than showing a blank
  -- pane — a mode whose whole content is "nothing yet" has to say how to put
  -- something in it.
  local tst = { mode = "trail", pins = {} }
  entries = view.entries(ir, tst)
  ok(#entries > 0, "trail view: the empty state is not an empty list")
  ok(
    table.concat(view.list_lines(entries, 60), "\n"):find("p ", 1, true) ~= nil,
    "trail view: and it names the key that pins"
  )

  tst.pins = {
    {
      mode = "deps",
      id = "lua/x/beta",
      dir = "in",
      depth = 2,
      label = "beta",
      source = "beta.lua",
    },
    { mode = "structure", id = "lua/x/gone", label = "gone" },
  }
  entries = view.entries(ir, tst)
  eq(#entries, 2, "trail view: one row per pin")
  eq(
    entries[1].pin.mode,
    "deps",
    "trail view: the row carries its pin, so <CR> can restore the view"
  )
  eq(entries[1].pin_index, 1, "trail view: and its index, so d can remove it")
  eq(
    entries[1].source,
    "beta.lua",
    "trail view: source is re-exposed, so gd/gq need no special case"
  )

  -- A pin whose node has since vanished says so instead of rendering a label
  -- for something that is no longer there, and stops being navigable.
  eq(entries[2].kind, "message", "trail view: a pin whose node is gone is not navigable")
  ok(
    entries[2].label:find("no longer", 1, true) ~= nil,
    "trail view: and says why rather than just disappearing"
  )

  status = view.status(ir, tst)
  ok(status:find("2 pinned", 1, true) ~= nil, "trail status: counts the pins")
  ok(status:find("trail", 1, true) ~= nil, "trail status: names the mode")

  -- The count is visible from every other mode too — a trail nobody can see
  -- from where they are pinning is a feature with no feedback — but only once
  -- there is something to count.
  status = view.status(ir, { mode = "structure", id = "lua/x", pins = tst.pins })
  ok(status:find("2", 1, true) ~= nil, "trail status: the count shows in other modes")
  status = view.status(ir, { mode = "structure", id = "lua/x", pins = {} })
  ok(
    status:find("📌", 1, true) == nil,
    "trail status: and stays out of the way when nothing is pinned"
  )

  -- ---------------------------------------------------------------- filter
  --
  -- The query language, driven straight — it is pure, so none of this needs a
  -- window. `describe` rather than the raw string is what the status line
  -- shows, so asserting on it also pins what a reader is told is in effect.
  local flt = require("documentation.editor.browse.filter")

  eq(flt.parse(""), nil, "filter: an empty query is no filter")
  eq(flt.parse("   "), nil, "filter: and so is whitespace")
  eq(flt.parse(nil), nil, "filter: and so is nothing at all")

  eq(flt.describe(flt.parse("fs")), "fs", "filter: one term")
  eq(flt.describe(flt.parse("  fs   bar ")), "fs bar", "filter: terms split on any run of spaces")
  eq(flt.describe(flt.parse("FS")), "fs", "filter: folded to lower case")

  -- AND, not OR. Narrowing that can lengthen the list is not narrowing.
  ok(flt.matches(flt.parse("fs bar"), "lib.fs.bar"), "filter: every term must match")
  ok(not flt.matches(flt.parse("fs bar"), "lib.fs.baz"), "filter: one miss is a miss")

  -- Substrings, not fuzzy. `/` is the forgiving one; the reason to type
  -- `-test` is that nothing containing "test" survives it.
  ok(not flt.matches(flt.parse("fsb"), "lib.fs.bar"), "filter: matching is literal, not fuzzy")

  ok(not flt.matches(flt.parse("-spec"), "alpha_spec"), "filter: - excludes")
  ok(flt.matches(flt.parse("-spec"), "alpha"), "filter: and passes everything else")
  ok(
    flt.matches(flt.parse("fs -spec"), "lib.fs.read"),
    "filter: positive and negative terms combine"
  )
  ok(not flt.matches(flt.parse("fs -spec"), "lib.fs.read_spec"), "filter: … and both apply")

  eq(flt.describe(flt.parse('"open url"')), '"open url"', "filter: a quoted phrase is one term")
  ok(flt.matches(flt.parse('"open url"'), "fs.open url.system"), "filter: spaces and all")
  ok(not flt.matches(flt.parse('"open url"'), "fs.open.url"), "filter: as a literal run")
  ok(not flt.matches(flt.parse('-"open url"'), "fs.open url"), "filter: phrases negate too")

  -- Typed live, so half a query is a normal intermediate state rather than
  -- something to reject.
  eq(
    flt.describe(flt.parse('"open ur')),
    '"open ur"',
    "filter: an unterminated quote runs to the end"
  )
  eq(flt.parse("-"), nil, "filter: a lone - negates nothing and is dropped")
  eq(flt.describe(flt.parse("- fs")), "fs", "filter: … even mid-query")

  -- apply() narrows on the LABEL, which is what is on screen. Filtering on
  -- data the row does not display would make rows vanish for reasons the
  -- reader cannot see.
  local fixture_rows = {
    { kind = "node", label = "▸ alpha", id = "lua/x/alpha" },
    { kind = "node", label = "▸ beta", id = "lua/x/beta" },
    { kind = "function", label = "ƒ run(opts)", id = "lua/x/alpha" },
  }
  local kept, hidden = flt.apply(flt.parse("beta"), fixture_rows)
  eq(#kept, 1, "filter: apply narrows the list")
  eq(hidden, 2, "filter: and reports how many it removed")
  eq(kept[1].id, "lua/x/beta", "filter: keeping the whole entry, not just its text")

  local all_kept, none_hidden = flt.apply(nil, fixture_rows)
  eq(#all_kept, 3, "filter: no filter keeps everything")
  eq(none_hidden, 0, "filter: with nothing hidden")

  local empty = flt.apply(flt.parse("nothingmatchesthis"), fixture_rows)
  eq(#empty, 0, "filter: a query matching nothing keeps nothing")

  -- The status line has to carry it, in every one of its three shapes. A
  -- filter is the only view state that *removes rows*, so without this a
  -- narrowed list and a genuinely short one look identical.
  for _, shape in ipairs({
    { mode = "deps", id = "lua/x/alpha", dir = "in", depth = 3 },
    { mode = "history", commits = {} },
    { mode = "trail", pins = {} },
  }) do
    shape.filter = flt.parse("fs -spec")
    shape.filter_hidden = 4
    local line = view.status(ir, shape)
    ok(line:find("fs -spec", 1, true) ~= nil, "filter: " .. shape.mode .. " status shows the query")
    ok(line:find("4 hidden", 1, true) ~= nil, "filter: … and how many rows it is holding back")
  end

  ok(
    view.status(ir, { mode = "trail", pins = {} }):find("hidden", 1, true) == nil,
    "filter: and says nothing at all when no filter is on"
  )

  -- ---------------------------------------------------------- trail_store
  --
  -- Persistence, pointed at a temp file rather than the user's real state
  -- directory — the reason `M.path` is a function every caller goes through
  -- instead of a constant.
  local store = require("documentation.editor.browse.trail_store")
  local store_file = H.tmpfile(".json")
  store.path = function()
    return store_file
  end

  trail.reset()
  store.reset()
  store.attach()

  local sroot = "/repo/one"
  trail.toggle(sroot, { mode = "deps", id = "lua/x/beta", dir = "in", depth = 3, label = "beta" })
  trail.toggle(sroot, { mode = "structure", id = "lua/x/alpha", label = "alpha" })
  eq(store.flush(), true, "store: flush writes the dirty roots")

  -- The round trip is the claim: drop everything in memory, read it back, and
  -- the trail is what it was — including the axes, which are what make a pin
  -- restore a view rather than a subject.
  trail.reset()
  store.reset()
  store.path = function()
    return store_file
  end
  eq(store.hydrate(sroot), 2, "store: hydrate restores the trail from disk")
  eq(trail.count(sroot), 2, "store: and the pins are back")
  eq(trail.list(sroot)[1].depth, 3, "store: with their axes intact")
  eq(trail.list(sroot)[1].mode, "deps", "store: and the mode they were taken in")

  -- Once per root. Re-reading on every open would silently discard whatever
  -- was pinned since — the newest pins, which is the worst half to lose.
  trail.toggle(sroot, { mode = "structure", id = "lua/x", label = "x" })
  eq(store.hydrate(sroot), 0, "store: hydrate is a no-op the second time")
  eq(trail.count(sroot), 3, "store: so a pin made after it survives")

  -- Named trails.
  store.attach()
  eq(#store.names(sroot), 0, "store: no saved trails yet")
  eq(store.save_named(sroot, "  "), false, "store: a trail needs a name")
  eq(store.save_named(sroot, "review"), true, "store: save under a name")
  eq(#store.names(sroot), 1, "store: which then shows up in the list")
  eq(store.names(sroot)[1], "review", "store: under the name given")

  -- Loading ADDS. Replacing would silently destroy the trail built this
  -- session, and a bookmark tool that can lose bookmarks stops being trusted.
  local _, added, skipped = store.load_named(sroot, "review")
  eq(added, 0, "store: loading a trail already in place adds nothing")
  eq(skipped, 3, "store: and says how many were already there")
  eq(trail.count(sroot), 3, "store: so nothing was duplicated")

  trail.clear(sroot)
  local _, added2 = store.load_named(sroot, "review")
  eq(added2, 3, "store: loading into an empty trail restores all of it")

  -- A saved trail must not alias the live one, or unpinning would edit the
  -- snapshot too.
  trail.clear(sroot)
  eq(#store.names(sroot), 1, "store: clearing the trail does not delete what was saved")

  eq(store.delete_named(sroot, "nope"), false, "store: deleting an unknown name is not an error")
  eq(store.delete_named(sroot, "review"), true, "store: delete_named forgets it")
  eq(#store.names(sroot), 0, "store: and the list is empty again")

  -- Roots stay separate on disk, same as in memory.
  trail.toggle(sroot, { mode = "structure", id = "lua/x/alpha", label = "alpha" })
  trail.toggle("/repo/two", { mode = "structure", id = "lua/y", label = "y" })
  store.flush()
  trail.reset()
  store.reset()
  store.path = function()
    return store_file
  end
  eq(store.hydrate("/repo/two"), 1, "store: the second root round-trips its own trail")
  eq(store.hydrate(sroot), 1, "store: and the first keeps its own")

  -- A corrupt or truncated file costs the pins, never an error on the way in:
  -- this lives in the user's state directory, where a full disk or an older
  -- version of this plugin can leave anything behind.
  local bad = H.tmpfile(".json")
  local fd = assert(io.open(bad, "w"))
  fd:write("{ this is not json")
  fd:close()
  trail.reset()
  store.reset()
  store.path = function()
    return bad
  end
  eq(store.hydrate(sroot), 0, "store: a malformed file yields no pins rather than an error")
  eq(store.save_named(sroot, "x"), false, "store: and saving from an empty trail still refuses")

  -- The debounced write, driven the way a pin drives it and with NO explicit
  -- flush — which is the only way to observe it. `trail.on_change` fans out
  -- under `pcall` so a broken listener cannot break pinning, and that pcall
  -- swallowed a real "attempt to call a table value" here: `debounce.new`
  -- returns a `{ call, cancel }` table, not a callable. Every assertion above
  -- passed throughout, because they all flush by hand.
  local timed = H.tmpfile(".json")
  os.remove(timed)
  trail.reset()
  store.reset()
  store.path = function()
    return timed
  end
  store.attach()
  trail.toggle(sroot, { mode = "structure", id = "lua/x/alpha", label = "alpha" })
  vim.wait(2000, function()
    return (vim.uv or vim.loop).fs_stat(timed) ~= nil
  end)
  ok((vim.uv or vim.loop).fs_stat(timed) ~= nil, "store: a pin alone reaches disk, on the debounce")
  os.remove(timed)

  trail.reset()
  store.reset()
  os.remove(bad)

  -- Left pointed at the temp file for the rest of the run, deliberately. The
  -- UI section below pins things, every pin schedules a write, and an
  -- unpatched `M.path` would put the suite's scratch pins into the real
  -- `stdpath("state")`. Removed at the very end instead of here.
  store.path = function()
    return store_file
  end

  -- --------------------------------------------------------------- the UI
  --
  -- Mounts the real layout against this repo's own map when one exists. The
  -- artifact is a build product, so its absence is not a failure — skip
  -- rather than making the suite depend on `:DocMap` having been run.
  local root = vim.fn.getcwd():gsub("\\", "/")
  local uv = vim.uv or vim.loop
  if uv.fs_stat(root .. "/docs/map/module_map.json") then
    eq(browse.is_open(), false, "browse: closed before opening")
    eq(browse.open({ root = root }), true, "browse: opens against the repo's own map")
    eq(browse.is_open(), true, "browse: reports itself open")

    local function slot(ft)
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local b = vim.api.nvim_win_get_buf(w)
        if vim.api.nvim_get_option_value("filetype", { buf = b }) == ft then
          return w, b
        end
      end
    end

    local list_win, list_buf = slot("documentation-browse-list")
    local _, detail_buf = slot("documentation-browse-detail")
    local _, status_buf = slot("documentation-browse-status")
    ok(list_win ~= nil, "browse: the list slot is mounted")
    ok(detail_buf ~= nil, "browse: the detail slot is mounted")
    ok(status_buf ~= nil, "browse: the status slot is mounted")
    ok(vim.api.nvim_buf_line_count(list_buf) > 0, "browse: the list has content")

    -- ------------------------------------------------------------------
    -- Inline code in the detail pane is highlighted, not left as literal
    -- backticks (QW8 — the editor half of what `prose()` does for the
    -- generated page).
    --
    -- Asserted against the pane the reader actually looks at, not against
    -- `highlight.spans` alone: the thing that can silently break is the
    -- *wiring*, and there are two render paths — a full render and the
    -- cursor-move one — which is exactly the shape that drifts. The `j`
    -- assertion below is that second path.
    --
    -- Counted rather than pinned to a number: this runs against the
    -- repository's own map, whose prose changes. What must hold is "there
    -- is code in this pane and it is marked", not how much.
    -- ------------------------------------------------------------------
    do
      local hl_ns = vim.api.nvim_create_namespace("documentation.browse.detail")

      ---@return integer spans, integer marks
      local function detail_marks()
        local lines = vim.api.nvim_buf_get_lines(detail_buf, 0, -1, false)
        local spans = 0
        for _, line in ipairs(lines) do
          spans = spans + #require("documentation.editor.browse.highlight").spans(line)
        end
        local marks = vim.api.nvim_buf_get_extmarks(detail_buf, hl_ns, 0, -1, {})
        return spans, #marks
      end

      -- Find a row whose detail pane actually contains inline code. The root
      -- node's own summary might not, and an assertion that depended on that
      -- would be a test of this repository's prose rather than of the
      -- feature.
      local found_row, found_spans = nil, 0
      for row = 1, math.min(vim.api.nvim_buf_line_count(list_buf), 40) do
        pcall(vim.api.nvim_win_set_cursor, list_win, { row, 0 })
        -- The cursor-move path is what a reader triggers with `j`, and it is
        -- the render this feature has to reach as well as the full one.
        vim.api.nvim_exec_autocmds("CursorMoved", { buffer = list_buf })
        local spans = detail_marks()
        if spans > 0 then
          found_row, found_spans = row, spans
          break
        end
      end

      ok(found_row ~= nil, "browse: some row's detail pane contains inline `code` to highlight")
      if found_row then
        local spans, marks = detail_marks()
        eq(spans, found_spans, "browse: the pane still shows the row that was found")
        eq(
          marks,
          spans * 3,
          "browse: three extmarks per span — the two ticks dimmed, the text between them raw"
        )

        -- The namespace is cleared per render, so moving away and back must
        -- not accumulate marks. Without the clear this grows on every `j`.
        pcall(vim.api.nvim_win_set_cursor, list_win, { found_row, 0 })
        vim.api.nvim_exec_autocmds("CursorMoved", { buffer = list_buf })
        local _, again = detail_marks()
        eq(again, marks, "browse: re-rendering the same row does not double its marks")
      end
    end

    vim.api.nvim_set_current_win(list_win)
    local before = vim.api.nvim_buf_get_lines(status_buf, 0, 1, false)[1]

    -- Selecting a different row and descending must act on THAT row. This is
    -- the regression that live-cursor `selected()` exists for: with a cached
    -- index, <CR> descended into row 1 regardless of the cursor.
    --
    -- The row is found by SHAPE, not by number. This asserted "row 3" and
    -- passed for as long as row 3 of this tree's root happened to be a
    -- module; splitting the tree into core/ and editor/ made it a function,
    -- whose status line names it without its parameter list, and the
    -- assertion failed on a claim about the fixture rather than about the
    -- code. The same mistake the extraction commit already had to fix three
    -- times. The last node row is used so it cannot be row 1, which is the
    -- one a cached index would wrongly descend into.
    local node_row, node_label
    for i, line in ipairs(vim.api.nvim_buf_get_lines(list_buf, 0, -1, false)) do
      if line:match("^%s*[▸·]%s") then
        node_row, node_label = i, line
      end
    end
    if node_row and node_row > 1 then
      vim.api.nvim_win_set_cursor(list_win, { node_row, 0 })
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
      local after = vim.api.nvim_buf_get_lines(status_buf, 0, 1, false)[1]
      ok(after ~= before, "browse: <CR> navigated somewhere new")
      local leaf = (node_label or ""):gsub("^%s*[▸·ƒ○≡◆]?%s*", "")
      ok(
        after:find(leaf, 1, true) ~= nil,
        "browse: <CR> descended into the row under the cursor, not a cached one"
      )
    end

    -- Mode switching reaches every mode without erroring.
    for _, key in ipairs({ "2", "3", "4", "5", "1" }) do
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), "x", false)
      ok(browse.is_open(), "browse: still open after switching to mode " .. key)
    end

    -- History. Untested until now, and it did not work: the trail recorded
    -- only *past* positions while `hindex` was left addressing the entry
    -- before the current one, so the first <C-o> fell off the front and the
    -- second landed one stop too far back. The status line is the cheapest
    -- observable proof of "where am I".
    local function press(k)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(k, true, false, true), "x", false)
    end
    local function status_now()
      local _, b = slot("documentation-browse-status")
      return vim.api.nvim_buf_get_lines(b, 0, 1, false)[1]
    end

    -- A fresh instance, so the trail has a known beginning: the moves above
    -- are still in the old one, and "stays put at the start" only means
    -- something when the start is where we think it is.
    browse.close()
    browse.open({ root = root })
    vim.api.nvim_set_current_win((slot("documentation-browse-list")))

    local at_start = status_now()
    press("2") -- deps
    local at_deps = status_now()
    press("3") -- calls
    local at_calls = status_now()
    ok(at_deps ~= at_start and at_calls ~= at_deps, "browse: three distinct positions to walk")

    press("<C-o>")
    eq(status_now(), at_deps, "browse: <C-o> steps back exactly one position")
    press("<C-o>")
    eq(status_now(), at_start, "browse: a second <C-o> reaches the one before that")
    press("<C-o>")
    eq(status_now(), at_start, "browse: <C-o> at the start of the trail stays put")

    press("<C-i>")
    eq(status_now(), at_deps, "browse: <C-i> steps forward again")
    press("<C-i>")
    eq(status_now(), at_calls, "browse: forward reaches the newest position")
    press("<C-i>")
    eq(status_now(), at_calls, "browse: <C-i> at the end of the trail stays put")

    -- A fresh move from the middle of the trail truncates the forward half,
    -- exactly like a browser.
    press("<C-o>")
    press("4") -- types, from the middle
    local at_types = status_now()
    press("<C-i>")
    eq(status_now(), at_types, "browse: a new move drops the forward history")

    -- Keys that cannot change anything must not become history stops: a
    -- `<C-o>` that visibly does nothing reads as broken history rather than
    -- as the key having been a no-op.
    -- Each check records the position it is standing on *before* the move, so
    -- the assertion never depends on counting entries in the trail.
    local prev = status_now()
    press("1") -- structure, where depth does not apply
    local at_structure = status_now()
    press("+")
    press("+")
    eq(status_now(), at_structure, "browse: depth keys do nothing outside deps")
    press("<C-o>")
    eq(status_now(), prev, "browse: and leave no dead stop behind them")

    prev = status_now()
    press("2") -- deps, dir starts at "out"
    local at_deps_out = status_now()
    press("l") -- already outgoing
    eq(status_now(), at_deps_out, "browse: setting the direction it already has is a no-op")
    press("<C-o>")
    eq(status_now(), prev, "browse: which also leaves no dead stop")

    -- History mode against this repo's own git history, which is the only
    -- place the *clearing* half of a move is observable. `go` applies its
    -- patch with `pairs`, and `pairs` never yields a key whose value is nil —
    -- so `{ sha = nil }` was the empty patch and `-` out of an opened commit
    -- redrew the same function list forever. Nothing above catches it: every
    -- other move only ever *sets* fields.
    -- `git rev-parse` rather than testing for a `.git` *directory*: in a
    -- worktree `.git` is a file, and this suite is normally run from one.
    local in_git = vim.fn.executable("git") == 1
      and vim.system({ "git", "rev-parse", "HEAD" }, { cwd = root }):wait().code == 0
    if in_git then
      browse.close()
      browse.open({ root = root, mode = "history" })
      local h_win, h_buf = slot("documentation-browse-list")
      vim.api.nvim_set_current_win(h_win)

      -- **Wait for `git log` before looking.** Since the async rewrite
      -- (`perf(async): Browse-History blockiert nicht mehr`) the commit list
      -- is fetched in a callback, and `render` draws `(loading commits…)`
      -- until it lands. Every assertion below reads a list that does not
      -- exist yet without this.
      --
      -- It failed in two different places for one reason, which is what made
      -- it look like two bugs: with a full history the row count came up
      -- short, and on CI — `actions/checkout` is shallow, so `rev-list
      -- --count HEAD` is 1 — `>= 1` was satisfied by the placeholder row
      -- itself, the `<CR>` below then landed on a `kind="message"` entry,
      -- and the failure surfaced seven lines further down as "opens a
      -- commit".
      --
      -- Polled through the *buffer* rather than the state: this spec drives
      -- the browser the way a person does, and a wait keyed on an internal
      -- field would keep passing if the render stopped reflecting it.
      vim.wait(20000, function()
        local first = vim.api.nvim_buf_get_lines(h_buf, 0, 1, false)[1] or ""
        return not first:find("loading commits", 1, true)
      end, 50)

      -- Captured *after* the wait, not before: the status line is
      -- `("%d commits"):format(#(st.commits or {}))`, so a copy taken while
      -- the load was still in flight would read "0 commits" — and the
      -- `-` assertion at the end compares against it.
      local commit_list = status_now()
      ok(commit_list:find("history", 1, true) ~= nil, "browse: mode=history opens on History")
      ok(
        commit_list:find("commits", 1, true) ~= nil,
        "browse: and on the commit list, not inside a commit"
      )
      -- Against the repository's actual commit count, not a hardcoded `> 1`.
      -- That literal was true for every run inside lib.nvim's ~95-commit
      -- history and became the first thing to fail in a freshly initialised
      -- checkout with a single commit — an assertion about the fixture, not
      -- about the code. `git log` is capped at 200 rows in `browse`, so the
      -- expectation is capped the same way.
      local counted = vim.system({ "git", "rev-list", "--count", "HEAD" }, { cwd = root }):wait()
      local ncommits = math.min(tonumber(vim.trim(counted.stdout or "")) or 1, 200)
      ok(
        vim.api.nvim_buf_line_count(h_buf) >= ncommits,
        ("browse: git log produced rows (expected >= %d)"):format(ncommits)
      )

      press("<CR>")
      local in_commit = status_now()
      ok(in_commit ~= commit_list, "browse: <CR> opens a commit")

      press("-")
      eq(status_now(), commit_list, "browse: - clears the open commit and returns to the list")
    end

    -- `?` — the cheatsheet, and the claim it rests on.
    --
    -- The overlay is rendered from the same `KEYS` table `bind()` installs
    -- from, so it cannot describe a key the browser does not have or omit one
    -- it does. That is a claim worth testing rather than asserting in a
    -- comment: every key actually bound on the list buffer has to appear in
    -- the panel. `keytrans` because `nvim_buf_get_keymap` hands back resolved
    -- termcodes (`\r`, `\15`) and the panel spells them `<CR>`, `<C-o>`.
    browse.close()
    browse.open({ root = root })
    local q_win, q_buf = slot("documentation-browse-list")
    vim.api.nvim_set_current_win(q_win)
    press("?")

    local _, help_buf = slot("documentation-browse-help")
    ok(help_buf ~= nil, "browse: ? opens the key panel")
    local help = table.concat(vim.api.nvim_buf_get_lines(help_buf or 0, 0, -1, false), "\n")
    ok(help:find("quickfix", 1, true) ~= nil, "browse: the panel describes what the keys do")

    -- `keytrans` is not quite the inverse of what a human writes: it escapes
    -- a literal `<` as `<lt>` (so `<CR>` comes back as `<lt>CR>`) and
    -- normalises the modifier case (`<C-o>` -> `<C-O>`). Undoing both is the
    -- comparison actually intended here — the panel is meant to be readable,
    -- not to spell keys the way the API round-trips them.
    local undocumented = {}
    local haystack = help:lower()
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(q_buf, "n")) do
      local lhs = (vim.fn.keytrans(m.lhs):gsub("<lt>", "<"))
      if haystack:find(lhs:lower(), 1, true) == nil then
        undocumented[#undocumented + 1] = lhs
      end
    end
    eq(
      #undocumented,
      0,
      "browse: every bound key is in the panel (missing: " .. table.concat(undocumented, " ") .. ")"
    )

    -- Mode-specific keys are marked, not hidden: "why did + do nothing" is
    -- exactly the question the panel is opened to answer.
    ok(
      help:find("not in this mode", 1, true) ~= nil,
      "browse: keys the current mode ignores say so instead of disappearing"
    )
    vim.api.nvim_buf_delete(help_buf, { force = true })

    -- `opts.keys` — rebinding and disabling.
    --
    -- Three cases in one open, because they share the same failure mode: an
    -- override that is silently ignored looks identical to one that worked
    -- until the key is actually pressed. So each is asserted from the buffer's
    -- real keymap table, not from the resolved spec list — the latter would
    -- pass just as well if `bind()` never read it.
    do
      browse.close()
      browse.open({
        root = root,
        keys = {
          quickfix = "gQ", -- a string replaces
          filter = { "F", "<C-f>" }, -- a list replaces with several
          pin = false, -- and false removes
        },
        -- which-key is not installed in the headless test environment, so this
        -- is belt and braces: the registration is a `pcall(require, ...)` that
        -- returns false there. Off explicitly so the spec never depends on
        -- which of those two facts is true.
        which_key = false,
      })

      local _, k_buf = slot("documentation-browse-list")
      local bound = {}
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(k_buf or 0, "n")) do
        bound[(vim.fn.keytrans(m.lhs):gsub("<lt>", "<")):lower()] = true
      end

      ok(bound["gq"] ~= nil, "browse: opts.keys rebinds an action to a new key")
      ok(bound["f"] ~= nil, "browse: opts.keys accepts a list of left-hand sides")
      ok(bound["<c-f>"] ~= nil, "browse: every key in an opts.keys list is bound")
      ok(bound["p"] == nil, "browse: opts.keys = false leaves the action unbound")

      -- The default `gq` is gone, not merely shadowed. Case matters here and
      -- `bound` is lower-cased, so this asks the keymap table directly.
      local still_default = false
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(k_buf or 0, "n")) do
        if vim.fn.keytrans(m.lhs) == "gq" then
          still_default = true
        end
      end
      ok(not still_default, "browse: a rebound action does not keep its default key as well")

      -- And the panel follows the override rather than the defaults — the
      -- whole point of rendering it from the resolved set.
      local kw = slot("documentation-browse-list")
      vim.api.nvim_set_current_win(kw)
      press("?")
      local _, k_help = slot("documentation-browse-help")
      ok(k_help ~= nil, "browse: ? still opens the panel with custom keys")
      local ktext = table.concat(vim.api.nvim_buf_get_lines(k_help or 0, 0, -1, false), "\n")
      ok(ktext:find("gQ", 1, true) ~= nil, "browse: the panel shows the rebound key")
      ok(
        ktext:find("(disabled)", 1, true) ~= nil,
        "browse: a disabled action is named and marked, not dropped from the panel"
      )

      -- The original invariant, re-checked under overrides: this is where a
      -- resolved-vs-default mismatch would actually show up.
      local missing = {}
      local khay = ktext:lower()
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(k_buf or 0, "n")) do
        local lhs = (vim.fn.keytrans(m.lhs):gsub("<lt>", "<"))
        if khay:find(lhs:lower(), 1, true) == nil then
          missing[#missing + 1] = lhs
        end
      end
      eq(
        #missing,
        0,
        "browse: every bound key is in the panel under overrides too (missing: "
          .. table.concat(missing, " ")
          .. ")"
      )
      vim.api.nvim_buf_delete(k_help, { force = true })
      browse.close()
    end

    -- `docs/BINDINGS.md` — the generated file, and the reason it is generated.
    --
    -- Same claim as the `?` panel one level up, aimed at a file instead of a
    -- float: a hand-maintained key list inside a drift detector would be
    -- indefensible, so the file is rendered from `KEYS` and this asserts the
    -- rendering actually covers it. Checked against the *rendered string*, not
    -- against the committed file, so the spec fails when the renderer drops a
    -- key rather than when someone forgets to regenerate — the latter is the
    -- map gate's job, and mixing the two would make one failure look like the
    -- other.
    do
      local rendered = require("documentation.bindings.docs").render()
      local specs = browse.keyspecs()

      local missing = {}
      for _, spec in ipairs(specs) do
        if rendered:find("`" .. spec.id .. "`", 1, true) == nil then
          missing[#missing + 1] = spec.id
        end
        for _, key in ipairs(spec.keys) do
          if rendered:find("`" .. key .. "`", 1, true) == nil then
            missing[#missing + 1] = spec.id .. ":" .. key
          end
        end
      end
      eq(
        #missing,
        0,
        "bindings docs: every action and key is in BINDINGS.md (missing: "
          .. table.concat(missing, " ")
          .. ")"
      )

      -- The distinction a generated table is most likely to flatten: `j`/`k`
      -- are documented *and deliberately not bound*, and a list that showed
      -- them like every other row would be actively misleading.
      ok(
        rendered:find("native Vim key, not bound", 1, true) ~= nil,
        "bindings docs: documented-but-native keys are marked as such"
      )

      -- Both commands and all four autocommands, from their manifests.
      local manifest = require("documentation.bindings.autocmds")
      for _, c in ipairs(manifest.usrcmds) do
        ok(
          rendered:find(":" .. c.name, 1, true) ~= nil,
          "bindings docs: " .. c.name .. " is documented"
        )
      end
      for _, a in ipairs(manifest.list) do
        ok(
          rendered:find(a.owner, 1, true) ~= nil,
          "bindings docs: the autocmd owned by " .. a.owner .. " is documented"
        )
      end
    end

    -- Trail, through the real keys. The model itself is covered above; what
    -- is left to prove is the wiring — that `p` reaches it, that mode 6 shows
    -- what it holds, and that `<CR>` there restores a *view* rather than only
    -- a subject.
    trail.clear(root)
    browse.close()
    browse.open({ root = root })
    vim.api.nvim_set_current_win((slot("documentation-browse-list")))

    -- Pinned from Deps, so the axes have something to restore that Structure
    -- would not reproduce on its own.
    press("2") -- deps
    press("h") -- incoming
    press("p")
    eq(trail.count(root), 1, "browse: p pins the entry under the cursor")
    ok(
      status_now():find("📌", 1, true) ~= nil,
      "browse: and the count shows in the mode you pinned from"
    )

    press("p")
    eq(trail.count(root), 0, "browse: p on the same entry unpins it")
    press("p")
    eq(trail.count(root), 1, "browse: and again re-pins")

    press("6")
    ok(status_now():find("1 pinned", 1, true) ~= nil, "browse: mode 6 opens the trail")
    local _, t_buf = slot("documentation-browse-list")
    ok(vim.api.nvim_buf_line_count(t_buf) >= 1, "browse: the trail lists the pin")

    -- The axes, not the whole status line: a pin records the *entry under the
    -- cursor*, which is a different node from the one that was centered when
    -- it was taken, so the two lines legitimately differ on the breadcrumb.
    -- What must survive is the view — had `<CR>` restored only the subject,
    -- this would read `[trail]` or `[structure]`.
    press("<CR>")
    local restored = status_now()
    ok(
      restored:find("deps", 1, true) ~= nil and restored:find("←in", 1, true) ~= nil,
      "browse: <CR> on a pin restores the view it was taken in — mode and direction, not just the node"
    )

    -- `-` in the trail is a no-op: a flat list has nothing to climb, and
    -- without the guard it silently moved the node axis under an unchanged
    -- screen, so the key looked broken *and* left the browser somewhere else.
    press("6")
    local in_trail = status_now()
    press("-")
    eq(
      status_now(),
      in_trail,
      "browse: - in the trail does nothing rather than something invisible"
    )

    press("d")
    eq(trail.count(root), 0, "browse: d unpins the entry under the cursor")
    ok(status_now():find("0 pinned", 1, true) ~= nil, "browse: and the trail says it is empty")

    -- `S`/`L`/`X` — their guards, which is the half of them that is not
    -- already covered by the `trail_store` block above. What each one *does*
    -- once it opens is a `save_named`/`load_named`/`delete_named` call and
    -- those round-trip through a real file up there; what is untested is
    -- whether the key refuses in the states where it should, and refusing
    -- means "no float appears".
    --
    -- Asserted by counting windows rather than by looking for a filetype:
    -- `kit.input` and `kit.select` are lib.nvim's surfaces, and pinning this
    -- to their internal buffer names would make a rename over there fail a
    -- test over here about something else entirely.
    local function wins()
      return #vim.api.nvim_list_wins()
    end

    -- Bound in every mode, gated in the handler — the same rule the other
    -- mode-specific keys follow. Unbound, `S` and `X` would fall through to
    -- Vim's own meaning on a nomodifiable buffer and `L` would move the
    -- cursor, which in this browser moves the selection.
    press("1") -- structure
    local outside = wins()
    press("S")
    press("L")
    press("X")
    eq(wins(), outside, "browse: S/L/X open nothing outside the trail")
    ok(browse.is_open(), "browse: and leave the browser alone")

    press("6") -- trail, empty
    local in_empty_trail = wins()
    press("S")
    eq(wins(), in_empty_trail, "browse: S with nothing pinned asks for no name")
    press("L")
    press("X")
    eq(wins(), in_empty_trail, "browse: L/X with nothing saved open no picker")

    -- `f` is the counter-example that keeps the three assertions above honest:
    -- they pass just as well on a key that is not bound at all. This one has
    -- to open something, in a mode where the trail keys refuse to.
    press("f")
    ok(wins() > in_empty_trail, "browse: f opens the filter prompt")
    press("<Esc>")
    eq(wins(), in_empty_trail, "browse: and <Esc> dismisses it")
    ok(browse.is_open(), "browse: leaving the browser open behind it")

    trail.clear(root)

    -- Centering on a NAMESPACE: `lua/documentation/render` has no init.lua and
    -- so declares no @module, but `documentation.core.render` is what a user types.
    -- Resolving only on a declared module silently lands on the root instead.
    browse.close()
    eq(
      browse.open({ root = root, center = "documentation.core.render" }),
      true,
      "browse: opens centered on a namespace"
    )
    local _, status2 = slot("documentation-browse-status")
    local line = vim.api.nvim_buf_get_lines(status2, 0, 1, false)[1]
    ok(
      line:find("render", 1, true) ~= nil,
      "browse: a namespace module path resolves to its node, not the root"
    )

    -- `gq` and `gd` are the two things that justify an editor-side view at
    -- all, and neither was exercised. Both are destructive to the browser
    -- (they close it), so they come last.
    browse.close()
    vim.fn.setqflist({}, "r")
    browse.open({ root = root, center = "documentation" })
    vim.api.nvim_set_current_win((slot("documentation-browse-list")))
    press("gq")

    eq(browse.is_open(), false, "browse: gq closes the browser")
    local qf = vim.fn.getqflist({ items = 0, title = 0 })
    ok(#qf.items > 0, "browse: gq fills the quickfix list")
    ok(
      (qf.title or ""):find("DocMap", 1, true) ~= nil,
      "browse: the quickfix list is titled with the mode and breadcrumb"
    )
    local first = qf.items[1]
    ok(first.bufnr and first.bufnr > 0, "browse: quickfix entries point at a real file")
    ok(first.lnum >= 1, "browse: and carry a line number")
    vim.cmd("cclose")

    -- `gI` reports the blast radius of whatever the DETAIL PANE is showing,
    -- not of the centered node. Those differ as soon as the cursor moves, and
    -- a number that disagrees with the one two panes over is worse than none.
    -- Centered on the root, and scanning every row rather than the first
    -- three: which rows carry an impact figure is a property of the tree this
    -- happens to run in, not of the code under test. Pinning it to a fixed
    -- module and a fixed window of rows is what made this assertion fail the
    -- moment the suite moved to a smaller repository — the check is "gI agrees
    -- with the pane", so any one row that reports a figure proves it.
    -- `break` after the first, because re-opening the browser per row is the
    -- expensive part and one agreement is the whole claim.
    browse.open({ root = root, center = "documentation" })
    local i_win, i_buf = slot("documentation-browse-list")
    local _, i_detail = slot("documentation-browse-detail")
    vim.api.nvim_set_current_win(i_win)

    local checked = 0
    for row = 1, vim.api.nvim_buf_line_count(i_buf) do
      vim.api.nvim_win_set_cursor(i_win, { row, 0 })
      vim.cmd("doautocmd CursorMoved")
      local shown = table
        .concat(vim.api.nvim_buf_get_lines(i_detail, 0, -1, false), "\n")
        :match("impact%s+(%d+) module")
      if shown then
        vim.fn.setqflist({}, "r")
        press("gI")
        eq(
          #vim.fn.getqflist(),
          tonumber(shown),
          "browse: gI matches the impact the detail pane just reported"
        )
        checked = checked + 1
        vim.cmd("cclose")
        break
      end
    end
    ok(checked > 0, "browse: at least one row carried an impact figure to check")
    browse.close()

    -- `gO` hands the current position to the page: the fragment must carry
    -- the mode, the centered node and the direction that are on screen.
    local handed = nil
    package.loaded["lib.nvim.fs.open.url.system_opener"] = {
      open = function(url)
        handed = url
        return true
      end,
    }
    browse.open({ root = root, center = "documentation" })
    vim.api.nvim_set_current_win((slot("documentation-browse-list")))
    press("2") -- deps
    press("h") -- incoming
    press("gO")
    ok(handed ~= nil, "browse: gO handed a URL to the opener")
    ok((handed or ""):find("view=deps", 1, true) ~= nil, "browse: carrying the current mode")
    ok((handed or ""):find("dir=in", 1, true) ~= nil, "browse: and the current direction")
    ok((handed or ""):find("documentation", 1, true) ~= nil, "browse: and the centered node")
    ok((handed or ""):sub(1, 5) == "file:", "browse: as a file:// URL, so the fragment survives")
    browse.close()
    package.loaded["lib.nvim.fs.open.url.system_opener"] = nil

    -- `gd` on a function entry lands in its file at its declaration line.
    --
    -- The expected path is derived from the module name rather than written
    -- out, so moving a module does not fail an assertion about `gd`. Splitting
    -- the tree into core/ and editor/ broke the literal form once already.
    local gd_center = "documentation.core.deps"
    local gd_expect = "lua/" .. gd_center:gsub("%.", "/") .. ".lua"
    browse.open({ root = root, center = gd_center })
    local gd_list_win, gd_list_buf = slot("documentation-browse-list")
    vim.api.nvim_set_current_win(gd_list_win)
    local target_row
    for i, row in ipairs(vim.api.nvim_buf_get_lines(gd_list_buf, 0, -1, false)) do
      if row:find("ƒ", 1, true) then
        target_row = i
        break
      end
    end
    if target_row then
      vim.api.nvim_win_set_cursor(gd_list_win, { target_row, 0 })
      press("gd")
      eq(browse.is_open(), false, "browse: gd closes the browser — the floats covered the file")
      local opened = vim.api.nvim_buf_get_name(0):gsub("\\", "/")
      ok(
        opened:find(gd_expect, 1, true) ~= nil,
        "browse: gd opened the file the entry pointed at (" .. gd_expect .. ")"
      )
      ok(vim.api.nvim_win_get_cursor(0)[1] > 1, "browse: at the declaration line, not line 1")
    end

    browse.close()
    eq(browse.is_open(), false, "browse: close() shuts it down")
    browse.close() -- idempotent
    eq(browse.is_open(), false, "browse: close() is idempotent")
  end

  -- Whatever the UI section's pins scheduled, landed here and nowhere else.
  trail.reset()
  store.reset()
  os.remove(store_file)
end
