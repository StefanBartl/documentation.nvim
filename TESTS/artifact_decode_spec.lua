-- TESTS/artifact_decode_spec.lua — `core/artifact.lua`'s `decode`/`load`
-- distinguish "no artifact" from "artifact is corrupt" (ERR-11).
--
-- `M.load(opts)` used to return the same bare `nil` for a project that has
-- never generated a map and for one whose `module_map.json` exists but is
-- truncated or otherwise undecodable — collapsing "empty and fine" into
-- "empty because broken". `core/api.lua`'s routes then all reported "no map
-- generated yet" for a corrupt file too, sending the reader to regenerate a
-- map they already had rather than naming the real problem.

return function(H)
  local eq, ok = H.eq, H.ok
  local artifact = require("documentation.core.artifact")

  -- decode(): three ways to be broken, one way to succeed.
  local ir_empty, err_empty = artifact.decode("")
  eq(ir_empty, nil, "artifact.decode: an empty string decodes to nil")
  ok(
    type(err_empty) == "string",
    "artifact.decode: an empty string carries an error, not a bare nil"
  )

  local ir_bad, err_bad = artifact.decode("{ not json")
  eq(ir_bad, nil, "artifact.decode: undecodable JSON decodes to nil")
  ok(type(err_bad) == "string", "artifact.decode: undecodable JSON carries an error")

  local ir_noNodes, err_noNodes = artifact.decode('{"foo": 1}')
  eq(ir_noNodes, nil, "artifact.decode: JSON with no 'nodes' table decodes to nil")
  ok(type(err_noNodes) == "string", "artifact.decode: a missing 'nodes' table carries an error")

  local ir_ok, err_ok = artifact.decode('{"nodes": [], "root": "x"}')
  ok(ir_ok ~= nil, "artifact.decode: a real artifact document decodes")
  eq(err_ok, nil, "artifact.decode: a successful decode carries no error")

  -- load(): absent file vs. present-but-corrupt file must not read alike.
  local root = (vim.fn.tempname():gsub("\\", "/"))
  vim.fn.mkdir(root .. "/docs/map", "p")

  local ir_absent, err_absent = artifact.load({ root = root })
  eq(ir_absent, nil, "artifact.load: no module_map.json on disk yields nil")
  eq(err_absent, nil, "artifact.load: absence itself is not an error")

  local corrupt_path = root .. "/docs/map/module_map.json"
  local fd = assert(io.open(corrupt_path, "w"))
  fd:write("") -- present on disk, but empty -- a broken artifact, not "none"
  fd:close()

  local ir_corrupt, err_corrupt = artifact.load({ root = root })
  eq(ir_corrupt, nil, "artifact.load: a present-but-empty artifact still yields nil")
  ok(
    type(err_corrupt) == "string",
    "artifact.load: a present-but-corrupt artifact carries an error, unlike a genuinely absent one"
  )

  vim.fn.delete(root, "rf")
end
