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

  -- link targets read as CommonMark does: title, angle brackets, %-escapes, trailing blank; code is no link
  H.write(root .. "/lua/t/a b(1).md", { "x" })
  H.write(root .. "/docs/links.md", {
    '[titled](../lua/t/init.lua "the init")',
    "[angled](<../lua/t/a b(1).md>)",
    "[escaped](../lua/t/a%20b%281%29.md)",
    "[blank](../lua/t/init.lua )",
    "a lambda [x](int x) and [](auto self, int n) in prose",
    "[placeholder]($REPOS_DIR/elsewhere/x.md)",
    "[braced](${HOME}/y.md)",
    "[escaped-gone](../lua/t/nope%20here.md)",
    -- a title or <...> must not make a dead target invisible
    '[titled-gone](../lua/t/gone-titled.md "x")',
    "[angled-gone](<../lua/t/zz b(1).md>)",
    -- a file that is really called `$x.md` is found, not taken for a placeholder
    "[dollar-file](../lua/t/$x.md)",
    -- %00 is not decoded: the NUL would end the name at the file-system call and pass a dead link
    "[nul](../lua/t/init.lua%00junk)",
    -- the file part of a target with an anchor is checked
    "[frag-gone](../lua/t/gone-frag.md#sec)",
    "[frag-ok](../lua/t/init.lua#top)",
    -- balanced and escaped parentheses belong to the name
    "[balanced](../lua/t/f(1).md)",
    "[escaped-parens](../lua/t/f\\(1\\).md)",
    -- an encoded separator is no separator
    "[slash](../lua%2Ft/init.lua)",
    -- a reference definition is read with the same rules; a footnote is no link
    "",
    '[r-gone]: ../lua/t/gone-ref.md "t"',
    "[r-angled-gone]: <../lua/t/zz ref.md>",
    "[r-ok]: ../lua/t/init.lua",
    "[r-angled-ok]: <../lua/t/a b(1).md> 'title'",
    "[^1]: ../lua/t/not-a-link.md",
  })
  -- reference definitions follow CommonMark: no interrupting a paragraph, label and title rules, first label
  -- wins, and an HTML comment is not rendered
  H.write(root .. "/docs/refs.md", {
    "Keys:",
    "[count]: ../lua/t/para-gone.md",
    "",
    "# Heading",
    "[h]: ../lua/t/head-gone.md",
    "",
    "[ ]: ../lua/t/blank-label.md",
    "",
    "[a[b]: ../lua/t/bracket-label.md",
    "",
    "[a\\]b]: ../lua/t/esc-label-gone.md",
    "",
    '[tt]: ../lua/t/two-titles.md "a" "b"',
    "",
    "[d]: ../lua/t/init.lua",
    "[D]: ../lua/t/dup-gone.md",
    "",
    "<!--",
    "[old]: ../lua/t/old-gone.md",
    "-->",
    "",
    "<!-- [c](../lua/t/comment-gone.md) --> [y](../lua/t/after-comment-gone.md)",
  })
  H.write(root .. "/lua/t/$x.md", { "x" })
  H.write(root .. "/lua/t/f(1).md", { "x" })

  local want_list = {
    "../lua/t/nope%20here.md",
    "C:/x/y.md",
    "a?b.md",
    "gone.md",
    "../lua/t/gone-titled.md",
    "../lua/t/zz b(1).md",
    "../lua/t/init.lua%00junk",
    "../lua/t/gone-frag.md#sec",
    "../lua%2Ft/init.lua",
    "../lua/t/gone-ref.md",
    "../lua/t/zz ref.md",
    "../lua/t/head-gone.md",
    "../lua/t/esc-label-gone.md",
    "../lua/t/after-comment-gone.md",
  }
  table.sort(want_list)
  local want = table.concat(want_list, " ")
  eq(
    dead_under(false),
    want,
    "readme links (POSIX rules): only the names that are not there are dead"
  )
  eq(dead_under(true), want, "readme links (Windows rules): the same targets, and no others")

  -- placeholders get their own finding, never "does not exist"
  local _, all = docmap.scan_full(config.build(root, { source = "lua/t", lua_root = "lua" }))
  local placeholders = {}
  for _, f in ipairs(all) do
    if f.check == "placeholder-readme-link" then
      placeholders[#placeholders + 1] = f.params.var
    end
  end
  table.sort(placeholders)
  eq(
    table.concat(placeholders, " "),
    "HOME REPOS_DIR",
    "readme links: a $VAR / ${VAR} target is a placeholder finding"
  )

  -- A CRLF file read in binary mode (as on POSIX) keeps its `\r`: it ends the line, not the destination.
  -- Read directly, because Windows' text mode drops the `\r` before the check sees it.
  local refs =
    require("documentation.core.docs").reference_links("[r]: a.md\r\n[s]: <b c.md> 't'\r\n")
  eq(
    #refs == 2 and refs[1].dest .. "|" .. refs[2].dest or tostring(#refs),
    "a.md|b c.md",
    "readme links: a CRLF line end is not part of a reference destination"
  )

  vim.fn.delete(root, "rf")
end
