-- TESTS/coverage_gaps_spec.lua — ir.meta.unclaimed / outside / claimed
--
-- The failure these three fields close was found twice in one session and
-- was the same shape both times: a map that looks perfectly healthy and is
-- missing part of its subject, with nothing anywhere saying so. Each case
-- below is one distinction the report depends on getting right — most
-- importantly the one between "outside the roots on purpose" (a scripts/
-- beside a lua/, which every repository has) and "outside the roots and
-- therefore absent from the map entirely", which nobody chose.

return function(H)
  local eq, ok = H.eq, H.ok
  local scan = require("documentation.core.scan")
  local cfg = require("documentation.config")

  local root = (vim.fn.tempname():gsub("\\", "/"))

  ---@param name string
  ---@param files table<string, string> Repo-relative path to contents.
  ---@return string abs
  local function tree(name, files)
    local abs = root .. "/" .. name
    for rel, body in pairs(files) do
      local path = abs .. "/" .. rel
      vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
      local fd = io.open(path, "w")
      if fd then
        fd:write(body)
        fd:close()
      end
    end
    return abs
  end

  local MOD = "---@module 'x'\n--- A module.\nlocal M = {}\nreturn M\n"

  -- A healthy single-language repository: nothing to report. This is the
  -- case that must stay silent, because it is every repository most of the
  -- time and a line printed always is a line read never.
  do
    local abs = tree("clean", { ["lua/core/init.lua"] = MOD })
    local ir = scan.scan(cfg.build(abs))
    eq(ir.meta.outside, nil, "coverage: a clean tree reports no outside files")
    eq(ir.meta.unclaimed, nil, "coverage: ... and nothing unclaimed")
    ok(ir.meta.claimed and ir.meta.claimed.lua > 0, "coverage: ... but does record what it read")
  end

  -- Lua outside the source root is ordinary — scripts/, standalone/, a
  -- root-level config. It is recorded, and the *report* suppresses it,
  -- because the language is in the map.
  do
    local abs = tree("scripts", {
      ["lua/core/init.lua"] = MOD,
      ["scripts/gen.lua"] = "return 1\n",
      ["scripts/check.lua"] = "return 2\n",
    })
    local ir = scan.scan(cfg.build(abs))
    eq(ir.meta.outside and ir.meta.outside.lua, 2, "coverage: lua outside the root is counted")
    ok(
      ir.meta.claimed and ir.meta.claimed.lua and ir.meta.claimed.lua > 0,
      "coverage: ... and the same language is also claimed, which is what suppresses the report line"
    )
  end

  -- The real gap: a language with files in the tree and no nodes in the map
  -- at all. Nothing else in the output would ever mention these.
  do
    local abs = tree("hidden", {
      ["lua/core/init.lua"] = MOD,
      ["tools/build.ts"] = "export const a = 1;\n",
      ["tools/lib.js"] = "export const b = 2;\n",
    })
    local ir = scan.scan(cfg.build(abs))
    eq(ir.meta.outside and ir.meta.outside.ts, 1, "coverage: a wholly-unmapped language is counted")
    eq(ir.meta.outside and ir.meta.outside.js, 1, "coverage: ... per backend, not lumped together")
    eq(
      ir.meta.claimed and ir.meta.claimed.ts,
      nil,
      "coverage: ... and is absent from claimed, which is what makes the report line fire"
    )
  end

  -- Files inside the roots that no backend reads. Mostly READMEs, which is
  -- exactly why this is recorded and not printed.
  do
    local abs = tree("unclaimed", {
      ["lua/core/init.lua"] = MOD,
      ["lua/core/README.md"] = "notes\n",
      ["lua/core/data.json"] = "{}\n",
    })
    local ir = scan.scan(cfg.build(abs))
    eq(ir.meta.unclaimed and ir.meta.unclaimed.md, 1, "coverage: unclaimed extensions are counted")
    eq(ir.meta.unclaimed and ir.meta.unclaimed.json, 1, "coverage: ... keyed by extension")
  end

  -- A second source root is not "outside" itself. Without this, a multi-root
  -- scan would report its own second half as missing from the map.
  do
    local abs = tree("multi", {
      ["lua/core/init.lua"] = MOD,
      ["src/a.ts"] = "export const a = 1;\n",
    })
    local ir = scan.scan(cfg.build(abs))
    eq(ir.meta.outside, nil, "coverage: a second source root is not reported as outside itself")
    ok(ir.meta.sources and #ir.meta.sources == 2, "coverage: ... and both roots were walked")
  end

  vim.fn.delete(root, "rf")
end
