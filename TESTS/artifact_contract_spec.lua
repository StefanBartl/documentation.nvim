-- TESTS/artifact_contract_spec.lua — every IR field reaches the artifact
--
-- `IDEAS.md` §9's payload-contract test, written after the trap it exists
-- for caught a sixth field.
--
-- The trap: `Documentation.Node` and `documentation.to_json`'s field list are
-- maintained separately, by hand, in two files. A field added to the first
-- and forgotten in the second produces a scan that is completely correct and
-- an artifact that silently lacks the data — which `--check` then cannot see
-- drift in, and which every consumer reading `module_map.json` rather than
-- the generated page sees as simply absent.
--
-- Its history, all found by a human noticing something missing rather than
-- by a test: `duplicates`, `docs`, `quicks` and `checklist` (see
-- `core/render/html.lua`'s own payload comment thread), then `language`, then
-- `endpoints` — the last of which had been missing since `core/endpoints.lua`
-- shipped, because the *page* encodes node tables wholesale and therefore
-- showed routes the artifact did not carry.
--
-- This spec compares the two mechanically, so the seventh is a failing test
-- rather than a discovery.

return function(H)
  local eq, ok = H.eq, H.ok
  local docmap = require("documentation")

  ---Fields a node legitimately carries and the artifact deliberately omits.
  ---
  ---**An allowlist, not a suppression list.** Adding a name here is a claim
  ---that the field is scratch state rather than data, and it needs the same
  ---justification `to_json`'s own comment gives for these two: they are
  ---unresolved input to the graph stages, already fully represented by
  ---`ir.edges` and the resolved `requires`/`calls_external` by the time
  ---anything is written, so serialising them would ship the same facts twice
  ---in two shapes, one of them raw.
  local NOT_SERIALISED = {
    requires_raw = true,
    calls_raw = true,
  }

  local root = (vim.fn.tempname():gsub("\\", "/"))
  local function write(rel, body)
    local path = root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    local fd = io.open(path, "w")
    if fd then
      fd:write(body)
      fd:close()
    end
  end

  -- A module *and* a leaf file, because the two are built at different sites
  -- in `walk_dir` with different field sets — a contract test that only ever
  -- saw one of them would have missed `language` on the other.
  write(
    "lua/core/init.lua",
    "---@module 'core'\n--- A module.\nlocal M = {}\n---Do a thing.\nfunction M.go() end\nreturn M\n"
  )
  write("lua/core/helper.lua", "---@module 'core.helper'\n--- A helper.\nreturn {}\n")

  local ir = require("documentation.core.scan").scan(require("documentation.config").build(root))
  local doc = vim.json.decode(docmap.to_json(ir), { luanil = { object = true, array = true } })

  local emitted = {}
  for _, n in ipairs(doc.nodes) do
    for k in pairs(n) do
      emitted[k] = true
    end
  end

  local seen_module, seen_file = false, false
  local missing = {}
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.kind == "module" then
      seen_module = true
    elseif node.kind == "file" then
      seen_file = true
    end
    for field in pairs(node) do
      if not emitted[field] and not NOT_SERIALISED[field] and not missing[field] then
        missing[field] = node.kind
      end
    end
  end

  -- The fixture has to actually exercise both shapes, or the assertion below
  -- passes for the wrong reason.
  ok(seen_module, "artifact contract: the fixture produced a module node")
  ok(seen_file, "artifact contract: ... and a file node")

  local names = {}
  for field, kind in pairs(missing) do
    names[#names + 1] = ("%s (on a %s node)"):format(field, kind)
  end
  table.sort(names)
  eq(
    table.concat(names, ", "),
    "",
    "artifact contract: every node field reaches module_map.json, or is a declared non-serialised one"
  )

  -- The reverse direction, so a field is not quietly dropped from the scan
  -- while the writer keeps emitting a stale key.
  local node_fields = {}
  for _, id in ipairs(ir.order) do
    for field in pairs(ir.nodes[id]) do
      node_fields[field] = true
    end
  end
  local orphaned = {}
  for field in pairs(emitted) do
    if not node_fields[field] then
      orphaned[#orphaned + 1] = field
    end
  end
  table.sort(orphaned)
  eq(
    table.concat(orphaned, ", "),
    "",
    "artifact contract: the writer emits no key the scan no longer produces"
  )

  vim.fn.delete(root, "rf")
end
