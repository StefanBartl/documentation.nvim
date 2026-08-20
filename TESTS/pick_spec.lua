-- TESTS/pick_spec.lua — `:DocMap pick`'s entry list
--
-- The picker itself is somebody else's code — `pickers.nvim` resolving
-- telescope, fzf-lua or snacks, or `kit.select` deferring to whatever the
-- reader wired into `vim.ui.select`. What belongs to this plugin is the
-- **list**: what is in it, what each entry points at, and the one property
-- the fallback path silently depends on.
--
-- **That property is label uniqueness.** `pick.run` builds a text→entry map
-- because fzf-lua hands back a bare string for an item with no `file`, and
-- `kit.select` takes plain strings throughout. A duplicate label would make
-- one of the two entries unreachable — silently, and only on those paths.
-- Measured over this repository's own map while writing it: 913 entries, 0
-- collisions. This asserts the property rather than the number, because the
-- number moves with every commit and the property must not.

return function(H)
  local eq, ok = H.eq, H.ok
  local pick = require("documentation.editor.pick")
  local scan = require("documentation.core.scan")

  local dr = H.tmpfile("_pick")
  local function dwrite(rel, lines)
    local abs = dr .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "pick spec: fixture must be writable")
    fd:write(table.concat(lines, "\n"))
    fd:close()
  end

  dwrite("lua/t/mod/init.lua", {
    "---@module 't.mod'",
    "--- A module with two functions.",
    "local M = {}",
    "---The first.",
    "function M.first()",
    "  return 1",
    "end",
    "---The second.",
    "function M.second()",
    "  return 2",
    "end",
    "return M",
  })
  -- A second module under the same namespace, so the tree has a namespace
  -- node — the shape with no `source` of its own.
  dwrite("lua/t/other/init.lua", {
    "---@module 't.other'",
    "--- Another module.",
    "local M = {}",
    "---Only one here.",
    "function M.only()",
    "  return 3",
    "end",
    "return M",
  })

  local opts = { root = dr, source = "lua/t", lua_root = "lua", extra_checks = {} }
  local ir = scan.scan(opts)
  local items = pick.entries(ir, dr)
  ok(#items > 0, "pick: the fixture produces entries")

  local by_text = {}
  for _, item in ipairs(items) do
    by_text[item.text] = item
  end

  -- Modules read as their dotted name, functions as `module#fn` — the same
  -- two shapes :DocBrowse's own fuzzy jump builds, so a name typed in one
  -- place is the name typed in the other.
  ok(by_text["t.mod"] ~= nil, "pick: a module is an entry under its dotted name")
  ok(by_text["t.mod#M.first"] ~= nil, "pick: a function is `module#name`")
  ok(by_text["t.mod#M.second"] ~= nil, "pick: ...for every function, not just the first")
  ok(by_text["t.other#M.only"] ~= nil, "pick: across modules")

  -- The location is what makes this a jump rather than a list.
  local first = by_text["t.mod#M.first"]
  ok(
    first.file ~= nil and first.file:find("lua/t/mod/init.lua", 1, true) ~= nil,
    "pick: a function entry carries an absolute path to its own file"
  )
  ok(type(first.line) == "number" and first.line > 0, "pick: ...and the line it starts on")

  local second = by_text["t.mod#M.second"]
  ok(
    second.line > first.line,
    "pick: the lines are the real ones, not a constant — the second function is below the first"
  )

  -- A module entry has a file but no line: `edit` lands at the top, which is
  -- what "take me to this module" means.
  eq(by_text["t.mod"].line, nil, "pick: a module entry has no line, so it opens at the top")
  ok(by_text["t.mod"].file ~= nil, "pick: ...but it does have a file")

  -- ---------------------------------------------------------------------
  -- The property the fallback paths depend on.
  -- ---------------------------------------------------------------------
  local seen, dupes = {}, {}
  for _, item in ipairs(items) do
    if seen[item.text] then
      dupes[#dupes + 1] = item.text
    end
    seen[item.text] = true
  end
  table.sort(dupes)
  eq(
    table.concat(dupes, ", "),
    "",
    "pick: labels are unique — the text→entry map fzf-lua and kit.select come "
      .. "back through would otherwise make one of a colliding pair unreachable"
  )

  -- Every entry must be resolvable by its own text, which is the same
  -- property stated the way the code actually uses it.
  for _, item in ipairs(items) do
    eq(by_text[item.text], item, "pick: " .. item.text .. " resolves to itself through the lookup")
  end

  -- ---------------------------------------------------------------------
  -- And over this repository's real map, which is the tree that produced
  -- the 913/0 measurement and the one a reader actually picks from.
  -- ---------------------------------------------------------------------
  local root = (vim.fn.getcwd():gsub("\\", "/"))
  local real = scan.scan(require("documentation.config").build(root, {}))
  local real_items = pick.entries(real, root)
  ok(#real_items > 100, "pick: the real map produces a substantial list (" .. #real_items .. ")")

  local real_seen, real_dupes = {}, 0
  local without_file = 0
  for _, item in ipairs(real_items) do
    if real_seen[item.text] then
      real_dupes = real_dupes + 1
    end
    real_seen[item.text] = true
    if not item.file then
      without_file = without_file + 1
    end
  end
  eq(real_dupes, 0, "pick: no duplicate labels in this repository's own map")
  ok(
    without_file < #real_items / 2,
    "pick: the overwhelming majority of entries can actually be opened ("
      .. (#real_items - without_file)
      .. " of "
      .. #real_items
      .. ")"
  )
end
