-- TESTS/payload_contract_spec.lua — every IR field reaches the page
--
-- The second half of `IDEAS.md` §9, and the half the trap actually lived in.
-- `TESTS/artifact_contract_spec.lua` covers `ir` against `to_json`;
-- `core/render/html.lua` keeps its *own* hand-maintained field list for the
-- `<script id="ir">` payload, and that is the list that swallowed four of the
-- six known victims.
--
-- Their own record, from html.lua's payload comment thread: `duplicates` made
-- the Duplicates panel show "this map predates duplicate detection —
-- regenerate it" on every map including one generated a second earlier, with
-- advice that was impossible to follow because regenerating produced the same
-- payload. `docs`, `quicks` and `checklist` each repeated it. `glossaries`
-- was nearly the fifth and only avoided it because someone read the comment.
--
-- A comment is not a mechanism. This is.

return function(H)
  local eq, ok = H.eq, H.ok
  local docmap = require("documentation")

  ---IR fields the page deliberately does not receive.
  ---
  ---**An allowlist, not a suppression list.** Each entry is a claim that the
  ---page is better off without the field, and has to survive being read
  ---aloud:
  ---
  ---  * `order` is not missing from the payload, it is *expressed* by it —
  ---    `nodes` is emitted as an array built by walking `ir.order`, so the
  ---    order is the array. Shipping both would be two answers to one
  ---    question.
  ---  * `timing` describes the *run*, not the repository: per-stage durations,
  ---    collected only under `opts.debug`, reported by
  ---    `bindings/usrcmds/generate.lua`. Putting it in the page would make two
  ---    renders of an unchanged tree differ, which is the same reason
  ---    `Documentation.Meta` deliberately carries no timestamp.
  local NOT_IN_PAYLOAD = {
    order = true,
    timing = true,
  }

  -- A fixture rich enough to actually hold the optional fields. `tools`,
  -- `features` and `checklist` are absent from `ir` entirely when the tree
  -- has no `docs/install.json`, no `docs/FEATURES/` and no `docs/CHECKLIST/`
  -- — and a key that is not there cannot be found missing, so a plain
  -- fixture would pass this spec while proving nothing about exactly the
  -- three fields most likely to be forgotten.
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

  write(
    "lua/r/init.lua",
    "---@module 'r'\n--- Rich fixture.\nlocal M = {}\n---Do it.\nfunction M.go() end\nreturn M\n"
  )
  write("docs/install.json", '{"tools":[{"bin":"rg","why":"search","pkg":{"arch":"ripgrep"}}]}\n')
  write(
    "docs/FEATURES/FEATURES.md",
    "# Features\n\n## A feature (2026-01-01)\n\nIt does a thing.\n"
  )
  write(
    "docs/CHECKLIST/CHECKLIST.md",
    "# Checklist\n\n- [x] something verified — `lua/r/init.lua`\n"
  )

  local opts = require("documentation.config").build(root)
  local ir, findings = docmap.scan_full(opts)
  local html = docmap.render.html(ir, findings, opts)

  -- Read back out of the rendered page rather than from any intermediate the
  -- renderer might expose: what a consumer gets is what this asserts on.
  local i = html:find('id="ir"', 1, true)
  ok(i ~= nil, "payload contract: the page carries an #ir payload at all")
  local from = html:find(">", i, true) + 1
  local to = html:find("</script>", from, true) - 1
  -- `</` is escaped in the payload so it cannot terminate the script block.
  local raw = html:sub(from, to):gsub("<" .. string.char(92) .. "/", "</")
  local payload = vim.json.decode(raw, { luanil = { object = true, array = true } })

  local in_payload = {}
  for key in pairs(payload) do
    in_payload[key] = true
  end

  -- The fixture has to actually carry the optional fields, or everything
  -- below passes for the wrong reason.
  for _, key in ipairs({ "tools", "features", "checklist", "quicks", "docs", "duplicates" }) do
    ok(ir[key] ~= nil, "payload contract: the fixture produced ir." .. key)
  end

  local missing = {}
  for key in pairs(ir) do
    if not in_payload[key] and not NOT_IN_PAYLOAD[key] then
      missing[#missing + 1] = key
    end
  end
  table.sort(missing)
  eq(
    table.concat(missing, ", "),
    "",
    "payload contract: every IR field reaches the page, or is a declared exclusion"
  )

  -- The reverse: a payload key the scan no longer produces is a panel reading
  -- something nothing writes.
  local orphaned = {}
  for key in pairs(payload) do
    -- Three payload fields are not IR fields by design, all for the same
    -- reason: they are tool data, the same bytes in every checkout, and so
    -- deliberately kept out of the byte-deterministic artifact that
    -- describes the repository. `glossaries` is read straight off
    -- `lang_registry`; `marker_kinds` is `core/markers.lua`'s keyword table,
    -- passed so the Notes tab does not keep a second copy of it; `tags` is
    -- `core/tags.lua`'s annotation catalogue, carried for the two panels
    -- that are gated on it. See `M.render`'s own notes on all three.
    --
    -- This list has to argue for itself, which is the point of it being a
    -- list rather than a rule: "not an IR field" is exactly what a panel
    -- reading something nothing writes looks like, and the only difference
    -- is a reason.
    local TOOL_DATA = { glossaries = true, marker_kinds = true, tags = true }
    if ir[key] == nil and not TOOL_DATA[key] then
      orphaned[#orphaned + 1] = key
    end
  end
  table.sort(orphaned)
  eq(
    table.concat(orphaned, ", "),
    "",
    "payload contract: the page is sent no key the scan stopped producing"
  )

  vim.fn.delete(root, "rf")
end
