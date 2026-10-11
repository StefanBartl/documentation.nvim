-- TESTS/readers_links_spec.lua — the readers that open fixed names under the
-- project root do not go through a link that leaves it.
--
-- `scan_links_spec.lua` covers the scanner's own walk. These are the others:
-- the prose corpus (every `.md` under the root), the tests directory, the
-- Features and Checklist folders, the README link targets and the committed
-- map `--api=` reads back. Each used to open whatever a link led to; each is
-- given a tree with one link that leaves the project holding a marker, and a
-- twin that stays inside, so "refuse every link" cannot pass.

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("documentation.config")
  local docmap = require("documentation")
  local docs = require("documentation.core.docs")
  local features = require("documentation.core.features")
  local checklist = require("documentation.core.checklist")
  local artifact = require("documentation.core.artifact")

  local base = (vim.fn.tempname():gsub("\\", "/")) .. "_readers_links"
  local root = base .. "/repo"
  local outside = base .. "/outside"

  H.write(root .. "/lua/t/init.lua", {
    "---@module 't'",
    "local M = {}",
    "function M.only_named_outside() end",
    "function M.named_inside() end",
    "return M",
  })
  H.write(root .. "/lua/t/README.md", {
    "# t",
    "[gone](nowhere/missing.md)",
    "[behind a link](../../leaving/gone.md)",
    "[behind a link, inside](../../staying/x.md)",
  })
  H.write(root .. "/notes.md", { "# plain note" })
  H.write(root .. "/keep/inside_note.md", { "# INSIDE-NOTE" })
  H.write(root .. "/feat_in/core.md", { "# Core", "", "## Inside feature", "- status: done" })
  H.write(root .. "/check_in/arch.md", { "# Arch", "", "- [x] inside item" })
  H.write(root .. "/TESTS_IN/a_spec.lua", { "local t = require('t')", "t.named_inside()" })

  H.write(outside .. "/notes/secret.md", { "# OUTSIDE-NOTE" })
  H.write(outside .. "/feat/core.md", { "# Core", "", "## OUTSIDE-FEATURE", "- status: done" })
  H.write(outside .. "/check/arch.md", { "# Arch", "", "- [x] OUTSIDE-ITEM" })
  H.write(outside .. "/tests/a_spec.lua", { "local t = require('t')", "t.only_named_outside()" })
  H.write(outside .. "/leaving/x.md", { "# there" })
  H.write(outside .. "/map/module_map.json", { '{"nodes":[{"id":"OUTSIDE-NODE"}]}' })

  local here = H.canonical(root)
  local made = true
  local function link(target, name, is_dir)
    local done = H.link(target, root .. "/" .. name, is_dir)
    made = made and done
    return done
  end
  link(outside .. "/notes", "outnotes", true)
  link(here .. "/keep", "innotes", true)
  link(outside .. "/feat", "linked_features", true)
  link(here .. "/feat_in", "linked_features_in", true)
  link(outside .. "/check", "linked_checklist", true)
  link(here .. "/check_in", "linked_checklist_in", true)
  link(outside .. "/tests", "TESTS", true)
  link(outside .. "/leaving", "leaving", true)
  link(here .. "/keep", "staying", true)
  ok(made, "the directory links can be made here")
  local file_link = H.link(outside .. "/notes/secret.md", root .. "/secret_link.md", false)
  local file_link_check = H.link(outside .. "/check/arch.md", root .. "/check_single.md", false)

  local function has(list, rel)
    for _, v in ipairs(list) do
      if v == rel then
        return true
      end
    end
    return false
  end

  -- ------------------------------------------------------------ the corpus
  local opts = config.build(root, { source = "lua/t", lua_root = "lua" })
  local corpus = docs.corpus(opts)
  ok(has(corpus, "notes.md"), "corpus: a plain note is in it")
  ok(has(corpus, "keep/inside_note.md"), "corpus: ...as is one in a plain folder")
  ok(not has(corpus, "outnotes/secret.md"), "corpus: nothing behind a link out of the project")
  ok(not has(corpus, "leaving/x.md"), "corpus: ...whatever the link is called")
  ok(not has(corpus, "innotes/inside_note.md"), "corpus: a folder link is not entered, as before")
  if file_link then
    ok(not has(corpus, "secret_link.md"), "corpus: a file link out is not listed")
  end

  -- ----------------------------------------------- Features and Checklist
  local out_feat = features.resolve(root, "linked_features")
  eq(out_feat, nil, "features: a folder that is a link out of the project is no folder")
  local in_feat = features.resolve(root, "linked_features_in")
  ok(in_feat ~= nil and #in_feat.files == 1, "features: one that stays inside is read")
  local out_check = checklist.resolve(root, "linked_checklist")
  eq(out_check, nil, "checklist: a folder that is a link out of the project is no folder")
  local in_check = checklist.resolve(root, "linked_checklist_in")
  ok(in_check ~= nil and #in_check.files == 1, "checklist: one that stays inside is read")

  if file_link_check then
    eq(
      checklist.resolve(root, "check_single.md"),
      nil,
      "checklist: a single file that is a link out of the project is not read"
    )
  end

  -- ------------------------------------------- tests dir, README targets
  local ir, findings = docmap.scan_full(opts)
  local fns = {}
  for _, fn in ipairs(ir.nodes["lua/t"].functions) do
    fns[fn.name] = fn.tested
  end
  eq(fns["M.only_named_outside"], false, "tests: a tests folder behind a link out is not read")

  local dead = {}
  for _, f in ipairs(findings) do
    if f.check == "dead-readme-link" then
      dead[#dead + 1] = vim.json.encode(f)
    end
  end
  local dead_text = table.concat(dead, "\n")
  ok(
    dead_text:find("nowhere/missing.md", 1, true) ~= nil,
    "readme: a target that is not there is dead"
  )
  ok(
    dead_text:find("leaving/gone.md", 1, true) == nil,
    "readme: a target behind a link out of the project is not judged at all"
  )
  ok(
    dead_text:find("staying/x.md", 1, true) ~= nil,
    "readme: ...a link inside the project is followed, and this target is not there"
  )

  local in_opts = config.build(root, { source = "lua/t", lua_root = "lua", tests_dir = "TESTS_IN" })
  local in_ir = docmap.scan_full(in_opts)
  local in_fns = {}
  for _, fn in ipairs(in_ir.nodes["lua/t"].functions) do
    in_fns[fn.name] = fn.tested
  end
  eq(in_fns["M.named_inside"], true, "tests: a plain tests folder still counts")

  -- ----------------------------------------------------------- the map
  vim.fn.mkdir(root .. "/docs", "p")
  ok(H.link(outside .. "/map", root .. "/docs/map", true), "map: a link out can be made")
  local loaded, why = artifact.load({ root = root, out_dir = "docs/map" })
  eq(loaded, nil, "map: a committed map behind a link out is not read")
  ok(tostring(why):find("not read", 1, true) ~= nil, "map: ...and it says why: " .. tostring(why))

  vim.fn.delete(root .. "/docs/map")
  vim.fn.mkdir(root .. "/real_map", "p")
  local generated = docmap.generate(
    config.build(root, { source = "lua/t", lua_root = "lua", out_dir = "real_map" })
  )
  ok(generated ~= nil, "map: a real map to point a link at")
  ok(H.link(here .. "/real_map", root .. "/docs/map", true), "map: a link inside can be made")
  local inside = artifact.load({ root = root, out_dir = "docs/map" })
  ok(inside ~= nil and inside.nodes ~= nil, "map: one behind a link that stays inside is read")

  vim.fn.delete(base, "rf")
end
