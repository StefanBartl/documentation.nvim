-- TESTS/check_readme_links_spec.lua — which README link targets are dead, and
-- that the answer is the same on Windows and on POSIX.
--
-- The map is compared byte for byte (`docmap --check`), and the findings are
-- in it: a README that is judged one way on the machine that wrote the map and
-- another on the CI runner that checks it makes a current map look stale.
-- `safe_fs.windows` is the switch for the path rules, read at call time, so
-- the same tree is scanned under both from one host.
--
-- Targets that stay inside the project and are not there are dead on both; a
-- URL scheme (`mailto:`, `tel:`) names no file and is never looked for; a
-- Windows drive path is no scheme, and is looked for like any other name.

return function(H)
  local eq = H.eq
  local config = require("documentation.config")
  local docmap = require("documentation")
  local safe_fs = require("documentation.core.safe_fs")

  local root = (H.tmpfile("_readme_links"):gsub("\\", "/"))
  H.write(root .. "/lua/t/init.lua", {
    "---@module 't'",
    "local M = {}",
    "return M",
  })
  H.write(root .. "/lua/t/README.md", {
    "# t",
    "[mail](mailto:a@b.c)",
    "[phone](tel:+49123)",
    "[web](https://example.org/x.md)",
    "[drive](C:/x/y.md)",
    "[gone](gone.md)",
    "[query](a?b.md)",
    "[here](init.lua)",
  })

  ---The `target` of every `dead-readme-link`, sorted, under the path rules of
  ---`windows`; the rules are put back whatever happens.
  ---@param windows boolean
  ---@return string
  local function dead_under(windows)
    local saved = safe_fs.windows
    safe_fs.windows = windows
    safe_fs.forget()
    local ran, result = pcall(function()
      local _, findings =
        docmap.scan_full(config.build(root, { source = "lua/t", lua_root = "lua" }))
      local targets = {}
      for _, f in ipairs(findings) do
        if f.check == "dead-readme-link" then
          targets[#targets + 1] = f.params.target
        end
      end
      table.sort(targets)
      return table.concat(targets, " ")
    end)
    safe_fs.windows = saved
    safe_fs.forget()
    if not ran then
      error(result, 0)
    end
    return result
  end

  local want = "C:/x/y.md a?b.md gone.md"
  eq(
    dead_under(false),
    want,
    "readme links (POSIX rules): only the names that are not there are dead"
  )
  eq(dead_under(true), want, "readme links (Windows rules): the same targets, and no others")

  vim.fn.delete(root, "rf")
end
