-- TESTS/sibling_references_spec.lua — the `sibling-reference-missing` check:
-- a path naming another repository, resolved against the checkout
-- `opts.external_repos` declares.
--
-- Its own file, on the precedent every cross-repository check here already
-- set (`check_tag_requires_spec.lua`, `consumer_require_spec.lua`): the
-- fixture is two trees, not one, and that does not belong inside a spec
-- built around a single root.
--
-- What these assertions protect, in order of how quietly each would break:
--
--   1. **Nothing is guessed.** Only a first segment matching a declared
--      sibling `name` is considered at all. A check that started inferring
--      repository names from paths would fire on every `docs/foo.md` in
--      every tree and be switched off within a day, which is worse than not
--      having it.
--   2. **URLs are not paths.** Both false positives this check produced on
--      real docs came from URL-shaped text — a full `https://` link and a
--      bare `<repo>/blob/<ref>/…` GitHub path. Both are excluded by rule
--      rather than by tuning, and both have a fixture here.
--   3. **Absence is silence.** No declaration, or a declared checkout that
--      is not on disk, must produce no findings — that is CI's normal state,
--      and a warning there would say only that CI is CI.

return function(H)
  local eq, ok = H.eq, H.ok
  local scan = require("documentation.core.scan")
  local check = require("documentation.core.check")

  ---@param root string
  ---@param rel string
  ---@param lines string[]
  local function write(root, rel, lines)
    local abs = root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "sibling_references spec: fixture must be writable")
    fd:write(table.concat(lines, "\n"))
    fd:close()
  end

  ---Every `sibling-reference-missing` target the check reported, sorted.
  ---@param findings Documentation.Finding[]
  ---@return string[]
  local function targets(findings)
    local out = {}
    for _, f in ipairs(findings) do
      if f.check == "sibling-reference-missing" then
        out[#out + 1] = f.params.target
      end
    end
    table.sort(out)
    return out
  end

  -- Two trees under one parent, the layout this ecosystem actually uses and
  -- the one a relative `local_path` is for.
  local parent = H.tmpfile("_siblings")
  local main = parent .. "/main.nvim"
  local other = parent .. "/other.nvim"

  write(other, "docs/real.md", { "# Real", "", "This file exists." })

  write(main, "lua/m/init.lua", {
    "---@module 'm'",
    "--- The module.",
    "---",
    "--- Cites `other.nvim/docs/real.md`, which is there, and",
    "--- `other.nvim/docs/gone.md`, which is not.",
    "local M = {}",
    "---Runs.",
    "function M.run()",
    "  return 1",
    "end",
    "return M",
  })
  write(main, "docs/notes.md", {
    "# Notes",
    "",
    "Live: `other.nvim/docs/real.md`.",
    "Dead: `other.nvim/docs/missing.md`.",
    "",
    "A full URL, which is somebody else's namespace and not a claim about a",
    "checkout: https://github.com/StefanBartl/other.nvim/blob/main/docs/x.md",
    "",
    "A scheme-less GitHub blob path, the same thing written shorter:",
    "`other.nvim/blob/main/docs/y.md` and `other.nvim/tree/main/docs`.",
    "",
    "An undeclared repository is not this check's business: `stranger.nvim/docs/z.md`.",
    "A plain local path is not either: `docs/map/index.html`.",
  })

  local function opts_with(local_path)
    return {
      root = main,
      source = "lua/m",
      lua_root = "lua",
      out_dir = "docs/map",
      external_repos = local_path
          and {
            other = { repo = "me/other.nvim", name = "other.nvim", local_path = local_path },
          }
        or nil,
    }
  end

  do
    -- The whole check in one pass: both dead citations found, in both places
    -- they can be written, and nothing else reported.
    local opts = opts_with("../other.nvim")
    local ir = scan.scan(opts)
    local found = targets(check.run(ir, opts))

    eq(#found, 2, "sibling refs: exactly the two dead citations")
    eq(found[1], "other.nvim/docs/gone.md", "sibling refs: the one in a module header")
    eq(found[2], "other.nvim/docs/missing.md", "sibling refs: and the one in a markdown file")
  end

  do
    -- The three shapes that must stay quiet, asserted through the same run as
    -- above rather than separately: a live path, a URL, and an undeclared
    -- repository each look like a hit to a careless pattern.
    local opts = opts_with("../other.nvim")
    local found = table.concat(targets(check.run(scan.scan(opts), opts)), " ")

    ok(not found:find("real.md", 1, true), "sibling refs: an existing file is not reported")
    ok(not found:find("/blob/", 1, true), "sibling refs: a GitHub blob path is a URL, not a path")
    ok(not found:find("/tree/", 1, true), "sibling refs: ... and so is a tree path")
    ok(not found:find("x.md", 1, true), "sibling refs: a full URL is stripped before matching")
    ok(not found:find("stranger", 1, true), "sibling refs: an undeclared repo is nobody's claim")
    ok(not found:find("index.html", 1, true), "sibling refs: a plain local path is not a citation")
  end

  do
    -- Absence is silence, twice over: nothing declared at all, and a
    -- declaration pointing at a checkout that is not on disk. The second is
    -- CI's normal state.
    local bare = opts_with(nil)
    eq(
      #targets(check.run(scan.scan(bare), bare)),
      0,
      "sibling refs: nothing declared, nothing said"
    )

    local absent = opts_with("../not-checked-out")
    eq(
      #targets(check.run(scan.scan(absent), absent)),
      0,
      "sibling refs: a declared but absent checkout is silence, not a finding"
    )
  end

  do
    -- An absolute path is still accepted: that is what a one-off `generate()`
    -- call passes, and only the *committed* declaration needs to be portable.
    local absolute = opts_with(other)
    eq(
      #targets(check.run(scan.scan(absolute), absolute)),
      2,
      "sibling refs: an absolute local_path resolves the same way"
    )
  end
end
